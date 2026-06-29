//! Push notification endpoints.
//!
//! - `POST /notifications/register` — register device token
//! - `GET  /notifications/preferences` — get notification preferences
//! - `PUT  /notifications/preferences` — update notification preferences

use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::auth::AuthUser;
use crate::AppState;

// ---------------------------------------------------------------------------
// POST /notifications/register
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct RegisterDeviceRequest {
    pub device_token: String,
    pub platform: String,
}

#[derive(Serialize)]
pub struct RegisterDeviceResponse {
    pub device_id: String,
}

/// Register a device token for push notifications.
///
/// POST /notifications/register
pub async fn register_device(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<RegisterDeviceRequest>,
) -> Result<Json<RegisterDeviceResponse>, StatusCode> {
    let platform = req.platform.to_lowercase();
    if !matches!(platform.as_str(), "ios" | "android" | "web") {
        return Err(StatusCode::BAD_REQUEST);
    }

    if req.device_token.trim().is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let device_id = db::notifications::register_device(
        &state.pool,
        user_id,
        &req.device_token,
        &platform,
    )
    .await
    .map_err(|e| {
        tracing::error!("register_device error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(RegisterDeviceResponse {
        device_id: device_id.to_string(),
    }))
}

// ---------------------------------------------------------------------------
// GET /notifications/preferences
// ---------------------------------------------------------------------------

/// Get the authenticated user's notification preferences.
///
/// GET /notifications/preferences
pub async fn get_preferences(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let prefs = db::notifications::get_notification_prefs(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_notification_prefs error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(prefs))
}

// ---------------------------------------------------------------------------
// PUT /notifications/preferences
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct UpdatePreferencesRequest {
    pub new_messages: Option<bool>,
    pub new_taps: Option<bool>,
    pub promotions: Option<bool>,
}

/// Update the authenticated user's notification preferences.
///
/// PUT /notifications/preferences
pub async fn update_preferences(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<UpdatePreferencesRequest>,
) -> Result<Json<Value>, StatusCode> {
    // Load current prefs as base
    let current = db::notifications::get_notification_prefs(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_notification_prefs error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // Merge request fields into current prefs
    let merged = merge_prefs(&current, &req);

    db::notifications::update_notification_prefs(&state.pool, user_id, &merged)
        .await
        .map_err(|e| {
            tracing::error!("update_notification_prefs error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(merged))
}

/// Merge partial update request into existing preferences JSON.
fn merge_prefs(current: &Value, req: &UpdatePreferencesRequest) -> Value {
    let mut map = if let Some(obj) = current.as_object() {
        obj.clone()
    } else {
        serde_json::Map::new()
    };

    if let Some(v) = req.new_messages {
        map.insert("new_messages".into(), Value::Bool(v));
    }
    if let Some(v) = req.new_taps {
        map.insert("new_taps".into(), Value::Bool(v));
    }
    if let Some(v) = req.promotions {
        map.insert("promotions".into(), Value::Bool(v));
    }

    Value::Object(map)
}
