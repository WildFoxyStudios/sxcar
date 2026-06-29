//! Integration tests for admin RBAC + Audit middleware (T11 — AD1).
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
}

/// URL de la BD de test (default: local dev).
fn test_db_url() -> String {
    std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://dev:dev@localhost:5433/appdb".to_string())
}

/// Asegura que las env vars KEK esten seteadas.
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
    format!("admin_mw_{}@test.com", uuid::Uuid::new_v4().simple())
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

/// Helper GET sin autenticacion.
async fn get(app: &axum::Router, uri: &str) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
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

/// Construye el contexto de test (app + pool).
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

/// Crea un staff en la BD y retorna (staff_id, totp_raw_bytes, email).
///
/// El staff se crea con password "test-password" y el rol indicado.
/// TOTP secret: 20 bytes random, cifrados con `kek`.
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

/// Helper: login + 2FA -> JWT.
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
async fn staff_without_permission_gets_403() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "support").await;

    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Hit the protected test route (requires "user.delete", which "support"
    // does NOT have per the migration 0011 seed).
    let (st, _body) = post_auth(
        &ctx.app,
        "/admin/_test_protected",
        serde_json::json!({}),
        &jwt,
    )
    .await;

    assert_eq!(
        st,
        StatusCode::FORBIDDEN,
        "expected 403 for missing 'user.delete' permission"
    );
}

#[tokio::test]
async fn unauthorized_request_not_audited() {
    let ctx = test_context().await;

    // Count existing audit_log rows before the request.
    let count_before: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM audit_log")
        .fetch_one(&ctx.pool)
        .await
        .expect("count_before");

    // Make an unauthenticated GET to a protected admin route.
    let (st, _body) = get(&ctx.app, "/admin/_test_auth").await;
    assert_eq!(
        st,
        StatusCode::UNAUTHORIZED,
        "expected 401 without Bearer token"
    );

    // Verify no audit_log row was inserted for this request.
    let count_after: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM audit_log")
        .fetch_one(&ctx.pool)
        .await
        .expect("count_after");

    assert_eq!(
        count_before, count_after,
        "unauthenticated requests must not produce audit_log entries"
    );
}
