//! Integration tests for the RevenueCat webhook receiver (G7a).
//!
//! Covers:
//!   valid_initial_purchase_grants_active_sub — INITIAL_PURCHASE → active row in DB
//!   bad_secret_401                           — wrong Authorization → 401
//!   test_event_200                           — type=TEST → 200, no DB change
//!   expiration_downgrades                    — grant then EXPIRATION → sub inactive
//!   unknown_user_acked_200                   — random UUID → 200, no crash
//!
//! DB: docker Postgres localhost:5433 (same as other billing tests).
//! Secret: "test-rc-webhook-secret" (set via env before AppState init).

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use tower::ServiceExt;

const TEST_SECRET: &str = "test-rc-webhook-secret";

fn test_db_url() -> String {
    std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://dev:dev@localhost:5433/appdb".to_string())
}

/// Build a test app with `REVENUECAT_WEBHOOK_SECRET` set.
/// Returns the axum Router and a direct DB pool for assertion queries.
async fn test_app() -> (axum::Router, sqlx::PgPool) {
    // Set the secret before AppState reads the env var.
    std::env::set_var("REVENUECAT_WEBHOOK_SECRET", TEST_SECRET);

    let pool = db::connect(&test_db_url()).await.unwrap();
    db::migrate(&pool).await.unwrap();

    let deps = api::AppDeps {
        jwt: auth::jwt::JwtConfig {
            secret: "test-webhook-jwt".into(),
            access_ttl_secs: 900,
        },
        refresh_ttl_secs: 3600,
        notifier: std::sync::Arc::new(auth::notify::DevNotifier),
        oauth: std::sync::Arc::new(auth::oauth::DevOAuthVerifier),
    };
    let app = api::app(pool.clone(), deps);
    (app, pool)
}

// ─── HTTP helpers ─────────────────────────────────────────────────────────────

async fn post_no_auth(
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
                .header("host", "localhost")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, json)
}

/// POST to the RC webhook endpoint with an explicit Authorization header value.
/// Pass `None` to omit the header entirely.
async fn post_webhook(
    app: &axum::Router,
    body: serde_json::Value,
    auth_header: Option<&str>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method("POST")
        .uri("/billing/revenuecat/webhook")
        .header("host", "localhost")
        .header("content-type", "application/json");

    if let Some(secret) = auth_header {
        builder = builder.header("authorization", secret);
    }

    let res = app
        .clone()
        .oneshot(builder.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();

    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, json)
}

// ─── Test helpers ─────────────────────────────────────────────────────────────

