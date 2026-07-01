//! Grindr Tier 1 parity endpoints:
//! - User status (online + last_seen)
//! - Heartbeat
//! - Profile views (Viewed Me)
//! - Profile health (HIV status, last_tested, PrEP)

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::AppState;

// ---------------------------------------------------------------------------
// GET /users/:id/status
// ---------------------------------------------------------------------------

/// GET /users/:id/status
///
/// Returns the user's online indicator + last_seen_at. Also auto-logs the
/// current caller as having viewed the profile (for the "Viewed Me" feature).
pub async fn user_status(
    AuthUser(current_user_id): AuthUser,
    State(state): State<AppState>,
    Path(user_id): Path<Uuid>,
) -> Result<Json<Value>, StatusCode> {
    // Auto-touch: current user is active (heartbeat)
    let _ = db::users::touch_last_seen(&state.pool, current_user_id).await;

    // Log profile view (current_user viewed user_id)
    let _ = db::profiles::log_profile_view(&state.pool, current_user_id, user_id).await;

    let status = db::users::get_user_status(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_user_status error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(json!({
        "user_id": status.user_id.to_string(),
        "is_online": status.is_online,
        "last_seen_at": status.last_seen_at.map(|t| t.to_string()),
    })))
}

// ---------------------------------------------------------------------------
// POST /heartbeat — lightweight last_seen touch for the current user
// ---------------------------------------------------------------------------

/// POST /heartbeat
///
/// Updates the caller's `last_seen_at`. Flutter can call this on app focus.
pub async fn heartbeat(
    AuthUser(current_user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    db::users::touch_last_seen(&state.pool, current_user_id)
        .await
        .map_err(|e| {
            tracing::error!("touch_last_seen error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    Ok(Json(json!({ "ok": true, "user_id": current_user_id.to_string() })))
}

// ---------------------------------------------------------------------------
// GET /profile/views — recent viewers ("Viewed Me")
// ---------------------------------------------------------------------------

/// GET /profile/views
///
/// Returns the most recent profile viewers (people who viewed me).
pub async fn list_profile_views(
    AuthUser(current_user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let rows = db::profiles::list_profile_views(&state.pool, current_user_id, 50)
        .await
        .map_err(|e| {
            tracing::error!("list_profile_views error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let json_rows: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "viewer_id": r.viewer_id.to_string(),
                "viewed_at": r.viewed_at.to_string(),
                "display_name": r.display_name,
                "profile_photo_url": r.profile_photo_url,
            })
        })
        .collect();

    Ok(Json(json!({ "viewers": json_rows })))
}

// ---------------------------------------------------------------------------
// Profile health (HIV status, last_tested, PrEP)
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct UpdateHealthReq {
    pub hiv_status: Option<String>,
    pub last_tested_on: Option<String>, // YYYY-MM-DD
    pub prep: Option<bool>,
}

/// GET /profile/health
pub async fn get_health(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let row = sqlx::query!(
        r#"SELECT hiv_status, last_tested_on, prep
           FROM profiles WHERE user_id = $1"#,
        user_id
    )
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("get_health query error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let (hiv_status, last_tested_on, prep) = match row {
        Some(r) => (r.hiv_status, r.last_tested_on, r.prep),
        None => (None, None, None),
    };

    Ok(Json(json!({
        "hiv_status": hiv_status,
        "last_tested_on": last_tested_on.map(|d| d.to_string()),
        "prep": prep,
    })))
}

/// PUT /profile/health
pub async fn update_health(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(body): Json<UpdateHealthReq>,
) -> Result<Json<Value>, StatusCode> {
    // Parse last_tested_on (YYYY-MM-DD). Empty string clears the field.
    let last_tested_on = match &body.last_tested_on {
        Some(s) if !s.is_empty() => {
            let fmt = time::format_description::parse_borrowed::<2>("[year]-[month]-[day]")
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            Some(time::Date::parse(s, &fmt).map_err(|_| StatusCode::BAD_REQUEST)?)
        }
        Some(_) => None,
        None => None,
    };

    // Ensure a profile row exists, then upsert.
    sqlx::query!(
        "INSERT INTO profiles (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING",
        user_id
    )
    .execute(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("ensure profile error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    sqlx::query!(
        r#"UPDATE profiles SET
             hiv_status    = $2,
             last_tested_on = $3,
             prep          = $4,
             updated_at    = now()
           WHERE user_id = $1"#,
        user_id,
        body.hiv_status.as_deref(),
        last_tested_on,
        body.prep
    )
    .execute(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("update_health error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let row = sqlx::query!(
        r#"SELECT hiv_status, last_tested_on, prep
           FROM profiles WHERE user_id = $1"#,
        user_id
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("get_health after update error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(json!({
        "hiv_status": row.hiv_status,
        "last_tested_on": row.last_tested_on.map(|d| d.to_string()),
        "prep": row.prep,
    })))
}