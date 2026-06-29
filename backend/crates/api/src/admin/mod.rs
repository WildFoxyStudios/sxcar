//! Admin auth endpoints (T10 — AD1) + middleware (T11 — AD1).
//!
//! Endpoints:
//! - `POST /admin/auth/login`  — email + password → mfa_token
//! - `POST /admin/auth/2fa`    — mfa_token + TOTP → access_token + session_id
//! - `POST /admin/auth/logout` — revoca sesion (requiere StaffAuth)
//!
//! Middleware (T11):
//! - `rbac`     — permission checks per-route
//! - `audit`    — logs mutations to `audit_log`

pub mod audit;
pub mod extractors;
pub mod handlers;
pub mod handlers_enterprise;
pub mod rbac;

use axum::{
    middleware::from_fn_with_state,
    routing::{delete, get, post},
    Router,
};

use crate::AppState;

/// Test-only handlers compiled always; they are harmless because they require
/// valid staff authentication to produce a non-error response.
mod test_routes {
    use axum::http::StatusCode;

    pub async fn protected() -> StatusCode {
        StatusCode::NO_CONTENT
    }

    pub async fn authenticated(
        _: crate::admin::extractors::StaffAuth,
    ) -> StatusCode {
        StatusCode::NO_CONTENT
    }
}

