//! Integration tests for Vibra Tier 3 endpoints.
//!
//! Covers:
//! - Right Now: create / list / delete + expiry filtering
//! - Sessions: list / revoke
//! - Screenshot alerts: log / list
//! - Idle reminder: get / set
//! - Unauthenticated requests return 401

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

async fn get(app: &axum::Router, uri: &str, token: Option<&str>) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder().method("GET").uri(uri);
    if let Some(t) = token {
        builder = builder.header("authorization", &format!("Bearer {t}"));
    }
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

async fn delete(
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

fn unique_email() -> String {
    format!("tier3_{}@test.com", uuid::Uuid::new_v4().simple())
}

async fn register_one(app: &axum::Router) -> (String, uuid::Uuid) {
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
    assert_eq!(st, StatusCode::CREATED, "register failed: {body}");
    let token = body["access"].as_str().unwrap().to_string();
    // Decode sub for UUID
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    let parts: Vec<&str> = token.split('.').collect();
    let payload = URL_SAFE_NO_PAD.decode(parts[1]).unwrap();
    let json: serde_json::Value = serde_json::from_slice(&payload).unwrap();
    let sub = json["sub"].as_str().unwrap();
    let user_id = uuid::Uuid::parse_str(sub).unwrap();
    (token, user_id)
}

// ---------------------------------------------------------------------------
// Right Now
// ---------------------------------------------------------------------------

#[tokio::test]
async fn right_now_create_and_list() {
    let app = test_app().await;
    let (token, user_id) = register_one(&app).await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    // Clean slate for this user
    sqlx::query!("DELETE FROM right_now_intents WHERE user_id = $1", user_id)
        .execute(&pool)
        .await
        .unwrap();

    // Create
    let (st, body) = post(
        &app,
        "/right-now",
        serde_json::json!({
            "body": "Looking for coffee, Right Now!",
            "expires_in_minutes": 30,
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let id1 = body["id"].as_str().unwrap().to_string();
    assert!(body["expires_at"].is_string());

    // Create second
    let (st, _body) = post(
        &app,
        "/right-now",
        serde_json::json!({
            "body": "Anything fun happening?"
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // List (should include both)
    let (st, body) = get(&app, "/right-now", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let intents = body["intents"].as_array().unwrap();
    assert!(intents.len() >= 2);

    // Delete one
    let (st, _body) = delete(&app, &format!("/right-now/{id1}"), &token).await;
    assert_eq!(st, StatusCode::NO_CONTENT);

    // Empty body -> 400
    let (st, _body) = post(
        &app,
        "/right-now",
        serde_json::json!({ "body": "   " }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // Negative expires_in_minutes -> 400
    let (st, _body) = post(
        &app,
        "/right-now",
        serde_json::json!({ "body": "hi", "expires_in_minutes": -1 }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn right_now_expires_correctly() {
    let app = test_app().await;
    let (token, user_id) = register_one(&app).await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    // Clean slate for this user
    sqlx::query!("DELETE FROM right_now_intents WHERE user_id = $1", user_id)
        .execute(&pool)
        .await
        .unwrap();

    // Insert an already-expired intent directly via SQL
    sqlx::query!(
        r#"INSERT INTO right_now_intents (user_id, body, expires_at)
           VALUES ($1, $2, now() - interval '1 hour')"#,
        user_id,
        "Expired intent"
    )
    .execute(&pool)
    .await
    .unwrap();

    // Insert a future intent
    sqlx::query!(
        r#"INSERT INTO right_now_intents (user_id, body, expires_at)
           VALUES ($1, $2, now() + interval '1 hour')"#,
        user_id,
        "Future intent"
    )
    .execute(&pool)
    .await
    .unwrap();

    // GET /right-now should only return the future one
    let (st, body) = get(&app, "/right-now", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let intents = body["intents"].as_array().unwrap();
    let bodies: Vec<String> = intents
        .iter()
        .map(|i| i["body"].as_str().unwrap().to_string())
        .collect();
    assert!(bodies.iter().any(|b| b == "Future intent"));
    assert!(!bodies.iter().any(|b| b == "Expired intent"));
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

#[tokio::test]
async fn sessions_list_and_revoke() {
    let app = test_app().await;
    let (token, user_id) = register_one(&app).await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    // Register creates a refresh_token. Clean slate + insert one synthetic.
    sqlx::query!("DELETE FROM refresh_tokens WHERE user_id = $1", user_id)
        .execute(&pool)
        .await
        .unwrap();

    // Insert two non-revoked, non-expired sessions. token_hash has a UNIQUE
    // constraint, so derive per-run-unique hashes from the (unique) user_id
    // to avoid collisions when this test runs against a shared DB more than once.
    let hash_a = format!("{user_id}-hash-A");
    let hash_b = format!("{user_id}-hash-B");
    sqlx::query!(
        r#"INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
           VALUES ($1, $2, now() + interval '1 day')"#,
        user_id,
        hash_a
    )
    .execute(&pool)
    .await
    .unwrap();
    sqlx::query!(
        r#"INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
           VALUES ($1, $2, now() + interval '1 day')"#,
        user_id,
        hash_b
    )
    .execute(&pool)
    .await
    .unwrap();

    // List -> 2
    let (st, body) = get(&app, "/me/sessions", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let sessions = body["sessions"].as_array().unwrap();
    assert_eq!(sessions.len(), 2);

    // Revoke first
    let sid = sessions[0]["id"].as_str().unwrap().to_string();
    let (st, _body) = delete(&app, &format!("/me/sessions/{sid}"), &token).await;
    assert_eq!(st, StatusCode::NO_CONTENT);

    // List -> 1
    let (st, body) = get(&app, "/me/sessions", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let sessions = body["sessions"].as_array().unwrap();
    assert_eq!(sessions.len(), 1);
}

// ---------------------------------------------------------------------------
// Screenshot alerts
// ---------------------------------------------------------------------------

#[tokio::test]
async fn screenshot_alert_log_and_list() {
    let app = test_app().await;
    let (token, user_id) = register_one(&app).await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    // Clean slate
    sqlx::query!("DELETE FROM screenshot_alerts WHERE user_id = $1", user_id)
        .execute(&pool)
        .await
        .unwrap();

    // We need a conversation the user belongs to. Create a self-conversation
    // by inserting one directly.
    let conv_id: uuid::Uuid = sqlx::query_scalar!(
        r#"INSERT INTO conversations DEFAULT VALUES RETURNING id"#
    )
    .fetch_one(&pool)
    .await
    .unwrap();
    sqlx::query!(
        r#"INSERT INTO conversation_members (conversation_id, user_id)
           VALUES ($1, $2)
           ON CONFLICT DO NOTHING"#,
        conv_id,
        user_id
    )
    .execute(&pool)
    .await
    .unwrap();

    // Empty list
    let (st, body) = get(&app, "/screenshots", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["alerts"].as_array().unwrap().len(), 0);

    // Log an alert
    let (st, body) = post(
        &app,
        "/screenshots",
        serde_json::json!({ "conversation_id": conv_id.to_string() }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["id"].is_string());
    assert_eq!(
        body["conversation_id"].as_str().unwrap(),
        conv_id.to_string()
    );

    // List -> 1
    let (st, body) = get(&app, "/screenshots", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let alerts = body["alerts"].as_array().unwrap();
    assert_eq!(alerts.len(), 1);
    assert_eq!(
        alerts[0]["conversation_id"].as_str().unwrap(),
        conv_id.to_string()
    );
}

// ---------------------------------------------------------------------------
// Idle reminder
// ---------------------------------------------------------------------------

#[tokio::test]
async fn idle_reminder_set_get() {
    let app = test_app().await;
    let (token, user_id) = register_one(&app).await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    // Clean slate (remove profile row so we can verify nullability)
    sqlx::query!("DELETE FROM profiles WHERE user_id = $1", user_id)
        .execute(&pool)
        .await
        .unwrap();

    // Initial get (no profile yet) -> hours: null
    let (st, body) = get(&app, "/me/idle-reminder", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["hours"].is_null());

    // Set 24 hours
    let (st, body) = put(
        &app,
        "/me/idle-reminder",
        serde_json::json!({ "hours": 24 }),
        &token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["ok"].as_bool(), Some(true));
    assert_eq!(body["hours"].as_i64(), Some(24));

    // Get -> 24
    let (st, body) = get(&app, "/me/idle-reminder", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["hours"].as_i64(), Some(24));

    // Update to 48
    let (st, _body) = put(
        &app,
        "/me/idle-reminder",
        serde_json::json!({ "hours": 48 }),
        &token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    let (st, body) = get(&app, "/me/idle-reminder", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["hours"].as_i64(), Some(48));

    // Clear by sending null
    let (st, _body) = put(
        &app,
        "/me/idle-reminder",
        serde_json::json!({ "hours": null }),
        &token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    let (st, body) = get(&app, "/me/idle-reminder", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["hours"].is_null());

    // Zero hours -> 400
    let (st, _body) = put(
        &app,
        "/me/idle-reminder",
        serde_json::json!({ "hours": 0 }),
        &token,
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}

// ---------------------------------------------------------------------------
// Unauthenticated access
// ---------------------------------------------------------------------------

#[tokio::test]
async fn unauthenticated_requests_return_401() {
    let app = test_app().await;

    let cases: &[(&str, &str, serde_json::Value)] = &[
        ("GET", "/right-now", serde_json::json!({})),
        ("POST", "/right-now", serde_json::json!({ "body": "x" })),
        ("GET", "/me/sessions", serde_json::json!({})),
        ("GET", "/screenshots", serde_json::json!({})),
        ("POST", "/screenshots", serde_json::json!({})),
        ("GET", "/me/idle-reminder", serde_json::json!({})),
        ("PUT", "/me/idle-reminder", serde_json::json!({ "hours": 12 })),
    ];

    for (method, path, body) in cases {
        let (status, _) = match *method {
            "GET" => get(&app, path, None).await,
            "POST" => post(&app, path, body.clone(), None).await,
            "PUT" => put(&app, path, body.clone(), "").await,
            _ => unreachable!(),
        };
        assert_eq!(
            status,
            StatusCode::UNAUTHORIZED,
            "{method} {path} should be 401 without auth"
        );
    }
}
