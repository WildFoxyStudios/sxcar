//! Integration tests for albums endpoints.

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

async fn put_auth(
    app: &axum::Router,
    uri: &str,
    token: &str,
    body: serde_json::Value,
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

async fn delete_auth(
    app: &axum::Router,
    uri: &str,
    token: &str,
) -> StatusCode {
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
    res.status()
}

fn unique_email() -> String {
    format!("album_{}@test.com", uuid::Uuid::new_v4().simple())
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
async fn create_and_list_albums() {
    let app = test_app().await;

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
    assert_eq!(st, StatusCode::CREATED);
    let token = body["access"].as_str().unwrap().to_string();

    // Create album 1
    let (st, body) = post(
        &app,
        "/albums",
        serde_json::json!({
            "name": "Vacation",
            "description": "Summer trip",
            "is_private": false
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "create album 1 should 201");
    assert!(body["id"].is_string());
    assert_eq!(body["name"], "Vacation");

    // Create album 2
    let (st, _body) = post(
        &app,
        "/albums",
        serde_json::json!({
            "name": "Private pics",
            "description": "Only me",
            "is_private": true
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "create album 2 should 201");

    // List albums
    let (st, body) = get(&app, "/albums", &token).await;
    assert_eq!(st, StatusCode::OK, "list albums should 200");
    let albums = body["albums"].as_array().unwrap();
    assert_eq!(albums.len(), 2, "should have 2 albums");

    let names: Vec<&str> = albums.iter().map(|a| a["name"].as_str().unwrap()).collect();
    assert!(names.contains(&"Vacation"));
    assert!(names.contains(&"Private pics"));

    // Verify photo_count is 0 for both
    for a in albums {
        assert_eq!(a["photo_count"].as_i64(), Some(0));
    }
}

#[tokio::test]
async fn add_photos_to_album_and_get() {
    let app = test_app().await;

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
    assert_eq!(st, StatusCode::CREATED);
    let token = body["access"].as_str().unwrap().to_string();
    let _user_id = user_id_from_token(&token);

    // Create album
    let (st, body) = post(
        &app,
        "/albums",
        serde_json::json!({
            "name": "Photo album",
            "description": null,
            "is_private": false
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let album_id = body["id"].as_str().unwrap().to_string();

    // Add photos (r2 keys that were previously uploaded)
    let (st, body) = post(
        &app,
        &format!("/albums/{album_id}/photos"),
        serde_json::json!({
            "photo_keys": ["r2/key1.jpg", "r2/key2.jpg"]
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "add photos should 200");
    assert_eq!(body["added"].as_i64(), Some(2), "should have added 2 photos");

    // Get album with photos
    let (st, body) = get(&app, &format!("/albums/{album_id}"), &token).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["album"]["photo_count"].as_i64(), Some(2));
    let photos = body["photos"].as_array().unwrap();
    assert_eq!(photos.len(), 2);

    // Verify photo details
    let r2_keys: Vec<&str> = photos
        .iter()
        .map(|p| p["r2_key"].as_str().unwrap())
        .collect();
    assert!(r2_keys.contains(&"r2/key1.jpg"));
    assert!(r2_keys.contains(&"r2/key2.jpg"));

    // Remove a photo
    let photo_id = photos[0]["id"].as_str().unwrap();
    let st = delete_auth(&app, &format!("/albums/{album_id}/photos/{photo_id}"), &token).await;
    assert_eq!(st, StatusCode::NO_CONTENT, "remove photo should 204");

    // Verify only 1 photo left
    let (st, body) = get(&app, &format!("/albums/{album_id}"), &token).await;
    assert_eq!(st, StatusCode::OK);
    let photos = body["photos"].as_array().unwrap();
    assert_eq!(photos.len(), 1);
}

#[tokio::test]
async fn share_album_and_recipient_sees_it() {
    let app = test_app().await;

    // Register album owner
    let email_owner = unique_email();
    let (st, body) = post(
        &app,
        "/auth/register",
        serde_json::json!({
            "email": email_owner,
            "password": "secret123",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let owner_token = body["access"].as_str().unwrap().to_string();

    // Register recipient
    let email_recip = unique_email();
    let (st, body) = post(
        &app,
        "/auth/register",
        serde_json::json!({
            "email": email_recip,
            "password": "secret456",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let recip_token = body["access"].as_str().unwrap().to_string();
    let recip_id = user_id_from_token(&recip_token);

    // Owner creates album
    let (st, body) = post(
        &app,
        "/albums",
        serde_json::json!({
            "name": "Shared album",
            "description": null,
            "is_private": false
        }),
        Some(&owner_token),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let album_id = body["id"].as_str().unwrap().to_string();

    // Share album with recipient
    let (st, body) = post(
        &app,
        &format!("/albums/{album_id}/share"),
        serde_json::json!({
            "user_id": recip_id.to_string()
        }),
        Some(&owner_token),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "share should 201");
    assert_eq!(body["shared_with_user_id"].as_str().unwrap(), recip_id.to_string());

    // Recipient lists shared albums
    let (st, body) = get(&app, "/albums/shared", &recip_token).await;
    assert_eq!(st, StatusCode::OK);
    let albums = body["albums"].as_array().unwrap();
    assert_eq!(albums.len(), 1, "recipient should see 1 shared album");
    assert_eq!(albums[0]["name"].as_str(), Some("Shared album"));
}

#[tokio::test]
async fn unshare_removes_access() {
    let app = test_app().await;

    // Register owner
    let email_owner = unique_email();
    let (st, body) = post(
        &app,
        "/auth/register",
        serde_json::json!({
            "email": email_owner,
            "password": "secret123",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let owner_token = body["access"].as_str().unwrap().to_string();

    // Register recipient
    let email_recip = unique_email();
    let (st, body) = post(
        &app,
        "/auth/register",
        serde_json::json!({
            "email": email_recip,
            "password": "secret456",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let recip_token = body["access"].as_str().unwrap().to_string();
    let recip_id = user_id_from_token(&recip_token);

    // Owner creates album and shares
    let (st, body) = post(
        &app,
        "/albums",
        serde_json::json!({
            "name": "Temporary share",
            "description": null,
            "is_private": false
        }),
        Some(&owner_token),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let album_id = body["id"].as_str().unwrap().to_string();

    let (st, _body) = post(
        &app,
        &format!("/albums/{album_id}/share"),
        serde_json::json!({"user_id": recip_id.to_string()}),
        Some(&owner_token),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);

    // Recipient sees it
    let (st, body) = get(&app, "/albums/shared", &recip_token).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["albums"].as_array().unwrap().len(), 1);

    // Owner unshares
    let st = delete_auth(
        &app,
        &format!("/albums/{album_id}/share/{recip_id}"),
        &owner_token,
    )
    .await;
    assert_eq!(st, StatusCode::NO_CONTENT, "unshare should 204");

    // Recipient no longer sees it
    let (st, body) = get(&app, "/albums/shared", &recip_token).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["albums"].as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn delete_album_returns_204() {
    let app = test_app().await;

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
    assert_eq!(st, StatusCode::CREATED);
    let token = body["access"].as_str().unwrap().to_string();

    // Create album
    let (st, body) = post(
        &app,
        "/albums",
        serde_json::json!({
            "name": "To delete",
            "description": null,
            "is_private": false
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let album_id = body["id"].as_str().unwrap().to_string();

    // Delete album
    let st = delete_auth(&app, &format!("/albums/{album_id}"), &token).await;
    assert_eq!(st, StatusCode::NO_CONTENT, "delete should 204");

    // Verify gone
    let (st, _body) = get(&app, &format!("/albums/{album_id}"), &token).await;
    assert_eq!(st, StatusCode::NOT_FOUND, "deleted album should 404");

    // Cannot delete again
    let st = delete_auth(&app, &format!("/albums/{album_id}"), &token).await;
    assert_eq!(st, StatusCode::NOT_FOUND, "second delete should 404");
}

#[tokio::test]
async fn update_album_modifies_fields() {
    let app = test_app().await;

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
    assert_eq!(st, StatusCode::CREATED);
    let token = body["access"].as_str().unwrap().to_string();

    // Create album
    let (st, body) = post(
        &app,
        "/albums",
        serde_json::json!({
            "name": "Original",
            "description": "Original desc",
            "is_private": false
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let album_id = body["id"].as_str().unwrap().to_string();

    // Update name and make private
    let (st, _body) = put_auth(
        &app,
        &format!("/albums/{album_id}"),
        &token,
        serde_json::json!({
            "name": "Updated",
            "is_private": true
        }),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "update should 200");

    // Get album and verify changes
    let (st, body) = get(&app, &format!("/albums/{album_id}"), &token).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["album"]["name"].as_str(), Some("Updated"));
    assert_eq!(body["album"]["is_private"].as_bool(), Some(true));
    // Description should remain unchanged since we didn't send it
    assert_eq!(body["album"]["description"].as_str(), Some("Original desc"));
}

#[tokio::test]
async fn unauthorized_returns_401() {
    let app = test_app().await;

    // POST /albums without token
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/albums")
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "name": "test",
                        "is_private": false
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);

    // GET /albums without token
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/albums")
                .body(Body::default())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
}
