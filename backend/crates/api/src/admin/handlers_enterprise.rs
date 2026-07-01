//! AD7 — Enterprise catalog handlers.
//!
//! Split into its own file because `handlers.rs` was already ~1800 lines.
//!
//! Endpoints: experiments, i18n, CMS, legal docs, campaigns,
//! notification templates, abuse rules, API keys, webhooks, config rollback.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::admin::audit::{AuditJustification, AuditTarget};
use crate::admin::extractors::StaffAuth;
use crate::AppState;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

fn rbac_check(staff: &StaffAuth, permission: &str) -> Result<(), StatusCode> {
    if !staff.0.permissions.iter().any(|p| p == permission) {
        return Err(StatusCode::FORBIDDEN);
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Request types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct UpsertExperimentRequest {
    pub name: String,
    pub description: Option<String>,
    pub variants: Value,
    pub enabled: bool,
    pub start_at: Option<String>,  // ISO-8601
    pub end_at: Option<String>,    // ISO-8601
}

fn parse_iso(s: Option<&str>) -> Result<Option<OffsetDateTime>, StatusCode> {
    match s {
        None | Some("") => Ok(None),
        Some(v) => OffsetDateTime::parse(v, &time::format_description::well_known::Rfc3339)
            .map(Some)
            .map_err(|_| StatusCode::BAD_REQUEST),
    }
}

#[derive(Deserialize)]
pub struct UpsertTranslationRequest {
    pub locale: String,
    pub key: String,
    pub value: String,
}

#[derive(Deserialize)]
pub struct UpsertCmsRequest {
    pub content_type: Option<String>,
    pub title: Option<String>,
    pub body: String,
    pub locale: Option<String>,
    pub active: Option<bool>,
    pub publish_at: Option<String>,
    pub expire_at: Option<String>,
}

#[derive(Deserialize)]
pub struct CreateLegalDocRequest {
    pub doc_type: String,
    pub version: String,
    pub title: String,
    pub body: String,
}

#[derive(Deserialize)]
pub struct CreateCampaignRequest {
    pub name: String,
    pub campaign_type: String,
    pub title: Option<String>,
    pub body: String,
    pub target_segment: Option<Value>,
    pub scheduled_at: Option<String>,
}

#[derive(Deserialize)]
pub struct UpsertNotificationTemplateRequest {
    pub key: String,
    pub name: String,
    pub channel: String,
    pub title_template: String,
    pub body_template: String,
    pub active: Option<bool>,
}

#[derive(Deserialize)]
pub struct UpsertAbuseRuleRequest {
    pub name: String,
    pub rule_type: String,
    pub config: Value,
    pub action: String,
    pub enabled: Option<bool>,
}

#[derive(Deserialize)]
pub struct CreateApiKeyRequest {
    pub name: String,
    pub permissions: Vec<String>,
    pub rate_limit_rps: Option<i32>,
}

#[derive(Serialize)]
pub struct CreateApiKeyResponse {
    pub id: Uuid,
    pub name: String,
    pub key_prefix: String,
    pub api_key: String,
    pub permissions: Vec<String>,
    pub rate_limit_rps: i32,
}

#[derive(Deserialize)]
pub struct CreateWebhookRequest {
    pub name: String,
    pub url: String,
    pub events: Vec<String>,
    pub secret: Option<String>,
}

#[derive(Deserialize)]
pub struct LocaleQuery {
    pub locale: Option<String>,
}

#[derive(Deserialize)]
pub struct StatusQuery {
    pub status: Option<String>,
}

#[derive(Deserialize)]
pub struct ConfigHistoryQuery {
    pub entity_type: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Deserialize)]
pub struct CampaignSendRequest {
    pub _justification: Option<String>,
}

#[derive(Deserialize)]
pub struct RollbackRequest {
    pub _justification: Option<String>,
}

// ===========================================================================
// Experiments
// ===========================================================================

/// GET /admin/experiments
pub async fn list_experiments(
    State(state): State<AppState>,
    staff: StaffAuth,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "experiments.read")?;

    let rows = db::enterprise::list_experiments(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let experiments: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "key": r.key,
                "name": r.name,
                "description": r.description,
                "variants": r.variants,
                "enabled": r.enabled,
                "start_at": r.start_at.map(|t| t.to_string()),
                "end_at": r.end_at.map(|t| t.to_string()),
                "created_at": r.created_at.to_string(),
                "updated_at": r.updated_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({ "experiments": experiments })))
}

