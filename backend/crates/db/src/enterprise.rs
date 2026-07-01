//! AD7 — Enterprise catalog: experiments, i18n, CMS, campaigns,
//! abuse rules, API keys, webhooks, config rollback queries.
//!
//! Tables in `0017_admin_ad7_enterprise.sql`.

use crate::Pool;
use serde_json::Value as JsonValue;
use time::OffsetDateTime;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Experiments
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct ExperimentRow {
    pub id: Uuid,
    pub key: String,
    pub name: String,
    pub description: Option<String>,
    pub variants: JsonValue,
    pub enabled: bool,
    pub start_at: Option<OffsetDateTime>,
    pub end_at: Option<OffsetDateTime>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

pub async fn list_experiments(pool: &Pool) -> anyhow::Result<Vec<ExperimentRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, key, name, description, variants, enabled, start_at, end_at,
                  created_at, updated_at
           FROM experiments
           ORDER BY key"#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| ExperimentRow {
            id: r.get("id"),
            key: r.get("key"),
            name: r.get("name"),
            description: r.get("description"),
            variants: r.get("variants"),
            enabled: r.get("enabled"),
            start_at: r.get("start_at"),
            end_at: r.get("end_at"),
            created_at: r.get("created_at"),
            updated_at: r.get("updated_at"),
        })
        .collect())
}

#[allow(clippy::too_many_arguments)]
pub async fn upsert_experiment(
    pool: &Pool,
    key: &str,
    name: &str,
    description: Option<&str>,
    variants: &JsonValue,
    enabled: bool,
    start_at: Option<OffsetDateTime>,
    end_at: Option<OffsetDateTime>,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO experiments (key, name, description, variants, enabled, start_at, end_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
           ON CONFLICT (key) DO UPDATE SET
             name = EXCLUDED.name,
             description = EXCLUDED.description,
             variants = EXCLUDED.variants,
             enabled = EXCLUDED.enabled,
             start_at = EXCLUDED.start_at,
             end_at = EXCLUDED.end_at,
             updated_at = NOW()"#,
    )
    .bind(key)
    .bind(name)
    .bind(description)
    .bind(variants)
    .bind(enabled)
    .bind(start_at)
    .bind(end_at)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn delete_experiment(pool: &Pool, key: &str) -> anyhow::Result<()> {
    sqlx::query("DELETE FROM experiments WHERE key = $1")
        .bind(key)
        .execute(pool)
        .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Translations (i18n)
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct TranslationRow {
    pub id: Uuid,
    pub locale: String,
    pub key: String,
    pub value: String,
}

pub async fn list_translations(
    pool: &Pool,
    locale: Option<&str>,
) -> anyhow::Result<Vec<TranslationRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, locale, key, value
           FROM translations
           WHERE ($1::text IS NULL OR locale = $1)
           ORDER BY locale, key"#,
    )
    .bind(locale)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| TranslationRow {
            id: r.get("id"),
            locale: r.get("locale"),
            key: r.get("key"),
            value: r.get("value"),
        })
        .collect())
}

pub async fn upsert_translation(
    pool: &Pool,
    locale: &str,
    key: &str,
    value: &str,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO translations (locale, key, value)
           VALUES ($1, $2, $3)
           ON CONFLICT (locale, key) DO UPDATE SET
             value = EXCLUDED.value"#,
    )
    .bind(locale)
    .bind(key)
    .bind(value)
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// CMS content
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct CmsContentRow {
    pub id: Uuid,
    pub key: String,
    pub content_type: String,
    pub title: Option<String>,
    pub body: String,
    pub locale: String,
    pub active: bool,
    pub publish_at: Option<OffsetDateTime>,
    pub expire_at: Option<OffsetDateTime>,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
    pub updated_by: Option<Uuid>,
}

pub async fn list_cms_content(
    pool: &Pool,
    locale: Option<&str>,
) -> anyhow::Result<Vec<CmsContentRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, key, content_type, title, body, locale, active,
                  publish_at, expire_at, created_at, updated_at, updated_by
           FROM cms_content
           WHERE ($1::text IS NULL OR locale = $1)
           ORDER BY key"#,
    )
    .bind(locale)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| CmsContentRow {
            id: r.get("id"),
            key: r.get("key"),
            content_type: r.get("content_type"),
            title: r.get("title"),
            body: r.get("body"),
            locale: r.get("locale"),
            active: r.get("active"),
            publish_at: r.get("publish_at"),
            expire_at: r.get("expire_at"),
            created_at: r.get("created_at"),
            updated_at: r.get("updated_at"),
            updated_by: r.get("updated_by"),
        })
        .collect())
}

