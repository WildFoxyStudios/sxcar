//! Integration tests for social endpoints (taps, favorites, blocks).
//!
//! Seeds users, exercises each endpoint, and verifies block enforcement in grid.

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
    let builder = if let Some(t) = token {
        Request::builder()
            .method("POST")
            .uri(uri)
            .header("content-type", "application/json")
            .header("authorization", &format!("Bearer {t}"))
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

async fn delete_(
    app: &axum::Router,
    uri: &str,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let builder = Request::builder()
        .method("DELETE")
        .uri(uri)
        .header("authorization", &format!("Bearer {token}"));
    let res = app
        .clone()
        .oneshot(builder.body(Body::default()).unwrap())
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
                .header("authorization", &format!("Bearer {token}"))
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
    format!("social_{}@test.com", uuid::Uuid::new_v4().simple())
}

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

async fn insert_profile(pool: &sqlx::PgPool, user_id: uuid::Uuid, display_name: &str) {
    sqlx::query!(
        "INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3) ON CONFLICT (user_id) DO NOTHING",
        user_id,
        display_name,
        "Hi"
    )
    .execute(pool)
    .await
    .unwrap();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn tap_user_and_list_received() {
    let app = test_app().await;

    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, user_a) = register_user(&app, &email_a).await;
    let (_token_b, user_b) = register_user(&app, &email_b).await;

    let pool = db::connect(&test_db_url()).await.unwrap();
    insert_profile(&pool, user_a, "Alice").await;
    insert_profile(&pool, user_b, "Bob").await;

    // User A taps user B
    let (st, body) = post(
        &app,
        "/taps",
        serde_json::json!({
            "to_user_id": user_b.to_string(),
            "tap_type": "fire"
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "tap should 201");
    assert!(body["id"].as_str().unwrap().len() > 0);

    // User B lists received taps -> should see 1 from Alice
    let (st, body) = get(&app, "/taps/received", &_token_b).await;
    assert_eq!(st, StatusCode::OK);
    let taps = body["taps"].as_array().unwrap();
    assert_eq!(taps.len(), 1);
    assert_eq!(taps[0]["from_user_id"].as_str().unwrap(), user_a.to_string());
    assert_eq!(taps[0]["from_display_name"].as_str(), Some("Alice"));
    assert_eq!(taps[0]["tap_type"].as_str(), Some("fire"));

    // User A lists sent taps -> should see 1 to Bob
    let (st, body) = get(&app, "/taps/sent", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let taps = body["taps"].as_array().unwrap();
    assert_eq!(taps.len(), 1);
    assert_eq!(taps[0]["tap_type"].as_str(), Some("fire"));
}

#[tokio::test]
async fn favorite_and_unfavorite() {
    let app = test_app().await;

    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, user_a) = register_user(&app, &email_a).await;
    let (_token_b, user_b) = register_user(&app, &email_b).await;

    let pool = db::connect(&test_db_url()).await.unwrap();
    insert_profile(&pool, user_a, "Alice").await;
    insert_profile(&pool, user_b, "Bob").await;

    // User A favorites user B
    let (st, _) = post(
        &app,
        "/favorites",
        serde_json::json!({ "user_id": user_b.to_string() }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "add favorite should 201");

    // List favorites -> should have 1
    let (st, body) = get(&app, "/favorites", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let favs = body["favorites"].as_array().unwrap();
    assert_eq!(favs.len(), 1);
    assert_eq!(favs[0]["user_id"].as_str().unwrap(), user_b.to_string());
    assert_eq!(favs[0]["display_name"].as_str(), Some("Bob"));

    // Unfavorite user B
    let (st, _) = delete_(&app, &format!("/favorites/{}", user_b), &token_a).await;
    assert_eq!(st, StatusCode::NO_CONTENT, "remove favorite should 204");

    // List favorites -> should be empty
    let (st, body) = get(&app, "/favorites", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let favs = body["favorites"].as_array().unwrap();
    assert!(favs.is_empty());
}

#[tokio::test]
async fn block_user_and_list() {
    let app = test_app().await;

    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, user_a) = register_user(&app, &email_a).await;
    let (_token_b, user_b) = register_user(&app, &email_b).await;

    let pool = db::connect(&test_db_url()).await.unwrap();
    insert_profile(&pool, user_a, "Alice").await;
    insert_profile(&pool, user_b, "Bob").await;

    // User A blocks user B with a reason
    let (st, _) = post(
        &app,
        "/blocks",
        serde_json::json!({
            "user_id": user_b.to_string(),
            "reason": "spam"
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "block should 201");

    // List blocks -> should have 1
    let (st, body) = get(&app, "/blocks", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let blocks = body["blocks"].as_array().unwrap();
    assert_eq!(blocks.len(), 1);
    assert_eq!(blocks[0]["user_id"].as_str().unwrap(), user_b.to_string());
    assert_eq!(blocks[0]["display_name"].as_str(), Some("Bob"));
    assert_eq!(blocks[0]["reason"].as_str(), Some("spam"));

    // Unblock user B
    let (st, _) = delete_(&app, &format!("/blocks/{}", user_b), &token_a).await;
    assert_eq!(st, StatusCode::NO_CONTENT, "unblock should 204");

    // List blocks -> should be empty
    let (st, body) = get(&app, "/blocks", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let blocks = body["blocks"].as_array().unwrap();
    assert!(blocks.is_empty());
}

#[tokio::test]
async fn blocked_user_not_in_grid() {
    let app = test_app().await;

    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, user_a) = register_user(&app, &email_a).await;
    let (_token_b, user_b) = register_user(&app, &email_b).await;

    let pool = db::connect(&test_db_url()).await.unwrap();
    insert_profile(&pool, user_a, "Alice").await;
    insert_profile(&pool, user_b, "Bob").await;

    // Insert locations close to each other
    sqlx::query!(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
        user_a,
        -99.1332_f64,
        19.4326_f64,
    )
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query!(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
        user_b,
        -99.1300_f64,
        19.4300_f64,
    )
    .execute(&pool)
    .await
    .unwrap();

    // User B should appear in grid initially
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=50",
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let users = body["users"].as_array().unwrap();
    let found_before = users.iter().any(|u| u["id"] == serde_json::json!(user_b.to_string()));
    assert!(found_before, "user B should be visible before block");

    // User A blocks user B
    let (st, _) = post(
        &app,
        "/blocks",
        serde_json::json!({ "user_id": user_b.to_string() }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);

    // User B should NOT appear in grid
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=50",
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let users = body["users"].as_array().unwrap();
    let found_after = users.iter().any(|u| u["id"] == serde_json::json!(user_b.to_string()));
    assert!(!found_after, "user B should NOT be visible after block");
}

#[tokio::test]
async fn unblock_restores_visibility() {
    let app = test_app().await;

    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, user_a) = register_user(&app, &email_a).await;
    let (_token_b, user_b) = register_user(&app, &email_b).await;

    let pool = db::connect(&test_db_url()).await.unwrap();
    insert_profile(&pool, user_a, "Alice").await;
    insert_profile(&pool, user_b, "Bob").await;

    // Insert locations close to each other
    sqlx::query!(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
        user_a,
        -99.1332_f64,
        19.4326_f64,
    )
    .execute(&pool)
    .await
    .unwrap();

    sqlx::query!(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
        user_b,
        -99.1300_f64,
        19.4300_f64,
    )
    .execute(&pool)
    .await
    .unwrap();

    // Block user B
    let (st, _) = post(
        &app,
        "/blocks",
        serde_json::json!({ "user_id": user_b.to_string() }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);

    // Verify not in grid
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=50",
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let users = body["users"].as_array().unwrap();
    assert!(!users.iter().any(|u| u["id"] == serde_json::json!(user_b.to_string())));

    // Unblock
    let (st, _) = delete_(&app, &format!("/blocks/{}", user_b), &token_a).await;
    assert_eq!(st, StatusCode::NO_CONTENT);

    // User B should be visible again
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=50",
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let users = body["users"].as_array().unwrap();
    let found_after = users.iter().any(|u| u["id"] == serde_json::json!(user_b.to_string()));
    assert!(found_after, "user B should be visible again after unblock");
}

#[tokio::test]
async fn block_deletes_conversation() {
    let app = test_app().await;

    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, user_a) = register_user(&app, &email_a).await;
    let (_token_b, user_b) = register_user(&app, &email_b).await;

    let pool = db::connect(&test_db_url()).await.unwrap();
    insert_profile(&pool, user_a, "Alice").await;
    insert_profile(&pool, user_b, "Bob").await;

    // Create a conversation between A and B
    let (st, body) = post(
        &app,
        "/chat/conversations",
        serde_json::json!({ "participant_id": user_b.to_string() }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let _conv_id = body["conversation_id"].as_str().unwrap().to_string();

    // Verify conversation exists
    let (st, body) = get(&app, "/chat/conversations", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let convos = body["conversations"].as_array().unwrap();
    assert_eq!(convos.len(), 1);

    // Block user B -> should delete the conversation
    let (st, _) = post(
        &app,
        "/blocks",
        serde_json::json!({ "user_id": user_b.to_string() }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);

    // Conversation should be gone
    let (st, body) = get(&app, "/chat/conversations", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let convos = body["conversations"].as_array().unwrap();
    assert!(convos.is_empty(), "conversation should be deleted after block");
}

#[tokio::test]
async fn tap_self_rejected() {
    let app = test_app().await;
    let email = unique_email();
    let (token, user) = register_user(&app, &email).await;

    let (st, _) = post(
        &app,
        "/taps",
        serde_json::json!({
            "to_user_id": user.to_string(),
            "tap_type": "fire"
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST, "tapping self should 400");
}

#[tokio::test]
async fn tap_invalid_type_rejected() {
    let app = test_app().await;
    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, _user_a) = register_user(&app, &email_a).await;
    let (_token_b, user_b) = register_user(&app, &email_b).await;

    let (st, _) = post(
        &app,
        "/taps",
        serde_json::json!({
            "to_user_id": user_b.to_string(),
            "tap_type": "invalid"
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST, "invalid tap type should 400");
}

#[tokio::test]
async fn tap_blocked_user_rejected() {
    let app = test_app().await;

    let email_a = unique_email();
    let email_b = unique_email();
    let (token_a, user_a) = register_user(&app, &email_a).await;
    let (_token_b, user_b) = register_user(&app, &email_b).await;

    let pool = db::connect(&test_db_url()).await.unwrap();
    insert_profile(&pool, user_a, "Alice").await;
    insert_profile(&pool, user_b, "Bob").await;

    // Block user B from user A
    let (st, _) = post(
        &app,
        "/blocks",
        serde_json::json!({ "user_id": user_b.to_string() }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);

    // Tap should be forbidden
    let (st, _) = post(
        &app,
        "/taps",
        serde_json::json!({
            "to_user_id": user_b.to_string(),
            "tap_type": "fire"
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN, "tapping blocked user should 403");
}

#[tokio::test]
async fn unauthenticated_requests_rejected() {
    let app = test_app().await;

    // POST /taps requires auth
    let (st, _) = post(
        &app,
        "/taps",
        serde_json::json!({"to_user_id": uuid::Uuid::new_v4(), "tap_type": "fire"}),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "/taps POST should 401 without auth");

    // GET /taps/received requires auth
    let (st, _) = get(&app, "/taps/received", "").await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "/taps/received should 401 without auth");

    // GET /taps/sent requires auth
    let (st, _) = get(&app, "/taps/sent", "").await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "/taps/sent should 401 without auth");

    // GET /favorites requires auth
    let (st, _) = get(&app, "/favorites", "").await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "/favorites should 401 without auth");

    // POST /favorites requires auth
    let (st, _) = post(
        &app,
        "/favorites",
        serde_json::json!({"user_id": uuid::Uuid::new_v4()}),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "/favorites POST should 401 without auth");

    // GET /blocks requires auth
    let (st, _) = get(&app, "/blocks", "").await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "/blocks should 401 without auth");

    // POST /blocks requires auth
    let (st, _) = post(
        &app,
        "/blocks",
        serde_json::json!({"user_id": uuid::Uuid::new_v4()}),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED, "/blocks POST should 401 without auth");
}

#[tokio::test]
async fn report_user_creates_report() {
    let app = test_app().await;

    let (token_a, _user_a) = register_user(&app, &unique_email()).await;
    let (_token_b, user_b) = register_user(&app, &unique_email()).await;

    // A reports B's profile
    let (st, body) = post(
        &app,
        "/reports",
        serde_json::json!({
            "target_user_id": user_b.to_string(),
            "target_kind": "profile",
            "reason": "Harassment"
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "report should 201: {body}");
    assert!(!body["id"].as_str().unwrap().is_empty());
}

#[tokio::test]
async fn report_self_rejected() {
    let app = test_app().await;
    let (token_a, user_a) = register_user(&app, &unique_email()).await;

    let (st, _) = post(
        &app,
        "/reports",
        serde_json::json!({
            "target_user_id": user_a.to_string(),
            "target_kind": "profile"
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST, "self-report should be 400");
}

#[tokio::test]
async fn report_invalid_kind_rejected() {
    let app = test_app().await;
    let (token_a, _user_a) = register_user(&app, &unique_email()).await;
    let (_token_b, user_b) = register_user(&app, &unique_email()).await;

    let (st, _) = post(
        &app,
        "/reports",
        serde_json::json!({
            "target_user_id": user_b.to_string(),
            "target_kind": "nonsense"
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST, "invalid kind should be 400");
}
