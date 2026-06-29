//! RBAC middleware for admin routes (T11 — AD1).
//!
//! Checks that the authenticated `StaffUser` has a specific permission before
//! allowing the request to proceed.
//!
//! # Usage
//!
//! ```ignore
//! use axum::middleware::from_fn_with_state;
//!
//! .route("/admin/users", get(list_users)
//!     .route_layer(from_fn_with_state(state, require_perm("user.view"))))
//! ```

use axum::{
    extract::State,
    http::StatusCode,
    middleware::Next,
    response::Response,
};

use crate::AppState;

/// Returns a middleware closure that checks whether the authenticated staff has
/// the given `permission`.
///
/// The closure is intended for use with
/// [`axum::middleware::from_fn_with_state`] so it can be applied per-route or
/// per-route-group with `.route_layer(...)`.
///
/// If the permission is missing the response is `403 Forbidden`.
#[allow(clippy::type_complexity)]
pub fn require_perm(
    permission: &'static str,
) -> impl Fn(
    State<AppState>,
    crate::admin::extractors::StaffAuth,
    axum::http::Request<axum::body::Body>,
    Next,
) -> std::pin::Pin<
    Box<dyn std::future::Future<Output = Result<Response, StatusCode>> + Send>,
> + Clone {
    move |_state: State<AppState>,
          staff: crate::admin::extractors::StaffAuth,
          request: axum::http::Request<axum::body::Body>,
          next: Next| {
        let perm = permission;
        let has = staff.0.permissions.iter().any(|p| p == perm);
        Box::pin(async move {
            if has {
                Ok(next.run(request).await)
            } else {
                Err(StatusCode::FORBIDDEN)
            }
        })
    }
}
