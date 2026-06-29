//! Integration tests for admin moderation endpoints (AD3).
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

/// Email unico para staff (uuid-based, evita colisiones entre tests).
fn unique_email() -> String {
    format!("ad3_mod_{}@test.com", uuid::Uuid::new_v4().simple())
}

/// Email unico para usuario normal (no staff).
fn unique_user_email() -> String {
    format!("ad3_target_{}@test.com", uuid::Uuid::new_v4().simple())
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Test setup helpers
// ---------------------------------------------------------------------------

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

/// Crea un usuario normal en la BD.
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

/// Crea un reporte en la BD.
async fn seed_report(
    ctx: &TestContext,
    reporter_id: uuid::Uuid,
    target_user_id: uuid::Uuid,
    status: &str,
) -> uuid::Uuid {
    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO reports (reporter_id, target_user_id, target_kind, reason, status) VALUES ($1, $2, 'profile', 'test reason', $3) RETURNING id",
    )
    .bind(reporter_id)
    .bind(target_user_id)
    .bind(status)
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_report insert failed");
    id
}

/// Crea una foto en la BD.
async fn seed_photo(ctx: &TestContext, user_id: uuid::Uuid, status: &str) -> uuid::Uuid {
    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO photos (user_id, r2_key, moderation_status) VALUES ($1, 'test-key', $2) RETURNING id",
    )
    .bind(user_id)
    .bind(status)
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_photo insert failed");
    id
}

/// Crea un hit de CSAM en la BD.
async fn seed_csam_hit(ctx: &TestContext, status: &str) -> uuid::Uuid {
    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO csam_hits (hash, source, status) VALUES ('test-hash', 'test-source', $1) RETURNING id",
    )
    .bind(status)
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_csam_hit insert failed");
    id
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn list_reports_returns_open_reports() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let reporter_email = unique_user_email();
    let target_email = unique_user_email();
    let reporter_id = seed_user(&ctx, &reporter_email).await;
    let target_id = seed_user(&ctx, &target_email).await;

    let open_id = seed_report(&ctx, reporter_id, target_id, "open").await;
    let dismissed_id = seed_report(&ctx, reporter_id, target_id, "dismissed").await;

    let (st, body) = get_auth(&ctx.app, "/admin/reports?status=open", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["reports"].is_array(), "reports should be an array");
    // Verificar que el reporte "open" esta presente y el "dismissed" no
    let open_id_str = open_id.to_string();
    let dismissed_id_str = dismissed_id.to_string();
    let report_ids: Vec<String> = body["reports"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["id"].as_str().unwrap().to_string())
        .collect();
    assert!(
        report_ids.contains(&open_id_str),
        "open report should be in the list"
    );
    assert!(
        !report_ids.contains(&dismissed_id_str),
        "dismissed report should NOT be in the list"
    );
}

#[tokio::test]
async fn review_report_transitions_to_reviewing() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let reporter_email = unique_user_email();
    let target_email = unique_user_email();
    let reporter_id = seed_user(&ctx, &reporter_email).await;
    let target_id = seed_user(&ctx, &target_email).await;

    let report_id = seed_report(&ctx, reporter_id, target_id, "open").await;

    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/reports/{report_id}/review"),
        serde_json::json!({}),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["status"], "reviewing");

    // Verificar en DB
    let db_status: String = sqlx::query_scalar("SELECT status FROM reports WHERE id = $1")
        .bind(report_id)
        .fetch_one(&ctx.pool)
        .await
        .expect("select report status");
    assert_eq!(db_status, "reviewing", "report should be 'reviewing' in DB");
}

