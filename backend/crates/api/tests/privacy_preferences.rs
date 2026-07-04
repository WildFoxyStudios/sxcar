//! Integration tests for /privacy/preferences.
//!
//! Phase 2 / T2.1: GET /privacy/preferences + PUT /privacy/preferences.
//! Mirrors the in-file helper style from tests/billing.rs (no common module).

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
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
            secret: "test-privacy-jwt-secret".into(),
            access_ttl_secs: 900,
        },
        refresh_ttl_secs: 3600,
        notifier: std::sync::Arc::new(auth::notify::DevNotifier),
        oauth: std::sync::Arc::new(auth::oauth::DevOAuthVerifier),
    };
    api::app(pool, deps)
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
                .header("host", "localhost")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
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

async fn put_auth(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(uri)
                .header("host", "localhost")
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
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

async fn register(app: &axum::Router) -> String {
    let email = format!("privacy_{}@test.com", uuid::Uuid::new_v4().simple());
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/register")
                .header("host", "localhost")
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "email": email,
                        "password": "secret123",
                        "dob": "1990-01-01",
                        "consents": ["tos", "privacy"]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    assert_eq!(
        status,
        StatusCode::CREATED,
        "register failed: {}",
        String::from_utf8_lossy(&bytes)
    );
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    json["access"].as_str().unwrap().to_string()
}

// ─── Tests ───

#[tokio::test]
async fn get_preferences_returns_defaults() {
    let app = test_app().await;
    let token = register(&app).await;

    let (status, body) = get_auth(&app, "/privacy/preferences", &token).await;
    assert_eq!(status, StatusCode::OK, "expected 200, got {status}: {body}");

    // Migration defaults: booleans true/true/true/true/false, integers 0/0
    assert_eq!(body["multimedia_show_album_updates"], serde_json::Value::Bool(true));
    assert_eq!(body["multimedia_show_carousel"], serde_json::Value::Bool(true));
    assert_eq!(body["chat_mark_chatted"], serde_json::Value::Bool(true));
    assert_eq!(body["chat_sync"], serde_json::Value::Bool(true));
    assert_eq!(body["screen_keep_unlocked"], serde_json::Value::Bool(false));
    assert_eq!(body["visitor_status"], serde_json::json!(0));
    assert_eq!(body["units"], serde_json::json!(0));
}

#[tokio::test]
async fn update_preferences_roundtrip() {
    let app = test_app().await;
    let token = register(&app).await;

    let (status, body) = put_auth(
        &app,
        "/privacy/preferences",
        serde_json::json!({
            "visitor_status": 2,
            "units": 1,
            "screen_keep_unlocked": true,
        }),
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "expected 200, got {status}: {body}");
    assert_eq!(body["visitor_status"], serde_json::json!(2));
    assert_eq!(body["units"], serde_json::json!(1));
    assert_eq!(body["screen_keep_unlocked"], serde_json::Value::Bool(true));
    // Unchanged fields should keep their defaults.
    assert_eq!(body["multimedia_show_album_updates"], serde_json::Value::Bool(true));
    assert_eq!(body["chat_sync"], serde_json::Value::Bool(true));

    // GET roundtrip — verify persistence.
    let (status, body) = get_auth(&app, "/privacy/preferences", &token).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["visitor_status"], serde_json::json!(2));
    assert_eq!(body["units"], serde_json::json!(1));
    assert_eq!(body["screen_keep_unlocked"], serde_json::Value::Bool(true));
}

#[tokio::test]
async fn update_units_rejects_invalid() {
    let app = test_app().await;
    let token = register(&app).await;

    let (status, body) = put_auth(
        &app,
        "/privacy/preferences",
        serde_json::json!({"units": 5}),
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY,
               "expected 422 for units=5, got {status}: {body}");
    assert_eq!(body["error"], "invalid_value");
}

#[tokio::test]
async fn update_visitor_status_rejects_invalid() {
    let app = test_app().await;
    let token = register(&app).await;

    let (status, body) = put_auth(
        &app,
        "/privacy/preferences",
        serde_json::json!({"visitor_status": 9}),
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY,
               "expected 422 for visitor_status=9, got {status}: {body}");
    assert_eq!(body["error"], "invalid_value");
}