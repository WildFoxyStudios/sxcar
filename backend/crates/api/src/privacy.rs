//! Privacy preferences endpoints.
//!
//! - `GET /privacy/preferences` — get current values
//! - `PUT /privacy/preferences` — partial update with validation

use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::auth::AuthUser;
use crate::AppState;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct PrivacyPreferences {
    pub multimedia_show_album_updates: bool,
    pub multimedia_show_carousel: bool,
    pub chat_mark_chatted: bool,
    pub chat_sync: bool,
    pub screen_keep_unlocked: bool,
    pub visitor_status: i16,
    pub units: i16,
    /// Incognito / invisible mode — when true the user is hidden from other
    /// users' grid/discover results (Grindr parity). Premium-gated client-side.
    pub incognito: bool,
}

#[derive(Deserialize, Debug, Default)]
pub struct UpdatePrivacyPreferences {
    pub multimedia_show_album_updates: Option<bool>,
    pub multimedia_show_carousel: Option<bool>,
    pub chat_mark_chatted: Option<bool>,
    pub chat_sync: Option<bool>,
    pub screen_keep_unlocked: Option<bool>,
    pub visitor_status: Option<i16>,
    pub units: Option<i16>,
    pub incognito: Option<bool>,
}

#[derive(Debug, thiserror::Error)]
pub enum PrivacyPrefError {
    #[error("invalid visitor_status: must be 0, 1, or 2")]
    InvalidVisitorStatus,
    #[error("invalid units: must be 0 or 1")]
    InvalidUnits,
    #[error("database error: {0}")]
    Db(#[from] sqlx::Error),
}

impl axum::response::IntoResponse for PrivacyPrefError {
    fn into_response(self) -> axum::response::Response {
        use axum::http::StatusCode;
        use axum::Json;
        use serde_json::json;
        let (status, code) = match &self {
            PrivacyPrefError::InvalidVisitorStatus
            | PrivacyPrefError::InvalidUnits => (StatusCode::UNPROCESSABLE_ENTITY, "invalid_value"),
            PrivacyPrefError::Db(_) => (StatusCode::INTERNAL_SERVER_ERROR, "db_error"),
        };
        (status, Json(json!({"error": code, "message": self.to_string()}))).into_response()
    }
}

fn row_to_prefs(row: sqlx::postgres::PgRow) -> Result<PrivacyPreferences, sqlx::Error> {
    Ok(PrivacyPreferences {
        multimedia_show_album_updates: row.try_get("multimedia_show_album_updates")?,
        multimedia_show_carousel: row.try_get("multimedia_show_carousel")?,
        chat_mark_chatted: row.try_get("chat_mark_chatted")?,
        chat_sync: row.try_get("chat_sync")?,
        screen_keep_unlocked: row.try_get("screen_keep_unlocked")?,
        visitor_status: row.try_get("visitor_status")?,
        units: row.try_get("units")?,
        incognito: row.try_get("incognito")?,
    })
}

/// GET /privacy/preferences
pub async fn get_preferences(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<PrivacyPreferences>, PrivacyPrefError> {
    // Ensure a profiles row exists (mirrors `notifications::update_notification_prefs`
    // upsert pattern — registration does not create a profile row by itself).
    sqlx::query(
        r#"INSERT INTO profiles (user_id) VALUES ($1)
           ON CONFLICT (user_id) DO NOTHING"#,
    )
    .bind(user_id)
    .execute(&state.pool)
    .await?;

    let row = sqlx::query(
        r#"SELECT multimedia_show_album_updates, multimedia_show_carousel,
                  chat_mark_chatted, chat_sync,
                  screen_keep_unlocked, visitor_status, units, incognito
             FROM profiles WHERE user_id = $1"#,
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await?;
    Ok(Json(row_to_prefs(row)?))
}

/// PUT /privacy/preferences — partial update
pub async fn update_preferences(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<UpdatePrivacyPreferences>,
) -> Result<Json<PrivacyPreferences>, PrivacyPrefError> {
    // Validate
    if let Some(v) = req.visitor_status {
        if !(0..=2).contains(&v) {
            return Err(PrivacyPrefError::InvalidVisitorStatus);
        }
    }
    if let Some(v) = req.units {
        if !(0..=1).contains(&v) {
            return Err(PrivacyPrefError::InvalidUnits);
        }
    }

    // Ensure a profiles row exists (mirrors the GET handler upsert pattern).
    sqlx::query(
        r#"INSERT INTO profiles (user_id) VALUES ($1)
           ON CONFLICT (user_id) DO NOTHING"#,
    )
    .bind(user_id)
    .execute(&state.pool)
    .await?;

    // Update each provided field with COALESCE pattern.
    sqlx::query(
        r#"UPDATE profiles
             SET multimedia_show_album_updates = COALESCE($1, multimedia_show_album_updates),
                 multimedia_show_carousel     = COALESCE($2, multimedia_show_carousel),
                 chat_mark_chatted            = COALESCE($3, chat_mark_chatted),
                 chat_sync                    = COALESCE($4, chat_sync),
                 screen_keep_unlocked         = COALESCE($5, screen_keep_unlocked),
                 visitor_status               = COALESCE($6, visitor_status),
                 units                        = COALESCE($7, units),
                 incognito                    = COALESCE($8, incognito)
             WHERE user_id = $9"#,
    )
    .bind(req.multimedia_show_album_updates)
    .bind(req.multimedia_show_carousel)
    .bind(req.chat_mark_chatted)
    .bind(req.chat_sync)
    .bind(req.screen_keep_unlocked)
    .bind(req.visitor_status)
    .bind(req.units)
    .bind(req.incognito)
    .bind(user_id)
    .execute(&state.pool)
    .await?;

    // Return the updated row.
    let row = sqlx::query(
        r#"SELECT multimedia_show_album_updates, multimedia_show_carousel,
                  chat_mark_chatted, chat_sync,
                  screen_keep_unlocked, visitor_status, units, incognito
             FROM profiles WHERE user_id = $1"#,
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await?;
    Ok(Json(row_to_prefs(row)?))
}