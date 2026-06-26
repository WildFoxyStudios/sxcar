use axum::{extract::State, http::StatusCode, Json};
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
