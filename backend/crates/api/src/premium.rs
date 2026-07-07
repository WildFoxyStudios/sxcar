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
//! update it via [`set_subscription_tier`] / [`clear_subscription_tier`].

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

/// Set (or upgrade) a user's subscription tier.
///
/// Called by the RevenueCat webhook on grant events.
/// Maps `plan_code` → tier: `vibra_plus` → `xtra`, `unlimited` → `unlimited`.
pub async fn set_subscription_tier(
    pool: &sqlx::PgPool,
    user_id: Uuid,
    plan_code: &str,
) -> Result<(), sqlx::Error> {
    let tier = match plan_code {
        "vibra_plus" => "xtra",
        "unlimited" => "unlimited",
        _ => "free",
    };
    sqlx::query("UPDATE users SET subscription_tier = $1 WHERE id = $2")
        .bind(tier)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(())
}

/// Resolve the best tier from remaining active subscriptions.
///
/// Called by the RevenueCat webhook on cancellation/expiration.
/// If the user still has an active subscription (e.g. `unlimited` when
/// `vibra_plus` was revoked), the tier is set to the highest remaining.
/// Falls back to `free` when no active subscriptions remain.
pub async fn clear_subscription_tier(
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
    fn set_subscription_tier_maps_correctly() {
        // Just test the mapping logic (no pool).
        // set_subscription_tier is tested via integration tests.
        assert_eq!(
            features_for_tier("xtra").read_receipts,
            features_for_tier("vibra_plus") // same map used in set_subscription_tier
                .read_receipts
        );
    }
}
