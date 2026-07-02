//! Integration tests for GET /media/get-url
//!
//! Validates the auth, kind, and key-validation paths without requiring a real
//! R2 config (which is absent in CI/dev). Mirrors the test patterns from
//! albums.rs: build the router with `api::app`, register a user to get a
//! Bearer token, then hit the endpoint.

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

fn unique_email() -> String {
    format!("murl_{}@test.com", uuid::Uuid::new_v4().simple())
}

/// Register a throwaway user and return its access token.
async fn register_token(app: &axum::Router) -> String {
    let body = serde_json::json!({
        "email": unique_email(),
        "password": "secret123",
        "dob": "1990-01-01",
        "consents": ["tos", "privacy"]
    });
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::CREATED, "register must succeed");
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    json["access"].as_str().unwrap().to_string()
}

/// Fire a GET /media/get-url request, optionally with a bearer token.
async fn call_get_url(app: &axum::Router, uri: &str, token: Option<&str>) -> StatusCode {
    let mut builder = Request::builder().method("GET").uri(uri);
    if let Some(t) = token {
        builder = builder.header("authorization", format!("Bearer {t}"));
    }
    app.clone()
        .oneshot(builder.body(Body::empty()).unwrap())
        .await
        .unwrap()
        .status()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// No Authorization header → 401 before any other validation.
#[tokio::test]
async fn get_url_unauth_returns_401() {
    let app = test_app().await;
    let st = call_get_url(
        &app,
        "/media/get-url?key=profile/u/x.jpg&kind=profile",
        None,
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED);
}

/// Unknown kind → 400.
#[tokio::test]
async fn get_url_bad_kind_returns_400() {
    let app = test_app().await;
    let token = register_token(&app).await;
    // "BADKIND" is not one of profile / album / verification
    let st = call_get_url(
        &app,
        "/media/get-url?key=profile%2Fu%2Fx.jpg&kind=BADKIND",
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}

/// Key containing ".." → 400 (path-traversal guard).
#[tokio::test]
async fn get_url_traversal_key_returns_400() {
    let app = test_app().await;
    let token = register_token(&app).await;
    // "..%2Fetc%2Fpasswd" decodes to "../etc/passwd" which contains ".."
    let st = call_get_url(
        &app,
        "/media/get-url?key=..%2Fetc%2Fpasswd&kind=profile",
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}

/// Empty key → 400.
#[tokio::test]
async fn get_url_empty_key_returns_400() {
    let app = test_app().await;
    let token = register_token(&app).await;
    let st = call_get_url(&app, "/media/get-url?key=&kind=album", Some(&token)).await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}

/// Valid auth + valid params but no R2 config in test env → 503.
#[tokio::test]
async fn get_url_no_r2_returns_503() {
    // R2_S3_ENDPOINT is not set in the test environment, so state.r2 is None.
    let app = test_app().await;
    let token = register_token(&app).await;
    let st = call_get_url(
        &app,
        "/media/get-url?key=album%2Fu%2Fphoto.jpg&kind=album",
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::SERVICE_UNAVAILABLE);
}
