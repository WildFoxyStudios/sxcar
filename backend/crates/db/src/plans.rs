//! AD6 — Plans, plan features, plan prices, and country config queries.
//!
//! Tables in `0016_admin_ad6_plans_countries.sql`:
//! - `plans` — subscription tiers (free, xtra, unlimited, etc.)
//! - `plan_features` — what features each plan unlocks
//! - `plan_prices` — regional pricing per plan
//! - `country_config` — per-country legal/geo/safety overrides

use crate::Pool;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Row types
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct PlanRow {
    pub code: String,
    pub name: String,
    pub tier: i32,
    pub active: bool,
    pub description: Option<String>,
}

#[derive(Debug)]
pub struct PlanFeatureRow {
    pub plan_code: String,
    pub feature: String,
    pub enabled: bool,
    pub limit_value: Option<i32>,
}

#[derive(Debug)]
pub struct PlanPriceRow {
    pub id: Uuid,
    pub plan_code: String,
    pub country_code: String,
    pub currency: String,
    pub price_monthly: Option<String>,
    pub price_yearly: Option<String>,
    pub revenuecat_product_id: Option<String>,
}

#[derive(Debug)]
pub struct CountryConfigRow {
    pub country_code: String,
    pub name: String,
    pub enabled: bool,
    pub disabled_features: Vec<String>,
    pub min_age: i32,
    pub requires_explicit_consent: bool,
    pub data_retention_days: Option<i32>,
    pub force_discreet_mode: bool,
    pub hide_sensitive_fields: bool,
    pub hide_distance: bool,
    pub geo_restricted: bool,
    pub restricted_features: Vec<String>,
    pub travel_warning: Option<String>,
}

// ---------------------------------------------------------------------------
// Plans CRUD
// ---------------------------------------------------------------------------

pub async fn list_plans(pool: &Pool) -> anyhow::Result<Vec<PlanRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT code, name, tier, active, description
           FROM plans
           ORDER BY tier, code"#,
    )
    .fetch_all(pool)
    .await?;

    let plans = rows
        .iter()
        .map(|r| PlanRow {
            code: r.get("code"),
            name: r.get("name"),
            tier: r.get("tier"),
            active: r.get("active"),
            description: r.get("description"),
        })
        .collect();

    Ok(plans)
}

pub async fn get_plan(pool: &Pool, code: &str) -> anyhow::Result<Option<PlanRow>> {
    use sqlx::Row;

    let row = sqlx::query(
        r#"SELECT code, name, tier, active, description
           FROM plans
           WHERE code = $1"#,
    )
    .bind(code)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| PlanRow {
        code: r.get("code"),
        name: r.get("name"),
        tier: r.get("tier"),
        active: r.get("active"),
        description: r.get("description"),
    }))
}

pub async fn upsert_plan(
    pool: &Pool,
    code: &str,
    name: &str,
    tier: i32,
    active: bool,
    description: Option<&str>,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO plans (code, name, tier, active, description)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (code) DO UPDATE SET
             name = EXCLUDED.name,
             tier = EXCLUDED.tier,
             active = EXCLUDED.active,
             description = EXCLUDED.description,
             updated_at = NOW()"#,
    )
    .bind(code)
    .bind(name)
    .bind(tier)
    .bind(active)
    .bind(description)
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Plan features
// ---------------------------------------------------------------------------

pub async fn list_plan_features(
    pool: &Pool,
    plan_code: &str,
) -> anyhow::Result<Vec<PlanFeatureRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT plan_code, feature, enabled, limit_value
           FROM plan_features
           WHERE plan_code = $1
           ORDER BY feature"#,
    )
    .bind(plan_code)
    .fetch_all(pool)
    .await?;

    let features = rows
        .iter()
        .map(|r| PlanFeatureRow {
            plan_code: r.get("plan_code"),
            feature: r.get("feature"),
            enabled: r.get("enabled"),
            limit_value: r.get("limit_value"),
        })
        .collect();

    Ok(features)
}

pub async fn upsert_plan_feature(
    pool: &Pool,
    plan_code: &str,
    feature: &str,
    enabled: bool,
    limit_value: Option<i32>,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO plan_features (plan_code, feature, enabled, limit_value)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (plan_code, feature) DO UPDATE SET
             enabled = EXCLUDED.enabled,
             limit_value = EXCLUDED.limit_value"#,
    )
    .bind(plan_code)
    .bind(feature)
    .bind(enabled)
    .bind(limit_value)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn delete_plan_feature(
    pool: &Pool,
    plan_code: &str,
    feature: &str,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"DELETE FROM plan_features
           WHERE plan_code = $1 AND feature = $2"#,
    )
    .bind(plan_code)
    .bind(feature)
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Plan prices
// ---------------------------------------------------------------------------

pub async fn list_plan_prices(
    pool: &Pool,
    plan_code: &str,
) -> anyhow::Result<Vec<PlanPriceRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT id, plan_code, country_code, currency,
                  price_monthly::text as "price_monthly",
                  price_yearly::text as "price_yearly",
                  revenuecat_product_id
           FROM plan_prices
           WHERE plan_code = $1
           ORDER BY country_code"#,
    )
    .bind(plan_code)
    .fetch_all(pool)
    .await?;

    let prices = rows
        .iter()
        .map(|r| PlanPriceRow {
            id: r.get("id"),
            plan_code: r.get("plan_code"),
            country_code: r.get("country_code"),
            currency: r.get("currency"),
            price_monthly: r.get("price_monthly"),
            price_yearly: r.get("price_yearly"),
            revenuecat_product_id: r.get("revenuecat_product_id"),
        })
        .collect();

    Ok(prices)
}

