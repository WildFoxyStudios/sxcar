//! Integration tests for message unsend (G5).
//!
//! Covers: POST /chat/messages/:id/unsend, verifies message still appears
//! in GET /messages with unsent_at set, and non-sender gets 404.

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
    format!("unsend_{}@test.com", uuid::Uuid::new_v4().simple())
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

async fn post_json(
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

async fn get_json(
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

/// Register a user and return (token, user_id_string).
async fn register_user(app: &axum::Router) -> (String, String) {
    let email = unique_email();
    let (st, body) = post_json(
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
    assert_eq!(st, StatusCode::CREATED, "register should 201: {body}");
    let token = body["access"].as_str().unwrap().to_string();
    let user_id = user_id_from_token(&token).to_string();
    (token, user_id)
}

/// Creates a conversation between user A and user B (using token_a), sends one
/// text message as user A. Returns (conv_id, msg_id).
async fn setup_conversation_with_message(
    app: &axum::Router,
    token_a: &str,
    user_id_b: &str,
) -> (String, String) {
    // Create conversation
    let (st, body) = post_json(
        app,
        "/chat/conversations",
        serde_json::json!({ "participant_id": user_id_b }),
        Some(token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "create_conversation should 201: {body}");
    let conv_id = body["conversation_id"].as_str().unwrap().to_string();

    // Send a message as user A
    let (st, body) = post_json(
        app,
        &format!("/chat/conversations/{conv_id}/messages"),
        serde_json::json!({ "text": "Hello!" }),
        Some(token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "send_message should 201: {body}");
    let msg_id = body["id"].as_str().unwrap().to_string();

    (conv_id, msg_id)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn unsend_message_own_sets_unsent_at() {
    let app = test_app().await;
    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;
    let (conv_id, msg_id) = setup_conversation_with_message(&app, &token_a, &uid_b).await;

    // Unsend the message as the sender
    let (st, body) = post_json(
        &app,
        &format!("/chat/messages/{msg_id}/unsend"),
        serde_json::json!({}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "unsend should 200: {body}");
    assert_eq!(body["ok"], serde_json::json!(true));

    // GET messages: the unsent message should still appear with unsent_at set
    let (st, body) = get_json(
        &app,
        &format!("/chat/conversations/{conv_id}/messages?limit=50"),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let msgs = body["messages"].as_array().unwrap();
    let msg = msgs.iter().find(|m| m["id"].as_str() == Some(&msg_id)).unwrap();
    assert!(
        msg["unsent_at"].as_str().is_some(),
        "unsent message should have unsent_at set: {msg:?}"
    );
}

#[tokio::test]
async fn non_sender_unsend_rejected() {
    let app = test_app().await;
    let (token_a, _uid_a) = register_user(&app).await;
    let (token_b, uid_b) = register_user(&app).await;
    let (_conv_id, msg_id) = setup_conversation_with_message(&app, &token_a, &uid_b).await;

    // User B (not the sender) tries to unsend user A's message → 404
    let (st, body) = post_json(
        &app,
        &format!("/chat/messages/{msg_id}/unsend"),
        serde_json::json!({}),
        Some(&token_b),
    )
    .await;
    assert_eq!(
        st, StatusCode::NOT_FOUND,
        "non-sender should get 404: {body}"
    );
}

#[tokio::test]
async fn unsend_already_unsent_returns_404() {
    let app = test_app().await;
    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;
    let (_conv_id, msg_id) = setup_conversation_with_message(&app, &token_a, &uid_b).await;

    // First unsend succeeds
    let (st, _) = post_json(
        &app,
        &format!("/chat/messages/{msg_id}/unsend"),
        serde_json::json!({}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // Second unsend returns 404 (already unsent)
    let (st, body) = post_json(
        &app,
        &format!("/chat/messages/{msg_id}/unsend"),
        serde_json::json!({}),
        Some(&token_a),
    )
    .await;
    assert_eq!(
        st, StatusCode::NOT_FOUND,
        "second unsend should 404 (already unsent): {body}"
    );
}
