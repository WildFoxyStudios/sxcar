//! Integration tests for admin countries endpoints (AD6).
//!
//! Tests:
//! 1. list_countries_includes_global_fallback
//! 2. upsert_country_sets_safety_override

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
    format!("ad6c_staff_{}@test.com", uuid::Uuid::new_v4().simple())
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
async fn list_countries_includes_global_fallback() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let (st, body) = get_auth(&ctx.app, "/admin/countries", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["countries"].is_array(), "countries should be an array");

    let countries = body["countries"].as_array().unwrap();
    let global = countries.iter().find(|c| c["country_code"] == "XX");
    assert!(
        global.is_some(),
        "Global (Default) country should be seeded"
    );
    assert_eq!(global.unwrap()["name"], "Global (Default)");
    assert_eq!(global.unwrap()["enabled"], true);
    assert_eq!(global.unwrap()["min_age"], 18);
}

#[tokio::test]
async fn upsert_country_sets_safety_override() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Create country with safety overrides
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/countries/SA",
        serde_json::json!({
            "name": "Saudi Arabia",
            "enabled": true,
            "disabled_features": ["public_chat", "location_sharing"],
            "min_age": 21,
            "requires_explicit_consent": true,
            "data_retention_days": 90,
            "force_discreet_mode": true,
            "hide_sensitive_fields": true,
            "hide_distance": true,
            "geo_restricted": true,
            "restricted_features": ["dating", "social_feed"],
            "travel_warning": "LGBTQ+ laws are strict in this country"
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["country_code"], "SA");

    // Verify via GET single
    let (st2, body2) = get_auth(&ctx.app, "/admin/countries/SA", &jwt).await;
    assert_eq!(st2, StatusCode::OK, "expected 200, got {st2}: {body2}");
    assert_eq!(body2["name"], "Saudi Arabia");
    assert_eq!(body2["force_discreet_mode"], true);
    assert_eq!(body2["hide_sensitive_fields"], true);
    assert_eq!(body2["hide_distance"], true);
    assert_eq!(body2["geo_restricted"], true);
    assert_eq!(body2["requires_explicit_consent"], true);
    assert_eq!(body2["min_age"], 21);
    assert_eq!(body2["data_retention_days"], 90);
    assert_eq!(
        body2["travel_warning"],
        "LGBTQ+ laws are strict in this country"
    );

    // Verify arrays
    let disabled: Vec<String> = body2["disabled_features"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap().to_string())
        .collect();
    assert!(disabled.contains(&"public_chat".to_string()));
    assert!(disabled.contains(&"location_sharing".to_string()));

    let restricted: Vec<String> = body2["restricted_features"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap().to_string())
        .collect();
    assert!(restricted.contains(&"dating".to_string()));
    assert!(restricted.contains(&"social_feed".to_string()));
}