#[allow(clippy::too_many_arguments)]
pub async fn upsert_cms_content(
    pool: &Pool,
    key: &str,
    content_type: &str,
    title: Option<&str>,
    body: &str,
    locale: &str,
    active: bool,
    publish_at: Option<OffsetDateTime>,
    expire_at: Option<OffsetDateTime>,
    updated_by: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO cms_content (key, content_type, title, body, locale, active, publish_at, expire_at, updated_by, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
           ON CONFLICT (key) DO UPDATE SET
             content_type = EXCLUDED.content_type,
             title = EXCLUDED.title,
             body = EXCLUDED.body,
             locale = EXCLUDED.locale,
             active = EXCLUDED.active,
             publish_at = EXCLUDED.publish_at,
             expire_at = EXCLUDED.expire_at,
             updated_by = EXCLUDED.updated_by,
             updated_at = NOW()"#,
    )
    .bind(key)
    .bind(content_type)
    .bind(title)
    .bind(body)
    .bind(locale)
    .bind(active)
    .bind(publish_at)
    .bind(expire_at)
    .bind(updated_by)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn delete_cms_content(pool: &Pool, key: &str) -> anyhow::Result<()> {
    sqlx::query("DELETE FROM cms_content WHERE key = $1")
        .bind(key)
        .execute(pool)
        .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Legal document versions
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct LegalDocRow {
    pub id: Uuid,
    pub doc_type: String,
    pub version: String,
    pub title: String,
    pub body: String,
    pub published_at: OffsetDateTime,
    pub created_by: Uuid,
}

pub async fn list_legal_docs(pool: &Pool) -> anyhow::Result<Vec<LegalDocRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, doc_type, version, title, body, published_at, created_by
           FROM legal_doc_versions
           ORDER BY doc_type, published_at DESC"#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| LegalDocRow {
            id: r.get("id"),
            doc_type: r.get("doc_type"),
            version: r.get("version"),
            title: r.get("title"),
            body: r.get("body"),
            published_at: r.get("published_at"),
            created_by: r.get("created_by"),
        })
        .collect())
}

pub async fn create_legal_doc(
    pool: &Pool,
    doc_type: &str,
    version: &str,
    title: &str,
    body: &str,
    created_by: Uuid,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO legal_doc_versions (doc_type, version, title, body, created_by)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id"#,
    )
    .bind(doc_type)
    .bind(version)
    .bind(title)
    .bind(body)
    .bind(created_by)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

// ---------------------------------------------------------------------------
// Campaigns
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct CampaignRow {
    pub id: Uuid,
    pub name: String,
    pub campaign_type: String,
    pub title: Option<String>,
    pub body: String,
    pub target_segment: Option<JsonValue>,
    pub scheduled_at: Option<OffsetDateTime>,
    pub sent_at: Option<OffsetDateTime>,
    pub status: String,
    pub created_at: OffsetDateTime,
    pub created_by: Option<Uuid>,
}

pub async fn list_campaigns(
    pool: &Pool,
    status: Option<&str>,
) -> anyhow::Result<Vec<CampaignRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, name, campaign_type, title, body, target_segment,
                  scheduled_at, sent_at, status, created_at, created_by
           FROM campaigns
           WHERE ($1::text IS NULL OR status = $1)
           ORDER BY created_at DESC"#,
    )
    .bind(status)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| CampaignRow {
            id: r.get("id"),
            name: r.get("name"),
            campaign_type: r.get("campaign_type"),
            title: r.get("title"),
            body: r.get("body"),
            target_segment: r.get("target_segment"),
            scheduled_at: r.get("scheduled_at"),
            sent_at: r.get("sent_at"),
            status: r.get("status"),
            created_at: r.get("created_at"),
            created_by: r.get("created_by"),
        })
        .collect())
}

#[allow(clippy::too_many_arguments)]
pub async fn create_campaign(
    pool: &Pool,
    name: &str,
    campaign_type: &str,
    title: Option<&str>,
    body: &str,
    target_segment: Option<&JsonValue>,
    scheduled_at: Option<OffsetDateTime>,
    created_by: Uuid,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO campaigns (name, campaign_type, title, body, target_segment, scheduled_at, created_by)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id"#,
    )
    .bind(name)
    .bind(campaign_type)
    .bind(title)
    .bind(body)
    .bind(target_segment)
    .bind(scheduled_at)
    .bind(created_by)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

