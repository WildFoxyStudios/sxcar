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

// ─── T4.3: details + show_* privacy flags ─────────────────────────────────

#[tokio::test]
async fn put_details_persists_and_get_own_returns_full() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;
    let custom_details = serde_json::json!({
        "vaccines": ["covid", "hepb"],
        "social": {"instagram": "@me"},
        "trip_count": 3
    });

    let (put_status, _) = put_auth(
        &app,
        "/profile",
        &token,
        serde_json::json!({ "details": custom_details }),
    ).await;
    assert_eq!(put_status, StatusCode::OK);

    // GET /profile returns unfiltered — owner sees full details
    let (get_status, body) = get_auth(&app, "/profile", &token).await;
    assert_eq!(get_status, StatusCode::OK);
    assert_eq!(body["user"]["details"], custom_details);
}

#[tokio::test]
async fn get_public_filters_show_age_when_false() {
    let app = test_app().await;
    let (_email1, token1) = register_and_login(&app).await;
    let (_email2, token2) = register_and_login(&app).await;

    // Owner sets show_age=false via PUT /profile
    let (s, _) = put_auth(
        &app,
        "/profile",
        &token1,
        serde_json::json!({ "birthdate": "1995-06-15", "show_age": false }),
    ).await;
    assert_eq!(s, StatusCode::OK);

    // Get owner id
    let (_, body1) = get_auth(&app, "/profile", &token1).await;
    let owner_id = body1["user"]["id"].as_str().unwrap();

    // Other user views owner's profile — birthdate must be stripped
    let (_, body) = get_auth(&app, &format!("/profile/{owner_id}"), &token2).await;
    assert!(
        body["user"].get("birthdate").is_none(),
        "birthdate must be absent when show_age=false, got: {body}"
    );
}

#[tokio::test]
async fn get_public_filters_show_role_when_false() {
    let app = test_app().await;
    let (_email1, token1) = register_and_login(&app).await;
    let (_email2, token2) = register_and_login(&app).await;

    let (s, _) = put_auth(
        &app,
        "/profile",
        &token1,
        serde_json::json!({ "show_role": false }),
    ).await;
    assert_eq!(s, StatusCode::OK);

    let (_, body1) = get_auth(&app, "/profile", &token1).await;
    let owner_id = body1["user"]["id"].as_str().unwrap();

    let (_, body) = get_auth(&app, &format!("/profile/{owner_id}"), &token2).await;
    assert!(body["user"].get("role").is_none(), "role must be absent when show_role=false");
}

#[tokio::test]
async fn get_public_filters_show_tribes_when_false() {
    let app = test_app().await;
    let (_email1, token1) = register_and_login(&app).await;
    let (_email2, token2) = register_and_login(&app).await;

    // Set tribes + show_tribes=false
    let (s, _) = put_auth(
        &app,
        "/profile",
        &token1,
        serde_json::json!({
            "tribes": ["twink", "bear"],
            "show_tribes": false,
        }),
    ).await;
    assert_eq!(s, StatusCode::OK);

    let (_, body1) = get_auth(&app, "/profile", &token1).await;
    let owner_id = body1["user"]["id"].as_str().unwrap();

    let (_, body) = get_auth(&app, &format!("/profile/{owner_id}"), &token2).await;
    // Per spec: when show_tribes=false, tribes is removed (not just emptied)
    assert!(
        body["user"].get("tribes").is_none(),
        "tribes must be absent when show_tribes=false"
    );
}

#[tokio::test]
async fn get_public_strips_all_six_show_flags_simultaneously() {
    let app = test_app().await;
    let (_email1, token1) = register_and_login(&app).await;
    let (_email2, token2) = register_and_login(&app).await;

    let (s, _) = put_auth(
        &app,
        "/profile",
        &token1,
        serde_json::json!({
            "birthdate": "1990-01-01",
            "role": "top",
            "position": "top",
            "ethnicity": "latino",
            "relationship_status": "single",
            "show_age": false,
            "show_role": false,
            "show_position": false,
            "show_ethnicity": false,
            "show_relationship_status": false,
            "show_tribes": false,
        }),
    ).await;
    assert_eq!(s, StatusCode::OK);

    let (_, body1) = get_auth(&app, "/profile", &token1).await;
    let owner_id = body1["user"]["id"].as_str().unwrap();

    let (_, body) = get_auth(&app, &format!("/profile/{owner_id}"), &token2).await;
    let user = &body["user"];
    for field in &["birthdate", "role", "position", "ethnicity", "relationship_status"] {
        assert!(
            user.get(field).is_none(),
            "{field} must be absent, got: {user}"
        );
    }
    // tribes is always present (empty array if no tribes set + show_tribes=false strips it; here
    // owner didn't set tribes, so the spec strips it too)
    assert!(user.get("tribes").is_none(), "tribes must also be absent");
    // details is always present (client-side gates social links via show_social_links)
    assert!(user.get("details").is_some(), "details must remain visible");
}

#[tokio::test]
async fn put_rejects_details_not_an_object() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    // Array is not an object — should 422
    let (s, _) = put_auth(
        &app,
        "/profile",
        &token,
        serde_json::json!({ "details": [1, 2, 3] }),
    ).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // Scalar is not an object — should 422
    let (s, _) = put_auth(
        &app,
        "/profile",
        &token,
        serde_json::json!({ "details": "a string" }),
    ).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // null is not an object — should 422
    let (s, _) = put_auth(
        &app,
        "/profile",
        &token,
        serde_json::json!({ "details": null }),
    ).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn put_rejects_details_over_8kb() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    // Build a JSON object whose serialized form is > 8192 bytes.
    // A single long string value of ~8100 chars wrapped in an object yields ~8120 bytes.
    let big_string = "x".repeat(8200);
    let (s, _) = put_auth(
        &app,
        "/profile",
        &token,
        serde_json::json!({ "details": { "big": big_string } }),
    ).await;
    assert_eq!(s, StatusCode::PAYLOAD_TOO_LARGE);
}

#[tokio::test]
async fn put_accepts_details_exactly_8kb() {
    let app = test_app().await;
    let (_email, token) = register_and_login(&app).await;

    // Build a JSON object whose serialized form is exactly 8192 bytes.
    // The skeleton `{"details":{"big":"..."}}` is ~21 bytes overhead;
    // the value field "big":"<N chars>" takes 8 + N chars; brackets add a few.
    // Calculate precisely: total = N (chars) + skeleton overhead.
    // 8192 - 19 (skeleton overhead after the value) = 8173 chars in value.
    // Easiest: build candidate, serialize, adjust, retry until exact.
    let mut payload_chars = 8100;
    let mut details = serde_json::json!({ "big": "x".repeat(payload_chars) });
    let mut body = serde_json::json!({ "details": details });
    let serialized_len = serde_json::to_vec(&body).unwrap().len();
    // Adjust to hit exactly 8192
    let diff = 8192_i64 - serialized_len as i64;
    if diff != 0 {
        payload_chars = (payload_chars as i64 + diff) as usize;
        details = serde_json::json!({ "big": "x".repeat(payload_chars) });
        body = serde_json::json!({ "details": details });
    }
    // Final sanity
    let final_len = serde_json::to_vec(&body).unwrap().len();
    assert!(
        final_len <= 8192,
        "test setup error: payload is {} bytes (want <= 8192)",
        final_len
    );

    let (s, _) = put_auth(&app, "/profile", &token, body).await;
    assert_eq!(s, StatusCode::OK, "exactly-8KB payload must be accepted");
}
