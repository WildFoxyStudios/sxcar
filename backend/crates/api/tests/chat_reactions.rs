//! Integration tests for message reaction endpoints (G4a).
//!
//! Covers: PUT /chat/messages/:id/reaction, DELETE /chat/messages/:id/reaction,
//! and verifies reactions appear in GET /chat/conversations/:id/messages.

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
    format!("react_{}@test.com", uuid::Uuid::new_v4().simple())
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

async fn put_json(
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
                .header("authorization", &format!("Bearer {token}"))
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

async fn delete_req(
    app: &axum::Router,
    uri: &str,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
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
async fn set_reaction_then_message_list_includes_it() {
    let app = test_app().await;
    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;
    let (conv_id, msg_id) = setup_conversation_with_message(&app, &token_a, &uid_b).await;

    // User A puts a reaction on the message
    let (st, body) = put_json(
        &app,
        &format!("/chat/messages/{msg_id}/reaction"),
        serde_json::json!({ "emoji": "❤️" }),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK, "put_reaction should 200: {body}");
    assert_eq!(body["ok"], serde_json::json!(true));

    // GET messages and verify the reaction appears
    let (st, body) = get_json(
        &app,
        &format!("/chat/conversations/{conv_id}/messages?limit=50"),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let msgs = body["messages"].as_array().unwrap();
    let msg = msgs.iter().find(|m| m["id"].as_str() == Some(&msg_id)).unwrap();
    let reactions = msg["reactions"].as_array().unwrap();
    assert_eq!(reactions.len(), 1, "should have 1 reaction");
    assert_eq!(reactions[0]["emoji"].as_str(), Some("❤️"));
}

#[tokio::test]
async fn reaction_replaces_on_second_emoji() {
    let app = test_app().await;
    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;
    let (conv_id, msg_id) = setup_conversation_with_message(&app, &token_a, &uid_b).await;

    // User A puts ❤️ first
    let (st, _) = put_json(
        &app,
        &format!("/chat/messages/{msg_id}/reaction"),
        serde_json::json!({ "emoji": "❤️" }),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // User A replaces with 😂
    let (st, _) = put_json(
        &app,
        &format!("/chat/messages/{msg_id}/reaction"),
        serde_json::json!({ "emoji": "😂" }),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // GET messages: should have only 😂 (one per user)
    let (st, body) = get_json(
        &app,
        &format!("/chat/conversations/{conv_id}/messages?limit=50"),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let msgs = body["messages"].as_array().unwrap();
    let msg = msgs.iter().find(|m| m["id"].as_str() == Some(&msg_id)).unwrap();
    let reactions = msg["reactions"].as_array().unwrap();
    assert_eq!(reactions.len(), 1, "should still have only 1 reaction (replaced)");
    assert_eq!(reactions[0]["emoji"].as_str(), Some("😂"));
}

#[tokio::test]
async fn delete_reaction_removes_it() {
    let app = test_app().await;
    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;
    let (conv_id, msg_id) = setup_conversation_with_message(&app, &token_a, &uid_b).await;

    // Set a reaction
    let (st, _) = put_json(
        &app,
        &format!("/chat/messages/{msg_id}/reaction"),
        serde_json::json!({ "emoji": "👍" }),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // Delete it
    let (st, body) = delete_req(
        &app,
        &format!("/chat/messages/{msg_id}/reaction"),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK, "delete_reaction should 200: {body}");

    // GET messages: reactions should be empty
    let (st, body) = get_json(
        &app,
        &format!("/chat/conversations/{conv_id}/messages?limit=50"),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let msgs = body["messages"].as_array().unwrap();
    let msg = msgs.iter().find(|m| m["id"].as_str() == Some(&msg_id)).unwrap();
    let reactions = msg["reactions"].as_array().unwrap();
    assert!(reactions.is_empty(), "reactions should be empty after delete");
}

#[tokio::test]
async fn non_member_forbidden() {
    let app = test_app().await;
    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;
    // Register a third user who is NOT a member
    let (token_c, _uid_c) = register_user(&app).await;

    let (_conv_id, msg_id) = setup_conversation_with_message(&app, &token_a, &uid_b).await;

    // User C (not in the conversation) tries to react → 403
    let (st, body) = put_json(
        &app,
        &format!("/chat/messages/{msg_id}/reaction"),
        serde_json::json!({ "emoji": "🔥" }),
        &token_c,
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN, "non-member should get 403: {body}");
}
