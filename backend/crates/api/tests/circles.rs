//! Integration tests for Circles (group chats).
//!
//! Tests cover: create group, add member, remove member, non-member can't
//! send (enforced by membership check), non-creator can't rename.

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
    token: Option<&str>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method("PUT")
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

fn unique_email() -> String {
    format!("circle_{}@test.com", uuid::Uuid::new_v4().simple())
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

/// Register a user and return (token, user_id).
async fn register_user(app: &axum::Router) -> (String, uuid::Uuid) {
    let email = unique_email();
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

#[tokio::test]
async fn create_group() {
    let app = test_app().await;

    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;

    // Create a group with user_a as creator and user_b as member
    let (st, body) = post(
        &app,
        "/chat/groups",
        serde_json::json!({
            "name": "Test Group",
            "member_ids": [uid_b.to_string()]
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "create group should 201");
    let group_id = body["group_id"].as_str().unwrap().to_string();

    // Creator should see the group in their group list
    let (st, body) = get(&app, "/chat/groups", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let groups = body["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 1, "creator should have 1 group");
    assert_eq!(groups[0]["group_id"].as_str().unwrap(), &group_id);
    assert_eq!(groups[0]["name"].as_str(), Some("Test Group"));
    assert_eq!(groups[0]["member_count"].as_i64(), Some(2));

    // Member should also see the group
    let (st, body) = get(&app, "/chat/groups", &_token_b).await;
    assert_eq!(st, StatusCode::OK);
    let groups = body["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 1, "member should have 1 group");

    // Conversation list should include groups with is_group = true
    let (st, body) = get(&app, "/chat/conversations", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let convos = body["conversations"].as_array().unwrap();
    let group_conv = convos.iter().find(|c| {
        c["conversation_id"].as_str() == Some(&group_id)
    });
    assert!(group_conv.is_some(), "group should appear in conversations");
    let gc = group_conv.unwrap();
    assert_eq!(gc["is_group"].as_bool(), Some(true));
    assert_eq!(gc["name"].as_str(), Some("Test Group"));
}

#[tokio::test]
async fn add_group_member() {
    let app = test_app().await;

    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;
    let (_token_c, uid_c) = register_user(&app).await;

    // Create a group with A and B
    let (st, body) = post(
        &app,
        "/chat/groups",
        serde_json::json!({
            "name": "Group",
            "member_ids": [uid_b.to_string()]
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let group_id = body["group_id"].as_str().unwrap().to_string();

    // Add user C via A (any member can add)
    let (st, _) = post(
        &app,
        &format!("/chat/groups/{group_id}/members"),
        serde_json::json!({"user_id": uid_c.to_string()}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "add member should 201");

    // Verify C sees the group
    let (st, body) = get(&app, "/chat/groups", &_token_c).await;
    assert_eq!(st, StatusCode::OK);
    let groups = body["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 1, "C should see the group");
    assert_eq!(groups[0]["member_count"].as_i64(), Some(3));
}

#[tokio::test]
async fn remove_group_member() {
    let app = test_app().await;

    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;
    let (_token_c, uid_c) = register_user(&app).await;

    // Create a group with A + B + C
    let (st, body) = post(
        &app,
        "/chat/groups",
        serde_json::json!({
            "name": "Trio",
            "member_ids": [uid_b.to_string(), uid_c.to_string()]
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let group_id = body["group_id"].as_str().unwrap().to_string();

    // Creator (A) removes C
    let (st, _) = delete_req(
        &app,
        &format!("/chat/groups/{group_id}/members/{}", uid_c),
        &token_a,
    )
    .await;
    assert_eq!(st, StatusCode::OK, "creator remove member should 200");

    // Verify C no longer sees the group
    let (st, body) = get(&app, "/chat/groups", &_token_c).await;
    assert_eq!(st, StatusCode::OK);
    let groups = body["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 0, "C should no longer see the group");

    // Member-count should be 2
    let (st, body) = get(&app, "/chat/groups", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let groups = body["groups"].as_array().unwrap();
    assert_eq!(groups[0]["member_count"].as_i64(), Some(2));
}

#[tokio::test]
async fn self_leave_group() {
    let app = test_app().await;

    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;

    // Create a group
    let (st, body) = post(
        &app,
        "/chat/groups",
        serde_json::json!({
            "name": "Duo",
            "member_ids": [uid_b.to_string()]
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let group_id = body["group_id"].as_str().unwrap().to_string();

    // B leaves (self-removal)
    let (st, _) = delete_req(
        &app,
        &format!("/chat/groups/{group_id}/members/{}", uid_b),
        &_token_b,
    )
    .await;
    assert_eq!(st, StatusCode::OK, "self-removal should 200");

    // B should no longer see the group
    let (st, body) = get(&app, "/chat/groups", &_token_b).await;
    assert_eq!(st, StatusCode::OK);
    let groups = body["groups"].as_array().unwrap();
    assert_eq!(groups.len(), 0, "leaver should not see group");
}

#[tokio::test]
async fn non_member_cannot_send_to_group() {
    let app = test_app().await;

    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;
    let (token_c, _uid_c) = register_user(&app).await;

    // Create a group with A + B
    let (st, body) = post(
        &app,
        "/chat/groups",
        serde_json::json!({
            "name": "Private",
            "member_ids": [uid_b.to_string()]
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let group_id = body["group_id"].as_str().unwrap().to_string();

    // C (non-member) tries to send a message -> should get FORBIDDEN
    let (st, _) = post(
        &app,
        &format!("/chat/conversations/{group_id}/messages"),
        serde_json::json!({"text": "Hello"}),
        Some(&token_c),
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN, "non-member should be forbidden from sending");
}

#[tokio::test]
async fn non_creator_cannot_rename() {
    let app = test_app().await;

    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;

    // Create a group with A as creator, B as member
    let (st, body) = post(
        &app,
        "/chat/groups",
        serde_json::json!({
            "name": "Original Name",
            "member_ids": [uid_b.to_string()]
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let group_id = body["group_id"].as_str().unwrap().to_string();

    // B (non-creator) tries to rename -> should get FORBIDDEN
    let (st, _) = put(
        &app,
        &format!("/chat/groups/{group_id}/name"),
        serde_json::json!({"name": "Hacked Name"}),
        Some(&_token_b),
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN, "non-creator should be forbidden from renaming");

    // Verify the name stayed the same
    let (st, body) = get(&app, "/chat/conversations", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let convos = body["conversations"].as_array().unwrap();
    let gc = convos.iter().find(|c| c["conversation_id"].as_str() == Some(&group_id)).unwrap();
    assert_eq!(gc["name"].as_str(), Some("Original Name"));
}

#[tokio::test]
async fn creator_can_rename() {
    let app = test_app().await;

    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;

    // Create a group
    let (st, body) = post(
        &app,
        "/chat/groups",
        serde_json::json!({
            "name": "Old Name",
            "member_ids": [uid_b.to_string()]
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let group_id = body["group_id"].as_str().unwrap().to_string();

    // Creator renames
    let (st, _) = put(
        &app,
        &format!("/chat/groups/{group_id}/name"),
        serde_json::json!({"name": "New Name"}),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "creator rename should 200");

    // Verify the name changed
    let (st, body) = get(&app, "/chat/conversations", &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let convos = body["conversations"].as_array().unwrap();
    let gc = convos.iter().find(|c| c["conversation_id"].as_str() == Some(&group_id)).unwrap();
    assert_eq!(gc["name"].as_str(), Some("New Name"));
}

#[tokio::test]
async fn list_group_members() {
    let app = test_app().await;

    let (token_a, _uid_a) = register_user(&app).await;
    let (_token_b, uid_b) = register_user(&app).await;

    // Create a group
    let (st, body) = post(
        &app,
        "/chat/groups",
        serde_json::json!({
            "name": "Member Test",
            "member_ids": [uid_b.to_string()]
        }),
        Some(&token_a),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let group_id = body["group_id"].as_str().unwrap().to_string();

    // List members
    let (st, body) = get(&app, &format!("/chat/groups/{group_id}/members"), &token_a).await;
    assert_eq!(st, StatusCode::OK);
    let members = body["members"].as_array().unwrap();
    assert_eq!(members.len(), 2, "should have 2 members");
}