pub fn router(state: AppState) -> Router<AppState> {
    let s = state.clone();
    Router::new()
        // Auth (sin RBAC, sin audit)
        .route("/admin/auth/login", post(handlers::login))
        .route("/admin/auth/2fa", post(handlers::two_factor))
        .route("/admin/auth/logout", post(handlers::logout))
        // AD2 — Users list & detail (GET, RBAC inline en handler)
        .route("/admin/users", get(handlers::list_users))
        .route("/admin/users/:id", get(handlers::get_user))
        // AD2 — User mutations (POST, RBAC inline + audit)
        .route(
            "/admin/users/:id/ban",
            post(handlers::ban_user)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/users/:id/suspend",
            post(handlers::suspend_user)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/users/:id/activate",
            post(handlers::activate_user)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/users/:id/force-logout",
            post(handlers::force_logout_user)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD2 — Audit viewer (GET, RBAC inline)
        .route("/admin/audit", get(handlers::list_audit))
        // AD3 — Reports (GET, RBAC inline en handler)
        .route("/admin/reports", get(handlers::list_reports))
        // AD3 — Report mutations (POST, RBAC inline + audit)
        .route(
            "/admin/reports/:id/review",
            post(handlers::review_report)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/reports/:id/resolve",
            post(handlers::resolve_report)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD3 — Photo moderation (GET, RBAC inline)
        .route(
            "/admin/moderation/photos",
            get(handlers::list_pending_photos),
        )
        // AD3 — Photo mutations (POST, RBAC inline + audit)
        .route(
            "/admin/moderation/photos/:id/approve",
            post(handlers::approve_photo)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/moderation/photos/:id/reject",
            post(handlers::reject_photo)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD3 — CSAM (GET, RBAC inline)
        .route("/admin/csam", get(handlers::list_csam_hits))
        // AD3 — CSAM mutations (POST, RBAC inline + audit)
        .route(
            "/admin/csam/:id/report",
            post(handlers::report_csam_hit)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD4 — Support (entitlements)
        .route(
            "/admin/support/users/:id/entitlements",
            get(handlers::list_entitlements),
        )
        .route(
            "/admin/support/users/:id/entitlements",
            post(handlers::manage_entitlement)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD4 — GDPR (data requests)
        .route("/admin/gdpr/data-requests", get(handlers::list_data_requests))
        .route(
            "/admin/gdpr/data-requests/:id/process",
            post(handlers::process_data_request)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD4 — Legal (LER)
        .route("/admin/legal/export/:user_id", get(handlers::legal_export))
        .route(
            "/admin/legal/hold",
            post(handlers::place_legal_hold)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/legal/hold/:id/release",
            post(handlers::release_legal_hold)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD5 — Feature flags (GET = read-only, POST = mutation)
        .route("/admin/flags", get(handlers::list_flags))
        .route(
            "/admin/flags",
            post(handlers::upsert_flag)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/flags/:key",
            delete(handlers::delete_flag)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD5 — App config (GET = read-only, POST = mutation)
        .route("/admin/config", get(handlers::list_config))
        .route(
            "/admin/config",
            post(handlers::upsert_config)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD5 — Analytics (GET = read-only, sin audit)
        .route(
            "/admin/analytics/overview",
            get(handlers::analytics_overview),
        )
        // AD6 — Plans (GET = read-only, POST = mutation)
        .route("/admin/plans", get(handlers::list_plans))
        .route(
            "/admin/plans",
            post(handlers::upsert_plan)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/plans/:code/features",
            get(handlers::list_plan_features),
        )
        .route(
            "/admin/plans/:code/features",
            post(handlers::upsert_plan_feature)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/plans/:code/features/:feature",
            delete(handlers::delete_plan_feature)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/plans/:code/prices",
            post(handlers::upsert_plan_price)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD6 — Countries (GET = read-only, POST = mutation)
        .route("/admin/countries", get(handlers::list_country_configs))
        .route("/admin/countries/:code", get(handlers::get_country_config))
        .route(
            "/admin/countries/:code",
            post(handlers::upsert_country_config)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — Experiments (GET = read-only, POST = mutation, DELETE = mutation)
        .route("/admin/experiments", get(handlers::list_experiments))
        .route(
            "/admin/experiments",
            post(handlers::upsert_experiment)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/experiments/:key",
            delete(handlers::delete_experiment)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — i18n / translations (GET = read-only, POST = mutation)
        .route("/admin/i18n", get(handlers::list_translations))
        .route(
            "/admin/i18n",
            post(handlers::upsert_translation)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — CMS (GET = read-only, POST = mutation, DELETE = mutation)
        .route("/admin/cms", get(handlers::list_cms_content))
        .route(
            "/admin/cms/:key",
            post(handlers::upsert_cms_content)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/cms/:key",
            delete(handlers::delete_cms_content)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — Legal docs (GET = read-only, POST = mutation)
        .route("/admin/legal-docs", get(handlers::list_legal_docs))
        .route(
            "/admin/legal-docs",
            post(handlers::create_legal_doc)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — Campaigns (GET = read-only, POST = mutation)
        .route("/admin/campaigns", get(handlers::list_campaigns))
        .route(
            "/admin/campaigns",
            post(handlers::create_campaign)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/campaigns/:id/send",
            post(handlers::send_campaign)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — Notification templates (GET = read-only, POST = mutation)
        .route("/admin/templates", get(handlers::list_notification_templates))
        .route(
            "/admin/templates",
            post(handlers::upsert_notification_template)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — Abuse rules (GET = read-only, POST = mutation, DELETE = mutation)
        .route("/admin/abuse/rules", get(handlers::list_abuse_rules))
        .route(
            "/admin/abuse/rules",
            post(handlers::upsert_abuse_rule)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/abuse/rules/:id",
            delete(handlers::delete_abuse_rule)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — API keys (GET = read-only, POST = mutation, revoke = mutation)
        .route("/admin/api-keys", get(handlers::list_api_keys))
        .route(
            "/admin/api-keys",
            post(handlers::create_api_key)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/api-keys/:id/revoke",
            post(handlers::revoke_api_key)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — Webhooks (GET = read-only, POST = mutation, DELETE = mutation)
        .route("/admin/webhooks", get(handlers::list_webhooks))
        .route(
            "/admin/webhooks",
            post(handlers::create_webhook)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        .route(
            "/admin/webhooks/:id",
            delete(handlers::delete_webhook)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // AD7 — Config history / rollback (GET = read-only, POST = mutation)
        .route(
            "/admin/config/history",
            get(handlers::list_config_versions),
        )
        .route(
            "/admin/config/history/:version_id/rollback",
            post(handlers::rollback_config_version)
                .route_layer(from_fn_with_state(s.clone(), audit::audit_mutation)),
        )
        // Test-only routes (harmless — require valid staff auth).
        .route(
            "/admin/_test_protected",
            post(test_routes::protected).route_layer(from_fn_with_state(
                s.clone(),
                rbac::require_perm("user.delete"),
            )),
        )
        .route(
            "/admin/_test_auth",
            get(test_routes::authenticated).route_layer(from_fn_with_state(
                s,
                audit::audit_mutation,
            )),
        )
}