pub async fn upsert_plan_price(
    pool: &Pool,
    plan_code: &str,
    country_code: &str,
    currency: &str,
    monthly: Option<&str>,
    yearly: Option<&str>,
    revenuecat_id: Option<&str>,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO plan_prices (plan_code, country_code, currency, price_monthly, price_yearly, revenuecat_product_id)
           VALUES ($1, $2, $3,
                   CASE WHEN $4::text IS NOT NULL THEN $4::numeric(10,2) ELSE NULL END,
                   CASE WHEN $5::text IS NOT NULL THEN $5::numeric(10,2) ELSE NULL END,
                   $6)
           ON CONFLICT (plan_code, country_code) DO UPDATE SET
             currency = EXCLUDED.currency,
             price_monthly = EXCLUDED.price_monthly,
             price_yearly = EXCLUDED.price_yearly,
             revenuecat_product_id = EXCLUDED.revenuecat_product_id"#,
    )
    .bind(plan_code)
    .bind(country_code)
    .bind(currency)
    .bind(monthly)
    .bind(yearly)
    .bind(revenuecat_id)
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Country config CRUD
// ---------------------------------------------------------------------------

pub async fn list_country_configs(pool: &Pool) -> anyhow::Result<Vec<CountryConfigRow>> {
    use sqlx::Row;

    let rows = sqlx::query(
        r#"SELECT country_code, name, enabled, disabled_features, min_age,
                  requires_explicit_consent, data_retention_days,
                  force_discreet_mode, hide_sensitive_fields, hide_distance,
                  geo_restricted, restricted_features, travel_warning
           FROM country_config
           ORDER BY country_code"#,
    )
    .fetch_all(pool)
    .await?;

    let configs = rows
        .iter()
        .map(|r| CountryConfigRow {
            country_code: r.get("country_code"),
            name: r.get("name"),
            enabled: r.get("enabled"),
            disabled_features: r.get("disabled_features"),
            min_age: r.get("min_age"),
            requires_explicit_consent: r.get("requires_explicit_consent"),
            data_retention_days: r.get("data_retention_days"),
            force_discreet_mode: r.get("force_discreet_mode"),
            hide_sensitive_fields: r.get("hide_sensitive_fields"),
            hide_distance: r.get("hide_distance"),
            geo_restricted: r.get("geo_restricted"),
            restricted_features: r.get("restricted_features"),
            travel_warning: r.get("travel_warning"),
        })
        .collect();

    Ok(configs)
}

pub async fn get_country_config(
    pool: &Pool,
    code: &str,
) -> anyhow::Result<Option<CountryConfigRow>> {
    use sqlx::Row;

    let row = sqlx::query(
        r#"SELECT country_code, name, enabled, disabled_features, min_age,
                  requires_explicit_consent, data_retention_days,
                  force_discreet_mode, hide_sensitive_fields, hide_distance,
                  geo_restricted, restricted_features, travel_warning
           FROM country_config
           WHERE country_code = $1"#,
    )
    .bind(code)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| CountryConfigRow {
        country_code: r.get("country_code"),
        name: r.get("name"),
        enabled: r.get("enabled"),
        disabled_features: r.get("disabled_features"),
        min_age: r.get("min_age"),
        requires_explicit_consent: r.get("requires_explicit_consent"),
        data_retention_days: r.get("data_retention_days"),
        force_discreet_mode: r.get("force_discreet_mode"),
        hide_sensitive_fields: r.get("hide_sensitive_fields"),
        hide_distance: r.get("hide_distance"),
        geo_restricted: r.get("geo_restricted"),
        restricted_features: r.get("restricted_features"),
        travel_warning: r.get("travel_warning"),
    }))
}

#[allow(clippy::too_many_arguments)]
pub async fn upsert_country_config(
    pool: &Pool,
    country_code: &str,
    name: &str,
    enabled: bool,
    disabled_features: &Vec<String>,
    min_age: i32,
    requires_explicit_consent: bool,
    data_retention_days: Option<i32>,
    force_discreet_mode: bool,
    hide_sensitive_fields: bool,
    hide_distance: bool,
    geo_restricted: bool,
    restricted_features: &Vec<String>,
    travel_warning: Option<&str>,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO country_config (
             country_code, name, enabled, disabled_features, min_age,
             requires_explicit_consent, data_retention_days,
             force_discreet_mode, hide_sensitive_fields, hide_distance,
             geo_restricted, restricted_features, travel_warning
           ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
           ON CONFLICT (country_code) DO UPDATE SET
             name = EXCLUDED.name,
             enabled = EXCLUDED.enabled,
             disabled_features = EXCLUDED.disabled_features,
             min_age = EXCLUDED.min_age,
             requires_explicit_consent = EXCLUDED.requires_explicit_consent,
             data_retention_days = EXCLUDED.data_retention_days,
             force_discreet_mode = EXCLUDED.force_discreet_mode,
             hide_sensitive_fields = EXCLUDED.hide_sensitive_fields,
             hide_distance = EXCLUDED.hide_distance,
             geo_restricted = EXCLUDED.geo_restricted,
             restricted_features = EXCLUDED.restricted_features,
             travel_warning = EXCLUDED.travel_warning"#,
    )
    .bind(country_code)
    .bind(name)
    .bind(enabled)
    .bind(disabled_features)
    .bind(min_age)
    .bind(requires_explicit_consent)
    .bind(data_retention_days)
    .bind(force_discreet_mode)
    .bind(hide_sensitive_fields)
    .bind(hide_distance)
    .bind(geo_restricted)
    .bind(restricted_features)
    .bind(travel_warning)
    .execute(pool)
    .await?;
    Ok(())
}
