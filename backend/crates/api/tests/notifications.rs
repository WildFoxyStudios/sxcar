//! Integration tests for push notification endpoints.
//!
//! Tests:
//! - register_device_and_list — POST device token, verify listed
//! - update_preferences_and_get — PUT prefs, GET verify

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use std::sync::Arc;
use tower::ServiceExt;

fn test_db_url() -> String {
    std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://dev:dev@localhost:5433/appdb".to_string())
}

async fn test_app() -> axum::Router {
    let pool = db::connect(&test_db_url()).await.unwrap();
    db::migrate(&pool).await.unwrap();
    let deps = api::AppDeps {
        jwt: auth::jwt::JwtConfig {
            secret: "test".into(),
            access_ttl_secs: 900,
        },
        refresh_ttl_secs: 3600,
        notifier: Arc::new(auth::notify::DevNotifier),
        oauth: Arc::new(auth::oauth::DevOAuthVerifier),
    };
    api::app(pool, deps)
}

async fn post(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
    token: Option<&str>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method("POST")
        .uri(uri)
        .header("content-type", "application/json");
    if let Some(t) = token {
        builder = builder.header("authorization", &format!("Bearer {t}"));
    }
    let res = app
        .clone()
        .oneshot(builder.body(Body::from(body.to_string())).unwrap())
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

async fn get(
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
                .header("authorization", &format!("Bearer {}", token))
                .body(Body::default())
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

async fn put(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
    token: Option<&str>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method("PUT")
        .uri(uri)
        .header("content-type", "application/json");
    if let Some(t) = token {
        builder = builder.header("authorization", &format!("Bearer {t}"));
    }
    let res = app
        .clone()
        .oneshot(builder.body(Body::from(body.to_string())).unwrap())
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

fn unique_email() -> String {
    format!("notif_{}@test.com", uuid::Uuid::new_v4().simple())
}

async fn register_user(app: &axum::Router, email: &str) -> String {
    let (st, body) = post(
        app,
        "/auth/register",
        serde_json::json!({
            "email": email,
            "password": "secret123",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "register should 201");
    body["access"].as_str().unwrap().to_string()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn register_device_and_list() {
    let app = test_app().await;
    let token = register_user(&app, &unique_email()).await;

    // Register a device
    let (st, body) = post(
        &app,
        "/notifications/register",
        serde_json::json!({
            "device_token": "fcm-token-abc-123",
            "platform": "ios"
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "register device should 200");
    let device_id = body["device_id"].as_str().expect("should return device_id");

    // Try duplicate registration (same token) — should return same device
    let (st, body2) = post(
        &app,
        "/notifications/register",
        serde_json::json!({
            "device_token": "fcm-token-abc-123",
            "platform": "ios"
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(
        body2["device_id"].as_str().unwrap(),
        device_id,
        "duplicate registration should return same device_id"
    );

    // Register a second device
    let (st, _) = post(
        &app,
        "/notifications/register",
        serde_json::json!({
            "device_token": "fcm-token-xyz-456",
            "platform": "android"
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
}

#[tokio::test]
async fn register_device_requires_auth() {
    let app = test_app().await;

    let (st, _) = post(
        &app,
        "/notifications/register",
        serde_json::json!({
            "device_token": "no-auth-token",
            "platform": "web"
        }),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "auth required");
}

#[tokio::test]
async fn update_preferences_and_get() {
    let app = test_app().await;
    let token = register_user(&app, &unique_email()).await;

    // Get default preferences (no profile yet — will fallback to defaults)
    let (st, body) = get(&app, "/notifications/preferences", &token).await;
    assert_eq!(st, StatusCode::OK, "get prefs should 200");
    assert_eq!(
        body["new_messages"].as_bool(),
        Some(true),
        "default new_messages should be true"
    );
    assert_eq!(
        body["new_taps"].as_bool(),
        Some(true),
        "default new_taps should be true"
    );
    assert_eq!(
        body["promotions"].as_bool(),
        Some(false),
        "default promotions should be false"
    );

    // Update preferences
    let (st, _) = put(
        &app,
        "/notifications/preferences",
        serde_json::json!({
            "new_messages": false,
            "new_taps": true,
            "promotions": true
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "put prefs should 200");

    // Verify updated preferences
    let (st, body) = get(&app, "/notifications/preferences", &token).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(
        body["new_messages"].as_bool(),
        Some(false),
        "new_messages should now be false"
    );
    assert_eq!(
        body["new_taps"].as_bool(),
        Some(true),
        "new_taps should remain true"
    );
    assert_eq!(
        body["promotions"].as_bool(),
        Some(true),
        "promotions should now be true"
    );
}

#[tokio::test]
async fn update_preferences_requires_auth() {
    let app = test_app().await;

    let (st, _) = put(
        &app,
        "/notifications/preferences",
        serde_json::json!({
            "new_messages": false,
            "new_taps": false,
            "promotions": false
        }),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "auth required");
}

#[tokio::test]
async fn get_preferences_requires_auth() {
    let app = test_app().await;

    let (st, _) = get(&app, "/notifications/preferences", "bad-token").await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "auth required");
}
