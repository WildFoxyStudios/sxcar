//! Premium subscription tier feature gating.
//!
//! # Tiers
//! - **free** — basic grid (50 profiles), basic filters, 1 tribe, ads
//! - **xtra** — no ads, unlimited grid, advanced filters, 3 tribes, read receipts, travel pass
//! - **unlimited** — all features, unlimited tribes, incognito mode, priority support
//!
//! # Endpoints
//! - `GET /me/premium` — returns current tier + resolved feature flags
//!
//! The tier is stored in `users.subscription_tier`. RevenueCat webhook events
//! update it via [`resolve_subscription_tier`], which recomputes the tier from the
//! user's currently-active subscriptions (never trusting a single event's plan).

use axum::{extract::State, Json};
use serde::Serialize;
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::AppState;

// ─── Feature model ────────────────────────────────────────────────────────────

/// All feature flags exposed by the premium system.
/// Add new booleans here, then wire them into [`features_for_tier`].
#[derive(Debug, Clone, Serialize)]
pub struct PremiumFeatures {
    /// Unlimited profiles in grid (free tier limited to ~50).
    pub unlimited_grid: bool,
    /// No ad interruptions.
    pub no_ads: bool,
    /// Browse in incognito mode.
    pub incognito_mode: bool,
    /// See read receipts in chat.
    pub read_receipts: bool,
    /// Travel Pass (roam to any city).
    pub travel_pass: bool,
    /// Priority customer support.
    pub priority_support: bool,
    /// Advanced filter options (beyond basic online/photos-only).
    pub advanced_filters: bool,
    /// Maximum number of tribes the user can select.
    pub max_tribes: i32,
    /// Maximum number of profiles visible in the grid.
    pub max_profiles_grid: i32,
}

impl PremiumFeatures {
    /// Free-tier defaults — intentionally restricted.
    const FREE: Self = Self {
        unlimited_grid: false,
        no_ads: false,
        incognito_mode: false,
        read_receipts: false,
        travel_pass: false,
        priority_support: false,
        advanced_filters: false,
        max_tribes: 1,
        max_profiles_grid: 50,
    };

    /// Xtra — mid-tier, removes ads and unlocks most features.
    const XTRA: Self = Self {
        unlimited_grid: true,
        no_ads: true,
        incognito_mode: false,
        read_receipts: true,
        travel_pass: true,
        priority_support: false,
        advanced_filters: true,
        max_tribes: 3,
        max_profiles_grid: i32::MAX,
    };

    /// Unlimited — top tier, everything unlocked.
    const UNLIMITED: Self = Self {
        unlimited_grid: true,
        no_ads: true,
        incognito_mode: true,
        read_receipts: true,
        travel_pass: true,
        priority_support: true,
        advanced_filters: true,
        max_tribes: i32::MAX,
        max_profiles_grid: i32::MAX,
    };
}

fn features_for_tier(tier: &str) -> PremiumFeatures {
    match tier {
        "xtra" => PremiumFeatures::XTRA,
        "unlimited" => PremiumFeatures::UNLIMITED,
        _ => PremiumFeatures::FREE,
    }
}

// ─── Response DTO ─────────────────────────────────────────────────────────────

#[derive(Debug, Serialize)]
pub struct PremiumStatus {
    /// The user's current tier: "free", "xtra", or "unlimited".
    pub tier: String,
    /// Resolved feature flags for this tier.
    pub features: PremiumFeatures,
}

// ─── Helpers (used by webhook handler) ────────────────────────────────────────

