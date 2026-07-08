//! Integration tests for GET /discover endpoint.
//!
//! Seeds 2 users with locations, photos, and onboarding completion,
//! sets different last_seen_at timestamps, calls /discover,
//! and verifies the sorted results.

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
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .header("content-type", "application/json")
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

async fn get(app: &axum::Router, uri: &str, token: &str) -> (StatusCode, serde_json::Value) {
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

fn unique_email() -> String {
    format!("discover_{:x}@test.com", uuid::Uuid::new_v4().as_u128())
}

#[tokio::test]
async fn discover_returns_sorted_users_with_photos() {
    let app = test_app().await;

    // ---------- Register user A (the viewer) ----------
    let email_a = unique_email();
    let (st, body) = post(
        &app,
        "/auth/register",
        serde_json::json!({
            "email": email_a,
            "password": "secret123",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "register user A should 201");
    let token_a = body["access"].as_str().unwrap().to_string();
    let user_id_a = uuid::Uuid::parse_str(
        body["user"]["id"].as_str().unwrap(),
    )
    .expect("user A id should be a valid UUID");

    // ---------- Register user B (nearby, has photo, recently active) ----------
    let email_b = unique_email();
    let (st, body) = post(
        &app,
        "/auth/register",
        serde_json::json!({
            "email": email_b,
            "password": "secret456",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "register user B should 201");
    let token_b = body["access"].as_str().unwrap().to_string();
    let user_id_b = uuid::Uuid::parse_str(
        body["user"]["id"].as_str().unwrap(),
    )
    .expect("user B id should be a valid UUID");

    let pool = db::connect(&test_db_url()).await.unwrap();

    // ---------- Insert profiles ----------
    sqlx::query!(
        "INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO NOTHING",
        user_id_a,
        "Alice",
        "Hello from Alice"
    )
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query!(
        "INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO NOTHING",
        user_id_b,
        "Bob",
        "Hello from Bob"
    )
    .execute(&pool)
    .await
    .unwrap();

    // ---------- Insert locations ----------
    sqlx::query!(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
        user_id_a,
        -99.1332_f64,
        19.4326_f64,
    )
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query!(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
        user_id_b,
        -99.1300_f64,
        19.4300_f64,
    )
    .execute(&pool)
    .await
    .unwrap();

    // ---------- Insert a primary photo for user B (required by discover) ----------
    sqlx::query!(
        "INSERT INTO photos (user_id, is_primary, r2_key, blur_key)
         VALUES ($1, true, 'profile/test-b/photo.jpg', 'profile/test-b/photo.blur.jpg')",
        user_id_b,
    )
    .execute(&pool)
    .await
    .unwrap();

    // ---------- Set onboarding_completed_at for both users ----------
    sqlx::query!(
        "UPDATE users SET onboarding_completed_at = now() WHERE id = $1",
        user_id_a,
    )
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query!(
        "UPDATE users SET onboarding_completed_at = now() WHERE id = $1",
        user_id_b,
    )
    .execute(&pool)
    .await
    .unwrap();

    // ---------- Set last_seen_at to make user B recently active ----------
    sqlx::query!(
        "UPDATE users SET last_seen_at = now() WHERE id = $1",
        user_id_b,
    )
    .execute(&pool)
    .await
    .unwrap();

    // ---------- Call /discover as user A ----------
    let (st, body) = get(
        &app,
        "/discover?lat=19.4326&lon=-99.1332&radius_m=5000&limit=50",
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK, "discover should 200");

    // ---------- Verify user B appears ----------
    let users = body["users"].as_array().unwrap();
    assert!(!users.is_empty(), "should have at least one nearby user");

    let bob = users
        .iter()
        .find(|u| u["id"] == serde_json::json!(user_id_b.to_string()))
        .expect("user B should be in discover results");
    assert_eq!(bob["email"], email_b);
    assert_eq!(bob["display_name"], "Bob");
    assert_eq!(bob["bio"], "Hello from Bob");
    assert!(
        bob["distance_m"].as_f64().unwrap() > 0.0,
        "distance should be > 0"
    );

    // ---------- Verify requesting user is excluded ----------
    let alice = users
        .iter()
        .find(|u| u["id"] == serde_json::json!(user_id_a.to_string()));
    assert!(
        alice.is_none(),
        "Alice (requesting user) should NOT be in discover results"
    );

    // ---------- Verify sorting: user B should be first (most recently active) ----------
    if let Some(first) = users.first() {
        assert_eq!(
            first["id"], serde_json::json!(user_id_b.to_string()),
            "first result should be Bob (most recently active)"
        );
    }

    // ---------- Call /discover without auth -> 401 ----------
    let (st, _) = get(
        &app,
        "/discover?lat=19.4326&lon=-99.1332&radius_m=5000&limit=50",
        "",
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "no auth should 401");
}