/// POST /admin/experiments
pub async fn upsert_experiment(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<UpsertExperimentRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "experiments.write")?;

    let key = body.name.to_lowercase().replace(' ', "_");
    let start_at = parse_iso(body.start_at.as_deref())?;
    let end_at = parse_iso(body.end_at.as_deref())?;

    db::enterprise::upsert_experiment(
        &state.pool,
        &key,
        &body.name,
        body.description.as_deref(),
        &body.variants,
        body.enabled,
        start_at,
        end_at,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(key.clone()),
        AuditJustification(key.clone()),
        Json(json!({ "key": key, "name": body.name })),
    ))
}

/// DELETE /admin/experiments/:key
pub async fn delete_experiment(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(key): Path<String>,
) -> Result<(AuditTarget, StatusCode), StatusCode> {
    rbac_check(&staff, "experiments.write")?;

    db::enterprise::delete_experiment(&state.pool, &key)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((AuditTarget(key), StatusCode::NO_CONTENT))
}

// ===========================================================================
// i18n / Translations
// ===========================================================================

/// GET /admin/i18n?locale=en
pub async fn list_translations(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<LocaleQuery>,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "cms.read")?;

    let rows = db::enterprise::list_translations(&state.pool, query.locale.as_deref())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let translations: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "locale": r.locale,
                "key": r.key,
                "value": r.value,
            })
        })
        .collect();

    Ok(Json(json!({ "translations": translations })))
}

/// POST /admin/i18n
pub async fn upsert_translation(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<UpsertTranslationRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "cms.write")?;

    db::enterprise::upsert_translation(&state.pool, &body.locale, &body.key, &body.value)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(format!("{}/{}", body.locale, body.key)),
        AuditJustification(body.key.clone()),
        Json(json!({ "locale": body.locale, "key": body.key })),
    ))
}

// ===========================================================================
// CMS
// ===========================================================================

/// GET /admin/cms?locale=en
pub async fn list_cms_content(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<LocaleQuery>,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "cms.read")?;

    let rows = db::enterprise::list_cms_content(&state.pool, query.locale.as_deref())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let items: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "key": r.key,
                "content_type": r.content_type,
                "title": r.title,
                "body": r.body,
                "locale": r.locale,
                "active": r.active,
                "publish_at": r.publish_at.map(|t| t.to_string()),
                "expire_at": r.expire_at.map(|t| t.to_string()),
                "updated_at": r.updated_at.to_string(),
                "updated_by": r.updated_by,
            })
        })
        .collect();

    Ok(Json(json!({ "cms_content": items })))
}

/// POST /admin/cms
pub async fn upsert_cms_content(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(key): Path<String>,
    Json(body): Json<UpsertCmsRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "cms.write")?;

    let publish_at = parse_iso(body.publish_at.as_deref())?;
    let expire_at = parse_iso(body.expire_at.as_deref())?;

    db::enterprise::upsert_cms_content(
        &state.pool,
        &key,
        body.content_type.as_deref().unwrap_or("text"),
        body.title.as_deref(),
        &body.body,
        body.locale.as_deref().unwrap_or("en"),
        body.active.unwrap_or(true),
        publish_at,
        expire_at,
        staff.0.id,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(key.clone()),
        AuditJustification(key.clone()),
        Json(json!({ "key": key })),
    ))
}

/// DELETE /admin/cms/:key
pub async fn delete_cms_content(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(key): Path<String>,
) -> Result<(AuditTarget, StatusCode), StatusCode> {
    rbac_check(&staff, "cms.write")?;

    db::enterprise::delete_cms_content(&state.pool, &key)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((AuditTarget(key), StatusCode::NO_CONTENT))
}

// ===========================================================================
// Legal docs
// ===========================================================================

