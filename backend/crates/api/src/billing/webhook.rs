//! POST /billing/revenuecat/webhook
//!
//! Receives RevenueCat server-side webhook events and syncs subscription state
//! into the `subscriptions` table (source='revenuecat').
//!
//! # Authentication
//! The endpoint is unauthenticated (no JWT). RevenueCat sends the shared secret
//! as the raw value of the `Authorization` header. We compare constant-time.
//! If `REVENUECAT_WEBHOOK_SECRET` is not configured → 503 (fail closed).
//! Header mismatch → 401.
//!
//! # Event mapping
//! Grant events  → upsert active subscription:
//!   INITIAL_PURCHASE, RENEWAL, PRODUCT_CHANGE, UNCANCELLATION, NON_RENEWING_PURCHASE
//!
//! Revoke events → downgrade subscription:
//!   CANCELLATION → status='cancelled' (access ends immediately in our model)
//!   EXPIRATION   → status='expired'
//!
//! Intentionally ignored (always 200 so RC stops retrying):
//!   TEST, unknown user UUID, unmappable plan, any other event type.
//!
//! # Plan-code mapping
//! The RC entitlement identifier must be `vibra_plus` or `unlimited`
//! (configure these exactly in the RC dashboard). Fallback: product_id containing
//! "plus" → vibra_plus, "unlimited" → unlimited.

use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    response::IntoResponse,
    Json,
};
use serde_json::{json, Value};
use time::OffsetDateTime;
use uuid::Uuid;

use crate::billing::subscriptions::{grant_revenuecat_subscription, revoke_revenuecat_subscription};
use crate::AppState;

const GRANT_EVENTS: &[&str] = &[
    "INITIAL_PURCHASE",
    "RENEWAL",
    "PRODUCT_CHANGE",
    "UNCANCELLATION",
    "NON_RENEWING_PURCHASE",
];

const REVOKE_EVENTS: &[&str] = &["CANCELLATION", "EXPIRATION"];

const KNOWN_PLAN_CODES: &[&str] = &["vibra_plus", "unlimited"];

/// Constant-time byte comparison — always touches all bytes.
///
/// Returns true iff `a == b` with no early exit on mismatch, preventing
/// timing-based secret recovery. Length check is done first (safe: the
/// attacker already knows our secret length from other signals).
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff: u8 = 0;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

/// Map RC entitlement_ids / product_id to a known plan_code.
///
/// Priority: exact match in entitlement_ids → product_id substring match.
fn map_plan_code<'a>(entitlement_ids: &[String], product_id: &str) -> Option<&'a str> {
    // 1. Exact entitlement match.
    for eid in entitlement_ids {
        if KNOWN_PLAN_CODES.contains(&eid.as_str()) {
            return KNOWN_PLAN_CODES.iter().find(|&&c| c == eid.as_str()).copied();
        }
    }
    // 2. product_id substring fallback.
    let pid = product_id.to_ascii_lowercase();
    if pid.contains("unlimited") {
        return Some("unlimited");
    }
    if pid.contains("plus") || pid.contains("vibra_plus") {
        return Some("vibra_plus");
    }
    None
}

