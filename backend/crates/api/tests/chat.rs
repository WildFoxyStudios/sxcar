//! Integration tests for chat (conversations + messages) endpoints.
//!
//! Seeds 2 users, creates a conversation, sends messages, and verifies
//! the conversation list and message history endpoints.

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

fn unique_email() -> String {
    format!("chat_{}@test.com", uuid::Uuid::new_v4().simple())
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn list_conversations_empty() {
    let app = test_app().await;

    // Register a new user
    let email = unique_email();
    let (st, body) = post(
        &app,
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
    let token = body["access"].as_str().unwrap();

    // List conversations -> empty
    let (st, body) = get(&app, "/chat/conversations", token).await;
    assert_eq!(st, StatusCode::OK, "list conversations should 200");
    let convos = body["conversations"].as_array().unwrap();
    assert!(convos.is_empty(), "new user should have 0 conversations");
}

#[tokio::test]
async fn create_conversation_and_list() {
    let app = test_app().await;

    // Register user A
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
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let token_a = body["access"].as_str().unwrap().to_string();
    let user_id_a = user_id_from_token(&token_a);

    // Register user B
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
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let _token_b = body["access"].as_str().unwrap().to_string();
    let user_id_b = user_id_from_token(&_token_b);

    // Insert profiles so display name is populated
    let pool = db::connect(&test_db_url()).await.unwrap();
    sqlx::query!(
        "INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO NOTHING",
        user_id_a,
        "Alice",
        "Hi from Alice"
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query!(
        "INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO NOTHING",
        user_id_b,
        "Bob",
        "Hi from Bob"
    )
    .execute(&pool)
    .await
    .unwrap();

    // User A creates a conversation with user B
    let (st, body) = post(
        &app,
        "/chat/conversations",
        serde_json::json!({
            "participant_id": user_id_b.to_string()
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "create conversation should 201");
    let conv_id = body["conversation_id"].as_str().unwrap().to_string();

    // User A lists conversations -> should have 1, shown from A's perspective
    let (st, body) = get(&app, "/chat/conversations", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let convos = body["conversations"].as_array().unwrap();
    assert_eq!(convos.len(), 1, "should have 1 conversation");
    let conv = &convos[0];
    assert_eq!(conv["conversation_id"].as_str().unwrap(), &conv_id);
    // The other user is Bob
    assert_eq!(conv["other_display_name"].as_str(), Some("Bob"));
    // No messages yet, so unread_count = 0
    assert_eq!(conv["unread_count"].as_i64(), Some(0));
}

#[tokio::test]
async fn send_message_and_retrieve() {
    let app = test_app().await;

    // Register two users
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
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let token_a = body["access"].as_str().unwrap().to_string();
    let user_id_a = user_id_from_token(&token_a);

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
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let token_b = body["access"].as_str().unwrap().to_string();
    let user_id_b = user_id_from_token(&token_b);

    let pool = db::connect(&test_db_url()).await.unwrap();
    sqlx::query!(
        "INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO NOTHING",
        user_id_a,
        "Alice",
        "Hi"
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query!(
        "INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO NOTHING",
        user_id_b,
        "Bob",
        "Hi"
    )
    .execute(&pool)
    .await
    .unwrap();

    // User A creates a conversation
    let (st, body) = post(
        &app,
        "/chat/conversations",
        serde_json::json!({"participant_id": user_id_b.to_string()}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let conv_id = body["conversation_id"].as_str().unwrap().to_string();

    // User A sends a message via REST (POST /chat/conversations/:id/messages)
    // First implement: we'll create a POST handler for sending messages
    let (st, body) = post(
        &app,
        &format!("/chat/conversations/{conv_id}/messages"),
        serde_json::json!({"text": "Hello Bob!"}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "send message should 201");
    let _msg_id = body["id"].as_str().unwrap().to_string();

    // User B sends a reply
    let (st, body) = post(
        &app,
        &format!("/chat/conversations/{conv_id}/messages"),
        serde_json::json!({"text": "Hey Alice!"}),
        Some(&token_b),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let _msg_id_2 = body["id"].as_str().unwrap().to_string();

    // User A retrieves message history
    let (st, body) = get(
        &app,
        &format!("/chat/conversations/{conv_id}/messages?limit=50"),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let msgs = body["messages"].as_array().unwrap();
    assert_eq!(msgs.len(), 2, "should have 2 messages");

    // Messages are in chronological order
    assert_eq!(msgs[0]["sender_id"].as_str().unwrap(), user_id_a.to_string());
    assert_eq!(msgs[0]["body"].as_str(), Some("Hello Bob!"));
    assert_eq!(msgs[1]["sender_id"].as_str().unwrap(), user_id_b.to_string());
    assert_eq!(msgs[1]["body"].as_str(), Some("Hey Alice!"));

    // User B lists conversations -> should have 1 with unread_count 0
    // (Since user B just wrote, there are no unread from A after B's message)
    let (st, body) = get(&app, "/chat/conversations", &token_b).await;
    assert_eq!(st, StatusCode::OK);
    let convos = body["conversations"].as_array().unwrap();
    assert_eq!(convos.len(), 1);
    // Last message should be "Hey Alice!" from B's perspective
    assert_eq!(convos[0]["last_message_preview"].as_str(), Some("Hey Alice!"));

    // User A marks as read
    let (st, _body) = post(
        &app,
        &format!("/chat/conversations/{conv_id}/read"),
        serde_json::json!({}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "mark read should 200");

    // User A lists conversations -> unread should be 0
    let (st, body) = get(&app, "/chat/conversations", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let convos = body["conversations"].as_array().unwrap();
    assert_eq!(convos[0]["unread_count"].as_i64(), Some(0));
}
