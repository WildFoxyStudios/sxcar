//! Audit middleware for admin routes (T11 — AD1).
//!
//! Logs every mutation (POST / PUT / PATCH / DELETE) performed by an
//! authenticated staff member to the `audit_log` table.
//!
//! Reads are NOT audited (GET requests pass through silently).
//! Unauthenticated requests pass through without auditing (the auth check is
//! enforced by the handler-layer, not by this middleware).
//!
//! Handlers can attach extra information to the response via `AuditTarget`
//! and `AuditJustification` response parts — the middleware reads them from
//! the response extensions after the handler runs.
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
    response::{IntoResponseParts, Response, ResponseParts},
};

use crate::AppState;

/// Response part: sets the audit target (e.g. user_id) for the mutation.
#[derive(Clone)]
pub struct AuditTarget(pub String);

impl IntoResponseParts for AuditTarget {
    type Error = (StatusCode, String);

    fn into_response_parts(self, mut res: ResponseParts) -> Result<ResponseParts, Self::Error> {
        res.extensions_mut().insert(self);
        Ok(res)
    }
}

/// Response part: sets the audit justification for the mutation.
#[derive(Clone)]
pub struct AuditJustification(pub String);

impl IntoResponseParts for AuditJustification {
    type Error = (StatusCode, String);

    fn into_response_parts(self, mut res: ResponseParts) -> Result<ResponseParts, Self::Error> {
        res.extensions_mut().insert(self);
        Ok(res)
    }
}

/// Middleware that records admin mutations in `audit_log`.
///
/// Extracts the authenticated staff member as optional — if the request is
/// unauthenticated the middleware is transparent and lets the handler decide
/// the response.  Only mutations (POST / PUT / PATCH / DELETE) with a valid
/// staff identity are logged.
///
/// Handlers may attach `AuditTarget` and `AuditJustification` to the response
/// via response parts; the middleware reads them from the response extensions
/// after the handler completes.
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
            // Clone out of response extensions before response is moved.
            let target = response
                .extensions()
                .get::<AuditTarget>()
                .map(|t| t.0.clone());
            let justification = response
                .extensions()
                .get::<AuditJustification>()
                .map(|j| j.0.clone());
            let action = format!("{}:{}", method, path);
            let result = sqlx::query(
                "INSERT INTO audit_log (actor_staff_id, staff_session_id, action, target, justification) \
                 VALUES ($1, $2, $3, $4, $5)",
            )
            .bind(staff.0.id)
            .bind(staff.0.session_id)
            .bind(&action)
            .bind(&target)
            .bind(&justification)
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
