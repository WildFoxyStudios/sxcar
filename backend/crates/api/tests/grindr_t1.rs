//! Integration tests for Grindr Tier 1 parity endpoints.
//!
//! Covers:
//! - Chat media messages (photo, location) + read receipts (read_at)
//! - User status (online + last_seen) + heartbeat
//! - Profile views ("Viewed Me")
//! - Profile health (HIV status, last_tested, PrEP)

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

async fn put(
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
                .header("content-type", "application/json")
                .header("authorization", &format!("Bearer {}", token))
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

fn unique_email() -> String {
    format!("grindr_t1_{}@test.com", uuid::Uuid::new_v4().simple())
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

/// Registers two users with profiles named Alice and Bob.
/// Returns (token_a, user_id_a, token_b, user_id_b).
async fn register_two(app: &axum::Router) -> (String, uuid::Uuid, String, uuid::Uuid) {
    let pool = db::connect(&test_db_url()).await.unwrap();

    let email_a = unique_email();
    let (st, body) = post(
        app,
        "/auth/register",
        serde_json::json!({
            "email": email_a,
            "password": "secret123",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let token_a = body["access"].as_str().unwrap().to_string();
    let user_id_a = user_id_from_token(&token_a);
    sqlx::query!(
        "INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO NOTHING",
        user_id_a, "Alice", "Hi"
    )
    .execute(&pool).await.unwrap();

    let email_b = unique_email();
    let (st, body) = post(
        app,
        "/auth/register",
        serde_json::json!({
            "email": email_b,
            "password": "secret456",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let token_b = body["access"].as_str().unwrap().to_string();
    let user_id_b = user_id_from_token(&token_b);
    sqlx::query!(
        "INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO NOTHING",
        user_id_b, "Bob", "Hi"
    )
    .execute(&pool).await.unwrap();

    (token_a, user_id_a, token_b, user_id_b)
}

// ---------------------------------------------------------------------------
// Media messages
// ---------------------------------------------------------------------------

#[tokio::test]
async fn send_photo_message_and_read_back() {
    let app = test_app().await;
    let (token_a, user_a, token_b, user_b) = register_two(&app).await;

    // A creates a conversation with B
    let (st, body) = post(
        &app,
        "/chat/conversations",
        serde_json::json!({"participant_id": user_b.to_string()}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let conv_id = body["conversation_id"].as_str().unwrap().to_string();

    // A sends a photo message
    let (st, body) = post(
        &app,
        &format!("/chat/conversations/{conv_id}/messages"),
        serde_json::json!({
            "media_key": "https://cdn.example.com/p.jpg",
            "media_type": "photo",
            "caption": "nice pic"
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let msg_id = body["id"].as_str().unwrap().to_string();

    // B reads the message — should see media fields populated
    let (st, body) = get(
        &app,
        &format!("/chat/conversations/{conv_id}/messages"),
        &token_b,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let msgs = body["messages"].as_array().unwrap();
    assert_eq!(msgs.len(), 1);
    let m = &msgs[0];
    assert_eq!(m["id"].as_str().unwrap(), msg_id);
    assert_eq!(m["media_key"].as_str(), Some("https://cdn.example.com/p.jpg"));
    assert_eq!(m["media_type"].as_str(), Some("photo"));
    assert_eq!(m["caption"].as_str(), Some("nice pic"));
}

#[tokio::test]
async fn send_location_message_and_read_back() {
    let app = test_app().await;
    let (token_a, user_a, token_b, user_b) = register_two(&app).await;

    let (st, body) = post(
        &app,
        "/chat/conversations",
        serde_json::json!({"participant_id": user_b.to_string()}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let conv_id = body["conversation_id"].as_str().unwrap().to_string();

    let (st, body) = post(
        &app,
        &format!("/chat/conversations/{conv_id}/messages"),
        serde_json::json!({
            "lat": 40.4168,
            "lon": -3.7038,
            "text": "Plaza Mayor"
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);

    let (st, body) = get(
        &app,
        &format!("/chat/conversations/{conv_id}/messages"),
        &token_b,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let m = &body["messages"][0];
    assert!((m["lat"].as_f64().unwrap() - 40.4168).abs() < 1e-6);
    assert!((m["lon"].as_f64().unwrap() - (-3.7038)).abs() < 1e-6);
    assert_eq!(m["body"].as_str(), Some("Plaza Mayor"));
}

#[tokio::test]
async fn empty_message_is_rejected() {
    let app = test_app().await;
    let (token_a, _user_a, _token_b, user_b) = register_two(&app).await;

    let (st, body) = post(
        &app,
        "/chat/conversations",
        serde_json::json!({"participant_id": user_b.to_string()}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let conv_id = body["conversation_id"].as_str().unwrap().to_string();

    // No text, no media, no location -> 400
    let (st, _body) = post(
        &app,
        &format!("/chat/conversations/{conv_id}/messages"),
        serde_json::json!({}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn read_receipts_set_read_at() {
    let app = test_app().await;
    let (token_a, _a, token_b, user_b) = register_two(&app).await;

    let (st, body) = post(
        &app,
        "/chat/conversations",
        serde_json::json!({"participant_id": user_b.to_string()}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let conv_id = body["conversation_id"].as_str().unwrap().to_string();

    // A sends a message
    let (st, body) = post(
        &app,
        &format!("/chat/conversations/{conv_id}/messages"),
        serde_json::json!({"text": "Hello!"}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let msg_id = body["id"].as_str().unwrap().to_string();

    // B marks as read
    let (st, body) = post(
        &app,
        &format!("/chat/conversations/{conv_id}/read"),
        serde_json::json!({}),
        Some(&token_b),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["marked"].as_u64().unwrap() >= 1);

    // B reads the conversation: message should now have read_at
    let (st, body) = get(
        &app,
        &format!("/chat/conversations/{conv_id}/messages"),
        &token_b,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let msgs = body["messages"].as_array().unwrap();
    let m = msgs.iter().find(|m| m["id"].as_str() == Some(&msg_id)).unwrap();
    assert!(m["read_at"].is_string(), "read_at should be set after mark_read");
}

// ---------------------------------------------------------------------------
// Online indicator / heartbeat
// ---------------------------------------------------------------------------

#[tokio::test]
async fn heartbeat_sets_last_seen() {
    let app = test_app().await;
    let (token_a, user_a, _token_b, _user_b) = register_two(&app).await;

    let (st, body) = post(
        &app,
        "/heartbeat",
        serde_json::json!({}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["ok"].as_bool(), Some(true));

    // Check DB: last_seen_at should now be set
    let pool = db::connect(&test_db_url()).await.unwrap();
    let row = sqlx::query!(
        "SELECT last_seen_at FROM users WHERE id = $1",
        user_a
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    assert!(row.last_seen_at.is_some(), "last_seen_at should be set after heartbeat");
}

#[tokio::test]
async fn user_status_returns_is_online_after_heartbeat() {
    let app = test_app().await;
    let (token_a, user_a, token_b, user_b) = register_two(&app).await;

    // B touches last_seen
    let (st, _body) = post(&app, "/heartbeat", serde_json::json!({}), Some(&token_b)).await;
    assert_eq!(st, StatusCode::OK);

    // A queries B's status
    let (st, body) = get(
        &app,
        &format!("/users/{}/status", user_b),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["is_online"].as_bool(), Some(true));
    assert!(body["last_seen_at"].is_string());
}

// ---------------------------------------------------------------------------
// Profile views (Viewed Me)
// ---------------------------------------------------------------------------

#[tokio::test]
async fn view_status_logs_profile_view() {
    let app = test_app().await;
    let (token_a, user_a, token_b, user_b) = register_two(&app).await;

    // Clean any stale profile views targeting user_b (shared DB) so the
    // assertion is deterministic.
    let pool = db::connect(&test_db_url()).await.unwrap();
    sqlx::query!("DELETE FROM profile_views WHERE target_id = $1", user_b)
        .execute(&pool).await.unwrap();

    // A views B's status (auto-logs view)
    let (st, _body) = get(
        &app,
        &format!("/users/{}/status", user_b),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // B lists viewers — should see A
    let (st, body) = get(&app, "/profile/views", &token_b).await;
    assert_eq!(st, StatusCode::OK);
    let viewers = body["viewers"].as_array().unwrap();
    // Search by user_id (A) instead of display_name — survives shared DB state
    let user_a_str = user_a.to_string();
    assert!(
        viewers.iter().any(|v| v["viewer_id"].as_str() == Some(&user_a_str)),
        "expected A ({}) in viewers: {viewers:?}",
        user_a_str
    );
}

#[tokio::test]
async fn list_profile_views_empty_initially() {
    let app = test_app().await;
    let (token_a, _user_a, _token_b, _user_b) = register_two(&app).await;

    let (st, body) = get(&app, "/profile/views", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let viewers = body["viewers"].as_array().unwrap();
    assert!(viewers.is_empty(), "no one has viewed Alice yet");
}

// ---------------------------------------------------------------------------
// Profile health
// ---------------------------------------------------------------------------

#[tokio::test]
async fn profile_health_get_then_put() {
    let app = test_app().await;
    let (token_a, _user_a, _token_b, _user_b) = register_two(&app).await;

    // Initial GET: all null
    let (st, body) = get(&app, "/profile/health", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["hiv_status"].is_null());
    assert!(body["last_tested_on"].is_null());
    assert!(body["prep"].is_null());

    // PUT health info
    let (st, body) = put(
        &app,
        "/profile/health",
        serde_json::json!({
            "hiv_status": "negative",
            "last_tested_on": "2025-06-15",
            "prep": true
        }),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["hiv_status"].as_str(), Some("negative"));
    assert_eq!(body["last_tested_on"].as_str(), Some("2025-06-15"));
    assert_eq!(body["prep"].as_bool(), Some(true));

    // GET again — values persisted
    let (st, body) = get(&app, "/profile/health", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["hiv_status"].as_str(), Some("negative"));
    assert_eq!(body["prep"].as_bool(), Some(true));
}

#[tokio::test]
async fn profile_health_invalid_date_is_400() {
    let app = test_app().await;
    let (token_a, _user_a, _token_b, _user_b) = register_two(&app).await;

    let (st, _body) = put(
        &app,
        "/profile/health",
        serde_json::json!({
            "last_tested_on": "not-a-date"
        }),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}