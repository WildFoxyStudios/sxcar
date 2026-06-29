//! Handlers para /admin/* endpoints.
//!
//! Incluye:
//! - Auth: login, 2fa, logout (AD1)
//! - Users: list, get, ban, suspend, activate, force-logout (AD2)
//! - Audit: list (AD2)

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

use crate::admin::audit::{AuditJustification, AuditTarget};
use crate::admin::extractors::StaffAuth;
use crate::AppState;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Convierte una fila UserRow a json, serializando `created_at` como string
/// (time::OffsetDateTime no impl Serialize sin feature flag en workspace).
fn user_row_to_json(u: db::users::UserRow) -> Value {
    json!({
        "id": u.id,
        "email": u.email,
        "email_verified": u.email_verified,
        "status": u.status,
        "role": u.role,
        "created_at": u.created_at.to_string(),
    })
}

/// Convierte una fila UserFullRow a json.
fn user_full_to_json(u: db::users::UserFullRow) -> Value {
    json!({
        "id": u.id,
        "email": u.email,
        "email_verified": u.email_verified,
        "status": u.status,
        "role": u.role,
        "created_at": u.created_at.to_string(),
        "display_name": u.display_name,
        "bio": u.bio,
        "profile_photo_url": u.profile_photo_url,
    })
}

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

// ---------------------------------------------------------------------------
// Auth — Request / Response types (AD1)
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
// AD2 — Request / Response types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct ListUsersQuery {
    pub q: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Deserialize)]
pub struct ActionRequest {
    pub reason: Option<String>,
}

#[derive(Deserialize)]
pub struct ListAuditQuery {
    pub staff_id: Option<Uuid>,
    pub action: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ---------------------------------------------------------------------------
// Auth handlers (AD1)
// ---------------------------------------------------------------------------

/// POST /admin/auth/login
///
/// Valida email+password, emite mfa_token (15 min TTL) para el paso 2FA.
pub async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<LoginRequest>,
) -> Result<Json<LoginResponse>, StatusCode> {
    let staff = db::staff::find_staff_by_email(&state.pool, &req.email)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let staff = match staff {
        Some(s) if s.status == "active" => s,
        _ => return Err(StatusCode::UNAUTHORIZED),
    };

    if let Some(locked_until) = staff.locked_until {
        if locked_until > OffsetDateTime::now_utc() {
            return Err(StatusCode::from_u16(423).unwrap());
        }
    }

    let password_ok = auth_admin::password::verify(&req.password, &staff.password_hash)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if !password_ok {
        let _ = db::staff::increment_failed_login(&state.pool, staff.id).await;
        return Err(StatusCode::UNAUTHORIZED);
    }

    let ip = client_ip(&headers);
    db::staff::update_last_login(&state.pool, staff.id, ip.as_deref())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

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
    let staff_id_str = auth_admin::mfa_token::verify(
        state.admin_jwt_secret.as_bytes(),
        &req.mfa_token,
    )
    .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let staff_id: Uuid = staff_id_str.parse().map_err(|_| StatusCode::UNAUTHORIZED)?;

    let staff = db::staff::find_staff_by_id(&state.pool, staff_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if staff.status != "active" {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let kek = auth_admin::keystore::Kek::from_env()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let totp_raw = auth_admin::totp::decrypt_secret(&kek.key, &staff.totp_secret_enc)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let totp_b32 = auth_admin::totp::raw_to_b32(&totp_raw);
    let totp_ok = auth_admin::totp::verify_code(&totp_b32, &req.totp_code, 1)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if !totp_ok {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let permissions = db::staff::get_role_permissions(&state.pool, &staff.role)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

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

    let access_token = auth_admin::jwt::issue(
        &state.admin_jwt_secret,
        staff_id,
        &staff.role,
        &permissions,
        28800,
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
// AD2 — User management handlers
// ---------------------------------------------------------------------------

/// GET /admin/users?q=&limit=20&offset=0
///
/// RBAC: user.view (checked inline).
/// Retorna lista paginada de usuarios + total + conteo por status.
pub async fn list_users(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<ListUsersQuery>,
) -> Result<Json<Value>, StatusCode> {
    // RBAC check inline
    if !staff.0.permissions.iter().any(|p| p == "user.view") {
        return Err(StatusCode::FORBIDDEN);
    }

    let q = query.q.as_deref().unwrap_or("");
    let limit = query.limit.unwrap_or(20).clamp(1, 100);
    let offset = query.offset.unwrap_or(0).max(0);

    let (users, total) = db::users::search_users(&state.pool, q, limit, offset)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let by_status = db::users::count_users_by_status(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let users_json: Vec<Value> = users.into_iter().map(user_row_to_json).collect();
    let by_status_json: Vec<Value> = by_status
        .into_iter()
        .map(|s| json!({"status": s.status, "count": s.count}))
        .collect();

    Ok(Json(json!({
        "users": users_json,
        "total": total,
        "by_status": by_status_json,
    })))
}

/// GET /admin/users/:id
///
/// RBAC: user.view (checked inline).
/// Retorna perfil completo del usuario (incluye datos de perfil/foto).
pub async fn get_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "user.view") {
        return Err(StatusCode::FORBIDDEN);
    }

    let user = db::users::find_user_full(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(json!({ "user": user_full_to_json(user) })))
}

/// POST /admin/users/:id/ban
///
/// RBAC: user.ban (requires_justification=true).
/// Body: { "reason": "..." }
pub async fn ban_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ActionRequest>,
) -> Result<
    (AuditTarget, AuditJustification, Json<Value>),
    StatusCode,
> {
    if !staff.0.permissions.iter().any(|p| p == "user.ban") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::users::update_user_status(&state.pool, id, "banned")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.reason.unwrap_or_default()),
        Json(json!({"status": "banned"})),
    ))
}

