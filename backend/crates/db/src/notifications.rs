use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::Pool;

// ---------------------------------------------------------------------------
// Device registration
// ---------------------------------------------------------------------------

/// Row from the `devices` table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub platform: Option<String>,
    pub push_token: Option<String>,
    pub last_seen_at: Option<time::OffsetDateTime>,
    pub created_at: time::OffsetDateTime,
}

/// Register (upsert) a device token for a user.
/// Returns the device ID (new or existing).
pub async fn register_device(
    pool: &Pool,
    user_id: Uuid,
    push_token: &str,
    platform: &str,
) -> anyhow::Result<Uuid> {
    // Upsert by (user_id, push_token), update platform and last_seen_at
    let row = sqlx::query!(
        r#"INSERT INTO devices (user_id, push_token, platform, last_seen_at)
           VALUES ($1, $2, $3, now())
           ON CONFLICT (user_id, push_token) DO UPDATE SET
             platform = COALESCE($3, devices.platform),
             last_seen_at = now()
           RETURNING id"#,
        user_id,
        push_token,
        platform,
    )
    .fetch_one(pool)
    .await?;
    Ok(row.id)
}

/// List all device tokens for a user.
pub async fn list_user_devices(pool: &Pool, user_id: Uuid) -> anyhow::Result<Vec<DeviceRow>> {
    let rows = sqlx::query_as!(
        DeviceRow,
        r#"SELECT id, user_id, platform, push_token, last_seen_at, created_at
           FROM devices
           WHERE user_id = $1
           ORDER BY created_at DESC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// Notification preferences
// ---------------------------------------------------------------------------

/// Default notification preferences.
pub fn default_notification_prefs() -> serde_json::Value {
    serde_json::json!({
        "new_messages": true,
        "new_taps": true,
        "promotions": false
    })
}

/// Get notification preferences for a user.
/// Falls back to defaults if no profile row exists or prefs are null.
pub async fn get_notification_prefs(pool: &Pool, user_id: Uuid) -> anyhow::Result<serde_json::Value> {
    let row = sqlx::query!(
        r#"SELECT notification_prefs FROM profiles WHERE user_id = $1"#,
        user_id
    )
    .fetch_optional(pool)
    .await?;

    match row {
        Some(r) => Ok(r.notification_prefs.unwrap_or_else(default_notification_prefs)),
        None => Ok(default_notification_prefs()),
    }
}

/// Update notification preferences for a user.
/// Ensures a profiles row exists (upserts if not).
pub async fn update_notification_prefs(
    pool: &Pool,
    user_id: Uuid,
    prefs: &serde_json::Value,
) -> anyhow::Result<()> {
    // Ensure profiles row exists first
    sqlx::query!(
        r#"INSERT INTO profiles (user_id) VALUES ($1)
           ON CONFLICT (user_id) DO NOTHING"#,
        user_id
    )
    .execute(pool)
    .await?;

    sqlx::query!(
        r#"UPDATE profiles SET notification_prefs = $1 WHERE user_id = $2"#,
        prefs,
        user_id,
    )
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// FCM push sending stub
// ---------------------------------------------------------------------------

use std::collections::HashMap;

/// Send a push notification to a user's devices.
///
/// TODO: Implement real FCM HTTP v1 API call using Firebase Admin credentials.
/// 1. Load service account from firebase/ directory or FIREBASE_SERVICE_ACCOUNT env var
/// 2. Get OAuth2 token
/// 3. POST to https://fcm.googleapis.com/v1/projects/foxy-85ecb/messages:send
///
/// For now, logs the notification via tracing::info!.
pub async fn send_push_notification(
    user_id: Uuid,
    title: &str,
    body: &str,
    data: Option<HashMap<String, String>>,
) {
    let _ = (user_id, title, body, data);
    tracing::info!(%user_id, %title, %body, "push notification (stub)");
}