/// GET /admin/legal-docs
pub async fn list_legal_docs(
    State(state): State<AppState>,
    staff: StaffAuth,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "cms.read")?;

    let rows = db::enterprise::list_legal_docs(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let docs: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "doc_type": r.doc_type,
                "version": r.version,
                "title": r.title,
                "body": r.body,
                "published_at": r.published_at.to_string(),
                "created_by": r.created_by,
            })
        })
        .collect();

    Ok(Json(json!({ "legal_docs": docs })))
}

/// POST /admin/legal-docs
pub async fn create_legal_doc(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<CreateLegalDocRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "cms.write")?;

    let id = db::enterprise::create_legal_doc(
        &state.pool,
        &body.doc_type,
        &body.version,
        &body.title,
        &body.body,
        staff.0.id,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.doc_type.clone()),
        Json(json!({ "id": id, "doc_type": body.doc_type, "version": body.version })),
    ))
}

// ===========================================================================
// Campaigns
// ===========================================================================

/// GET /admin/campaigns?status=draft
pub async fn list_campaigns(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<StatusQuery>,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "campaigns.read")?;

    let rows = db::enterprise::list_campaigns(&state.pool, query.status.as_deref())
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let campaigns: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "name": r.name,
                "campaign_type": r.campaign_type,
                "title": r.title,
                "body": r.body,
                "target_segment": r.target_segment,
                "scheduled_at": r.scheduled_at.map(|t| t.to_string()),
                "sent_at": r.sent_at.map(|t| t.to_string()),
                "status": r.status,
                "created_at": r.created_at.to_string(),
                "created_by": r.created_by,
            })
        })
        .collect();

    Ok(Json(json!({ "campaigns": campaigns })))
}

/// POST /admin/campaigns
pub async fn create_campaign(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<CreateCampaignRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "campaigns.write")?;

    let scheduled_at = parse_iso(body.scheduled_at.as_deref())?;

    let id = db::enterprise::create_campaign(
        &state.pool,
        &body.name,
        &body.campaign_type,
        body.title.as_deref(),
        &body.body,
        body.target_segment.as_ref(),
        scheduled_at,
        staff.0.id,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.name),
        Json(json!({ "id": id, "status": "draft" })),
    ))
}

/// POST /admin/campaigns/:id/send
///
/// Sends push notifications to the campaign's target segment via FCM.
/// Falls back gracefully if FCM is not configured.
pub async fn send_campaign(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
    Json(body): Json<CampaignSendRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "campaigns.write")?;

    // Load campaign details
    let campaign = db::enterprise::get_campaign(&state.pool, id)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    if campaign.campaign_type == "push" {
        // Determine target user IDs from target_segment ({"user_ids": ["uuid", ...]})
        let target_user_ids: Vec<Uuid> = campaign
            .target_segment
            .as_ref()
            .and_then(|seg| seg.get("user_ids"))
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().and_then(|s| Uuid::parse_str(s).ok()))
                    .collect()
            })
            .unwrap_or_default();

        let user_ids = db::enterprise::get_campaign_target_user_ids(&state.pool, &target_user_ids)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

        // Send push via FCM if available
        if let Some(ref fcm) = state.fcm {
            let title = campaign.title.as_deref().unwrap_or("New update");
            let body = &campaign.body;

            for uid in &user_ids {
                if let Err(e) = fcm.send_to_user(&state.pool, *uid, title, body).await {
                    tracing::warn!(user_id = %uid, error = %e, "campaign push failed");
                }
            }

            tracing::info!(
                campaign_id = %id,
                total_users = %user_ids.len(),
                "campaign push sent"
            );
        } else {
            tracing::warn!(campaign_id = %id, "FCM not configured — push not sent");
        }
    }

    // Mark as sent
    db::enterprise::update_campaign_status(&state.pool, id, "sent")
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let justification = body._justification.unwrap_or_else(|| "send campaign".into());
    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(justification),
        Json(json!({ "id": id, "status": "sent" })),
    ))
}

// ===========================================================================
// Notification templates
// ===========================================================================

