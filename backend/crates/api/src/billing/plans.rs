//! GET /billing/plans — list active plans with features and regional prices.
//!
//! Response shape (consumed by the Flutter TiendaScreen via /billing/plans):
//!   { "plans": [ PlanDto, ... ] }
//! Each PlanDto has:
//!   - code, name, tier, description, active — from `plans` table
//!   - features — list of feature keys (filtered to `enabled = true`) from `plan_features`
//!   - prices — one PriceDto per (country, period) combo from `plan_prices`
//!
//! Sort order: `tier ASC, code ASC`. Only `active = true` plans are returned.

use super::error::BillingResult;
use crate::AppState;
use axum::{extract::State, Json};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

#[derive(Debug, Serialize)]
pub struct PlanDto {
    pub code: String,
    pub name: String,
    pub tier: i32,
    pub description: Option<String>,
    pub active: bool,
    pub features: Vec<String>,
    pub prices: Vec<PriceDto>,
}

#[derive(Debug, Serialize)]
pub struct PriceDto {
    pub id: Uuid,
    pub country_code: String,
    pub currency: String,
    /// "monthly" | "yearly" — derived from the `plan_prices` row's price_*
    pub period: String,
    /// price * 100 as integer (cents / minor units) for Flutter display
    pub amount_minor: i32,
}

#[derive(Debug, Serialize)]
pub struct ListPlansResponse {
    pub plans: Vec<PlanDto>,
}

pub async fn list_plans(
    State(state): State<AppState>,
) -> BillingResult<Json<ListPlansResponse>> {
    // 1. Fetch all active plans (db helper returns all; we filter for active here).
    let plans_rows = db::plans::list_plans(&state.pool).await
        .map_err(super::error::BillingError::Db)?;
    let active: Vec<_> = plans_rows.into_iter()
        .filter(|p| p.active)
        .collect();

    // 2. For each plan, fetch its features + prices.
    let mut out = Vec::with_capacity(active.len());
    for p in active {
        let feat_rows = db::plans::list_plan_features(&state.pool, &p.code).await
            .map_err(super::error::BillingError::Db)?;
        let features: Vec<String> = feat_rows.into_iter()
            .filter(|f| f.enabled)
            .map(|f| f.feature)
            .collect();

        let price_rows = db::plans::list_plan_prices(&state.pool, &p.code).await
            .map_err(super::error::BillingError::Db)?;
        let mut prices = Vec::new();
        for pr in price_rows {
            // price_monthly / price_yearly are Option<Decimal-as-String>; derive period + minor.
            if let Some(s) = &pr.price_monthly {
                let amount_minor = decimal_string_to_minor(s);
                prices.push(PriceDto {
                    id: pr.id,
                    country_code: pr.country_code.clone(),
                    currency: pr.currency.clone(),
                    period: "monthly".to_string(),
                    amount_minor,
                });
            }
            if let Some(s) = &pr.price_yearly {
                let amount_minor = decimal_string_to_minor(s);
                prices.push(PriceDto {
                    id: pr.id,
                    country_code: pr.country_code.clone(),
                    currency: pr.currency.clone(),
                    period: "yearly".to_string(),
                    amount_minor,
                });
            }
        }

        out.push(PlanDto {
            code: p.code,
            name: p.name,
            tier: p.tier,
            description: p.description,
            active: p.active,
            features,
            prices,
        });
    }

    // Sort by tier then code.
    out.sort_by(|a, b| (a.tier, &a.code).cmp(&(b.tier, &b.code)));
    Ok(Json(ListPlansResponse { plans: out }))
}

/// Convert "8.99" -> 899, "99.99" -> 9999. Handles 0–2 decimal places.
fn decimal_string_to_minor(s: &str) -> i32 {
    let s = s.trim();
    let (int_part, frac_part) = match s.split_once('.') {
        Some((i, f)) => (i, f),
        None => (s, ""),
    };
    let int_part: i64 = int_part.parse().unwrap_or(0);
    // Pad/truncate frac_part to exactly 2 digits.
    let frac_chars: Vec<char> = frac_part.chars().take(2).collect();
    let frac_padded: String = frac_chars.iter().collect();
    let frac_padded = format!("{:0<2}", frac_padded);
    let frac_part: i64 = if frac_padded.is_empty() { 0 } else { frac_padded.parse().unwrap_or(0) };
    let minor = int_part * 100 + frac_part;
    minor as i32
}

#[cfg(test)]
mod tests {
    use super::decimal_string_to_minor;

    #[test]
    fn converts_8_99() {
        assert_eq!(decimal_string_to_minor("8.99"), 899);
    }
    #[test]
    fn converts_99_99() {
        assert_eq!(decimal_string_to_minor("99.99"), 9999);
    }
    #[test]
    fn converts_whole_number() {
        assert_eq!(decimal_string_to_minor("10"), 1000);
    }
    #[test]
    fn handles_three_decimal_places() {
        assert_eq!(decimal_string_to_minor("8.999"), 899); // truncate
    }
}