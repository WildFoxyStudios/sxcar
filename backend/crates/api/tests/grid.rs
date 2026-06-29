//! Integration tests for grid (nearby users) endpoints.
//!
//! Seeds 2 users with locations, calls /grid/nearby with one user's token,
//! and verifies the other user appears with distance_m > 0.

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
    format!("grid_{}@test.com", uuid::Uuid::new_v4().simple())
}

/// Decodifica el payload de un JWT (segundo segmento base64url) y devuelve
/// el valor del campo `sub` (user_id).
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

#[tokio::test]
async fn nearby_returns_other_user_with_distance() {
    let app = test_app().await;

    // ---------- Register user A ----------
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
    let user_id_a = user_id_from_token(&token_a);

    // ---------- Register user B ----------
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
    let _token_b = body["access"].as_str().unwrap().to_string();
    let user_id_b = user_id_from_token(&_token_b);

    // Extract the pool from the app state for direct DB operations
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

    // ---------- Insert locations using PostGIS ----------
    // User A at (lon=-99.1332, lat=19.4326) — Mexico City
    sqlx::query!(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
        user_id_a,
        -99.1332_f64, // lon
        19.4326_f64,  // lat
    )
    .execute(&pool)
    .await
    .unwrap();

    // User B at (lon=-99.1300, lat=19.4300) — ~350m away
    sqlx::query!(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
        user_id_b,
        -99.1300_f64, // lon
        19.4300_f64,  // lat
    )
    .execute(&pool)
    .await
    .unwrap();

    // ---------- Call /grid/nearby as user A ----------
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999",
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK, "nearby should 200");

    // ---------- Verify user B appears ----------
    let users = body["users"].as_array().unwrap();
    assert!(!users.is_empty(), "should have at least one nearby user");

    // Find Bob by his user_id
    let bob = users
        .iter()
        .find(|u| u["id"] == serde_json::json!(user_id_b.to_string()))
        .expect("user B should be in results");
    assert_eq!(bob["email"], email_b);
    assert_eq!(bob["display_name"], "Bob");
    assert_eq!(bob["bio"], "Hello from Bob");
    assert!(
        bob["distance_m"].as_f64().unwrap() > 0.0,
        "distance should be > 0"
    );

    // ---------- Verify requesting user is excluded ----------
    let alice = users.iter().find(|u| u["id"] == serde_json::json!(user_id_a.to_string()));
    assert!(
        alice.is_none(),
        "Alice (requesting user) should NOT be in results"
    );

    // ---------- Call /grid/nearby without auth -> 401 ----------
    let (st, _) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999",
        "",
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "no auth should 401");
}
