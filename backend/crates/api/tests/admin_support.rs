//! Integration tests for admin support/GDPR/legal endpoints (AD4).
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
    format!("ad4_staff_{}@test.com", uuid::Uuid::new_v4().simple())
}

/// Email unico para usuario normal (no staff).
fn unique_user_email() -> String {
    format!("ad4_user_{}@test.com", uuid::Uuid::new_v4().simple())
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

/// Helper GET con autenticacion Bearer y body JSON.
async fn get_auth_body(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
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

/// Crea una suscripcion en la BD.
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

/// Crea una entitlement en la BD.
async fn seed_entitlement(ctx: &TestContext, user_id: uuid::Uuid, feature: &str) {
    sqlx::query(
        "INSERT INTO entitlements (user_id, feature, enabled) VALUES ($1, $2, true) ON CONFLICT DO NOTHING",
    )
    .bind(user_id)
    .bind(feature)
    .execute(&ctx.pool)
    .await
    .expect("seed_entitlement insert failed");
}

/// Crea una data_request en la BD.
async fn seed_data_request(
    ctx: &TestContext,
    user_id: uuid::Uuid,
    kind: &str,
    status: &str,
) -> uuid::Uuid {
    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO data_requests (user_id, kind, status) VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(user_id)
    .bind(kind)
    .bind(status)
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_data_request insert failed");
    id
}

/// Crea un profile en la BD.
async fn seed_profile(ctx: &TestContext, user_id: uuid::Uuid, display_name: &str) {
    sqlx::query(
        "INSERT INTO profiles (user_id, display_name) VALUES ($1, $2)",
    )
    .bind(user_id)
    .bind(display_name)
    .execute(&ctx.pool)
    .await
    .expect("seed_profile insert failed");
}

/// Crea un device en la BD.
async fn seed_device(ctx: &TestContext, user_id: uuid::Uuid, platform: &str) -> uuid::Uuid {
    let id: uuid::Uuid = sqlx::query_scalar(
        "INSERT INTO devices (user_id, platform, push_token) VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(user_id)
    .bind(platform)
    .bind(uuid::Uuid::new_v4().simple().to_string())
    .fetch_one(&ctx.pool)
    .await
    .expect("seed_device insert failed");
    id
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn view_entitlements_returns_subs_and_entitlements() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    let _sub_id = seed_subscription(&ctx, user_id, "xtra").await;
    seed_entitlement(&ctx, user_id, "unlimited_likes").await;

    let (st, body) = get_auth(
        &ctx.app,
        &format!("/admin/support/users/{user_id}/entitlements"),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(
        body["subscriptions"].is_array(),
        "subscriptions should be an array"
    );
    assert!(
        body["entitlements"].is_array(),
        "entitlements should be an array"
    );

    let subs = body["subscriptions"].as_array().unwrap();
    assert_eq!(subs.len(), 1, "should have 1 subscription");
    assert_eq!(subs[0]["tier"], "xtra");

    let ents = body["entitlements"].as_array().unwrap();
    assert_eq!(ents.len(), 1, "should have 1 entitlement");
    assert_eq!(ents[0]["feature"], "unlimited_likes");
    assert_eq!(ents[0]["enabled"], true);
}

#[tokio::test]
async fn grant_entitlement_adds_row() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    // Grant entitlement via API
    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/support/users/{user_id}/entitlements"),
        serde_json::json!({"feature": "boost", "action": "grant"}),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["status"], "grant");

    // Verify in DB
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM entitlements WHERE user_id = $1 AND feature = 'boost' AND enabled = true")
            .bind(user_id)
            .fetch_one(&ctx.pool)
            .await
            .expect("select entitlement count");
    assert_eq!(count, 1, "entitlement should be created in DB");

    // Revoke via API
    let (st2, _) = post_auth(
        &ctx.app,
        &format!("/admin/support/users/{user_id}/entitlements"),
        serde_json::json!({"feature": "boost", "action": "revoke"}),
        &jwt,
    )
    .await;
    assert_eq!(st2, StatusCode::OK, "revoke should succeed");

    // Verify revoked in DB
    let enabled: bool =
        sqlx::query_scalar("SELECT enabled FROM entitlements WHERE user_id = $1 AND feature = 'boost'")
            .bind(user_id)
            .fetch_one(&ctx.pool)
            .await
            .expect("select entitlement enabled");
    assert!(!enabled, "entitlement should be disabled after revoke");
}

#[tokio::test]
async fn list_data_requests_filters_by_status() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    let pending_id = seed_data_request(&ctx, user_id, "export", "pending").await;
    let _completed_id = seed_data_request(&ctx, user_id, "delete", "completed").await;

    // Filter by status=pending
    let (st, body) = get_auth(
        &ctx.app,
        "/admin/gdpr/data-requests?status=pending",
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert!(body["requests"].is_array(), "requests should be an array");
    assert!(
        body["total"].as_i64().unwrap_or(0) >= 1,
        "total should be at least 1, got {:?}",
        body["total"]
    );

    let pending_id_str = pending_id.to_string();
    let req_ids: Vec<String> = body["requests"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["id"].as_str().unwrap().to_string())
        .collect();
    assert!(
        req_ids.contains(&pending_id_str),
        "pending request should be in the list"
    );
    // Ensure completed request is NOT in the results
    let completed_id_str = _completed_id.to_string();
    assert!(
        !req_ids.contains(&completed_id_str),
        "completed request should NOT appear in pending filter"
    );
}

#[tokio::test]
async fn process_data_request_changes_status() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    let req_id = seed_data_request(&ctx, user_id, "export", "pending").await;

    // Process to "processing"
    let (st, body) = post_auth(
        &ctx.app,
        &format!("/admin/gdpr/data-requests/{req_id}/process"),
        serde_json::json!({"status": "processing"}),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");
    assert_eq!(body["status"], "processing");

    // Verify in DB
    let db_status: String =
        sqlx::query_scalar("SELECT status FROM data_requests WHERE id = $1")
            .bind(req_id)
            .fetch_one(&ctx.pool)
            .await
            .expect("select data_request status");
    assert_eq!(db_status, "processing", "should be 'processing' in DB");

    // Process to "completed"
    let (st2, body2) = post_auth(
        &ctx.app,
        &format!("/admin/gdpr/data-requests/{req_id}/process"),
        serde_json::json!({"status": "completed", "notes": "export sent to user"}),
        &jwt,
    )
    .await;

    assert_eq!(st2, StatusCode::OK, "expected 200, got {st2}: {body2}");
    assert_eq!(body2["status"], "completed");

    // Verify completed_at is set
    let completed_at: Option<time::OffsetDateTime> =
        sqlx::query_scalar("SELECT completed_at FROM data_requests WHERE id = $1")
            .bind(req_id)
            .fetch_one(&ctx.pool)
            .await
            .expect("select completed_at");
    assert!(
        completed_at.is_some(),
        "completed_at should be set after completion"
    );
}

#[tokio::test]
async fn legal_export_returns_dossier() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    // Seed profile + device + subscription
    seed_profile(&ctx, user_id, "TestUser").await;
    let _dev_id = seed_device(&ctx, user_id, "ios").await;
    let _sub_id = seed_subscription(&ctx, user_id, "xtra").await;

    // GET with body for legal export
    let (st, body) = get_auth_body(
        &ctx.app,
        &format!("/admin/legal/export/{user_id}"),
        serde_json::json!({
            "justification": "court order #123",
            "legal_basis": "GDPR Art. 15"
        }),
        &jwt,
    )
    .await;

    assert_eq!(st, StatusCode::OK, "expected 200, got {st}: {body}");

    // Verify dossier structure
    assert!(
        body["user"].is_object(),
        "dossier should have user object"
    );
    assert_eq!(
        body["user"]["email"], user_email,
        "user email should match"
    );
    assert!(
        body["profile"].is_object(),
        "dossier should have profile object"
    );
    assert_eq!(
        body["profile"]["display_name"], "TestUser",
        "profile display_name should match"
    );
    assert!(body["devices"].is_array(), "dossier should have devices array");
    assert_eq!(
        body["devices"].as_array().unwrap().len(),
        1,
        "should have 1 device"
    );
    assert!(
        body["subscriptions"].is_array(),
        "dossier should have subscriptions array"
    );
    assert_eq!(
        body["subscriptions"].as_array().unwrap().len(),
        1,
        "should have 1 subscription"
    );
    assert_eq!(
        body["subscriptions"][0]["tier"], "xtra",
        "subscription tier should match"
    );

    // Verify audit log was written manually
    let audit_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM audit_log WHERE action LIKE '%legal/export%' AND legal_basis IS NOT NULL",
    )
    .fetch_one(&ctx.pool)
    .await
    .expect("select audit count");
    assert!(
        audit_count >= 1,
        "legal export should be audited with legal_basis"
    );
}

