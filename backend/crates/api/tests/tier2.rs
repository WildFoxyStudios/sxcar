//! Integration tests for Vibra Tier 2 endpoints.
//!
//! Covers:
//! - Boost: create + check active
//! - Saved phrases: add / list / delete / reorder
//! - Saved places: add / list / delete
//! - Roam location preference: set / get / clear
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
    format!("tier2_{}@test.com", uuid::Uuid::new_v4().simple())
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
// Boost
// ---------------------------------------------------------------------------

#[tokio::test]
async fn boost_create_and_check_active() {
    let app = test_app().await;
    let (token, _user_id) = register_one(&app).await;

    // Initially not boosted
    let (st, body) = get(&app, "/boost/active", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["is_boosted"].as_bool(), Some(false));
    assert_eq!(body["remaining_secs"].as_i64(), Some(0));

    // Create a boost
    let (st, body) = post(&app, "/boost", serde_json::json!({}), Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["duration_secs"].as_i64(), Some(1800));
    assert_eq!(body["source"].as_str(), Some("manual"));
    assert!(body["id"].is_string());

    // Now boosted with remaining_secs close to 1800
    let (st, body) = get(&app, "/boost/active", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["is_boosted"].as_bool(), Some(true));
    let remaining = body["remaining_secs"].as_i64().unwrap();
    assert!(remaining > 1700 && remaining <= 1800, "remaining {remaining} not in range");
}

// ---------------------------------------------------------------------------
// Saved phrases
// ---------------------------------------------------------------------------

