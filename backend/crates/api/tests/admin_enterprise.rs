//! Integration tests for admin enterprise endpoints (AD7).
//!
//! Tests:
//! 1. list_experiments_empty_by_default
//! 2. upsert_experiment_creates_and_lists
//! 3. upsert_translation_and_list_by_locale
//! 4. create_campaign_draft_and_list
//! 5. create_api_key_returns_full_key_once_and_list_hides_it
//! 6. create_webhook_and_list

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
    format!("ad7e_staff_{}@test.com", uuid::Uuid::new_v4().simple())
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
async fn list_experiments_empty_by_default() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let (st, body) = get_auth(&ctx.app, "/admin/experiments", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(
        body["experiments"].is_array(),
        "experiments should be an array, got {body}"
    );
}

#[tokio::test]
async fn upsert_experiment_creates_and_lists() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Create experiment
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/experiments",
        serde_json::json!({
            "name": "Test Experiment",
            "description": "A test A/B experiment",
            "variants": [{"name": "A", "pct": 50}, {"name": "B", "pct": 50}],
            "enabled": true
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["key"], "test_experiment");

    // List and verify
    let (st2, body2) = get_auth(&ctx.app, "/admin/experiments", &jwt).await;
    assert_eq!(st2, StatusCode::OK);
    let experiments = body2["experiments"].as_array().unwrap();
    assert_eq!(experiments.len(), 1);
    assert_eq!(experiments[0]["key"], "test_experiment");
    assert_eq!(experiments[0]["name"], "Test Experiment");
    assert_eq!(experiments[0]["enabled"], true);
}

#[tokio::test]
async fn upsert_translation_and_list_by_locale() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Create Spanish translation
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/i18n",
        serde_json::json!({
            "locale": "es",
            "key": "welcome_message",
            "value": "Bienvenido"
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");

    // Also create English translation
    let (_st_en, _body_en) = post_auth(
        &ctx.app,
        "/admin/i18n",
        serde_json::json!({
            "locale": "en",
            "key": "welcome_message",
            "value": "Welcome"
        }),
        &jwt,
    )
    .await;

    // List with locale=es
    let (st2, body2) = get_auth(&ctx.app, "/admin/i18n?locale=es", &jwt).await;
    assert_eq!(st2, StatusCode::OK);
    let trans = body2["translations"].as_array().unwrap();
    assert_eq!(trans.len(), 1, "should return only Spanish translations, got {body2}");
    assert_eq!(trans[0]["locale"], "es");
    assert_eq!(trans[0]["key"], "welcome_message");
    assert_eq!(trans[0]["value"], "Bienvenido");

    // List without locale filter returns both
    let (st3, body3) = get_auth(&ctx.app, "/admin/i18n", &jwt).await;
    assert_eq!(st3, StatusCode::OK);
    let all = body3["translations"].as_array().unwrap();
    assert_eq!(all.len(), 2, "should return all translations");
}

#[tokio::test]
async fn create_campaign_draft_and_list() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Create campaign
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/campaigns",
        serde_json::json!({
            "name": "Summer Sale Push",
            "campaign_type": "push",
            "title": "Summer Sale!",
            "body": "Get 50% off this summer!"
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["id"].as_str().is_some(), "campaign should have an id");
    assert_eq!(body["status"], "draft");

    // List campaigns
    let (st2, body2) = get_auth(&ctx.app, "/admin/campaigns", &jwt).await;
    assert_eq!(st2, StatusCode::OK, "expected 200, got {st2}: {body2}");
    let campaigns = body2["campaigns"].as_array().unwrap();
    assert!(!campaigns.is_empty(), "should have at least one campaign");
    let campaign = &campaigns[0];
    assert_eq!(campaign["name"], "Summer Sale Push");
    assert_eq!(campaign["status"], "draft");
    assert_eq!(campaign["campaign_type"], "push");

    // Filter by status=draft
    let (st3, body3) = get_auth(&ctx.app, "/admin/campaigns?status=draft", &jwt).await;
    assert_eq!(st3, StatusCode::OK);
    let draft = body3["campaigns"].as_array().unwrap();
    assert!(!draft.is_empty(), "should find draft campaigns");
}

#[tokio::test]
async fn create_api_key_returns_full_key_once_and_list_hides_it() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Create API key
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/api-keys",
        serde_json::json!({
            "name": "Test Integration Key",
            "permissions": ["users:read", "reports:read"],
            "rate_limit_rps": 20
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(
        body["api_key"].as_str().is_some(),
        "response should contain full api_key, got {body}"
    );
    assert!(
        body["api_key"].as_str().unwrap().len() > 64,
        "api_key should be a long base64 string"
    );
    assert_eq!(
        body["key_prefix"],
        body["api_key"].as_str().unwrap()[..8],
        "key_prefix should match first 8 chars of api_key"
    );
    assert_eq!(body["name"], "Test Integration Key");

    // List API keys (should NOT contain key_hash or full key)
    let (st2, body2) = get_auth(&ctx.app, "/admin/api-keys", &jwt).await;
    assert_eq!(st2, StatusCode::OK);
    let keys = body2["api_keys"].as_array().unwrap();
    assert!(!keys.is_empty(), "should have at least one key");
    let listed = &keys[0];
    assert_eq!(listed["name"], "Test Integration Key");
    assert!(
        listed.get("api_key").is_none(),
        "list should NOT include the full api_key"
    );
    assert!(
        listed.get("key_hash").is_none(),
        "list should NOT include key_hash"
    );
    assert!(
        listed["key_prefix"].as_str().is_some(),
        "list SHOULD include key_prefix"
    );
}

#[tokio::test]
async fn create_webhook_and_list() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Create webhook
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/webhooks",
        serde_json::json!({
            "name": "User Events Hook",
            "url": "https://example.com/webhooks/user-events",
            "events": ["user.registered", "user.banned"],
            "secret": "whsec_abc123"
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["id"].as_str().is_some(), "webhook should have an id");
    assert_eq!(body["name"], "User Events Hook");
    assert_eq!(
        body["url"],
        "https://example.com/webhooks/user-events"
    );

    // List webhooks (should NOT contain secret)
    let (st2, body2) = get_auth(&ctx.app, "/admin/webhooks", &jwt).await;
    assert_eq!(st2, StatusCode::OK);
    let webhooks = body2["webhooks"].as_array().unwrap();
    assert!(!webhooks.is_empty(), "should have at least one webhook");
    let listed = &webhooks[0];
    assert_eq!(listed["name"], "User Events Hook");
    assert_eq!(
        listed["url"],
        "https://example.com/webhooks/user-events"
    );
    assert!(
        listed.get("secret").is_none(),
        "list should NOT include the webhook secret"
    );
    let events = listed["events"].as_array().unwrap();
    assert_eq!(events.len(), 2);
}
