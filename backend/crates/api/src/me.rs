//! Self-service user actions: GDPR data export, account deletion.

use axum::{extract::State, http::StatusCode, Json};
use serde_json::{json, Value};

use crate::auth::AuthUser;
use crate::AppState;

/// POST /me/export-data
///
/// GDPR data export for the authenticated user. Builds a legal dossier
/// with all stored data and returns a summary with key counts.
/// No RBAC — the user owns their data.
pub async fn export_data(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<Value>, StatusCode> {
    let dossier = db::support::build_legal_dossier(&state.pool, user_id)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    Ok(Json(json!({
        "status": "ok",
        "user_id": user_id.to_string(),
        "email": dossier.user.email,
        "display_name": dossier.profile.as_ref()
            .and_then(|p| p.display_name.clone()),
        "photos_count": dossier.photos.len(),
        "subscriptions_count": dossier.subscriptions.len(),
        "reports_against_count": dossier.reports_against.len(),
        "consent_records_count": dossier.consent_records.len(),
    })))
}

/// DELETE /me
///
/// Self-service account deletion. Anonymizes all PII, revokes all active
/// sessions, and marks the account as deleted. Per GDPR the underlying data
/// is retained for 30 days before a hard-delete can be considered.
pub async fn delete_account(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<Value>, StatusCode> {
    // Revoke all refresh tokens so the user is forcibly logged out.
    db::users::revoke_all_refresh(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("delete_account revoke_all_refresh error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // Anonymize and soft-delete.
    let deletion_date = db::users::anonymize_user(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("delete_account anonymize_user error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "message": "Account scheduled for deletion",
        "deletion_date": deletion_date.to_string(),
    })))
}
