//! Integration tests for admin auth endpoints (T10 — AD1).
//!
//! Tests real requests against the full app stack (axum + sqlx + Postgres).
//! DB is localhost:5433/appdb (dev). Tests are idempotent via unique emails.

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
    kek: auth_admin::keystore::Kek,
}

/// URL de la BD de test (default: local dev).
fn test_db_url() -> String {
    std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://dev:dev@localhost:5433/appdb".to_string())
}

/// Asegura que las env vars KEK esten seteadas.
fn setup_kek_env() {
    if std::env::var("STAFF_TOTP_KEK").is_err() {
        // [0u8; 32] en base64 estándar
        std::env::set_var(
            "STAFF_TOTP_KEK",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        );
    }
    if std::env::var("STAFF_TOTP_KEK_VERSION").is_err() {
        std::env::set_var("STAFF_TOTP_KEK_VERSION", "1");
    }
}

/// KEK para tests (32 bytes de ceros, version 1).
fn test_kek() -> auth_admin::keystore::Kek {
    auth_admin::keystore::Kek::new([0u8; 32], 1)
}

/// Hash de password — computado una sola vez porque argon2id m=64MB es lento.
fn staff_password_hash() -> &'static str {
    static HASH: OnceLock<String> = OnceLock::new();
    HASH.get_or_init(|| {
        setup_kek_env();
        auth_admin::password::hash("test-password").unwrap()
    })
}

/// Email unico por llamada (uuid-based, evita colisiones entre tests).
fn unique_email() -> String {
    format!("admin_{}@test.com", uuid::Uuid::new_v4().simple())
}

/// Helper POST sin autenticacion.
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

/// Helper POST con autenticacion Bearer.
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

/// Construye el contexto de test (app + pool + kek).
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
    TestContext {
        app,
        pool,
        kek: test_kek(),
    }
}

/// Crea un staff en la BD y retorna (staff_id, totp_raw_bytes, email).
///
/// El staff se crea con password "test-password" y rol "moderator".
/// TOTP secret: 20 bytes random, cifrados con `kek`.
async fn seed_staff(ctx: &TestContext, email: &str) -> (uuid::Uuid, Vec<u8>) {
    let secret = totp_rs::Secret::generate_secret();
    let totp_raw = secret.to_bytes().expect("Secret::to_bytes");
    let encrypted = auth_admin::totp::encrypt_secret(&ctx.kek.key, &totp_raw).unwrap();
    let hash = staff_password_hash();

    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO staff (email, password_hash, totp_secret_enc, totp_enabled_at, recovery_codes_hash, role, status) VALUES ($1, $2, $3, now(), '{}'::text[], 'moderator', 'active') RETURNING id",
    )
    .bind(email)
    .bind(hash)
    .bind(&encrypted[..])
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_staff insert failed");

    (id, totp_raw)
}

/// Genera el codigo TOTP actual para un secret raw.
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn login_with_valid_credentials_returns_mfa_token() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_, _) = seed_staff(&ctx, &email).await;

    let (st, body) = post(
        &ctx.app,
        "/admin/auth/login",
        serde_json::json!({"email": email, "password": "test-password"}),
    )
    .await;

    assert_eq!(st, StatusCode::OK, "login should 200");
    assert!(
        body["mfa_token"].is_string(),
        "mfa_token should be a string, got: {body}"
    );
    assert!(!body["mfa_token"].as_str().unwrap().is_empty());
}

#[tokio::test]
async fn login_with_wrong_password_returns_401() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_, _) = seed_staff(&ctx, &email).await;

    let (st, _body) = post(
        &ctx.app,
        "/admin/auth/login",
        serde_json::json!({"email": email, "password": "wrong-password"}),
    )
    .await;

    assert_eq!(st, StatusCode::UNAUTHORIZED, "wrong password should 401");
}

#[tokio::test]
async fn login_with_nonexistent_email_returns_401() {
    let ctx = test_context().await;

    let (st, _body) = post(
        &ctx.app,
        "/admin/auth/login",
        serde_json::json!({"email": "nobody@nonexistent.com", "password": "test-password"}),
    )
    .await;

    assert_eq!(
        st,
        StatusCode::UNAUTHORIZED,
        "nonexistent email should 401"
    );
}

#[tokio::test]
async fn two_factor_with_valid_mfa_and_totp_returns_jwt() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_, totp_raw) = seed_staff(&ctx, &email).await;

    // 1. Login → mfa_token
    let (st, body) = post(
        &ctx.app,
        "/admin/auth/login",
        serde_json::json!({"email": email, "password": "test-password"}),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "login should 200");
    let mfa_token = body["mfa_token"].as_str().unwrap().to_string();

    // 2. Generate current TOTP code
    let code = current_totp_code(&totp_raw);

    // 3. 2FA → JWT
    let (st2, body2) = post(
        &ctx.app,
        "/admin/auth/2fa",
        serde_json::json!({"mfa_token": mfa_token, "totp_code": code}),
    )
    .await;

    assert_eq!(st2, StatusCode::OK, "2fa should 200, got: {body2}");
    assert!(
        body2["access_token"].is_string(),
        "access_token should be a string"
    );
    assert!(
        body2["session_id"].is_string(),
        "session_id should be a string"
    );
    assert!(!body2["access_token"].as_str().unwrap().is_empty());
    assert!(!body2["session_id"].as_str().unwrap().is_empty());
}

#[tokio::test]
async fn two_factor_with_invalid_totp_returns_401() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_, _) = seed_staff(&ctx, &email).await;

    // Login → mfa_token
    let (st, body) = post(
        &ctx.app,
        "/admin/auth/login",
        serde_json::json!({"email": email, "password": "test-password"}),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let mfa_token = body["mfa_token"].as_str().unwrap().to_string();

    // 2FA with wrong code
    let (st2, _body2) = post(
        &ctx.app,
        "/admin/auth/2fa",
        serde_json::json!({"mfa_token": mfa_token, "totp_code": "000000"}),
    )
    .await;

    assert_eq!(st2, StatusCode::UNAUTHORIZED, "wrong totp should 401");
}

#[tokio::test]
async fn logout_with_valid_session_returns_204() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_, totp_raw) = seed_staff(&ctx, &email).await;

    // Login → mfa_token
    let (_st, body) = post(
        &ctx.app,
        "/admin/auth/login",
        serde_json::json!({"email": email, "password": "test-password"}),
    )
    .await;
    let mfa_token = body["mfa_token"].as_str().unwrap().to_string();

    // 2FA → JWT + session_id
    let code = current_totp_code(&totp_raw);
    let (st2, body2) = post(
        &ctx.app,
        "/admin/auth/2fa",
        serde_json::json!({"mfa_token": mfa_token, "totp_code": code}),
    )
    .await;
    assert_eq!(st2, StatusCode::OK);
    let access_token = body2["access_token"].as_str().unwrap().to_string();
    let session_id = body2["session_id"].as_str().unwrap().to_string();

    // Logout
    let (st3, _body3) = post_auth(
        &ctx.app,
        "/admin/auth/logout",
        serde_json::json!({"session_id": session_id}),
        &access_token,
    )
    .await;

    assert_eq!(st3, StatusCode::NO_CONTENT, "logout should 204");
}

#[tokio::test]
async fn unauthenticated_request_returns_401() {
    let ctx = test_context().await;

    let (st, _body) = post(
        &ctx.app,
        "/admin/auth/logout",
        serde_json::json!({"session_id": "00000000-0000-0000-0000-000000000000"}),
    )
    .await;

    assert_eq!(
        st,
        StatusCode::UNAUTHORIZED,
        "no auth should 401 on logout"
    );
}