pub async fn get_campaign(pool: &Pool, id: Uuid) -> anyhow::Result<CampaignRow> {
    use sqlx::Row;

    let row = sqlx::query(
        r#"SELECT id, name, campaign_type, title, body, target_segment,
                  scheduled_at, sent_at, status, created_at, created_by
           FROM campaigns
           WHERE id = $1"#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    match row {
        Some(r) => Ok(CampaignRow {
            id: r.get("id"),
            name: r.get("name"),
            campaign_type: r.get("campaign_type"),
            title: r.get("title"),
            body: r.get("body"),
            target_segment: r.get("target_segment"),
            scheduled_at: r.get("scheduled_at"),
            sent_at: r.get("sent_at"),
            status: r.get("status"),
            created_at: r.get("created_at"),
            created_by: r.get("created_by"),
        }),
        None => anyhow::bail!("campaign not found"),
    }
}

/// Get all user IDs, optionally filtered by a list of user_ids from target_segment.
/// If user_ids is empty, returns all user IDs.
pub async fn get_campaign_target_user_ids(
    pool: &Pool,
    user_ids: &[Uuid],
) -> anyhow::Result<Vec<Uuid>> {
    if user_ids.is_empty() {
        // Return all user IDs
        let rows = sqlx::query_scalar::<_, Uuid>(
            r#"SELECT id FROM users ORDER BY id"#,
        )
        .fetch_all(pool)
        .await?;
        Ok(rows)
    } else {
        // Filter to only the specified user IDs that exist
        let rows = sqlx::query_scalar::<_, Uuid>(
            r#"SELECT id FROM users WHERE id = ANY($1) ORDER BY id"#,
        )
        .bind(user_ids)
        .fetch_all(pool)
        .await?;
        Ok(rows)
    }
}

pub async fn update_campaign_status(
    pool: &Pool,
    id: Uuid,
    status: &str,
) -> anyhow::Result<()> {
    let updated = sqlx::query(
        r#"UPDATE campaigns SET status = $1, sent_at = CASE WHEN $1 = 'sent' THEN NOW() ELSE sent_at END WHERE id = $2"#,
    )
    .bind(status)
    .bind(id)
    .execute(pool)
    .await?
    .rows_affected();

    if updated == 0 {
        anyhow::bail!("campaign not found");
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Notification templates
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct NotificationTemplateRow {
    pub id: Uuid,
    pub key: String,
    pub name: String,
    pub channel: String,
    pub title_template: String,
    pub body_template: String,
    pub active: bool,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

pub async fn list_notification_templates(pool: &Pool) -> anyhow::Result<Vec<NotificationTemplateRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, key, name, channel, title_template, body_template, active,
                  created_at, updated_at
           FROM notification_templates
           ORDER BY key"#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| NotificationTemplateRow {
            id: r.get("id"),
            key: r.get("key"),
            name: r.get("name"),
            channel: r.get("channel"),
            title_template: r.get("title_template"),
            body_template: r.get("body_template"),
            active: r.get("active"),
            created_at: r.get("created_at"),
            updated_at: r.get("updated_at"),
        })
        .collect())
}

pub async fn upsert_notification_template(
    pool: &Pool,
    key: &str,
    name: &str,
    channel: &str,
    title_template: &str,
    body_template: &str,
    active: bool,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO notification_templates (key, name, channel, title_template, body_template, active, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, NOW())
           ON CONFLICT (key) DO UPDATE SET
             name = EXCLUDED.name,
             channel = EXCLUDED.channel,
             title_template = EXCLUDED.title_template,
             body_template = EXCLUDED.body_template,
             active = EXCLUDED.active,
             updated_at = NOW()"#,
    )
    .bind(key)
    .bind(name)
    .bind(channel)
    .bind(title_template)
    .bind(body_template)
    .bind(active)
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Abuse rules
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct AbuseRuleRow {
    pub id: Uuid,
    pub name: String,
    pub rule_type: String,
    pub config: JsonValue,
    pub action: String,
    pub enabled: bool,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
}

