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
    format!("u{}@test.com", uuid::Uuid::new_v4().simple())
}

/// Helper POST con autenticacion Bearer.
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

/// Helper GET con autenticacion Bearer.
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
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
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

/// Helper PUT con autenticacion Bearer y body JSON.
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
                .header("authorization", format!("Bearer {token}"))
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn get_own_profile_returns_full_data() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (st, body) = get_auth(&app, "/profile", &token).await;
    assert_eq!(st, StatusCode::OK, "GET /profile should 200");
    assert!(body["user"]["id"].is_string(), "user.id should be a string");
    assert!(
        body["user"]["email"].is_string(),
        "user.email should be a string"
    );
    assert!(
        body["user"]["display_name"].is_null(),
        "display_name should be null initially"
    );
    assert!(
        body["user"]["tribes"].is_array(),
        "tribes should be an array"
    );
    assert!(
        body["user"]["looking_for"].is_array(),
        "looking_for should be an array"
    );
    assert!(
        body["user"]["meet_at"].is_array(),
        "meet_at should be an array"
    );
    assert!(body["user"]["tags"].is_array(), "tags should be an array");
}

#[tokio::test]
async fn update_profile_changes_display_name() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (st, body) = put_auth(
        &app,
        "/profile",
        &token,
        serde_json::json!({"display_name": "TestUser"}),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "PUT /profile should 200");
    assert_eq!(body["user"]["display_name"], "TestUser");

    // Verify persistence via GET
    let (st, body) = get_auth(&app, "/profile", &token).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["user"]["display_name"], "TestUser");
}

#[tokio::test]
async fn update_profile_with_all_fields() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    let (st, body) = put_auth(
        &app,
        "/profile",
        &token,
        serde_json::json!({
            "display_name": "FullProfile",
            "bio": "Hello world",
            "birthdate": "1995-06-15",
            "height_cm": 180,
            "weight_kg": 75,
            "body_type": "athletic",
            "relationship_status": "single",
            "position": "versatile",
            "ethnicity": "latino",
            "pronouns": "he/him",
            "tribes": ["geek", "bear"],
            "looking_for": ["chat", "friends"],
            "meet_at": ["bar", "gym"],
            "tags": ["fitness", "music"]
        }),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["user"]["display_name"], "FullProfile");
    assert_eq!(body["user"]["bio"], "Hello world");
    assert_eq!(body["user"]["birthdate"], "1995-06-15");
    assert_eq!(body["user"]["height_cm"], 180);
    assert_eq!(body["user"]["weight_kg"], 75);
    assert_eq!(body["user"]["body_type"], "athletic");
    assert_eq!(body["user"]["relationship_status"], "single");
    assert_eq!(body["user"]["position"], "versatile");
    assert_eq!(body["user"]["ethnicity"], "latino");
    assert_eq!(body["user"]["pronouns"], "he/him");

    // Verify arrays
    let tribes = body["user"]["tribes"].as_array().unwrap();
    let tribe_names: Vec<&str> = tribes.iter().map(|v| v.as_str().unwrap()).collect();
    assert!(tribe_names.contains(&"bear"));
    assert!(tribe_names.contains(&"geek"));

    let looking_for = body["user"]["looking_for"].as_array().unwrap();
    let lf: Vec<&str> = looking_for.iter().map(|v| v.as_str().unwrap()).collect();
    assert!(lf.contains(&"chat"));
    assert!(lf.contains(&"friends"));

    let tags = body["user"]["tags"].as_array().unwrap();
    let tag_vals: Vec<&str> = tags.iter().map(|v| v.as_str().unwrap()).collect();
    assert!(tag_vals.contains(&"fitness"));

    // Verify via GET
    let (st, body) = get_auth(&app, "/profile", &token).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["user"]["display_name"], "FullProfile");
}

#[tokio::test]
async fn get_other_profile_by_id_returns_public_data() {
    let app = test_app().await;
    let (_email1, token1) = register_and_login(&app).await;
    let (_email2, token2) = register_and_login(&app).await;

    // Set display_name for user2
    put_auth(
        &app,
        "/profile",
        &token2,
        serde_json::json!({"display_name": "UserTwo"}),
    )
    .await;

    // Get user2's id from their own profile
    let (_st, body2) = get_auth(&app, "/profile", &token2).await;
    let user2_id = body2["user"]["id"].as_str().unwrap().to_string();

    // User1 views User2's profile
    let (st, body) = get_auth(&app, &format!("/profile/{user2_id}"), &token1).await;
    assert_eq!(st, StatusCode::OK, "GET /profile/:id should 200");
    assert_eq!(body["user"]["display_name"], "UserTwo");
}

#[tokio::test]
async fn get_other_profile_returns_404_for_nonexistent() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;
    let bogus_id = uuid::Uuid::new_v4();

    let (st, _body) = get_auth(&app, &format!("/profile/{bogus_id}"), &token).await;
    assert_eq!(st, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn unauthenticated_returns_401() {
    let app = test_app().await;

    // GET /profile without token
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/profile")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);

    // PUT /profile without token
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/profile")
                .header("content-type", "application/json")
                .body(Body::from(serde_json::json!({"display_name": "test"}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);

    // GET /profile/:id without token
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/profile/00000000-0000-0000-0000-000000000000")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
}
