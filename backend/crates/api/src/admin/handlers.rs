//! Handlers para /admin/auth/* endpoints.
//!
//! Flujo: login (email+password) → mfa_token → 2fa (mfa_token+totp) → JWT.
//! Logout revoca la sesion asociada al JWT.

use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    Json,
};
use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

use crate::admin::extractors::StaffAuth;
use crate::AppState;

// ---------------------------------------------------------------------------
// Request/Response types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct LoginResponse {
    pub mfa_token: String,
}

#[derive(Deserialize)]
pub struct TwoFactorRequest {
    pub mfa_token: String,
    pub totp_code: String,
}

#[derive(Serialize)]
pub struct TwoFactorResponse {
    pub access_token: String,
    pub session_id: String,
}

#[derive(Deserialize)]
pub struct LogoutRequest {
    pub session_id: String,
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// POST /admin/auth/login
///
/// Valida email+password, emite mfa_token (15 min TTL) para el paso 2FA.
pub async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, StatusCode> {
    // 1. Buscar staff por email
    let staff = db::staff::find_staff_by_email(&state.pool, &req.email)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let staff = match staff {
        Some(s) if s.status == "active" => s,
        _ => return Err(StatusCode::UNAUTHORIZED),
    };

    // 2. Cuenta bloqueada?
    if let Some(locked_until) = staff.locked_until {
        if locked_until > OffsetDateTime::now_utc() {
            return Err(StatusCode::from_u16(423).unwrap());
        }
    }

    // 3. Verificar password
    let password_ok = auth_admin::password::verify(&req.password, &staff.password_hash)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if !password_ok {
        // Incrementar contador de intentos fallidos
        let _ = db::staff::increment_failed_login(&state.pool, staff.id).await;
        return Err(StatusCode::UNAUTHORIZED);
    }

    // 4. Actualizar ultimo login (resetea failed_login_count)
    let ip = client_ip(&headers);
    db::staff::update_last_login(&state.pool, staff.id, ip.as_deref())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // 5. Emitir mfa_token
    let mfa_token = auth_admin::mfa_token::issue(
        state.admin_jwt_secret.as_bytes(),
        &staff.id.to_string(),
    );

    Ok(Json(LoginResponse { mfa_token }))
}

/// POST /admin/auth/2fa
///
/// Verifica mfa_token + codigo TOTP, crea sesion, emite JWT (8h).
pub async fn two_factor(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<TwoFactorRequest>,
) -> Result<Json<TwoFactorResponse>, StatusCode> {
    // 1. Verificar mfa_token → extraer staff_id
    let staff_id_str = auth_admin::mfa_token::verify(
        state.admin_jwt_secret.as_bytes(),
        &req.mfa_token,
    )
    .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let staff_id: Uuid = staff_id_str.parse().map_err(|_| StatusCode::UNAUTHORIZED)?;

    // 2. Buscar staff por id
    let staff = db::staff::find_staff_by_id(&state.pool, staff_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if staff.status != "active" {
        return Err(StatusCode::UNAUTHORIZED);
    }

    // 3. Desencriptar TOTP secret
    let kek = auth_admin::keystore::Kek::from_env()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let totp_raw = auth_admin::totp::decrypt_secret(&kek.key, &staff.totp_secret_enc)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    // 4. Verificar codigo TOTP (window=1, acepta ±1 step = 90s)
    let totp_b32 = auth_admin::totp::raw_to_b32(&totp_raw);
    let totp_ok = auth_admin::totp::verify_code(&totp_b32, &req.totp_code, 1)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if !totp_ok {
        return Err(StatusCode::UNAUTHORIZED);
    }

    // 5. Obtener permisos del rol
    let permissions = db::staff::get_role_permissions(&state.pool, &staff.role)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // 6. Crear sesion (8h)
    let expires_at = OffsetDateTime::now_utc() + Duration::hours(8);
    let ip = client_ip(&headers);
    let user_agent = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let session_id = db::staff::create_session(
        &state.pool,
        staff_id,
        expires_at,
        ip.as_deref(),
        user_agent.as_deref(),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // 7. Emitir JWT con jti = session_id
    let access_token = auth_admin::jwt::issue(
        &state.admin_jwt_secret,
        staff_id,
        &staff.role,
        &permissions,
        28800, // 8 horas
        &session_id.to_string(),
    )
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(Json(TwoFactorResponse {
        access_token,
        session_id: session_id.to_string(),
    }))
}

/// POST /admin/auth/logout
///
/// Revoca la sesion indicada (requiere token valido en Authorization header).
pub async fn logout(
    State(state): State<AppState>,
    _staff: StaffAuth,
    Json(req): Json<LogoutRequest>,
) -> Result<StatusCode, StatusCode> {
    let session_id: Uuid = req
        .session_id
        .parse()
        .map_err(|_| StatusCode::BAD_REQUEST)?;

    db::staff::revoke_session(&state.pool, session_id, "logout")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Extrae la direccion IP del cliente desde headers (X-Forwarded-For o X-Real-IP).
fn client_ip(headers: &HeaderMap) -> Option<String> {
    headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next().map(|s| s.trim().to_string()))
        .or_else(|| {
            headers
                .get("x-real-ip")
                .and_then(|v| v.to_str().ok())
                .map(String::from)
        })
}
