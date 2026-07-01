//! Vibra Tier 3 backend: Right Now intents, active sessions (multi-instance),
//! screenshot alerts, friendly reminder delay.
//!
//! All queries use `query!` / `query_as!` macros so that the SQL is checked
//! against the live schema at compile time.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::Pool;

// ---------------------------------------------------------------------------
// Row types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntentRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub body: String,
    pub expires_at: time::OffsetDateTime,
    pub created_at: time::OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionRow {
    pub id: Uuid,
    pub device_id: Option<Uuid>,
    pub issued_at: time::OffsetDateTime,
    pub expires_at: time::OffsetDateTime,
    pub revoked_at: Option<time::OffsetDateTime>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlertRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub conversation_id: Uuid,
    pub reported_at: time::OffsetDateTime,
}

// ---------------------------------------------------------------------------
// Right Now intents
// ---------------------------------------------------------------------------

/// Insert a Right Now intent that expires at `expires_at`.
/// Returns the new intent id.
pub async fn create_intent(
    pool: &Pool,
    user_id: Uuid,
    body: &str,
    expires_at: time::OffsetDateTime,
) -> anyhow::Result<Uuid> {
    let row = sqlx::query!(
        r#"INSERT INTO right_now_intents (user_id, body, expires_at)
           VALUES ($1, $2, $3)
           RETURNING id"#,
        user_id,
        body,
        expires_at
    )
    .fetch_one(pool)
    .await?;
    Ok(row.id)
}

/// List active (non-expired) intents across all users, ordered by created_at DESC.
/// `limit` caps the number of rows returned.
pub async fn list_nearby_intents(
    pool: &Pool,
    now: time::OffsetDateTime,
    limit: i64,
) -> anyhow::Result<Vec<IntentRow>> {
    let rows = sqlx::query_as!(
        IntentRow,
        r#"SELECT id, user_id, body, expires_at, created_at
           FROM right_now_intents
           WHERE expires_at > $1
           ORDER BY created_at DESC
           LIMIT $2"#,
        now,
        limit
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Delete a Right Now intent owned by the user. No-op if not owned / not found.
pub async fn delete_intent(
    pool: &Pool,
    user_id: Uuid,
    intent_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"DELETE FROM right_now_intents WHERE id = $1 AND user_id = $2"#,
        intent_id,
        user_id
    )
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Active sessions (refresh_tokens, multi-instance)
// ---------------------------------------------------------------------------

/// List a user's non-revoked, non-expired refresh tokens (sessions).
pub async fn list_active_sessions(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Vec<SessionRow>> {
    let now = time::OffsetDateTime::now_utc();
    let rows = sqlx::query_as!(
        SessionRow,
        r#"SELECT id, device_id, issued_at, expires_at, revoked_at
           FROM refresh_tokens
           WHERE user_id = $1
             AND revoked_at IS NULL
             AND expires_at > $2
           ORDER BY issued_at DESC"#,
        user_id,
        now
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Revoke a specific session (refresh token) owned by the user.
pub async fn revoke_session(
    pool: &Pool,
    user_id: Uuid,
    session_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"UPDATE refresh_tokens
           SET revoked_at = now()
           WHERE id = $1
             AND user_id = $2
             AND revoked_at IS NULL"#,
        session_id,
        user_id
    )
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Screenshot alerts
// ---------------------------------------------------------------------------

/// Log a screenshot alert for a (user, conversation) pair.
/// Returns the new alert id.
pub async fn log_screenshot_alert(
    pool: &Pool,
    user_id: Uuid,
    conversation_id: Uuid,
) -> anyhow::Result<Uuid> {
    let row = sqlx::query!(
        r#"INSERT INTO screenshot_alerts (user_id, conversation_id)
           VALUES ($1, $2)
           RETURNING id"#,
        user_id,
        conversation_id
    )
    .fetch_one(pool)
    .await?;
    Ok(row.id)
}

/// List all screenshot alerts for a user, most recent first.
pub async fn list_screenshot_alerts(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Vec<AlertRow>> {
    let rows = sqlx::query_as!(
        AlertRow,
        r#"SELECT id, user_id, conversation_id, reported_at
           FROM screenshot_alerts
           WHERE user_id = $1
           ORDER BY reported_at DESC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// Friendly reminder delay
// ---------------------------------------------------------------------------

/// Upsert the user's idle reminder hours. NULL clears the setting.
pub async fn set_idle_reminder_hours(
    pool: &Pool,
    user_id: Uuid,
    hours: Option<i32>,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"INSERT INTO profiles (user_id, idle_reminder_hours)
           VALUES ($1, $2)
           ON CONFLICT (user_id) DO UPDATE SET
             idle_reminder_hours = EXCLUDED.idle_reminder_hours"#,
        user_id,
        hours
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// Get the user's idle reminder hours setting, if any.
pub async fn get_idle_reminder_hours(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Option<i32>> {
    let row = sqlx::query!(
        r#"SELECT idle_reminder_hours
           FROM profiles
           WHERE user_id = $1"#,
        user_id
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.and_then(|r| r.idle_reminder_hours))
}
