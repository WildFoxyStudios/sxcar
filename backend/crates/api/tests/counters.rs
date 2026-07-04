//! Integration tests for counter endpoints:
//! - GET /profile/views/count
//! - GET /taps/count

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
    format!("counters_{}@test.com", uuid::Uuid::new_v4().simple())
}

/// Decode user_id from a JWT access token.
fn user_id_from_token(token: &str) -> uuid::Uuid {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    let parts: Vec<&str> = token.split('.').collect();
    assert_eq!(parts.len(), 3, "JWT should have 3 parts");
    let payload = URL_SAFE_NO_PAD
        .decode(parts[1])
        .expect("JWT payload should be valid base64url");
    let json: serde_json::Value =
        serde_json::from_slice(&payload).expect("JWT payload should be valid JSON");
    let sub = json["sub"].as_str().expect("JWT should have 'sub' claim");
    uuid::Uuid::parse_str(sub).expect("sub should be a valid UUID")
}

async fn post(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
    token: Option<&str>,
) -> (StatusCode, serde_json::Value) {
    let builder = if let Some(t) = token {
        Request::builder()
            .method("POST")
            .uri(uri)
            .header("content-type", "application/json")
            .header("authorization", format!("Bearer {t}"))
    } else {
        Request::builder()
            .method("POST")
            .uri(uri)
            .header("content-type", "application/json")
    };
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
                .header("authorization", format!("Bearer {token}"))
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

async fn register_user(app: &axum::Router, email: &str) -> (String, uuid::Uuid) {
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
    let token = body["access"].as_str().unwrap().to_string();
    let uid = user_id_from_token(&token);
    (token, uid)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Empty case: a freshly registered user has no views and no taps.
#[tokio::test]
async fn counters_are_zero_for_new_user() {
    let app = test_app().await;
    let email = unique_email();
    let (token, _uid) = register_user(&app, &email).await;

    // /profile/views/count
    let (st, body) = get(&app, "/profile/views/count", &token).await;
    assert_eq!(st, StatusCode::OK, "GET /profile/views/count should 200");
    assert_eq!(body["count"].as_i64(), Some(0));

    // /taps/count
    let (st, body) = get(&app, "/taps/count", &token).await;
    assert_eq!(st, StatusCode::OK, "GET /taps/count should 200");
    assert_eq!(body["count"].as_i64(), Some(0));
    // types should be an empty object (not null, not missing)
    assert!(
        body["types"].is_object(),
        "types must be a JSON object, got: {}",
        body["types"]
    );
    assert_eq!(body["types"].as_object().unwrap().len(), 0);
}

/// Profile views counter increments by 1 (distinct) when another user
/// views A's profile via GET /users/:id/status (which auto-logs the view).
#[tokio::test]
async fn profile_views_count_after_other_user_views() {
    let app = test_app().await;
    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, user_a) = register_user(&app, &email_a).await;
    let (token_b, user_b) = register_user(&app, &email_b).await;

    // Clean stale views targeting A (shared DB).
    let pool = db::connect(&test_db_url()).await.unwrap();
    sqlx::query!("DELETE FROM profile_views WHERE target_id = $1", user_a)
        .execute(&pool)
        .await
        .unwrap();

    // Baseline: A's counter is 0.
    let (st, body) = get(&app, "/profile/views/count", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["count"].as_i64(), Some(0));

    // B views A's status (auto-logs view).
    let (st, _body) = get(&app, &format!("/users/{user_a}/status"), &token_b).await;
    assert_eq!(st, StatusCode::OK);

    // A's counter should now be 1.
    let (st, body) = get(&app, "/profile/views/count", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(
        body["count"].as_i64(),
        Some(1),
        "expected A to have 1 distinct viewer (B)"
    );

    let _ = (user_b, pool);
}

/// Taps count with types breakdown: 2 fire + 1 wave = {count: 3, types: {fire: 2, wave: 1}}.
#[tokio::test]
async fn taps_count_with_type_breakdown() {
    let app = test_app().await;
    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, user_a) = register_user(&app, &email_a).await;
    let (token_b, user_b) = register_user(&app, &email_b).await;

    // Clean stale taps targeting A (shared DB).
    let pool = db::connect(&test_db_url()).await.unwrap();
    sqlx::query!("DELETE FROM taps WHERE to_user = $1", user_a)
        .execute(&pool)
        .await
        .unwrap();

    // Baseline: A's taps count is 0.
    let (st, body) = get(&app, "/taps/count", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["count"].as_i64(), Some(0));
    assert_eq!(body["types"].as_object().unwrap().len(), 0);

    // B taps A twice with "fire" and once with "wave".
    for tap_type in ["fire", "fire", "wave"] {
        let (st, _body) = post(
            &app,
            "/taps",
            serde_json::json!({
                "to_user_id": user_a.to_string(),
                "tap_type": tap_type,
            }),
            Some(&token_b),
        )
        .await;
        assert_eq!(st, StatusCode::CREATED, "tap {tap_type} should 201");
    }

    // A's taps/count should be {count: 3, types: {fire: 2, wave: 1}}.
    let (st, body) = get(&app, "/taps/count", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["count"].as_i64(), Some(3), "expected 3 total taps");
    let types = body["types"].as_object().expect("types is an object");
    assert_eq!(types.get("fire").and_then(|v| v.as_i64()), Some(2));
    assert_eq!(types.get("wave").and_then(|v| v.as_i64()), Some(1));

    let _ = (token_a, user_b, pool);
}