#[tokio::test]
async fn place_and_release_legal_hold() {
    let ctx = test_context().await;
    let email = unique_email();
    let (_staff_id, totp_raw) = seed_staff(&ctx, &email, "admin").await;
    let jwt = login_and_get_jwt(&ctx.app, &email, &totp_raw).await;

    let user_email = unique_user_email();
    let user_id = seed_user(&ctx, &user_email).await;

    // Place legal hold
    let (st, body) = post_auth(
        &ctx.app,
        "/admin/legal/hold",
        serde_json::json!({
            "user_id": user_id,
            "reason": "court order #456",
            "reference": "CR-2026-07-001"
        }),
        &jwt,
    )
    .await;

    assert_eq!(
        st,
        StatusCode::CREATED,
        "expected 201, got {st}: {body}"
    );
    let hold_id = body["id"].as_str().unwrap();
    assert!(!hold_id.is_empty(), "hold_id should be present");

    // Verify hold appears in list (query DB directly)
    let hold_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM legal_holds WHERE user_id = $1 AND released_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(&ctx.pool)
    .await
    .expect("select legal_hold count");
    assert_eq!(hold_count, 1, "legal hold should be active");

    // Release the hold
    let (st2, body2) = post_auth(
        &ctx.app,
        &format!("/admin/legal/hold/{hold_id}/release"),
        serde_json::json!({"reason": "case closed"}),
        &jwt,
    )
    .await;

    assert_eq!(st2, StatusCode::OK, "expected 200, got {st2}: {body2}");
    assert_eq!(body2["status"], "released");

    // Verify released_at is set
    let released_at: Option<time::OffsetDateTime> = sqlx::query_scalar(
        "SELECT released_at FROM legal_holds WHERE id = $1",
    )
    .bind(uuid::Uuid::parse_str(hold_id).unwrap())
    .fetch_one(&ctx.pool)
    .await
    .expect("select released_at");
    assert!(
        released_at.is_some(),
        "released_at should be set after release"
    );
}
