//! Integration tests for admin user management endpoints (AD2).
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
    format!("ad2_user_{}@test.com", uuid::Uuid::new_v4().simple())
}

/// Email unico para usuario normal (no staff).
fn unique_user_email() -> String {
    format!("ad2_target_{}@test.com", uuid::Uuid::new_v4().simple())
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

/// Helper GET con autenticacion Bearer.
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

/// Crea un staff en la BD y retorna (staff_id, totp_raw_bytes).
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

/// Crea un usuario normal en la BD (target de acciones admin).
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
async fn list_users_requires_auth() {
    let ctx = test_context().await;

    // GET /admin/users sin token → 401
    let (st, _body) = get(&ctx.app, "/admin/users").await;

    assert_eq!(
        st,
        StatusCode::UNAUTHORIZED,
        "expected 401 without Bearer token"
    );
}

#[tokio::test]
async fn list_users_returns_paginated() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Seed al menos un usuario para que la lista no este vacia
    let user_email = unique_user_email();
    seed_user(&ctx, &user_email).await;

    let (st, body) = get_auth(&ctx.app, "/admin/users?limit=10&offset=0", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["users"].is_array(), "users should be an array");
    assert!(body["total"].is_number(), "total should be a number");
    assert!(body["by_status"].is_array(), "by_status should be an array");
}

#[tokio::test]
async fn get_user_by_id_returns_full_profile() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    let (st, body) = get_auth(&ctx.app, &format!("/admin/users/{user_id}"), &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(
        body["user"]["id"].as_str(),
        Some(user_id.to_string()).as_deref()
    );
    assert_eq!(
        body["user"]["email"].as_str(),
        Some(user_email.as_str()),
        "email should match"
    );
}

#[tokio::test]
async fn get_user_returns_404_for_nonexistent() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let fake_id = uuid::Uuid::new_v4();
    let (st, _body) = get_auth(
        &ctx.app,
        &format!("/admin/users/{fake_id}"),
        &jwt,
    )
    .await;

    assert_eq!(
        st,
        StatusCode::NOT_FOUND,
        "expected 404 for nonexistent user"
    );
}

#[tokio::test]
async fn ban_user_bans_and_returns_200() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/users/{user_id}/ban"),
        serde_json::json!({"reason": "spam"}),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["status"], "banned");

    // Verificar en DB que el status cambió
    let status: String = sqlx::query_scalar("SELECT status FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(&ctx.pool)
        .await
        .expect("select status");
    assert_eq!(status, "banned", "user should be banned in DB");
}

#[tokio::test]
async fn suspend_user_suspends() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/users/{user_id}/suspend"),
        serde_json::json!({"reason": "TOS violation"}),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["status"], "suspended");

    let status: String = sqlx::query_scalar("SELECT status FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(&ctx.pool)
        .await
        .expect("select status");
    assert_eq!(status, "suspended", "user should be suspended in DB");
}

#[tokio::test]
async fn activate_user_reactivates() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    // Primero banear, luego activar
    let (_st, _) = post_auth(
        &ctx.app,
        &format!("/admin/users/{user_id}/ban"),
        serde_json::json!({"reason": "test"}),
        &jwt,
    )
    .await;

    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/users/{user_id}/activate"),
        serde_json::json!({}),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["status"], "active");

    let status: String = sqlx::query_scalar("SELECT status FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(&ctx.pool)
        .await
        .expect("select status");
    assert_eq!(status, "active", "user should be active in DB");
}

#[tokio::test]
async fn force_logout_revokes_tokens() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Crear usuario con refresh token
    let user_email = unique_user_email();
    use sha2::{Digest, Sha256};
    let token_raw = uuid::Uuid::new_v4().to_string();
    let token_hash = format!("{:x}", Sha256::digest(token_raw.as_bytes()));

    let user_id = sqlx::query_scalar::<_, uuid::Uuid>(
        "INSERT INTO users (email, status) VALUES ($1, 'active') RETURNING id",
    )
    .bind(&user_email)
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_user");

    sqlx::query(
        "INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, now() + interval '30 days')",
    )
    .bind(user_id)
    .bind(&token_hash)
    .execute(&ctx.pool)
    .await
    .expect("insert refresh token");

    // Verificar que el refresh token existe y no está revocado
    let before: bool = sqlx::query_scalar(
        "SELECT (revoked_at IS NOT NULL) FROM refresh_tokens WHERE token_hash = $1",
    )
    .bind(&token_hash)
    .fetch_one(&ctx.pool)
    .await
    .expect("select refresh token");
    assert!(!before, "refresh token should not be revoked before force-logout");

    // Staff hace force-logout
    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/users/{user_id}/force-logout"),
        serde_json::json!({"reason": "security incident"}),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["revoked"], true);

    // Verificar que el refresh token ahora está revocado
    let after: bool = sqlx::query_scalar(
        "SELECT (revoked_at IS NOT NULL) FROM refresh_tokens WHERE token_hash = $1",
    )
    .bind(&token_hash)
    .fetch_one(&ctx.pool)
    .await
    .expect("select refresh token");
    assert!(after, "refresh token should be revoked after force-logout");
}

#[tokio::test]
async fn staff_without_permission_gets_403() {
    let ctx = test_context().await;
    // Staff con role "support" — NO tiene user.ban segun seed de migration 0011
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "support").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/users/{user_id}/ban"),
        serde_json::json!({"reason": "spam"}),
        &jwt,
    )
    .await;

    assert_eq!(
        st,
        StatusCode::FORBIDDEN,
        "expected 403, got {st}: {body}"
    );

    // Verificar que el usuario NO fue baneado
    let status: String = sqlx::query_scalar("SELECT status FROM users WHERE id = $1")
        .bind(user_id)
        .fetch_one(&ctx.pool)
        .await
        .expect("select status");
    assert_eq!(status, "active", "user should remain active");
}