/// GET /admin/templates
pub async fn list_notification_templates(
    State(state): State<AppState>,
    staff: StaffAuth,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "templates.read")?;

    let rows = db::enterprise::list_notification_templates(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let templates: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "key": r.key,
                "name": r.name,
                "channel": r.channel,
                "title_template": r.title_template,
                "body_template": r.body_template,
                "active": r.active,
                "created_at": r.created_at.to_string(),
                "updated_at": r.updated_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({ "templates": templates })))
}

/// POST /admin/templates
pub async fn upsert_notification_template(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<UpsertNotificationTemplateRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "templates.write")?;

    db::enterprise::upsert_notification_template(
        &state.pool,
        &body.key,
        &body.name,
        &body.channel,
        &body.title_template,
        &body.body_template,
        body.active.unwrap_or(true),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(body.key.clone()),
        AuditJustification(body.key.clone()),
        Json(json!({ "key": body.key })),
    ))
}

// ===========================================================================
// Abuse rules
// ===========================================================================

/// GET /admin/abuse/rules
pub async fn list_abuse_rules(
    State(state): State<AppState>,
    staff: StaffAuth,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "abuse.read")?;

    let rows = db::enterprise::list_abuse_rules(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let rules: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "name": r.name,
                "rule_type": r.rule_type,
                "config": r.config,
                "action": r.action,
                "enabled": r.enabled,
                "created_at": r.created_at.to_string(),
                "updated_at": r.updated_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({ "abuse_rules": rules })))
}

/// POST /admin/abuse/rules
pub async fn upsert_abuse_rule(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<UpsertAbuseRuleRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "abuse.write")?;

    db::enterprise::upsert_abuse_rule(
        &state.pool,
        &body.name,
        &body.rule_type,
        &body.config,
        &body.action,
        body.enabled.unwrap_or(true),
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(body.name.clone()),
        AuditJustification(body.name.clone()),
        Json(json!({ "name": body.name })),
    ))
}

/// DELETE /admin/abuse/rules/:id
pub async fn delete_abuse_rule(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<(AuditTarget, StatusCode), StatusCode> {
    rbac_check(&staff, "abuse.write")?;

    db::enterprise::delete_abuse_rule(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((AuditTarget(id.to_string()), StatusCode::NO_CONTENT))
}

// ===========================================================================
// API keys
// ===========================================================================

/// GET /admin/api-keys  (sin key_hash)
pub async fn list_api_keys(
    State(state): State<AppState>,
    staff: StaffAuth,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "apikeys.read")?;

    let rows = db::enterprise::list_api_keys(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let keys: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "name": r.name,
                "key_prefix": r.key_prefix,
                "permissions": r.permissions,
                "rate_limit_rps": r.rate_limit_rps,
                "active": r.active,
                "created_by": r.created_by,
                "last_used_at": r.last_used_at.map(|t| t.to_string()),
                "created_at": r.created_at.to_string(),
                "expires_at": r.expires_at.map(|t| t.to_string()),
            })
        })
        .collect();

    Ok(Json(json!({ "api_keys": keys })))
}

/// POST /admin/api-keys
///
/// Genera una API key aleatoria (64 bytes, base64url), guarda SHA-256 hash.
/// Retorna el key completo SOLO en esta respuesta.
pub async fn create_api_key(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<CreateApiKeyRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "apikeys.write")?;

    // Generate 64 random bytes
    let mut raw = vec![0u8; 64];
    rand::RngCore::fill_bytes(&mut rand::rngs::OsRng, &mut raw);

    // Base64url encode (no padding) for the API key
    use base64::Engine as _;
    let api_key = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&raw);

    // SHA-256 hash for storage
    use sha2::Digest;
    let hash = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(
        sha2::Sha256::digest(&raw),
    );

    let key_prefix = api_key[..8].to_string();
    let rate_limit = body.rate_limit_rps.unwrap_or(10);

    let id = db::enterprise::create_api_key(
        &state.pool,
        &body.name,
        &hash,
        &key_prefix,
        &body.permissions,
        rate_limit,
        staff.0.id,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.name.clone()),
        Json(serde_json::to_value(CreateApiKeyResponse {
            id,
            name: body.name,
            key_prefix,
            api_key,
            permissions: body.permissions,
            rate_limit_rps: rate_limit,
        })
        .unwrap()),
    ))
}

