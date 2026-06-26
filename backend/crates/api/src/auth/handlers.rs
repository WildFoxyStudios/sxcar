use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use time::{Duration, OffsetDateTime};
use validator::Validate;

use crate::AppState;

#[derive(Serialize)]
pub struct TokenPair {
    pub access: String,
    pub refresh: String,
}

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

#[derive(Deserialize, Validate)]
pub struct RegisterReq {
    #[validate(email)]
    pub email: String,
    #[validate(length(min = 8))]
    pub password: String,
    /// fecha de nacimiento YYYY-MM-DD
    pub dob: String,
    #[serde(default)]
    pub consents: Vec<String>,
}

pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterReq>,
) -> Result<(StatusCode, Json<TokenPair>), StatusCode> {
    req.validate().map_err(|_| StatusCode::BAD_REQUEST)?;
    let dob = time::Date::parse(
        &req.dob,
        time::macros::format_description!("[year]-[month]-[day]"),
    )
    .map_err(|_| StatusCode::BAD_REQUEST)?;
    let today = OffsetDateTime::now_utc().date();
    if !auth::age::is_adult(dob, today) {
        return Err(StatusCode::FORBIDDEN); // age-gate
    }
    let hash = auth::password::hash_password(&req.password)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let user_id =
        db::users::create_user_full(&state.pool, &req.email, Some(&hash), Some(dob), true)
            .await
            .map_err(|_| StatusCode::CONFLICT)?; // email duplicado → conflicto genérico

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

#[derive(Deserialize)]
pub struct LoginReq {
    pub email: String,
    pub password: String,
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
    let pair = issue_pair(&state, user.id).await?;
    Ok(Json(pair))
}

#[derive(Deserialize)]
pub struct RefreshReq {
    pub refresh: String,
}

pub async fn refresh(
    State(state): State<AppState>,
    Json(req): Json<RefreshReq>,
) -> Result<Json<TokenPair>, StatusCode> {
    let th = auth::tokens::hash_token(&req.refresh);
    let row = db::users::find_refresh_token(&state.pool, &th)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;
    if row.revoked || row.expired {
        return Err(StatusCode::UNAUTHORIZED);
    }
    // rotación: revoca el viejo, emite par nuevo
    db::users::revoke_refresh_token(&state.pool, &th)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let pair = issue_pair(&state, row.user_id).await?;
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

#[derive(Deserialize)]
pub struct CodeReq {
    pub code: String,
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

#[derive(Deserialize, Validate)]
pub struct ResetReq {
    pub email: String,
    pub code: String,
    #[validate(length(min = 8))]
    pub new_password: String,
}

pub async fn reset_password(
    State(state): State<AppState>,
    Json(req): Json<ResetReq>,
) -> Result<StatusCode, StatusCode> {
    req.validate().map_err(|_| StatusCode::BAD_REQUEST)?;
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
        Some(uid) => uid,
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
