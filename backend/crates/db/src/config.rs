//! AD5 — Feature flags, app config, analytics queries.
//!
//! Tables: `feature_flags`, `app_config` in 0015_admin_ad5_config.sql.

use crate::Pool;
use serde_json::Value as JsonValue;
use time::OffsetDateTime;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Feature flags
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct FeatureFlag {
    pub key: String,
    pub value: JsonValue,
    pub description: Option<String>,
    pub enabled: bool,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
    pub updated_by: Option<Uuid>,
}

pub async fn list_feature_flags(pool: &Pool) -> anyhow::Result<Vec<FeatureFlag>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT key, value, description, enabled, created_at, updated_at, updated_by
           FROM feature_flags
           ORDER BY key"#,
    )
    .fetch_all(pool)
    .await?;

    let flags = rows
        .iter()
        .map(|r| FeatureFlag {
            key: r.get("key"),
            value: r.get("value"),
            description: r.get("description"),
            enabled: r.get("enabled"),
            created_at: r.get("created_at"),
            updated_at: r.get("updated_at"),
            updated_by: r.get("updated_by"),
        })
        .collect();

    Ok(flags)
}

pub async fn get_feature_flag(pool: &Pool, key: &str) -> anyhow::Result<Option<FeatureFlag>> {
    use sqlx::Row;

    let row = sqlx::query(
        r#"SELECT key, value, description, enabled, created_at, updated_at, updated_by
           FROM feature_flags
           WHERE key = $1"#,
    )
    .bind(key)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| FeatureFlag {
        key: r.get("key"),
        value: r.get("value"),
        description: r.get("description"),
        enabled: r.get("enabled"),
        created_at: r.get("created_at"),
        updated_at: r.get("updated_at"),
        updated_by: r.get("updated_by"),
    }))
}

pub async fn upsert_feature_flag(
    pool: &Pool,
    key: &str,
    value: &JsonValue,
    description: Option<&str>,
    enabled: bool,
    updated_by: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO feature_flags (key, value, description, enabled, updated_by, updated_at)
           VALUES ($1, $2, $3, $4, $5, NOW())
           ON CONFLICT (key) DO UPDATE SET
             value = EXCLUDED.value,
             description = EXCLUDED.description,
             enabled = EXCLUDED.enabled,
             updated_by = EXCLUDED.updated_by,
             updated_at = NOW()"#,
    )
    .bind(key)
    .bind(value)
    .bind(description)
    .bind(enabled)
    .bind(updated_by)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn delete_feature_flag(pool: &Pool, key: &str) -> anyhow::Result<()> {
    sqlx::query("DELETE FROM feature_flags WHERE key = $1")
        .bind(key)
        .execute(pool)
        .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// App config
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct AppConfigEntry {
    pub key: String,
    pub value: JsonValue,
    pub description: Option<String>,
    pub updated_at: OffsetDateTime,
    pub updated_by: Option<Uuid>,
}

pub async fn list_app_config(pool: &Pool) -> anyhow::Result<Vec<AppConfigEntry>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT key, value, description, updated_at, updated_by
           FROM app_config
           ORDER BY key"#,
    )
    .fetch_all(pool)
    .await?;

    let configs = rows
        .iter()
        .map(|r| AppConfigEntry {
            key: r.get("key"),
            value: r.get("value"),
            description: r.get("description"),
            updated_at: r.get("updated_at"),
            updated_by: r.get("updated_by"),
        })
        .collect();

    Ok(configs)
}

pub async fn upsert_app_config(
    pool: &Pool,
    key: &str,
    value: &JsonValue,
    updated_by: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO app_config (key, value, updated_by, updated_at)
           VALUES ($1, $2, $3, NOW())
           ON CONFLICT (key) DO UPDATE SET
             value = EXCLUDED.value,
             updated_by = EXCLUDED.updated_by,
             updated_at = NOW()"#,
    )
    .bind(key)
    .bind(value)
    .bind(updated_by)
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Analytics overview
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct AnalyticsOverview {
    pub total_users: i64,
    pub active_today: i64,
    pub banned_users: i64,
    pub suspended_users: i64,
    pub premium_users: i64,
    pub new_users_today: i64,
}

pub async fn get_analytics_overview(pool: &Pool) -> anyhow::Result<AnalyticsOverview> {
    use sqlx::Row;

    let row = sqlx::query(
        r#"SELECT
            (SELECT COUNT(*) FROM users)::bigint as total_users,
            (SELECT COUNT(DISTINCT user_id) FROM locations WHERE updated_at > NOW() - '24h'::interval)::bigint as active_today,
            (SELECT COUNT(*) FROM users WHERE status = 'banned')::bigint as banned_users,
            (SELECT COUNT(*) FROM users WHERE status = 'suspended')::bigint as suspended_users,
            (SELECT COUNT(DISTINCT user_id) FROM subscriptions WHERE tier != 'free' AND status = 'active')::bigint as premium_users,
            (SELECT COUNT(*) FROM users WHERE created_at > NOW() - INTERVAL '1 day')::bigint as new_users_today"#,
    )
    .fetch_one(pool)
    .await?;

    Ok(AnalyticsOverview {
        total_users: row.get("total_users"),
        active_today: row.get("active_today"),
        banned_users: row.get("banned_users"),
        suspended_users: row.get("suspended_users"),
        premium_users: row.get("premium_users"),
        new_users_today: row.get("new_users_today"),
    })
}