#[tokio::test]
async fn phrases_add_list_delete_reorder() {
    let app = test_app().await;
    let (token, user_id) = register_one(&app).await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    // Clean slate for this user
    sqlx::query!("DELETE FROM saved_phrases WHERE user_id = $1", user_id)
        .execute(&pool)
        .await
        .unwrap();

    // Empty list
    let (st, body) = get(&app, "/phrases", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["phrases"].as_array().unwrap().len(), 0);

    // Add three phrases
    let (st, body) = post(
        &app,
        "/phrases",
        serde_json::json!({ "phrase": "Hey!" }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let id1 = body["id"].as_str().unwrap().to_string();

    let (st, body) = post(
        &app,
        "/phrases",
        serde_json::json!({ "phrase": "What's up?" }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let id2 = body["id"].as_str().unwrap().to_string();

    let (st, body) = post(
        &app,
        "/phrases",
        serde_json::json!({ "phrase": "Coffee?" }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let id3 = body["id"].as_str().unwrap().to_string();

    // List returns them in insertion order (positions 0, 1, 2)
    let (st, body) = get(&app, "/phrases", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let phrases = body["phrases"].as_array().unwrap();
    assert_eq!(phrases.len(), 3);
    let phrases_str: Vec<String> = phrases
        .iter()
        .map(|p| p["phrase"].as_str().unwrap().to_string())
        .collect();
    assert_eq!(phrases_str, vec!["Hey!", "What's up?", "Coffee?"]);

    // Reorder: reverse the order
    let (st, _body) = put(
        &app,
        "/phrases/order",
        serde_json::json!({ "ids": [&id3, &id2, &id1] }),
        &token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    // List should reflect new order
    let (st, body) = get(&app, "/phrases", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let phrases = body["phrases"].as_array().unwrap();
    let phrases_str: Vec<String> = phrases
        .iter()
        .map(|p| p["phrase"].as_str().unwrap().to_string())
        .collect();
    assert_eq!(phrases_str, vec!["Coffee?", "What's up?", "Hey!"]);

    // Delete the middle one
    let (st, _body) = delete(&app, &format!("/phrases/{id2}"), &token).await;
    assert_eq!(st, StatusCode::NO_CONTENT);

    // List should have 2 phrases
    let (st, body) = get(&app, "/phrases", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["phrases"].as_array().unwrap().len(), 2);

    // Empty phrase -> 400
    let (st, _body) = post(
        &app,
        "/phrases",
        serde_json::json!({ "phrase": "  " }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);
}

// ---------------------------------------------------------------------------
// Saved places
// ---------------------------------------------------------------------------

#[tokio::test]
async fn places_add_list_delete() {
    let app = test_app().await;
    let (token, user_id) = register_one(&app).await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    // Clean slate for this user
    sqlx::query!("DELETE FROM saved_places WHERE user_id = $1", user_id)
        .execute(&pool)
        .await
        .unwrap();

    // Empty list
    let (st, body) = get(&app, "/places", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["places"].as_array().unwrap().len(), 0);

    // Add two places
    let (st, body) = post(
        &app,
        "/places",
        serde_json::json!({
            "name": "Plaza Mayor",
            "lat": 40.4155,
            "lon": -3.7074,
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let id1 = body["id"].as_str().unwrap().to_string();
    assert_eq!(body["name"].as_str(), Some("Plaza Mayor"));

    let (st, body) = post(
        &app,
        "/places",
        serde_json::json!({
            "name": "Chueca",
            "lat": 40.4220,
            "lon": -3.6970,
        }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let id2 = body["id"].as_str().unwrap().to_string();

    // List both
    let (st, body) = get(&app, "/places", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let places = body["places"].as_array().unwrap();
    assert_eq!(places.len(), 2);

    // Delete one
    let (st, _body) = delete(&app, &format!("/places/{id1}"), &token).await;
    assert_eq!(st, StatusCode::NO_CONTENT);

    // List now has 1
    let (st, body) = get(&app, "/places", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let places = body["places"].as_array().unwrap();
    assert_eq!(places.len(), 1);
    assert_eq!(places[0]["name"].as_str(), Some("Chueca"));

    // Empty name -> 400
    let (st, _body) = post(
        &app,
        "/places",
        serde_json::json!({ "name": "", "lat": 1.0, "lon": 2.0 }),
        Some(&token),
    )
    .await;
    assert_eq!(st, StatusCode::BAD_REQUEST);

    // Silence unused warning
    let _ = id2;
}

// ---------------------------------------------------------------------------
// Roam location preference
// ---------------------------------------------------------------------------

#[tokio::test]
async fn roam_pref_set_get_clear() {
    let app = test_app().await;
    let (token, user_id) = register_one(&app).await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    // Clean slate
    sqlx::query!("DELETE FROM user_location_pref WHERE user_id = $1", user_id)
        .execute(&pool)
        .await
        .unwrap();

    // Initially empty (returns null lat/lon/place_name)
    let (st, body) = get(&app, "/me/location", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["lat"].is_null());
    assert!(body["lon"].is_null());
    assert!(body["place_name"].is_null());
    assert_eq!(body["is_roam"].as_bool(), Some(false));

    // Set roam preference
    let (st, body) = put(
        &app,
        "/me/location",
        serde_json::json!({
            "lat": 40.4168,
            "lon": -3.7038,
            "place_name": "Madrid",
            "is_roam": true,
        }),
        &token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["ok"].as_bool(), Some(true));
    assert_eq!(body["place_name"].as_str(), Some("Madrid"));
    assert_eq!(body["is_roam"].as_bool(), Some(true));

    // Read back
    let (st, body) = get(&app, "/me/location", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    let lat = body["lat"].as_f64().unwrap();
    let lon = body["lon"].as_f64().unwrap();
    assert!((lat - 40.4168).abs() < 1e-6);
    assert!((lon - (-3.7038)).abs() < 1e-6);
    assert_eq!(body["place_name"].as_str(), Some("Madrid"));
    assert_eq!(body["is_roam"].as_bool(), Some(true));

    // Update (upsert) — set is_roam false, change name
    let (st, _body) = put(
        &app,
        "/me/location",
        serde_json::json!({
            "lat": 41.3851,
            "lon": 2.1734,
            "place_name": "Barcelona",
            "is_roam": false,
        }),
        &token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    let (st, body) = get(&app, "/me/location", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(body["place_name"].as_str(), Some("Barcelona"));
    assert_eq!(body["is_roam"].as_bool(), Some(false));

    // Empty place_name is treated as None
    let (st, _body) = put(
        &app,
        "/me/location",
        serde_json::json!({
            "lat": 0.0,
            "lon": 0.0,
            "place_name": "   ",
            "is_roam": false,
        }),
        &token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);

    let (st, body) = get(&app, "/me/location", Some(&token)).await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["place_name"].is_null(), "whitespace-only place_name should be cleared");
}

// ---------------------------------------------------------------------------
// Unauthenticated access
// ---------------------------------------------------------------------------

#[tokio::test]
async fn unauthenticated_requests_return_401() {
    let app = test_app().await;

    let cases: &[(&str, &str)] = &[
        ("GET", "/boost/active"),
        ("POST", "/boost"),
        ("GET", "/phrases"),
        ("POST", "/phrases"),
        ("GET", "/places"),
        ("POST", "/places"),
        ("GET", "/me/location"),
        ("PUT", "/me/location"),
    ];

    for (method, path) in cases {
        let (status, _) = match *method {
            "GET" => get(&app, path, None).await,
            "POST" => post(&app, path, serde_json::json!({}), None).await,
            "PUT" => put(&app, path, serde_json::json!({}), "").await,
            _ => unreachable!(),
        };
        assert_eq!(
            status,
            StatusCode::UNAUTHORIZED,
            "{method} {path} should be 401 without auth"
        );
    }
}