pub async fn list_abuse_rules(pool: &Pool) -> anyhow::Result<Vec<AbuseRuleRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, name, rule_type, config, action, enabled, created_at, updated_at
           FROM abuse_rules
           ORDER BY name"#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| AbuseRuleRow {
            id: r.get("id"),
            name: r.get("name"),
            rule_type: r.get("rule_type"),
            config: r.get("config"),
            action: r.get("action"),
            enabled: r.get("enabled"),
            created_at: r.get("created_at"),
            updated_at: r.get("updated_at"),
        })
        .collect())
}

#[allow(clippy::too_many_arguments)]
pub async fn upsert_abuse_rule(
    pool: &Pool,
    name: &str,
    rule_type: &str,
    config: &JsonValue,
    action: &str,
    enabled: bool,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO abuse_rules (name, rule_type, config, action, enabled, updated_at)
           VALUES ($1, $2, $3, $4, $5, NOW())
           ON CONFLICT (id) DO UPDATE SET
             name = EXCLUDED.name,
             rule_type = EXCLUDED.rule_type,
             config = EXCLUDED.config,
             action = EXCLUDED.action,
             enabled = EXCLUDED.enabled,
             updated_at = NOW()"#,
    )
    .bind(name)
    .bind(rule_type)
    .bind(config)
    .bind(action)
    .bind(enabled)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn delete_abuse_rule(pool: &Pool, id: Uuid) -> anyhow::Result<()> {
    sqlx::query("DELETE FROM abuse_rules WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// API keys
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct ApiKeyRow {
    pub id: Uuid,
    pub name: String,
    pub key_prefix: String,
    pub permissions: Vec<String>,
    pub rate_limit_rps: i32,
    pub active: bool,
    pub created_by: Option<Uuid>,
    pub last_used_at: Option<OffsetDateTime>,
    pub created_at: OffsetDateTime,
    pub expires_at: Option<OffsetDateTime>,
}

pub async fn list_api_keys(pool: &Pool) -> anyhow::Result<Vec<ApiKeyRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, name, key_prefix, permissions, rate_limit_rps, active,
                  created_by, last_used_at, created_at, expires_at
           FROM api_keys
           ORDER BY created_at DESC"#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| ApiKeyRow {
            id: r.get("id"),
            name: r.get("name"),
            key_prefix: r.get("key_prefix"),
            permissions: r.get("permissions"),
            rate_limit_rps: r.get("rate_limit_rps"),
            active: r.get("active"),
            created_by: r.get("created_by"),
            last_used_at: r.get("last_used_at"),
            created_at: r.get("created_at"),
            expires_at: r.get("expires_at"),
        })
        .collect())
}

pub async fn create_api_key(
    pool: &Pool,
    name: &str,
    key_hash: &str,
    key_prefix: &str,
    permissions: &[String],
    rate_limit_rps: i32,
    created_by: Uuid,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO api_keys (name, key_hash, key_prefix, permissions, rate_limit_rps, created_by)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING id"#,
    )
    .bind(name)
    .bind(key_hash)
    .bind(key_prefix)
    .bind(permissions)
    .bind(rate_limit_rps)
    .bind(created_by)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

pub async fn revoke_api_key(pool: &Pool, id: Uuid) -> anyhow::Result<()> {
    let updated = sqlx::query("UPDATE api_keys SET active = false WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await?
        .rows_affected();

    if updated == 0 {
        anyhow::bail!("api key not found");
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Webhook subscriptions
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct WebhookRow {
    pub id: Uuid,
    pub name: String,
    pub url: String,
    pub events: Vec<String>,
    pub active: bool,
    pub created_at: OffsetDateTime,
    pub updated_at: OffsetDateTime,
    pub created_by: Option<Uuid>,
}

pub async fn list_webhooks(pool: &Pool) -> anyhow::Result<Vec<WebhookRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, name, url, events, active, created_at, updated_at, created_by
           FROM webhook_subscriptions
           ORDER BY created_at DESC"#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| WebhookRow {
            id: r.get("id"),
            name: r.get("name"),
            url: r.get("url"),
            events: r.get("events"),
            active: r.get("active"),
            created_at: r.get("created_at"),
            updated_at: r.get("updated_at"),
            created_by: r.get("created_by"),
        })
        .collect())
}

pub async fn create_webhook(
    pool: &Pool,
    name: &str,
    url: &str,
    events: &[String],
    secret: Option<&str>,
    created_by: Uuid,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO webhook_subscriptions (name, url, events, secret, created_by)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id"#,
    )
    .bind(name)
    .bind(url)
    .bind(events)
    .bind(secret)
    .bind(created_by)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

