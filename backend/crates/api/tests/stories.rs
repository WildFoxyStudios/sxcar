//! Integration tests for stories endpoints (POST/GET/DELETE/view).
//!
//! Seeds users, creates stories, and verifies CRUD + access control.

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
    format!("story_{}@test.com", uuid::Uuid::new_v4().simple())
}

async fn register_and_login(app: &axum::Router) -> (String, String) {
    let email = unique_email();
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "email": email,
                        "password": "testpass123",
                        "dob": "1990-01-01",
                        "consents": ["tos", "privacy"]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let access = body["access"].as_str().unwrap().to_string();
    (email, access)
}

fn user_id_from_token(token: &str) -> uuid::Uuid {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        return uuid::Uuid::nil();
    }
    let payload = parts[1];
    use base64::Engine;
    let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload)
        .unwrap_or_default();
    let json: serde_json::Value =
        serde_json::from_slice(&decoded).unwrap_or(serde_json::Value::Null);
    json["sub"]
        .as_str()
        .and_then(|s| s.parse().ok())
        .unwrap_or(uuid::Uuid::nil())
}

/// Build a story media_key owned by the token's user, matching the
/// `story/<user_id>/...` prefix the handler now enforces.
fn story_key(token: &str, name: &str) -> String {
    format!("story/{}/{}", user_id_from_token(token), name)
}

