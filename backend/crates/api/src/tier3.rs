//! Vibra Tier 3 endpoints:
//! - Right Now (`POST /right-now`, `GET /right-now`, `DELETE /right-now/:id`)
//! - Sessions (`GET /me/sessions`, `DELETE /me/sessions/:session_id`)
//! - Screenshot alerts (`POST /screenshots`, `GET /screenshots`)
//! - Friendly reminder (`GET /me/idle-reminder`, `PUT /me/idle-reminder`)
//!
//! All endpoints require authentication via the `AuthUser` extractor.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{delete, get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::AppState;

/// Default intent lifetime (in minutes) when the client doesn't specify.
const DEFAULT_INTENT_MINUTES: i64 = 30;

/// Max intents returned by `GET /right-now`.
const NEARBY_INTENT_LIMIT: i64 = 100;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/right-now", post(create_intent).get(list_intents))
        .route("/right-now/:id", delete(delete_intent))
        .route("/me/sessions", get(list_sessions))
        .route("/me/sessions/:session_id", delete(revoke_session))
        .route("/screenshots", post(log_screenshot).get(list_screenshots))
        .route("/me/idle-reminder", get(get_idle_reminder).put(set_idle_reminder))
}

// ---------------------------------------------------------------------------
// Right Now
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct CreateIntentReq {
    pub body: String,
    /// Lifetime in minutes from now. Defaults to 30.
    pub expires_in_minutes: Option<i64>,
}

/// POST /right-now
pub async fn create_intent(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(body): Json<CreateIntentReq>,
) -> Result<Json<Value>, StatusCode> {
    let text = body.body.trim();
    if text.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let minutes = body.expires_in_minutes.unwrap_or(DEFAULT_INTENT_MINUTES);
    if minutes <= 0 {
        return Err(StatusCode::BAD_REQUEST);
    }

    let now = time::OffsetDateTime::now_utc();
    let expires_at = now + time::Duration::minutes(minutes);

    let id = db::tier3::create_intent(&state.pool, user_id, text, expires_at)
        .await
        .map_err(|e| {
            tracing::error!("create_intent error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "id": id.to_string(),
        "user_id": user_id.to_string(),
        "body": text,
        "expires_at": expires_at.to_string(),
        "created_at": now.to_string(),
    })))
}

/// GET /right-now
pub async fn list_intents(
    AuthUser(_user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let now = time::OffsetDateTime::now_utc();
    let rows = db::tier3::list_nearby_intents(&state.pool, now, NEARBY_INTENT_LIMIT)
        .await
        .map_err(|e| {
            tracing::error!("list_nearby_intents error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let intents: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id.to_string(),
                "user_id": r.user_id.to_string(),
                "body": r.body,
                "expires_at": r.expires_at.to_string(),
                "created_at": r.created_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({ "intents": intents })))
}

/// DELETE /right-now/:id
pub async fn delete_intent(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    db::tier3::delete_intent(&state.pool, user_id, id)
        .await
        .map_err(|e| {
            tracing::error!("delete_intent error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

/// GET /me/sessions
pub async fn list_sessions(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let rows = db::tier3::list_active_sessions(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_active_sessions error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let sessions: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id.to_string(),
                "device_id": r.device_id.map(|d| d.to_string()),
                "issued_at": r.issued_at.to_string(),
                "expires_at": r.expires_at.to_string(),
                "revoked_at": r.revoked_at.map(|d| d.to_string()),
            })
        })
        .collect();

    Ok(Json(json!({ "sessions": sessions })))
}

/// DELETE /me/sessions/:session_id
pub async fn revoke_session(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(session_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    db::tier3::revoke_session(&state.pool, user_id, session_id)
        .await
        .map_err(|e| {
            tracing::error!("revoke_session error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------
// Screenshot alerts
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct ScreenshotReq {
    pub conversation_id: Uuid,
}

/// POST /screenshots
pub async fn log_screenshot(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(body): Json<ScreenshotReq>,
) -> Result<Json<Value>, StatusCode> {
    let id = db::tier3::log_screenshot_alert(&state.pool, user_id, body.conversation_id)
        .await
        .map_err(|e| {
            tracing::error!("log_screenshot_alert error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "id": id.to_string(),
        "user_id": user_id.to_string(),
        "conversation_id": body.conversation_id.to_string(),
    })))
}

/// GET /screenshots
pub async fn list_screenshots(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let rows = db::tier3::list_screenshot_alerts(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_screenshot_alerts error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let alerts: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id.to_string(),
                "user_id": r.user_id.to_string(),
                "conversation_id": r.conversation_id.to_string(),
                "reported_at": r.reported_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({ "alerts": alerts })))
}

// ---------------------------------------------------------------------------
// Friendly reminder
// ---------------------------------------------------------------------------

/// GET /me/idle-reminder
pub async fn get_idle_reminder(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let hours = db::tier3::get_idle_reminder_hours(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_idle_reminder_hours error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "hours": hours,
    })))
}

#[derive(Deserialize)]
pub struct SetIdleReminderReq {
    /// NULL / null clears the setting.
    pub hours: Option<i32>,
}

/// PUT /me/idle-reminder
pub async fn set_idle_reminder(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(body): Json<SetIdleReminderReq>,
) -> Result<Json<Value>, StatusCode> {
    if let Some(h) = body.hours {
        if h <= 0 {
            return Err(StatusCode::BAD_REQUEST);
        }
    }

    db::tier3::set_idle_reminder_hours(&state.pool, user_id, body.hours)
        .await
        .map_err(|e| {
            tracing::error!("set_idle_reminder_hours error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "ok": true,
        "hours": body.hours,
    })))
}
