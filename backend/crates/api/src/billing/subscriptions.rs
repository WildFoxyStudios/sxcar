//! Billing subscriptions: GET /billing/me + RevenueCat grant/revoke helpers.
//!
//! Returns 200 with `{ "subscription": SubscriptionDto | null }`.
//! Always authenticated (AuthUser extractor).
//!
//! "Active" = status='active' AND expires_at > now() (legacy-safe per T1.2 review).

use crate::AppState;
use crate::auth::AuthUser;
use crate::billing::error::{BillingError, BillingResult};
use crate::billing::simulate::SubscriptionDto;
use axum::{extract::State, Json};
use serde::Serialize;
use sqlx::Row;
use time::OffsetDateTime;
use uuid::Uuid;

#[derive(Debug, Serialize)]
pub struct MySubscriptionResponse {
    pub subscription: Option<SubscriptionDto>,
}

/// Format an OffsetDateTime as an RFC3339 string (UTC, with subseconds).
fn format_rfc3339(t: OffsetDateTime) -> String {
    let format = time::format_description::well_known::Rfc3339;
    t.format(&format).unwrap_or_else(|_| t.to_string())
}

pub async fn my_subscription(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> BillingResult<Json<MySubscriptionResponse>> {
    let row = sqlx::query(
        r#"SELECT s.id,
                  s.plan_code,
                  p.name      AS plan_name,
                  s.price_id,
                  s.period,
                  s.period_days,
                  s.status,
                  s.source,
                  s.started_at,
                  s.expires_at,
                  GREATEST(0, EXTRACT(DAY FROM (s.expires_at - now())))::bigint
                    AS days_remaining
           FROM subscriptions s
           JOIN plans p ON p.code = s.plan_code
           WHERE s.user_id = $1
             AND s.status = 'active'
             AND s.expires_at > now()
           ORDER BY s.expires_at DESC
           LIMIT 1"#,
    )
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(BillingError::from)?;

    // price_id, period, period_days are nullable for RC-sourced subscriptions.
    let dto = row.map(|r| SubscriptionDto {
        id: r.get::<Uuid, _>("id"),
        plan_code: r.get("plan_code"),
        plan_name: r.get("plan_name"),
        price_id: r.try_get::<Uuid, _>("price_id").ok(),
        period: r.try_get::<String, _>("period").ok(),
        period_days: r.try_get::<i32, _>("period_days").ok(),
        status: r.get("status"),
        source: r.get("source"),
        started_at: format_rfc3339(r.get::<OffsetDateTime, _>("started_at")),
        expires_at: format_rfc3339(r.get::<OffsetDateTime, _>("expires_at")),
        days_remaining: r.get::<i64, _>("days_remaining"),
    });

    Ok(Json(MySubscriptionResponse { subscription: dto }))
}

// ─── RevenueCat helpers (used by billing/webhook.rs) ─────────────────────────

/// Grant an active `revenuecat` subscription for `(user_id, plan_code)`.
///
/// Idempotent: expires any existing active RC row for this user+plan first,
/// then inserts a fresh active row. A repeated identical event produces 1 active
/// row (not stacked rows).
pub async fn grant_revenuecat_subscription(
    pool: &sqlx::PgPool,
    user_id: Uuid,
    plan_code: &str,
    expires_at: OffsetDateTime,
) -> Result<(), sqlx::Error> {
    // Expire existing active RC rows to prevent stacking.
    sqlx::query(
        r#"UPDATE subscriptions
           SET status = 'expired'
           WHERE user_id    = $1
             AND plan_code  = $2
             AND source     = 'revenuecat'
             AND status     = 'active'"#,
    )
    .bind(user_id)
    .bind(plan_code)
    .execute(pool)
    .await?;

    // Insert the new active row.
    // price_id / period / period_days are left NULL (not available from RC events).
    sqlx::query(
        r#"INSERT INTO subscriptions
             (user_id, plan_code, source, status, started_at, expires_at)
           VALUES ($1, $2, 'revenuecat', 'active', now(), $3)"#,
    )
    .bind(user_id)
    .bind(plan_code)
    .bind(expires_at)
    .execute(pool)
    .await?;

    Ok(())
}

/// Revoke (cancel or expire) a `revenuecat` subscription for `(user_id, plan_code)`.
///
/// `new_status` should be `'cancelled'` (CANCELLATION event — auto-renew off,
/// access ends immediately in our model) or `'expired'` (EXPIRATION event).
///
/// Note on CANCELLATION semantics: we set `status='cancelled'` which means
/// `/billing/me` (which checks `status='active'`) will no longer return this
/// subscription. If future product direction requires keeping access until
/// `expires_at`, change this to a no-op and only act on EXPIRATION.
pub async fn revoke_revenuecat_subscription(
    pool: &sqlx::PgPool,
    user_id: Uuid,
    plan_code: &str,
    new_status: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"UPDATE subscriptions
           SET status = $3
           WHERE user_id   = $1
             AND plan_code = $2
             AND source    = 'revenuecat'
             AND status    = 'active'"#,
    )
    .bind(user_id)
    .bind(plan_code)
    .bind(new_status)
    .execute(pool)
    .await?;

    Ok(())
}