pub async fn delete_webhook(pool: &Pool, id: Uuid) -> anyhow::Result<()> {
    let updated = sqlx::query("DELETE FROM webhook_subscriptions WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await?
        .rows_affected();

    if updated == 0 {
        anyhow::bail!("webhook not found");
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Config versions
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct ConfigVersionRow {
    pub id: Uuid,
    pub entity_type: String,
    pub entity_key: String,
    pub previous_value: JsonValue,
    pub new_value: JsonValue,
    pub changed_by: Uuid,
    pub rolled_back: bool,
    pub created_at: OffsetDateTime,
}

pub async fn list_config_versions(
    pool: &Pool,
    entity_type: Option<&str>,
    limit: i64,
) -> anyhow::Result<Vec<ConfigVersionRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, entity_type, entity_key, previous_value, new_value,
                  changed_by, rolled_back, created_at
           FROM config_versions
           WHERE ($1::text IS NULL OR entity_type = $1)
           ORDER BY created_at DESC
           LIMIT $2"#,
    )
    .bind(entity_type)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .iter()
        .map(|r| ConfigVersionRow {
            id: r.get("id"),
            entity_type: r.get("entity_type"),
            entity_key: r.get("entity_key"),
            previous_value: r.get("previous_value"),
            new_value: r.get("new_value"),
            changed_by: r.get("changed_by"),
            rolled_back: r.get("rolled_back"),
            created_at: r.get("created_at"),
        })
        .collect())
}

pub async fn create_config_version(
    pool: &Pool,
    entity_type: &str,
    entity_key: &str,
    previous_value: &JsonValue,
    new_value: &JsonValue,
    changed_by: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO config_versions (entity_type, entity_key, previous_value, new_value, changed_by)
           VALUES ($1, $2, $3, $4, $5)"#,
    )
    .bind(entity_type)
    .bind(entity_key)
    .bind(previous_value)
    .bind(new_value)
    .bind(changed_by)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn rollback_config_version(
    pool: &Pool,
    version_id: Uuid,
    _staff_id: Uuid,
) -> anyhow::Result<()> {
    use sqlx::Row;

    // Read the version entry
    let version = sqlx::query(
        r#"SELECT entity_type, entity_key, previous_value, rolled_back
           FROM config_versions
           WHERE id = $1"#,
    )
    .bind(version_id)
    .fetch_optional(pool)
    .await?
    .ok_or_else(|| anyhow::anyhow!("config version not found"))?;

    let entity_type: String = version.get("entity_type");
    let entity_key: String = version.get("entity_key");
    let previous_value: JsonValue = version.get("previous_value");
    let rolled_back: bool = version.get("rolled_back");

    if rolled_back {
        anyhow::bail!("config version already rolled back");
    }

    // Re-apply the previous value to the appropriate table
    match entity_type.as_str() {
        "feature_flag" => {
            let updated = sqlx::query(
                "UPDATE feature_flags SET value = $1, updated_at = NOW() WHERE key = $2",
            )
            .bind(&previous_value)
            .bind(&entity_key)
            .execute(pool)
            .await?
            .rows_affected();
            if updated == 0 {
                anyhow::bail!("feature flag '{entity_key}' not found");
            }
        }
        "app_config" => {
            let updated = sqlx::query(
                "UPDATE app_config SET value = $1, updated_at = NOW() WHERE key = $2",
            )
            .bind(&previous_value)
            .bind(&entity_key)
            .execute(pool)
            .await?
            .rows_affected();
            if updated == 0 {
                anyhow::bail!("app_config '{entity_key}' not found");
            }
        }
        "plan" => {
            let updated = sqlx::query(
                "UPDATE plans SET description = $1, updated_at = NOW() WHERE code = $2",
            )
            .bind(previous_value.get("description").and_then(|v| v.as_str()))
            .bind(&entity_key)
            .execute(pool)
            .await?
            .rows_affected();
            if updated == 0 {
                anyhow::bail!("plan '{entity_key}' not found");
            }
        }
        other => {
            anyhow::bail!("rollback not supported for entity type '{other}'");
        }
    }

    // Mark rolled back
    sqlx::query(
        "UPDATE config_versions SET rolled_back = true WHERE id = $1",
    )
    .bind(version_id)
    .execute(pool)
    .await?;

    Ok(())
}