/// Register a fresh user and return their UUID (via direct DB query) + JWT.
async fn register_user(app: &axum::Router, pool: &sqlx::PgPool) -> (uuid::Uuid, String) {
    let email = format!("rc_wh_{}@test.com", uuid::Uuid::new_v4().simple());
    let (st, body) = post_no_auth(
        app,
        "/auth/register",
        serde_json::json!({
            "email": email,
            "password": "secret123",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "register failed: {body}");
    let token = body["access"].as_str().unwrap().to_string();

    let user_id: uuid::Uuid =
        sqlx::query_scalar("SELECT id FROM users WHERE email = $1")
            .bind(&email)
            .fetch_one(pool)
            .await
            .expect("user not found in DB after register");

    (user_id, token)
}

/// Build a minimal RC event body.
fn rc_event(
    event_type: &str,
    user_id: uuid::Uuid,
    entitlement_ids: &[&str],
    expiration_at_ms: Option<i64>,
) -> serde_json::Value {
    serde_json::json!({
        "api_version": "1.0",
        "event": {
            "type": event_type,
            "app_user_id": user_id.to_string(),
            "product_id": "vibra_plus_monthly",
            "entitlement_ids": entitlement_ids,
            "expiration_at_ms": expiration_at_ms,
            "environment": "SANDBOX"
        }
    })
}

// ─── Tests ────────────────────────────────────────────────────────────────────

/// INITIAL_PURCHASE with correct secret grants an active subscription.
#[tokio::test]
async fn valid_initial_purchase_grants_active_sub() {
    let (app, pool) = test_app().await;
    let (user_id, _token) = register_user(&app, &pool).await;

    // ~30 days from now in epoch-ms.
    let exp_ms: i64 = (time::OffsetDateTime::now_utc() + time::Duration::days(30))
        .unix_timestamp()
        * 1000;

    let payload = rc_event("INITIAL_PURCHASE", user_id, &["vibra_plus"], Some(exp_ms));
    let (status, body) = post_webhook(&app, payload, Some(TEST_SECRET)).await;
    assert_eq!(status, StatusCode::OK, "expected 200, got {status}: {body}");
    assert_eq!(body["ok"], true);

    // Verify DB: one active revenuecat row with a future expiry.
    let count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM subscriptions
           WHERE user_id   = $1
             AND plan_code = 'vibra_plus'
             AND source    = 'revenuecat'
             AND status    = 'active'
             AND expires_at > now()"#,
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert_eq!(count, 1, "expected 1 active revenuecat sub, got {count}");
}

/// A repeated RENEWAL for the same period must NOT stack rows.
#[tokio::test]
async fn repeated_renewal_does_not_stack() {
    let (app, pool) = test_app().await;
    let (user_id, _token) = register_user(&app, &pool).await;

    let exp_ms: i64 = (time::OffsetDateTime::now_utc() + time::Duration::days(30))
        .unix_timestamp()
        * 1000;

    let payload = rc_event("RENEWAL", user_id, &["vibra_plus"], Some(exp_ms));

    // Send the same RENEWAL event twice.
    let (s1, _) = post_webhook(&app, payload.clone(), Some(TEST_SECRET)).await;
    assert_eq!(s1, StatusCode::OK);
    let (s2, _) = post_webhook(&app, payload, Some(TEST_SECRET)).await;
    assert_eq!(s2, StatusCode::OK);

    // Only 1 active row (the first was expired before the second insert).
    let count: i64 = sqlx::query_scalar(
        r#"SELECT COUNT(*) FROM subscriptions
           WHERE user_id   = $1
             AND plan_code = 'vibra_plus'
             AND source    = 'revenuecat'
             AND status    = 'active'"#,
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert_eq!(count, 1, "expected exactly 1 active row after 2 renewals, got {count}");
}

/// Wrong Authorization header → 401, no DB change.
#[tokio::test]
async fn bad_secret_401() {
    let (app, pool) = test_app().await;
    let (user_id, _) = register_user(&app, &pool).await;

    let exp_ms: i64 = (time::OffsetDateTime::now_utc() + time::Duration::days(30))
        .unix_timestamp()
        * 1000;
    let payload = rc_event("INITIAL_PURCHASE", user_id, &["vibra_plus"], Some(exp_ms));

    let (status, _body) = post_webhook(&app, payload, Some("wrong-secret")).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "expected 401");

    // No subscription must have been created.
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM subscriptions WHERE user_id = $1 AND source = 'revenuecat'",
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count, 0, "no row should exist after bad-secret request");
}

/// type=TEST → 200, no DB mutation.
#[tokio::test]
async fn test_event_200() {
    let (app, _pool) = test_app().await;

    let payload = serde_json::json!({
        "api_version": "1.0",
        "event": {
            "type": "TEST",
            "app_user_id": uuid::Uuid::new_v4().to_string(),
            "product_id": "any_product",
            "entitlement_ids": ["vibra_plus"],
            "expiration_at_ms": serde_json::Value::Null,
            "environment": "SANDBOX"
        }
    });

    let (status, body) = post_webhook(&app, payload, Some(TEST_SECRET)).await;
    assert_eq!(status, StatusCode::OK, "TEST event must return 200: {body}");
    assert_eq!(body["ok"], true);
}

/// Grant then EXPIRATION → subscription no longer active.
#[tokio::test]
async fn expiration_downgrades() {
    let (app, pool) = test_app().await;
    let (user_id, _token) = register_user(&app, &pool).await;

    let exp_ms: i64 = (time::OffsetDateTime::now_utc() + time::Duration::days(30))
        .unix_timestamp()
        * 1000;

    // 1. Grant.
    let grant = rc_event("INITIAL_PURCHASE", user_id, &["vibra_plus"], Some(exp_ms));
    let (s, _) = post_webhook(&app, grant, Some(TEST_SECRET)).await;
    assert_eq!(s, StatusCode::OK, "grant should return 200");

    // Verify active before revoke.
    let active_before: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM subscriptions WHERE user_id=$1 AND source='revenuecat' AND status='active'",
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(active_before, 1, "should have 1 active sub before expiration");

    // 2. Expire.
    let expire = rc_event("EXPIRATION", user_id, &["vibra_plus"], Some(exp_ms));
    let (s2, body2) = post_webhook(&app, expire, Some(TEST_SECRET)).await;
    assert_eq!(s2, StatusCode::OK, "EXPIRATION should return 200: {body2}");

    // Verify no longer active.
    let active_after: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM subscriptions WHERE user_id=$1 AND source='revenuecat' AND status='active'",
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(
        active_after, 0,
        "sub should be inactive after EXPIRATION, got {active_after} active rows"
    );

    // Row still exists but with status='expired'.
    let expired: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM subscriptions WHERE user_id=$1 AND source='revenuecat' AND status='expired'",
    )
    .bind(user_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(expired, 1, "one row should have status='expired'");
}

/// Random UUID not in our users table → 200 ack (no crash, no DB mutation).
#[tokio::test]
async fn unknown_user_acked_200() {
    let (app, pool) = test_app().await;
    let random_id = uuid::Uuid::new_v4();

    let payload = rc_event("INITIAL_PURCHASE", random_id, &["vibra_plus"], Some(9_999_999_999_000));

    let (status, body) = post_webhook(&app, payload, Some(TEST_SECRET)).await;
    assert_eq!(status, StatusCode::OK, "unknown user must return 200: {body}");
    assert_eq!(body["ignored"], "unknown_user");

    // Absolutely no rows for this random user.
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM subscriptions WHERE user_id = $1",
    )
    .bind(random_id)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(count, 0);
}
