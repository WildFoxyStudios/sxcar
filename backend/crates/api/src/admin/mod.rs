//! Admin auth endpoints (T10 — AD1) + middleware (T11 — AD1).
//!
//! Endpoints:
//! - `POST /admin/auth/login`  — email + password → mfa_token
//! - `POST /admin/auth/2fa`    — mfa_token + TOTP → access_token + session_id
//! - `POST /admin/auth/logout` — revoca sesion (requiere StaffAuth)
//!
//! Middleware (T11):
//! - `rbac`     — permission checks per-route
//! - `audit`    — logs mutations to `audit_log`

pub mod audit;
pub mod extractors;
pub mod handlers;
pub mod rbac;

use axum::{middleware::from_fn_with_state, routing::{get, post}, Router};

use crate::AppState;

/// Test-only handlers compiled always; they are harmless because they require
/// valid staff authentication to produce a non-error response.
mod test_routes {
    use axum::http::StatusCode;

    pub async fn protected() -> StatusCode {
        StatusCode::NO_CONTENT
    }

    pub async fn authenticated(
        _: crate::admin::extractors::StaffAuth,
    ) -> StatusCode {
        StatusCode::NO_CONTENT
    }
}

pub fn router(state: AppState) -> Router<AppState> {
    Router::new()
        .route("/admin/auth/login", post(handlers::login))
        .route("/admin/auth/2fa", post(handlers::two_factor))
        .route("/admin/auth/logout", post(handlers::logout))
        // Test-only routes (harmless — require valid staff auth).
        .route(
            "/admin/_test_protected",
            post(test_routes::protected).route_layer(from_fn_with_state(
                state.clone(),
                rbac::require_perm("user.delete"),
            )),
        )
        .route(
            "/admin/_test_auth",
            get(test_routes::authenticated).route_layer(from_fn_with_state(
                state,
                audit::audit_mutation,
            )),
        )
}
