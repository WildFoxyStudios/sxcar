pub mod handlers;

use std::sync::Arc;

use async_trait::async_trait;
use auth::{jwt::JwtConfig, notify::Notifier, oauth::OAuthVerifier};
use axum::{
    extract::FromRequestParts,
    http::{request::Parts, StatusCode},
    routing::post,
    Router,
};

use crate::AppState;

/// Extractor de usuario autenticado (valida `Authorization: Bearer <access>`).
pub struct AuthUser(pub uuid::Uuid);

#[async_trait]
impl FromRequestParts<AppState> for AuthUser {
    type Rejection = StatusCode;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get(axum::http::header::AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .ok_or(StatusCode::UNAUTHORIZED)?;
        let token = header
            .strip_prefix("Bearer ")
            .ok_or(StatusCode::UNAUTHORIZED)?;
        let claims =
            auth::jwt::verify_access(token, &state.jwt).map_err(|_| StatusCode::UNAUTHORIZED)?;
        let id = claims
            .sub
            .parse::<uuid::Uuid>()
            .map_err(|_| StatusCode::UNAUTHORIZED)?;
        Ok(AuthUser(id))
    }
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/auth/register", post(handlers::register))
        .route("/auth/login", post(handlers::login))
        .route("/auth/refresh", post(handlers::refresh))
        .route("/auth/logout", post(handlers::logout))
        .route("/auth/verify-email", post(handlers::verify_email))
        .route("/auth/resend-email", post(handlers::resend_email))
        .route(
            "/auth/password/reset-request",
            post(handlers::reset_request),
        )
        .route("/auth/password/reset", post(handlers::reset_password))
}

/// Dependencias de auth que viven en AppState.
#[derive(Clone)]
pub struct AuthDeps {
    pub jwt: JwtConfig,
    pub refresh_ttl_secs: i64,
    pub notifier: Arc<dyn Notifier>,
    pub oauth: Arc<dyn OAuthVerifier>,
}
