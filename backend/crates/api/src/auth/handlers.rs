use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::Deserialize;
use time::{Duration, OffsetDateTime};

use crate::AppState;
use px_core::dto::{TokenPair, RegisterReq, LoginReq, RefreshReq, CodeReq};
use px_core::validation::{valid_email, is_adult, valid_password};

/// Emite par access+refresh y persiste el refresh hasheado.
pub(crate) async fn issue_pair(
    state: &AppState,
    user_id: uuid::Uuid,
) -> Result<TokenPair, StatusCode> {
    let access = auth::jwt::issue_access(&user_id.to_string(), &state.jwt)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let refresh = auth::tokens::generate_refresh();
    let exp = OffsetDateTime::now_utc() + Duration::seconds(state.refresh_ttl_secs);
    db::users::store_refresh_token(
        &state.pool,
        user_id,
        &auth::tokens::hash_token(&refresh),
        exp,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(TokenPair { access, refresh })
}

pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterReq>,
) -> Result<(StatusCode, Json<TokenPair>), StatusCode> {
    if !valid_email(&req.email) || !valid_password(&req.password) {
        return Err(StatusCode::BAD_REQUEST);
    }
    let dob = time::Date::parse(
        &req.dob,
        time::macros::format_description!("[year]-[month]-[day]"),
    )
    .map_err(|_| StatusCode::BAD_REQUEST)?;
    let today = OffsetDateTime::now_utc().date();
    if !is_adult(dob, today) {
        return Err(StatusCode::FORBIDDEN); // age-gate
    }
    let hash = auth::password::hash_password(&req.password)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let user_id =
        match db::users::create_user_full(&state.pool, &req.email, Some(&hash), Some(dob), true)
            .await
        {
            Ok(id) => id,
            Err(e) => {
                // Only a genuine unique-constraint violation (duplicate email or
                // phone) is a real "already registered" 409. Any other failure
                // (DB/connection error) must NOT be masked as a duplicate — that
                // told users a brand-new email was already taken. Surface 500 and
                // log the real cause instead.
                let is_duplicate = e
                    .downcast_ref::<sqlx::Error>()
                    .and_then(|se| match se {
                        sqlx::Error::Database(db_err) => Some(db_err.is_unique_violation()),
                        _ => None,
                    })
                    .unwrap_or(false);
                if is_duplicate {
                    return Err(StatusCode::CONFLICT);
                }
                tracing::error!("register: create_user_full failed (non-duplicate): {e:?}");
                return Err(StatusCode::INTERNAL_SERVER_ERROR);
            }
        };

    for kind in req.consents.iter() {
        let _ = db::users::record_consent(&state.pool, user_id, kind, "1.0").await;
    }

    // Código de verificación de email
    let code = auth::code::generate_code();
    let cexp = OffsetDateTime::now_utc() + Duration::minutes(30);
    db::users::issue_auth_code(
        &state.pool,
        user_id,
        "email_verify",
        &auth::code::hash_code(&code),
        cexp,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let _ = state
        .notifier
        .send_email(&req.email, "Verifica tu email", &format!("Código: {code}"))
        .await;

    let pair = issue_pair(&state, user_id).await?;
    Ok((StatusCode::CREATED, Json(pair)))
}

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginReq>,
) -> Result<Json<TokenPair>, StatusCode> {
    let user = db::users::find_user_by_email(&state.pool, &req.email)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    // Mensaje genérico tanto si no existe el usuario como si la password es incorrecta.
    let user = user.ok_or(StatusCode::UNAUTHORIZED)?;
    let hash = db::users::password_hash_for(&state.pool, user.id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;
    if !auth::password::verify_password(&hash, &req.password)
        .map_err(|_| StatusCode::UNAUTHORIZED)?
    {
        return Err(StatusCode::UNAUTHORIZED);
    }
    // P0-1: rechaza cuentas no activas (banned/suspended/deleted/shadowbanned).
    // `status == "deleted"` cubre el soft-delete (deleted_at IS NOT NULL).
    if user.status != "active" {
        return Err(StatusCode::FORBIDDEN);
    }
    let pair = issue_pair(&state, user.id).await?;
    Ok(Json(pair))
}

pub async fn refresh(
    State(state): State<AppState>,
    Json(req): Json<RefreshReq>,
) -> Result<Json<TokenPair>, StatusCode> {
    let th = auth::tokens::hash_token(&req.refresh);
    // Bug 2 (P2): rotación ATÓMICA. Un único UPDATE ... RETURNING revoca-y-reclama
    // el token, de modo que dos peticiones concurrentes con el mismo refresh no
    // puedan pasar ambas el chequeo (evita double-spend / reuse race).
    let user_id = match db::users::revoke_and_claim_refresh(&state.pool, &th)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    {
        db::users::RefreshClaim::Claimed { user_id, expired } => {
            if expired {
                return Err(StatusCode::UNAUTHORIZED);
            }
            user_id
        }
        // Reuse detectado: el token ya estaba revocado. Revoca toda la familia
        // del usuario (defensa ante robo de refresh token) y rechaza.
        db::users::RefreshClaim::AlreadyRevoked { user_id } => {
            let _ = db::users::revoke_all_refresh(&state.pool, user_id).await;
            return Err(StatusCode::UNAUTHORIZED);
        }
        db::users::RefreshClaim::NotFound => return Err(StatusCode::UNAUTHORIZED),
    };
    // P0-1: valida que la cuenta siga activa antes de emitir tokens nuevos.
    // Un usuario baneado/suspendido/borrado no debe poder refrescar su sesión.
    // El token viejo ya quedó revocado atómicamente arriba.
    let status = db::users::user_status(&state.pool, user_id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;
    if status != "active" {
        return Err(StatusCode::FORBIDDEN);
    }
    let pair = issue_pair(&state, user_id).await?;
    Ok(Json(pair))
}

pub async fn logout(
    State(state): State<AppState>,
    Json(req): Json<RefreshReq>,
) -> Result<StatusCode, StatusCode> {
    let th = auth::tokens::hash_token(&req.refresh);
    db::users::revoke_refresh_token(&state.pool, &th)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn verify_email(
    State(state): State<AppState>,
    user: crate::auth::AuthUser,
    Json(req): Json<CodeReq>,
) -> Result<StatusCode, StatusCode> {
    let ok = db::users::consume_auth_code(
        &state.pool,
        user.0,
        "email_verify",
        &auth::code::hash_code(&req.code),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    if !ok {
        return Err(StatusCode::BAD_REQUEST);
    }
    db::users::set_email_verified(&state.pool, user.0)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn resend_email(
    State(state): State<AppState>,
    user: crate::auth::AuthUser,
) -> Result<StatusCode, StatusCode> {
    let u = db::users::find_user_by_id(&state.pool, user.0)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;
    let code = auth::code::generate_code();
    let cexp = OffsetDateTime::now_utc() + Duration::minutes(30);
    db::users::issue_auth_code(
        &state.pool,
        user.0,
        "email_verify",
        &auth::code::hash_code(&code),
        cexp,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let _ = state
        .notifier
        .send_email(&u.email, "Verifica tu email", &format!("Código: {code}"))
        .await;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub struct ResetRequestReq {
    pub email: String,
}

pub async fn reset_request(
    State(state): State<AppState>,
    Json(req): Json<ResetRequestReq>,
) -> StatusCode {
    // Respuesta SIEMPRE 200 (sin enumeración). Si el usuario existe, emitimos y enviamos código.
    if let Ok(Some(u)) = db::users::find_user_by_email(&state.pool, &req.email).await {
        let code = auth::code::generate_code();
        let cexp = OffsetDateTime::now_utc() + Duration::minutes(30);
        if db::users::issue_auth_code(
            &state.pool,
            u.id,
            "password_reset",
            &auth::code::hash_code(&code),
            cexp,
        )
        .await
        .is_ok()
        {
            let _ = state
                .notifier
                .send_email(
                    &req.email,
                    "Restablecer contraseña",
                    &format!("Código: {code}"),
                )
                .await;
        }
    }
    StatusCode::OK
}

#[derive(Deserialize)]
pub struct ResetReq {
    pub email: String,
    pub code: String,
    pub new_password: String,
}

pub async fn reset_password(
    State(state): State<AppState>,
    Json(req): Json<ResetReq>,
) -> Result<StatusCode, StatusCode> {
    // Bug 1 (P1): reset debe exigir la MISMA fortaleza que register.
    // Antes solo comprobaba `len() < 8`, permitiendo passwords más débiles
    // que las aceptadas en el alta. Usa la misma validación (`valid_password`)
    // y el mismo status (400) que `register`.
    if !valid_password(&req.new_password) {
        return Err(StatusCode::BAD_REQUEST);
    }
    let u = db::users::find_user_by_email(&state.pool, &req.email)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::BAD_REQUEST)?;
    let ok = db::users::consume_auth_code(
        &state.pool,
        u.id,
        "password_reset",
        &auth::code::hash_code(&req.code),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    if !ok {
        return Err(StatusCode::BAD_REQUEST);
    }
    let hash = auth::password::hash_password(&req.new_password)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    db::users::update_password(&state.pool, u.id, &hash)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    db::users::revoke_all_refresh(&state.pool, u.id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub struct PhoneReq {
    pub phone: String,
}

pub async fn send_phone_code(
    State(state): State<AppState>,
    user: crate::auth::AuthUser,
    Json(req): Json<PhoneReq>,
) -> Result<StatusCode, StatusCode> {
    let code = auth::code::generate_code();
    let cexp = OffsetDateTime::now_utc() + Duration::minutes(10);
    db::users::issue_auth_code(
        &state.pool,
        user.0,
        "phone_verify",
        &auth::code::hash_code(&code),
        cexp,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let _ = state
        .notifier
        .send_sms(&req.phone, &format!("Código: {code}"))
        .await;
    Ok(StatusCode::NO_CONTENT)
}

pub async fn verify_phone(
    State(state): State<AppState>,
    user: crate::auth::AuthUser,
    Json(req): Json<CodeReq>,
) -> Result<StatusCode, StatusCode> {
    let ok = db::users::consume_auth_code(
        &state.pool,
        user.0,
        "phone_verify",
        &auth::code::hash_code(&req.code),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    if !ok {
        return Err(StatusCode::BAD_REQUEST);
    }
    db::users::set_phone_verified(&state.pool, user.0)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub struct OAuthReq {
    pub id_token: String,
}

pub async fn oauth(
    State(state): State<AppState>,
    Path(provider): Path<String>,
    Json(req): Json<OAuthReq>,
) -> Result<Json<TokenPair>, StatusCode> {
    if provider != "apple" && provider != "google" {
        return Err(StatusCode::BAD_REQUEST);
    }
    let id = state
        .oauth
        .verify(&provider, &req.id_token)
        .await
        .map_err(|_| StatusCode::UNAUTHORIZED)?;
    // find-or-create
    let user_id = match db::users::find_auth_identity(&state.pool, &provider, &id.provider_uid)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    {
        Some(uid) => {
            // P0-3: una identidad OAuth existente puede apuntar a una cuenta
            // baneada/suspendida/borrada. Rechaza si no está activa para que no
            // se pueda "resucitar" una cuenta muerta vía OAuth.
            let status = db::users::user_status(&state.pool, uid)
                .await
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
                .ok_or(StatusCode::UNAUTHORIZED)?;
            if status != "active" {
                return Err(StatusCode::FORBIDDEN);
            }
            uid
        }
        None => {
            // email del proveedor (o sintético) — único
            let email = id
                .email
                .clone()
                .unwrap_or_else(|| format!("{}+{}@oauth.local", id.provider_uid, provider));
            let uid = db::users::create_user_full(&state.pool, &email, None, None, true)
                .await
                .map_err(|_| StatusCode::CONFLICT)?;
            db::users::add_auth_identity(&state.pool, uid, &provider, &id.provider_uid)
                .await
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            uid
        }
    };
    let pair = issue_pair(&state, user_id).await?;
    Ok(Json(pair))
}