/// POST /admin/users/:id/suspend
///
/// RBAC: user.suspend (requires_justification=true).
/// Body: { "reason": "..." }
pub async fn suspend_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ActionRequest>,
) -> Result<
    (AuditTarget, AuditJustification, Json<Value>),
    StatusCode,
> {
    if !staff.0.permissions.iter().any(|p| p == "user.suspend") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::users::update_user_status(&state.pool, id, "suspended")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.reason.unwrap_or_default()),
        Json(json!({"status": "suspended"})),
    ))
}

/// POST /admin/users/:id/activate
///
/// RBAC: user.activate (sin justificación obligatoria).
/// Body opcional (se ignora).
pub async fn activate_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<(AuditTarget, Json<Value>), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "user.activate") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::users::update_user_status(&state.pool, id, "active")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        Json(json!({"status": "active"})),
    ))
}

/// POST /admin/users/:id/force-logout
///
/// RBAC: user.force_logout (requires_justification=true).
/// Revoca todos los refresh tokens del usuario.
/// Body: { "reason": "..." }
pub async fn force_logout_user(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<ActionRequest>,
) -> Result<
    (AuditTarget, AuditJustification, Json<Value>),
    StatusCode,
> {
    if !staff.0.permissions.iter().any(|p| p == "user.force_logout") {
        return Err(StatusCode::FORBIDDEN);
    }

    db::users::revoke_all_refresh(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.reason.unwrap_or_default()),
        Json(json!({"revoked": true})),
    ))
}

// ---------------------------------------------------------------------------
// AD2 — Audit handler
// ---------------------------------------------------------------------------

/// GET /admin/audit?staff_id=&action=&limit=20&offset=0
///
/// RBAC: audit.read (checked inline).
/// Retorna entradas del audit_log con filtros opcionales.
pub async fn list_audit(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<ListAuditQuery>,
) -> Result<Json<Value>, StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == "audit.read") {
        return Err(StatusCode::FORBIDDEN);
    }

    let limit = query.limit.unwrap_or(20).clamp(1, 200);
    let offset = query.offset.unwrap_or(0).max(0);

    let (entries, total) = db::staff::search_audit_log(
        &state.pool,
        query.staff_id,
        query.action.as_deref(),
        limit,
        offset,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Convertir cada entrada manualmente porque AuditRow contiene
    // OffsetDateTime que no implementa Serialize sin feature flag en time.
    let entries_json: Vec<Value> = entries
        .into_iter()
        .map(|e| {
            json!({
                "id": e.id,
                "actor_staff_id": e.actor_staff_id,
                "action": e.action,
                "target": e.target,
                "metadata": e.metadata,
                "created_at": e.created_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({
        "entries": entries_json,
        "total": total,
    })))
}
