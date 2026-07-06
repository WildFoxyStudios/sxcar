//! Self-service user actions: GDPR data export.

use axum::{extract::State, http::StatusCode, Json};
use serde_json::Value;

use crate::auth::AuthUser;
use crate::AppState;

/// POST /me/export-data
///
/// GDPR data export for the authenticated user. Calls the same
/// `build_legal_dossier` used by the admin legal export handler
/// (no RBAC — the user owns their data).
pub async fn export_data(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<Value>, StatusCode> {
    let dossier = db::support::build_legal_dossier(&state.pool, user_id)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    Ok(Json(dossier))
}
