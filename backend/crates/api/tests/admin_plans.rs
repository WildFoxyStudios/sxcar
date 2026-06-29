//! Integration tests for admin plans endpoints (AD6).
//!
//! Tests:
//! 1. list_plans_includes_free_seed
//! 2. upsert_plan_creates_new_tier
//! 3. add_feature_to_plan_and_list
//! 4. add_price_for_country

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use std::sync::Arc;
use std::sync::OnceLock;
use tower::ServiceExt;

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

struct TestContext {
    app: axum::Router,
    pool: db::Pool,
}

fn test_db_url() -> String {
    std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://dev:dev@localhost:5433/appdb".to_string())
}

fn setup_kek_env() {
    if std::env::var("STAFF_TOTP_KEK").is_err() {
        std::env::set_var(
            "STAFF_TOTP_KEK",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        );
    }
    if std::env::var("STAFF_TOTP_KEK_VERSION").is_err() {
        std::env::set_var("STAFF_TOTP_KEK_VERSION", "1");
    }
}

fn test_kek() -> auth_admin::keystore::Kek {
    auth_admin::keystore::Kek::new([0u8; 32], 1)
}

fn staff_password_hash() -> &'static str {
    static HASH: OnceLock<String> = OnceLock::new();
    HASH.get_or_init(|| {
        setup_kek_env();
        auth_admin::password::hash("test-password").unwrap()
    })
}

fn unique_email() -> String {
    format!("ad6p_staff_{}@test.com", uuid::Uuid::new_v4().simple())
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

async fn get_auth(
    app: &axum::Router,
    uri: &str,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .header("authorization", format!("Bearer {token}"))
                .header("host", "localhost")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, json)
}

async fn post_auth(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .header("host", "localhost")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, json)
}

// ---------------------------------------------------------------------------
// Test setup helpers
// ---------------------------------------------------------------------------

async fn test_context() -> TestContext {
    setup_kek_env();
    let pool = db::connect(&test_db_url()).await.unwrap();
    db::migrate(&pool).await.unwrap();
    let deps = api::AppDeps {
        jwt: auth::jwt::JwtConfig {
            secret: "test-admin-jwt-secret".into(),
            access_ttl_secs: 900,
        },
        refresh_ttl_secs: 3600,
        notifier: Arc::new(auth::notify::DevNotifier),
        oauth: Arc::new(auth::oauth::DevOAuthVerifier),
    };
    let app = api::app(pool.clone(), deps);
    TestContext { app, pool }
}

async fn seed_staff(ctx: &TestContext, email: &str, role: &str) -> (uuid::Uuid, Vec<u8>) {
    let secret = totp_rs::Secret::generate_secret();
    let totp_raw = secret.to_bytes().expect("Secret::to_bytes");
    let encrypted = auth_admin::totp::encrypt_secret(&test_kek().key, &totp_raw).unwrap();
    let hash = staff_password_hash();

    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO staff (email, password_hash, totp_secret_enc, totp_enabled_at, recovery_codes_hash, role, status) VALUES ($1, $2, $3, now(), '{}'::text[], $4, 'active') RETURNING id",
    )
    .bind(email)
    .bind(hash)
    .bind(&encrypted[..])
    .bind(role)
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_staff insert failed");

    (id, totp_raw)
}

fn current_totp_code(raw: &[u8]) -> String {
    let totp = totp_rs::TOTP::new(
        totp_rs::Algorithm::SHA1,
        6,
        1,
        30,
        raw.to_vec(),
        None,
        "admin".to_string(),
    )
    .expect("TOTP::new");
    totp.generate_current().expect("generate_current")
}

async fn login_and_get_jwt(app: &axum::Router, email: &str, totp_raw: &[u8]) -> String {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/admin/auth/login")
                .header("content-type", "application/json")
                .header("host", "localhost")
                .body(Body::from(
                    serde_json::json!({"email": email, "password": "test-password"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let mfa_token = body["mfa_token"].as_str().unwrap().to_string();

    let code = current_totp_code(totp_raw);
    let res2 = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/admin/auth/2fa")
                .header("content-type", "application/json")
                .header("host", "localhost")
                .body(Body::from(
                    serde_json::json!({"mfa_token": mfa_token, "totp_code": code}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let bytes2 = res2.into_body().collect().await.unwrap().to_bytes();
    let body2: serde_json::Value = serde_json::from_slice(&bytes2).unwrap();
    body2["access_token"].as_str().unwrap().to_string()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn list_plans_includes_free_seed() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let (st, body) = get_auth(&ctx.app, "/admin/plans", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["plans"].is_array(), "plans should be an array");

    let plans = body["plans"].as_array().unwrap();
    let free_plan = plans.iter().find(|p| p["code"] == "free");
    assert!(free_plan.is_some(), "free plan should be seeded");
    assert_eq!(free_plan.unwrap()["name"], "Free");
    assert_eq!(free_plan.unwrap()["tier"], 0);
    assert_eq!(free_plan.unwrap()["active"], true);
    assert_eq!(
        free_plan.unwrap()["description"],
        "Basic free tier with ads"
    );
}

#[tokio::test]
async fn upsert_plan_creates_new_tier() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Create plan "xtra"
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/plans",
        serde_json::json!({
            "code": "xtra",
            "name": "Xtra",
            "tier": 1,
            "active": true,
            "description": "Premium tier"
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["code"], "xtra");
    assert_eq!(body["name"], "Xtra");
    assert_eq!(body["tier"], 1);

    // Verify in list
    let (st2, body2) = get_auth(&ctx.app, "/admin/plans", &jwt).await;
    assert_eq!(st2, StatusCode::OK, "expected 200, got {st2}: {body2}");

    let plans = body2["plans"].as_array().unwrap();
    let xtra = plans.iter().find(|p| p["code"] == "xtra");
    assert!(xtra.is_some(), "xtra plan should appear after upsert");
    assert_eq!(xtra.unwrap()["name"], "Xtra");
    assert_eq!(xtra.unwrap()["tier"], 1);
}

#[tokio::test]
async fn add_feature_to_plan_and_list() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Add feature to free plan
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/plans/free/features",
        serde_json::json!({
            "feature": "unlimited_swipes",
            "enabled": true,
            "limit_value": null
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["plan_code"], "free");
    assert_eq!(body["feature"], "unlimited_swipes");
    assert_eq!(body["enabled"], true);

    // List features
    let (st2, body2) = get_auth(&ctx.app, "/admin/plans/free/features", &jwt).await;
    assert_eq!(st2, StatusCode::OK, "expected 200, got {st2}: {body2}");

    let features = body2["features"].as_array().unwrap();
    let swipes = features.iter().find(|f| f["feature"] == "unlimited_swipes");
    assert!(
        swipes.is_some(),
        "unlimited_swipes should appear in features list"
    );
    assert_eq!(swipes.unwrap()["enabled"], true);
}

#[tokio::test]
async fn add_price_for_country() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Add price for MX country
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/plans/free/prices",
        serde_json::json!({
            "country_code": "MX",
            "currency": "MXN",
            "price_monthly": "99.99",
            "price_yearly": "999.99",
            "revenuecat_product_id": null
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["plan_code"], "free");
    assert_eq!(body["country_code"], "MX");
}