async fn post_auth(
    app: &axum::Router,
    uri: &str,
    token: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
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

async fn get_auth(
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

async fn delete_auth(
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn create_story_returns_201() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (st, body) = post_auth(
        &app,
        "/stories",
        &token,
        serde_json::json!({
            "media_key": story_key(&token, "test.jpg"),
            "media_type": "photo",
        }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    assert!(body["id"].is_string());
}

#[tokio::test]
async fn create_story_with_caption() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (st, body) = post_auth(
        &app,
        "/stories",
        &token,
        serde_json::json!({
            "media_key": story_key(&token, "test.jpg"),
            "media_type": "photo",
            "caption": "Hello stories!",
        }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    assert!(body["id"].is_string());
}

#[tokio::test]
async fn create_story_rejects_invalid_media_type() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (st, _) = post_auth(
        &app,
        "/stories",
        &token,
        serde_json::json!({
            "media_key": story_key(&token, "test.jpg"),
            "media_type": "document",
        }),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn create_story_rejects_empty_media_key() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (st, _) = post_auth(
        &app,
        "/stories",
        &token,
        serde_json::json!({
            "media_key": "",
            "media_type": "photo",
        }),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn list_stories_returns_only_active() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;
    let user_id = user_id_from_token(&token);

    // Create a story
    let (st, _) = post_auth(
        &app,
        "/stories",
        &token,
        serde_json::json!({
            "media_key": story_key(&token, "active.jpg"),
            "media_type": "photo",
        }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);

    // List stories — should include own story
    let (st, body) = get_auth(&app, "/stories", &token).await;
    assert_eq!(st, StatusCode::OK);
    let stories = body["stories"].as_array().unwrap();
    assert!(!stories.is_empty(), "should have at least own story");

    // Create an expired story directly in DB (for testing expiry filter)
    sqlx::query(
        "INSERT INTO stories (user_id, media_key, media_type, expires_at) VALUES ($1, $2, $3, now() - interval '1 hour')"
    )
    .bind(user_id)
    .bind("story/uuid/expired.jpg")
    .bind("photo")
    .execute(&db::connect(&test_db_url()).await.unwrap())
    .await
    .unwrap();

    // List should not include expired
    let (st, body) = get_auth(&app, "/stories", &token).await;
    assert_eq!(st, StatusCode::OK);
    let stories = body["stories"].as_array().unwrap();
    for s in stories {
        let mk = s["media_key"].as_str().unwrap();
        assert_ne!(mk, "story/uuid/expired.jpg", "expired story must not appear");
    }
}

#[tokio::test]
async fn delete_own_story_returns_204() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (_st, body) = post_auth(
        &app,
        "/stories",
        &token,
        serde_json::json!({
            "media_key": story_key(&token, "to-delete.jpg"),
            "media_type": "photo",
        }),
    )
    .await;
    let story_id = body["id"].as_str().unwrap().to_string();

    let (st, _) = delete_auth(&app, &format!("/stories/{story_id}"), &token).await;
    assert_eq!(st, StatusCode::NO_CONTENT);

    // Verify deletion: GET should not include it
    let (st, body) = get_auth(&app, "/stories", &token).await;
    assert_eq!(st, StatusCode::OK);
    let stories = body["stories"].as_array().unwrap();
    for s in stories {
        let sid = s["id"].as_str().unwrap();
        assert_ne!(sid, story_id, "deleted story must not appear");
    }
}

#[tokio::test]
async fn delete_other_users_story_returns_404() {
    let app = test_app().await;
    let (_email1, token1) = register_and_login(&app).await;
    let (_email2, token2) = register_and_login(&app).await;

    // User1 creates a story
    let (_st, body) = post_auth(
        &app,
        "/stories",
        &token1,
        serde_json::json!({
            "media_key": story_key(&token1, "other.jpg"),
            "media_type": "photo",
        }),
    )
    .await;
    let story_id = body["id"].as_str().unwrap().to_string();

    // User2 tries to delete User1's story
    let (st, _) = delete_auth(&app, &format!("/stories/{story_id}"), &token2).await;
    assert_eq!(st, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn view_story_returns_200() {
    let app = test_app().await;
    let (_email1, token1) = register_and_login(&app).await;
    let (_email2, token2) = register_and_login(&app).await;

    // User1 creates a story
    let (_st, body) = post_auth(
        &app,
        "/stories",
        &token1,
        serde_json::json!({
            "media_key": story_key(&token1, "view-test.jpg"),
            "media_type": "photo",
        }),
    )
    .await;
    let story_id = body["id"].as_str().unwrap().to_string();

    // User2 views the story
    let (st, _) = post_auth(
        &app,
        &format!("/stories/{story_id}/view"),
        &token2,
        serde_json::json!({}),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
}

#[tokio::test]
async fn view_story_viewing_own_returns_200_noop() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (_st, body) = post_auth(
        &app,
        "/stories",
        &token,
        serde_json::json!({
            "media_key": story_key(&token, "own-view.jpg"),
            "media_type": "photo",
        }),
    )
    .await;
    let story_id = body["id"].as_str().unwrap().to_string();

    // Viewing own story should also return 200 (noop)
    let (st, _) = post_auth(
        &app,
        &format!("/stories/{story_id}/view"),
        &token,
        serde_json::json!({}),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
}

#[tokio::test]
async fn view_nonexistent_story_returns_404() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;
    let bogus_id = uuid::Uuid::new_v4();

    let (st, _) = post_auth(
        &app,
        &format!("/stories/{bogus_id}/view"),
        &token,
        serde_json::json!({}),
    )
    .await;
    assert_eq!(st, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn unauthenticated_returns_401() {
    let app = test_app().await;

    // POST /stories without token
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/stories")
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "media_key": "story/uuid/noauth.jpg",
                        "media_type": "photo",
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);

    // GET /stories without token
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/stories")
                .body(Body::default())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);

    // DELETE /stories/:id without token
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri("/stories/00000000-0000-0000-0000-000000000000")
                .body(Body::default())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn grouped_response_includes_own_stories() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (_st, _) = post_auth(
        &app,
        "/stories",
        &token,
        serde_json::json!({
            "media_key": story_key(&token, "group-test.jpg"),
            "media_type": "photo",
        }),
    )
    .await;

    let (st, body) = get_auth(&app, "/stories", &token).await;
    assert_eq!(st, StatusCode::OK);

    let grouped = body["grouped"].as_array().unwrap();
    assert!(!grouped.is_empty(), "grouped should not be empty");

    // Find own group
    let user_id = user_id_from_token(&token).to_string();
    let own_group = grouped.iter().find(|g| g["user_id"].as_str() == Some(&user_id));
    assert!(own_group.is_some(), "own stories should appear in grouped response");
}