#[tokio::test]
async fn resolve_report_actioned_creates_moderation_action() {
    let ctx = test_context().await;
    let email = unique_email();
    let (staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let reporter_email = unique_user_email();
    let target_email = unique_user_email();
    let reporter_id = seed_user(&ctx, &reporter_email).await;
    let target_id = seed_user(&ctx, &target_email).await;

    let report_id = seed_report(&ctx, reporter_id, target_id, "open").await;

    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/reports/{report_id}/resolve"),
        serde_json::json!({
            "resolution": "actioned",
            "action": "ban",
            "note": "spam account"
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["report_status"], "actioned");
    assert!(
        body["moderation_action_id"].is_string(),
        "moderation_action_id should be present"
    );

    // Verificar report status en DB
    let report_status: String = sqlx::query_scalar("SELECT status FROM reports WHERE id = $1")
        .bind(report_id)
        .fetch_one(&ctx.pool)
        .await
        .expect("select report status");
    assert_eq!(report_status, "actioned", "report should be 'actioned' in DB");

    // Verificar moderation_action creado
    let action_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM moderation_actions WHERE staff_id = $1 AND target_user_id = $2 AND action = 'ban'",
    )
    .bind(staff_id)
    .bind(target_id)
    .fetch_one(&ctx.pool)
    .await
    .expect("select moderation_action count");
    assert_eq!(action_count, 1, "moderation_action should be created");

    // Verificar usuario baneado
    let user_status: String = sqlx::query_scalar("SELECT status FROM users WHERE id = $1")
        .bind(target_id)
        .fetch_one(&ctx.pool)
        .await
        .expect("select user status");
    assert_eq!(user_status, "banned", "user should be banned");
}

#[tokio::test]
async fn resolve_report_dismissed_does_not_ban() {
    let ctx = test_context().await;
    let email = unique_email();
    let (staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let reporter_email = unique_user_email();
    let target_email = unique_user_email();
    let reporter_id = seed_user(&ctx, &reporter_email).await;
    let target_id = seed_user(&ctx, &target_email).await;

    let report_id = seed_report(&ctx, reporter_id, target_id, "open").await;

    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/reports/{report_id}/resolve"),
        serde_json::json!({
            "resolution": "dismissed",
            "action": "clear",
            "note": "no violation found"
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["report_status"], "dismissed");
    assert!(
        body["moderation_action_id"].is_null(),
        "moderation_action_id should be null for dismissed"
    );

    // Verificar usuario sigue activo
    let user_status: String = sqlx::query_scalar("SELECT status FROM users WHERE id = $1")
        .bind(target_id)
        .fetch_one(&ctx.pool)
        .await
        .expect("select user status");
    assert_eq!(user_status, "active", "user should remain active");

    // Verificar que NO se creo moderation_action con este staff
    let action_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM moderation_actions WHERE staff_id = $1",
    )
    .bind(staff_id)
    .fetch_one(&ctx.pool)
    .await
    .expect("select moderation_action count");
    assert_eq!(action_count, 0, "no moderation_action should be created");
}

#[tokio::test]
async fn list_pending_photos_returns_only_pending() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    let pending_id = seed_photo(&ctx, user_id, "pending").await;
    let approved_id = seed_photo(&ctx, user_id, "approved").await;

    let (st, body) = get_auth(&ctx.app, "/admin/moderation/photos", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["photos"].is_array(), "photos should be an array");
    // Verificar que la foto "pending" esta presente y la "approved" no
    let pending_id_str = pending_id.to_string();
    let approved_id_str = approved_id.to_string();
    let photo_ids: Vec<String> = body["photos"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["id"].as_str().unwrap().to_string())
        .collect();
    assert!(
        photo_ids.contains(&pending_id_str),
        "pending photo should be in the list"
    );
    assert!(
        !photo_ids.contains(&approved_id_str),
        "approved photo should NOT be in the list"
    );
}

#[tokio::test]
async fn approve_photo_changes_status() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;
    let photo_id = seed_photo(&ctx, user_id, "pending").await;

    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/moderation/photos/{photo_id}/approve"),
        serde_json::json!({}),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["status"], "approved");

    // Verificar en DB
    let db_status: String = sqlx::query_scalar(
        "SELECT moderation_status FROM photos WHERE id = $1",
    )
    .bind(photo_id)
    .fetch_one(&ctx.pool)
    .await
    .expect("select photo moderation_status");
    assert_eq!(db_status, "approved", "photo should be 'approved' in DB");
}

#[tokio::test]
async fn reject_photo_changes_status() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;
    let photo_id = seed_photo(&ctx, user_id, "pending").await;

    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/moderation/photos/{photo_id}/reject"),
        serde_json::json!({}),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["status"], "rejected");

    // Verificar en DB
    let db_status: String = sqlx::query_scalar(
        "SELECT moderation_status FROM photos WHERE id = $1",
    )
    .bind(photo_id)
    .fetch_one(&ctx.pool)
    .await
    .expect("select photo moderation_status");
    assert_eq!(db_status, "rejected", "photo should be 'rejected' in DB");
}

#[tokio::test]
async fn list_csam_hits_and_report_to_authority() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    // Seed 2 hits: 1 pending, 1 already dismissed
    let hit_id = seed_csam_hit(&ctx, "pending").await;
    let _dismissed_id = seed_csam_hit(&ctx, "dismissed").await;

    // List pending hits
    let (st, body) = get_auth(&ctx.app, "/admin/csam?status=pending", &jwt).await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["hits"].is_array(), "hits should be an array");
    assert_eq!(
        body["hits"].as_array().unwrap().len(),
        1,
        "should return exactly 1 pending hit"
    );
    assert_eq!(body["total"], 1, "total should be 1");

    // Report the pending hit to authority
    let (st2, body2) = post_auth(
        &ctx.app,
        &format!("/admin/csam/{hit_id}/report"),
        serde_json::json!({"notes": "reported to law enforcement"}),
        &jwt,
    )
    .await;

    assert_eq!(st2, StatusCode::OK, "expected 200, got {st2}: {body2}");
    assert_eq!(body2["status"], "reported");

    // Verificar en DB
    let db_status: String = sqlx::query_scalar("SELECT status FROM csam_hits WHERE id = $1")
        .bind(hit_id)
        .fetch_one(&ctx.pool)
        .await
        .expect("select csam status");
    assert_eq!(db_status, "reported", "CSAM hit should be 'reported' in DB");

    let reported_at: Option<time::OffsetDateTime> = sqlx::query_scalar(
        "SELECT reported_to_authority_at FROM csam_hits WHERE id = $1",
    )
    .bind(hit_id)
    .fetch_one(&ctx.pool)
    .await
    .expect("select reported_to_authority_at");
    assert!(
        reported_at.is_some(),
        "reported_to_authority_at should NOT be NULL after reporting"
    );
}