/// Resolve and persist a user's subscription tier from their active subscriptions.
///
/// Called by the RevenueCat webhook on BOTH grant and revoke events. This is the
/// single source of truth for `users.subscription_tier`: it never trusts the tier
/// implied by an individual event's plan_code (which would allow a lower-tier grant
/// to clobber/downgrade an existing higher tier, or a spoofed event to downgrade).
///
/// Instead it selects the BEST currently-active, non-expired subscription for the
/// user (priority: `unlimited` > `vibra_plus` > free) and writes the corresponding
/// tier. Falls back to `free` when no active subscriptions remain.
///
/// Callers must have already upserted/expired the relevant `subscriptions` row for
/// the current event before invoking this, so the query sees up-to-date state.
pub async fn resolve_subscription_tier(
    pool: &sqlx::PgPool,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    // Find the highest plan_code among active subscriptions.
    // Priority: unlimited > vibra_plus > free.
    let best_plan: Option<String> = sqlx::query_scalar(
        r#"SELECT plan_code FROM subscriptions
           WHERE user_id = $1
             AND status = 'active'
             AND expires_at > now()
           ORDER BY
             CASE plan_code
               WHEN 'unlimited'  THEN 2
               WHEN 'vibra_plus' THEN 1
               ELSE 0
             END DESC
           LIMIT 1"#,
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    let tier = match best_plan.as_deref() {
        Some("unlimited") => "unlimited",
        Some("vibra_plus") => "xtra",
        _ => "free",
    };

    sqlx::query("UPDATE users SET subscription_tier = $1 WHERE id = $2")
        .bind(tier)
        .bind(user_id)
        .execute(pool)
        .await?;

    Ok(())
}

// ─── Handlers ─────────────────────────────────────────────────────────────────

/// `GET /me/premium`
///
/// Returns the user's current subscription tier and resolved feature set.
pub async fn get_premium_status(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Json<PremiumStatus> {
    let tier: String = sqlx::query_scalar("SELECT subscription_tier FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(&state.pool)
        .await
        .unwrap_or(None)
        .unwrap_or_else(|| "free".to_string());

    let features = features_for_tier(&tier);

    Json(PremiumStatus { tier, features })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn free_tier_features() {
        let f = features_for_tier("free");
        assert!(!f.unlimited_grid);
        assert!(!f.no_ads);
        assert!(!f.incognito_mode);
        assert!(!f.read_receipts);
        assert!(!f.travel_pass);
        assert!(!f.priority_support);
        assert!(!f.advanced_filters);
        assert_eq!(f.max_tribes, 1);
        assert_eq!(f.max_profiles_grid, 50);
    }

    #[test]
    fn xtra_tier_features() {
        let f = features_for_tier("xtra");
        assert!(f.unlimited_grid);
        assert!(f.no_ads);
        assert!(!f.incognito_mode); // Xtra does not get incognito
        assert!(f.read_receipts);
        assert!(f.travel_pass);
        assert!(!f.priority_support);
        assert!(f.advanced_filters);
        assert_eq!(f.max_tribes, 3);
        assert_eq!(f.max_profiles_grid, i32::MAX);
    }

    #[test]
    fn unlimited_tier_features() {
        let f = features_for_tier("unlimited");
        assert!(f.unlimited_grid);
        assert!(f.no_ads);
        assert!(f.incognito_mode);
        assert!(f.read_receipts);
        assert!(f.travel_pass);
        assert!(f.priority_support);
        assert!(f.advanced_filters);
        assert_eq!(f.max_tribes, i32::MAX);
        assert_eq!(f.max_profiles_grid, i32::MAX);
    }

    #[test]
    fn unknown_tier_defaults_to_free() {
        let f = features_for_tier("unknown_tier");
        assert!(!f.no_ads);
        assert_eq!(f.max_tribes, 1);
    }

    #[test]
    fn resolve_subscription_tier_maps_correctly() {
        // Tier resolution (resolve_subscription_tier) maps plan_code → tier the same
        // way features_for_tier does. vibra_plus is an unknown *feature* key, so it
        // resolves to free defaults; the DB query maps it to "xtra" before this point.
        // This just asserts the feature map is stable for the known tiers.
        assert!(features_for_tier("xtra").read_receipts);
        assert!(!features_for_tier("free").read_receipts);
    }
}
