//! GET /billing/me — return the user's currently-active subscription, if any.
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

    let dto = row.map(|r| SubscriptionDto {
        id: r.get::<Uuid, _>("id"),
        plan_code: r.get("plan_code"),
        plan_name: r.get("plan_name"),
        price_id: r.get("price_id"),
        period: r.get("period"),
        period_days: r.get("period_days"),
        status: r.get("status"),
        source: r.get("source"),
        started_at: format_rfc3339(r.get::<OffsetDateTime, _>("started_at")),
        expires_at: format_rfc3339(r.get::<OffsetDateTime, _>("expires_at")),
        days_remaining: r.get::<i64, _>("days_remaining"),
    });

    Ok(Json(MySubscriptionResponse { subscription: dto }))
}