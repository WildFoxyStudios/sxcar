//! Audit middleware for admin routes (T11 — AD1).
//!
//! Logs every mutation (POST / PUT / PATCH / DELETE) performed by an
//! authenticated staff member to the `audit_log` table.
//!
//! Reads are NOT audited (GET requests pass through silently).
//! Unauthenticated requests pass through without auditing (the auth check is
//! enforced by the handler-layer, not by this middleware).
//!
//! # Usage
//!
//! ```ignore
//! use axum::middleware::from_fn_with_state;
//!
//! .route("/admin/action", post(handler)
//!     .route_layer(from_fn_with_state(state, audit::audit_mutation)))
//! ```

use axum::{
    extract::State,
    http::{Method, StatusCode},
    middleware::Next,
    response::Response,
};

use crate::AppState;

/// Middleware that records admin mutations in `audit_log`.
///
/// Extracts the authenticated staff member as optional — if the request is
/// unauthenticated the middleware is transparent and lets the handler decide
/// the response.  Only mutations (POST / PUT / PATCH / DELETE) with a valid
/// staff identity are logged.
pub async fn audit_mutation(
    State(state): State<AppState>,
    staff: Option<crate::admin::extractors::StaffAuth>,
    request: axum::http::Request<axum::body::Body>,
    next: Next,
) -> Result<Response, StatusCode> {
    let method = request.method().clone();
    let path = request.uri().path().to_string();

    let response = next.run(request).await;

    // Only audit mutations by authenticated staff.
    if let Some(staff) = staff {
        if matches!(
            method,
            Method::POST | Method::PUT | Method::PATCH | Method::DELETE
        ) {
            let action = format!("{}:{}", method, path);
            let result = sqlx::query(
                "INSERT INTO audit_log (actor_staff_id, staff_session_id, action) \
                 VALUES ($1, $2, $3)",
            )
            .bind(staff.0.id)
            .bind(staff.0.session_id)
            .bind(&action)
            .execute(&state.pool)
            .await;

            if let Err(e) = result {
                tracing::warn!(
                    %action,
                    staff_id = %staff.0.id,
                    error = %e,
                    "audit_log insert failed"
                );
            }
        }
    }

    Ok(response)
}