/// POST /admin/api-keys/:id/revoke
pub async fn revoke_api_key(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "apikeys.write")?;

    db::enterprise::revoke_api_key(&state.pool, id)
        .await
        .map_err(|_| StatusCode::NOT_FOUND)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification("revoke".into()),
        Json(json!({ "id": id, "active": false })),
    ))
}

// ===========================================================================
// Webhooks
// ===========================================================================

/// GET /admin/webhooks (sin secret)
pub async fn list_webhooks(
    State(state): State<AppState>,
    staff: StaffAuth,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "webhooks.read")?;

    let rows = db::enterprise::list_webhooks(&state.pool)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let webhooks: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "name": r.name,
                "url": r.url,
                "events": r.events,
                "active": r.active,
                "created_at": r.created_at.to_string(),
                "updated_at": r.updated_at.to_string(),
                "created_by": r.created_by,
            })
        })
        .collect();

    Ok(Json(json!({ "webhooks": webhooks })))
}

/// POST /admin/webhooks
pub async fn create_webhook(
    State(state): State<AppState>,
    staff: StaffAuth,
    Json(body): Json<CreateWebhookRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "webhooks.write")?;

    let id = db::enterprise::create_webhook(
        &state.pool,
        &body.name,
        &body.url,
        &body.events,
        body.secret.as_deref(),
        staff.0.id,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((
        AuditTarget(id.to_string()),
        AuditJustification(body.name.clone()),
        Json(json!({ "id": id, "name": body.name, "url": body.url })),
    ))
}

/// DELETE /admin/webhooks/:id
pub async fn delete_webhook(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(id): Path<Uuid>,
) -> Result<(AuditTarget, StatusCode), StatusCode> {
    rbac_check(&staff, "webhooks.write")?;

    db::enterprise::delete_webhook(&state.pool, id)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    Ok((AuditTarget(id.to_string()), StatusCode::NO_CONTENT))
}

// ===========================================================================
// Config history / rollback
// ===========================================================================

/// GET /admin/config/history?entity_type=&limit=50
pub async fn list_config_versions(
    State(state): State<AppState>,
    staff: StaffAuth,
    Query(query): Query<ConfigHistoryQuery>,
) -> Result<Json<Value>, StatusCode> {
    rbac_check(&staff, "config.read")?;

    let limit = query.limit.unwrap_or(50).clamp(1, 500);
    let rows = db::enterprise::list_config_versions(
        &state.pool,
        query.entity_type.as_deref(),
        limit,
    )
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let versions: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id,
                "entity_type": r.entity_type,
                "entity_key": r.entity_key,
                "previous_value": r.previous_value,
                "new_value": r.new_value,
                "changed_by": r.changed_by,
                "rolled_back": r.rolled_back,
                "created_at": r.created_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({ "config_versions": versions })))
}

/// POST /admin/config/history/:version_id/rollback
///
/// Lee el previous_value de config_versions, determina entity_type,
/// y actualiza la tabla correspondiente con el valor anterior.
pub async fn rollback_config_version(
    State(state): State<AppState>,
    staff: StaffAuth,
    Path(version_id): Path<Uuid>,
    Json(body): Json<RollbackRequest>,
) -> Result<(AuditTarget, AuditJustification, Json<Value>), StatusCode> {
    rbac_check(&staff, "config.write")?;

    db::enterprise::rollback_config_version(&state.pool, version_id, staff.0.id)
        .await
        .map_err(|e| {
            if e.to_string().contains("not found") {
                StatusCode::NOT_FOUND
            } else {
                tracing::warn!("rollback error: {e}");
                StatusCode::BAD_REQUEST
            }
        })?;

    Ok((
        AuditTarget(version_id.to_string()),
        AuditJustification(body._justification.unwrap_or_else(|| "rollback".into())),
        Json(json!({ "version_id": version_id, "rolled_back": true })),
    ))
}