pub async fn revenuecat_webhook(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<Value>,
) -> axum::response::Response {
    // ── 1. Secret verification ──────────────────────────────────────────────
    let secret = match &state.revenuecat_webhook_secret {
        Some(s) => s.clone(),
        None => {
            tracing::warn!("REVENUECAT_WEBHOOK_SECRET not configured — rejecting webhook (503)");
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": "webhook_unconfigured"})),
            )
                .into_response();
        }
    };

    let provided = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    if !constant_time_eq(provided.as_bytes(), secret.as_bytes()) {
        tracing::warn!("RevenueCat webhook: bad or missing Authorization header");
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({"error": "invalid_secret"})),
        )
            .into_response();
    }

    // ── 2. Parse event fields ───────────────────────────────────────────────
    let event = &body["event"];
    let event_type = event["type"].as_str().unwrap_or("").to_string();

    // TEST events: ack immediately (lets the RC dashboard "Send test event" go green).
    if event_type == "TEST" {
        tracing::info!("RevenueCat TEST event received; acking 200");
        return (StatusCode::OK, Json(json!({"ok": true}))).into_response();
    }

    let app_user_id_str = event["app_user_id"].as_str().unwrap_or("");
    let product_id = event["product_id"].as_str().unwrap_or("");
    let expiration_at_ms = event["expiration_at_ms"].as_i64();

    let entitlement_ids: Vec<String> = event["entitlement_ids"]
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();

    // ── 3. Parse app_user_id as UUID ────────────────────────────────────────
    let user_id = match Uuid::parse_str(app_user_id_str) {
        Ok(id) => id,
        Err(_) => {
            tracing::warn!(
                app_user_id = app_user_id_str,
                event_type,
                "RevenueCat webhook: app_user_id is not a valid UUID; ignoring"
            );
            return (
                StatusCode::OK,
                Json(json!({"ok": true, "ignored": "invalid_user_id"})),
            )
                .into_response();
        }
    };

    // Check user exists in our DB.
    let user_exists: bool = match sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)",
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await
    {
        Ok(v) => v,
        Err(e) => {
            tracing::error!(%user_id, error = %e, "RevenueCat webhook: DB error checking user");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"error": "db_error"})),
            )
                .into_response();
        }
    };

    if !user_exists {
        tracing::warn!(%user_id, event_type, "RevenueCat webhook: user not found; ignoring");
        return (
            StatusCode::OK,
            Json(json!({"ok": true, "ignored": "unknown_user"})),
        )
            .into_response();
    }

    // ── 4. Map plan_code ────────────────────────────────────────────────────
    let plan_code = match map_plan_code(&entitlement_ids, product_id) {
        Some(p) => p,
        None => {
            tracing::warn!(
                event_type,
                product_id,
                ?entitlement_ids,
                "RevenueCat webhook: cannot map to a known plan_code; ignoring"
            );
            return (
                StatusCode::OK,
                Json(json!({"ok": true, "ignored": "unmappable_plan"})),
            )
                .into_response();
        }
    };

    // ── 5. Grant or revoke ──────────────────────────────────────────────────
    if GRANT_EVENTS.contains(&event_type.as_str()) {
        let expires_at = expiration_at_ms
            .map(|ms| {
                OffsetDateTime::from_unix_timestamp(ms / 1000)
                    .unwrap_or_else(|_| OffsetDateTime::now_utc() + time::Duration::days(30))
            })
            .unwrap_or_else(|| OffsetDateTime::now_utc() + time::Duration::days(30));

        if let Err(e) =
            grant_revenuecat_subscription(&state.pool, user_id, plan_code, expires_at).await
        {
            tracing::error!(%user_id, plan_code, error = %e, "RevenueCat grant DB error");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"error": "db_error"})),
            )
                .into_response();
        }
        tracing::info!(%user_id, plan_code, event_type, "RevenueCat: subscription granted");
    } else if REVOKE_EVENTS.contains(&event_type.as_str()) {
        // CANCELLATION → 'cancelled' (access ends immediately; RC will send EXPIRATION later).
        // EXPIRATION   → 'expired'.
        let new_status = if event_type == "CANCELLATION" {
            "cancelled"
        } else {
            "expired"
        };

        if let Err(e) =
            revoke_revenuecat_subscription(&state.pool, user_id, plan_code, new_status).await
        {
            tracing::error!(%user_id, plan_code, error = %e, "RevenueCat revoke DB error");
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"error": "db_error"})),
            )
                .into_response();
        }
        tracing::info!(%user_id, plan_code, event_type, new_status, "RevenueCat: subscription revoked");
    } else {
        // Unknown / unhandled event type — ack so RC doesn't retry forever.
        tracing::info!(event_type, "RevenueCat webhook: unhandled event type; ignoring");
    }

    (StatusCode::OK, Json(json!({"ok": true}))).into_response()
}
