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
    let s = state.clone();
    Router::new()
        // Auth (sin RBAC, sin audit)
        .route("/admin/auth/login", post(handlers::login))
        .route("/admin/auth/2fa", post(handlers::two_factor))
        .route("/admin/auth/logout", post(handlers::logout))
        // AD2 — Users list & detail (GET, RBAC inline en handler)
        .route("/admin/users", get(handlers::list_users))
        .route("/admin/users/:id", get(handlers::get_user))
        // AD2 — User mutations (POST, RBAC inline + audit)
        .route(
            "/admin/users/:id/ban",
            post(handlers::ban_user)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/users/:id/suspend",
            post(handlers::suspend_user)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/users/:id/activate",
            post(handlers::activate_user)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/users/:id/force-logout",
            post(handlers::force_logout_user)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD2 — Audit viewer (GET, RBAC inline)
        .route("/admin/audit", get(handlers::list_audit))
        // Test-only routes (harmless — require valid staff auth).
        .route(
            "/admin/_test_protected",
            post(test_routes::protected).route_layer(from_fn_with_state(
                s.clone(),
                rbac::require_perm("user.delete"),
            )),
        )
        .route(
            "/admin/_test_auth",
            get(test_routes::authenticated).route_layer(from_fn_with_state(
                s,
                audit::audit_mutation,
            )),
        )
}
