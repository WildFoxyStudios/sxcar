//! Admin auth endpoints (T10 — AD1).
//!
//! Endpoints:
//! - `POST /admin/auth/login`  — email + password → mfa_token
//! - `POST /admin/auth/2fa`    — mfa_token + TOTP → access_token + session_id
//! - `POST /admin/auth/logout` — revoca sesion (requiere StaffAuth)

pub mod extractors;
pub mod handlers;

use axum::{routing::post, Router};

use crate::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/admin/auth/login", post(handlers::login))
        .route("/admin/auth/2fa", post(handlers::two_factor))
        .route("/admin/auth/logout", post(handlers::logout))
}
