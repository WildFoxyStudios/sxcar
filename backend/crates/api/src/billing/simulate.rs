//! POST /billing/simulate-purchase
//!
//! Request: { "price_id": "<uuid of plan_prices row>" }
//! Effect: creates a new subscription row tied to the user for the plan/period
//!          implied by the price_id. Idempotent for the same price_id+user
//!          if no active entitlement exists.
//! Returns 201 with the new SubscriptionDto on success.
//! Returns 409 AlreadyActive if the user already has an active subscription
//!          for the SAME `plan_code`.
//! Returns 404 if the price_id doesn't exist.

use crate::AppState;
use crate::auth::AuthUser;
use crate::billing::error::{BillingError, BillingResult};
use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use time::{Duration, OffsetDateTime};
use uuid::Uuid;

/// Format an OffsetDateTime as an RFC3339 string (UTC, with subseconds).
fn format_rfc3339(t: OffsetDateTime) -> String {
    let format = time::format_description::well_known::Rfc3339;
    t.format(&format).unwrap_or_else(|_| t.to_string())
}

#[derive(Debug, Deserialize)]
pub struct SimulatePurchaseReq {
    pub price_id: Uuid,
}

#[derive(Debug, Serialize)]
pub struct SubscriptionDto {
    pub id: Uuid,
    pub plan_code: String,
    pub plan_name: String,
    /// None for RevenueCat subscriptions (no DB price_id available).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub price_id: Option<Uuid>,
    /// None for RevenueCat subscriptions.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub period: Option<String>,
    /// None for RevenueCat subscriptions.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub period_days: Option<i32>,
    pub status: String,
    pub source: String,
    /// RFC3339 timestamp string (e.g. "2026-07-04T12:34:56.789Z").
    pub started_at: String,
    /// RFC3339 timestamp string (e.g. "2026-08-03T12:34:56.789Z").
    pub expires_at: String,
    pub days_remaining: i64,
}

pub async fn simulate_purchase(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Json(req): Json<SimulatePurchaseReq>,
) -> BillingResult<(axum::http::StatusCode, Json<SubscriptionDto>)> {
    // 1. Look up plan_prices by id; join plans to get name + tier context.
    let row = sqlx::query(
        r#"SELECT pp.plan_code AS plan_code,
                  p.name      AS plan_name,
                  p.active    AS plan_active,
                  pp.currency AS currency,
                  pp.price_monthly::text AS price_monthly,
                  pp.price_yearly::text  AS price_yearly
           FROM plan_prices pp
           JOIN plans p ON p.code = pp.plan_code
           WHERE pp.id = $1"#,
    )
    .bind(req.price_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(BillingError::from)?
    .ok_or(BillingError::PlanNotFound)?;

    if !row.get::<bool, _>("plan_active") {
        return Err(BillingError::PlanNotFound);
    }

    let plan_code: String = row.get("plan_code");
    let plan_name: String = row.get("plan_name");
    let price_monthly: Option<String> = row.get("price_monthly");
    let price_yearly: Option<String> = row.get("price_yearly");

    // 2. Derive period + period_days from the price row.
    let (period, period_days): (&str, i32) = if price_monthly.is_some() {
        ("monthly", 30)
    } else if price_yearly.is_some() {
        ("yearly", 365)
    } else {
        return Err(BillingError::PlanNotFound);
    };

    // 3. Refuse if user already has an active entitlement for this plan_code.
    //    CRITICAL: include `AND expires_at > now()` per T1.2 review (legacy rows
    //    may have status='active' but expires_at IS NULL).
    let existing: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM subscriptions
           WHERE user_id = $1
             AND plan_code = $2
             AND status = 'active'
             AND expires_at > now()"#,
    )
    .bind(user_id)
    .bind(&plan_code)
    .fetch_one(&state.pool)
    .await
    .map_err(BillingError::from)?;

    if existing > 0 {
        return Err(BillingError::AlreadyActive);
    }

    // 4. Compute expiry and INSERT.
    let started_at: OffsetDateTime = OffsetDateTime::now_utc();
    let expires_at: OffsetDateTime = started_at + Duration::days(period_days.into());

    let inserted = sqlx::query(
        r#"INSERT INTO subscriptions
             (user_id, plan_code, price_id, period, period_days,
              source, status, started_at, expires_at)
           VALUES ($1, $2, $3, $4, $5, 'simulated', 'active', $6, $7)
           RETURNING id, started_at, expires_at"#,
    )
    .bind(user_id)
    .bind(&plan_code)
    .bind(req.price_id)
    .bind(period)
    .bind(period_days)
    .bind(started_at)
    .bind(expires_at)
    .fetch_one(&state.pool)
    .await
    .map_err(BillingError::from)?;

    let dto = SubscriptionDto {
        id: inserted.get("id"),
        plan_code,
        plan_name,
        price_id: Some(req.price_id),
        period: Some(period.to_string()),
        period_days: Some(period_days),
        status: "active".to_string(),
        source: "simulated".to_string(),
        started_at: format_rfc3339(inserted.get("started_at")),
        expires_at: format_rfc3339(inserted.get("expires_at")),
        days_remaining: period_days as i64,
    };

    Ok((axum::http::StatusCode::CREATED, Json(dto)))
}