//! Integration tests for admin config endpoints (AD5).
//!
//! Tests:
//! 1. list_flags_returns_seeded
//! 2. upsert_flag_creates_and_updates
//! 3. delete_flag_removes
//! 4. list_config_has_maintenance_mode
//! 5. analytics_overview_returns_counts

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
    format!("ad5_staff_{}@test.com", uuid::Uuid::new_v4().simple())
}

fn unique_user_email() -> String {
    format!("ad5_user_{}@test.com", uuid::Uuid::new_v4().simple())
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

async fn post(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .header("content-type", "application/json")
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

async fn delete_auth(
    app: &axum::Router,
    uri: &str,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
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

async fn seed_user(ctx: &TestContext, email: &str) -> uuid::Uuid {
    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO users (email, status) VALUES ($1, 'active') RETURNING id",
    )
    .bind(email)
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_user insert failed");
    id
}

async fn seed_subscription(ctx: &TestContext, user_id: uuid::Uuid, tier: &str) -> uuid::Uuid {
    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO subscriptions (user_id, tier, status) VALUES ($1, $2, 'active') RETURNING id",
    )
    .bind(user_id)
    .bind(tier)
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_subscription insert failed");
    id
}

async fn seed_location(ctx: &TestContext, user_id: uuid::Uuid) {
    sqlx::query(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint(0, 0), 4326))",
    )
    .bind(user_id)
    .execute(&ctx.pool)
    .await
    .expect("seed_location insert failed");
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
    let (_st, body) = post(
        app,
        "/admin/auth/login",
        serde_json::json!({"email": email, "password": "test-password"}),
    )
    .await;
    let mfa_token = body["mfa_token"].as_str().unwrap().to_string();

    let code = current_totp_code(totp_raw);
    let (_st2, body2) = post(
        app,
        "/admin/auth/2fa",
        serde_json::json!({"mfa_token": mfa_token, "totp_code": code}),
    )
    .await;
    body2["access_token"].as_str().unwrap().to_string()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn list_flags_returns_seeded() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let (st, body) = get_auth(&ctx.app, "/admin/flags", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["flags"].is_array(), "flags should be an array");

    let flags = body["flags"].as_array().unwrap();
    assert!(!flags.is_empty(), "flags should not be empty");

    // Verify seeded flag exists
    let keys: Vec<&str> = flags.iter().filter_map(|f| f["key"].as_str()).collect();
    assert!(
        keys.contains(&"chat_enabled"),
        "chat_enabled should be seeded"
    );
    assert!(
        keys.contains(&"registration_open"),
        "registration_open should be seeded"
    );
}

#[tokio::test]
async fn upsert_flag_creates_and_updates() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Create new flag
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/flags",
        serde_json::json!({
            "key": "test_feature",
            "value": true,
            "description": "Test feature flag",
            "enabled": true,
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["key"], "test_feature");
    assert_eq!(body["enabled"], true);

    // Verify via GET
    let (st2, body2) = get_auth(&ctx.app, "/admin/flags", &jwt).await;
    assert_eq!(st2, StatusCode::OK, "expected 200, got {st2}: {body2}");

    let test_flag = body2["flags"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["key"] == "test_feature");
    assert!(
        test_flag.is_some(),
        "test_feature should appear after upsert"
    );
    assert_eq!(test_flag.unwrap()["enabled"], true);
    assert_eq!(
        test_flag.unwrap()["description"],
        "Test feature flag"
    );

    // Update the same flag
    let (st3, body3) = post_auth(
        &ctx.app,
        "/admin/flags",
        serde_json::json!({
            "key": "test_feature",
            "value": false,
            "description": "Updated description",
            "enabled": false,
        }),
        &jwt,
    )
    .await;

    assert_eq!(st3, StatusCode::OK, "expected 200, got {st3}: {body3}");
    assert_eq!(body3["key"], "test_feature");
    assert_eq!(body3["enabled"], false);

    // Verify update via GET
    let (_st4, body4) = get_auth(&ctx.app, "/admin/flags", &jwt).await;
    let updated_flag = body4["flags"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["key"] == "test_feature")
        .unwrap();
    // value may be `false` or the actual JSON representation
    assert_eq!(updated_flag["enabled"], false);
    assert_eq!(
        updated_flag["description"],
        "Updated description"
    );
}

#[tokio::test]
async fn delete_flag_removes() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Create a flag first
    let (st, _) = post_auth(
        &ctx.app,
        "/admin/flags",
        serde_json::json!({
            "key": "temp_flag",
            "value": true,
            "description": "Temporary flag",
            "enabled": true,
        }),
        &jwt,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // Verify it exists
    let (st2, body2) = get_auth(&ctx.app, "/admin/flags", &jwt).await;
    assert_eq!(st2, StatusCode::OK);
    let has_temp = body2["flags"]
        .as_array()
        .unwrap()
        .iter()
        .any(|f| f["key"] == "temp_flag");
    assert!(has_temp, "temp_flag should exist before delete");

    // Delete it
    let (st3, body3) = delete_auth(&ctx.app, "/admin/flags/temp_flag", &jwt).await;
    assert_eq!(
        st3,
        StatusCode::NO_CONTENT,
        "expected 204, got {st3}: {body3:?}"
    );

    // Verify it's gone
    let (_st4, body4) = get_auth(&ctx.app, "/admin/flags", &jwt).await;
    assert_eq!(_st4, StatusCode::OK);
    let still_has = body4["flags"]
        .as_array()
        .unwrap()
        .iter()
        .any(|f| f["key"] == "temp_flag");
    assert!(!still_has, "temp_flag should be gone after delete");
}

#[tokio::test]
async fn list_config_has_maintenance_mode() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let (st, body) = get_auth(&ctx.app, "/admin/config", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["config"].is_array(), "config should be an array");
    assert!(!body["config"].as_array().unwrap().is_empty(), "config should not be empty");

    // Verify seeded config entry exists
    let maintenance = body["config"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["key"] == "maintenance_mode");
    assert!(
        maintenance.is_some(),
        "maintenance_mode should be seeded"
    );
    assert_eq!(
        maintenance.unwrap()["value"],
        serde_json::json!(false),
        "maintenance_mode should be false"
    );
}

#[tokio::test]
async fn analytics_overview_returns_counts() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Seed a user with subscription and location for meaningful counts
    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;
    let _sub_id = seed_subscription(&ctx, user_id, "xtra").await;
    seed_location(&ctx, user_id).await;

    let (st, body) = get_auth(&ctx.app, "/admin/analytics/overview", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(
        body["total_users"].as_i64().unwrap_or(0) > 0,
        "total_users should be > 0, got {:?}",
        body["total_users"]
    );
    assert!(
        body["new_users_today"].as_i64().unwrap_or(0) > 0,
        "new_users_today should be > 0, got {:?}",
        body["new_users_today"]
    );
    assert!(
        body["premium_users"].as_i64().unwrap_or(0) >= 1,
        "premium_users should be >= 1, got {:?}",
        body["premium_users"]
    );

    // Check all fields exist and are integers
    for field in &[
        "total_users",
        "active_today",
        "banned_users",
        "suspended_users",
        "premium_users",
        "new_users_today",
    ] {
        assert!(
            body[field].is_i64() || body[field].is_null(),
            "field {field} should be an integer or null, got {:?}",
            body[field]
        );
    }
}
