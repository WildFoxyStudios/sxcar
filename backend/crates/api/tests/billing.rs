//! Integration tests for the billing endpoints (Phase 1 / T1.3 + T1.4).
//!
//! T1.3 covers GET /billing/plans (no auth).
//! T1.4 covers POST /billing/simulate-purchase + GET /billing/me (auth required).

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
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
            secret: "test-billing-jwt-secret".into(),
            access_ttl_secs: 900,
        },
        refresh_ttl_secs: 3600,
        notifier: std::sync::Arc::new(auth::notify::DevNotifier),
        oauth: std::sync::Arc::new(auth::oauth::DevOAuthVerifier),
    };
    api::app(pool, deps)
}

async fn get_no_auth(app: &axum::Router, uri: &str) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .header("host", "localhost")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = if bytes.is_empty() {
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
                .header("host", "localhost")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, json)
}

async fn post_no_auth(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .header("host", "localhost")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, json)
}

async fn post_auth(
    app: &axum::Router,
    uri: &str,
    body: serde_json::Value,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .header("host", "localhost")
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, json)
}

// ─── T1.4 helpers ───

async fn register(app: &axum::Router) -> String {
    let email = format!("billing_{}@test.com", uuid::Uuid::new_v4().simple());
    let (st, body) = post_no_auth(
        app,
        "/auth/register",
        serde_json::json!({
            "email": email,
            "password": "secret123",
            "dob": "1990-01-01",
            "consents": ["tos", "privacy"]
        }),
    )
    .await;
    assert_eq!(st, axum::http::StatusCode::CREATED, "register failed: {body}");
    body["access"].as_str().unwrap().to_string()
}

async fn get_first_price_id_for(app: &axum::Router, plan_code: &str, period: &str) -> uuid::Uuid {
    let (_st, body) = get_no_auth(app, "/billing/plans").await;
    let plans = body["plans"].as_array().unwrap();
    let p = plans.iter().find(|x| x["code"] == plan_code).expect("plan in /billing/plans");
    let prices = p["prices"].as_array().expect("prices array");
    let hit = prices.iter().find(|x| x["period"] == period).expect("period");
    uuid::Uuid::parse_str(hit["id"].as_str().unwrap()).unwrap()
}

// ─── T1.3 tests ───

#[tokio::test]
async fn plans_list_returns_seeded_paid_tiers() {
    let app = test_app().await;
    let (status, body) = get_no_auth(&app, "/billing/plans").await;
    assert_eq!(status, StatusCode::OK, "expected 200, got {status}: {body}");
    let plans = body["plans"].as_array().expect("plans array");
    assert!(!plans.is_empty(), "expected at least one plan");

    // Both seeded paid tiers must be present (T1.2 migration seeds them).
    let codes: Vec<&str> = plans.iter()
        .filter_map(|p| p["code"].as_str())
        .collect();
    assert!(codes.contains(&"vibra_plus"), "vibra_plus missing: {codes:?}");
    assert!(codes.contains(&"unlimited"), "unlimited missing: {codes:?}");
}

#[tokio::test]
async fn plans_list_includes_features_and_prices() {
    let app = test_app().await;
    let (_status, body) = get_no_auth(&app, "/billing/plans").await;
    let plans = body["plans"].as_array().unwrap();
    let vibra = plans.iter().find(|p| p["code"] == "vibra_plus")
        .expect("vibra_plus in response");
    let features = vibra["features"].as_array().unwrap();
    assert!(features.iter().any(|f| f == "unlimited_chats"));
    assert!(features.iter().any(|f| f == "no_ads"));
    let prices = vibra["prices"].as_array().unwrap();
    assert!(!prices.is_empty(), "expected at least one price for vibra_plus");
    let monthly = prices.iter().find(|p| p["period"] == "monthly")
        .expect("monthly price");
    assert_eq!(monthly["currency"], "EUR");
    assert_eq!(monthly["country_code"], "XX");
    assert_eq!(monthly["amount_minor"], 899); // 8.99 * 100
    let yearly = prices.iter().find(|p| p["period"] == "yearly").unwrap();
    assert_eq!(yearly["amount_minor"], 4999); // 49.99 * 100
}

#[tokio::test]
async fn plans_list_sorted_by_tier_then_code() {
    let app = test_app().await;
    let (_status, body) = get_no_auth(&app, "/billing/plans").await;
    let plans = body["plans"].as_array().unwrap();
    let mut sorted = plans.clone();
    sorted.sort_by(|a, b| {
        a["tier"].as_i64().unwrap().cmp(&b["tier"].as_i64().unwrap())
            .then(a["code"].as_str().unwrap().cmp(b["code"].as_str().unwrap()))
    });
    assert_eq!(plans, &sorted, "plans not sorted by tier+code");
}

// ─── T1.4 tests ───

#[tokio::test]
async fn simulate_purchase_creates_active_subscription() {
    let app = test_app().await;
    let token = register(&app).await;
    let price_id = get_first_price_id_for(&app, "vibra_plus", "monthly").await;

    let (st, body) = post_auth(
        &app,
        "/billing/simulate-purchase",
        serde_json::json!({"price_id": price_id}),
        &token,
    ).await;
    assert_eq!(st, StatusCode::CREATED, "expected 201, got {st}: {body}");
    assert_eq!(body["plan_code"], "vibra_plus");
    assert_eq!(body["period"], "monthly");
    assert_eq!(body["period_days"], 30);
    assert_eq!(body["status"], "active");
    assert_eq!(body["source"], "simulated");
    assert!(body["started_at"].is_string());
    assert!(body["expires_at"].is_string());
    assert!(body["id"].is_string());
}

#[tokio::test]
async fn simulate_purchase_twice_same_plan_returns_409() {
    let app = test_app().await;
    let token = register(&app).await;
    let price_id = get_first_price_id_for(&app, "vibra_plus", "monthly").await;

    // First purchase: 201
    let (st, _body) = post_auth(
        &app,
        "/billing/simulate-purchase",
        serde_json::json!({"price_id": price_id}),
        &token,
    ).await;
    assert_eq!(st, StatusCode::CREATED);

    // Second purchase for same plan_code: 409 AlreadyActive
    let (st, body) = post_auth(
        &app,
        "/billing/simulate-purchase",
        serde_json::json!({"price_id": price_id}),
        &token,
    ).await;
    assert_eq!(st, StatusCode::CONFLICT, "expected 409, got {st}: {body}");
    assert_eq!(body["error"], "already_active");
}

#[tokio::test]
async fn simulate_purchase_unknown_price_id_returns_404() {
    let app = test_app().await;
    let token = register(&app).await;
    let bogus = uuid::Uuid::new_v4();
    let (st, body) = post_auth(
        &app,
        "/billing/simulate-purchase",
        serde_json::json!({"price_id": bogus}),
        &token,
    ).await;
    assert_eq!(st, StatusCode::NOT_FOUND, "expected 404, got {st}: {body}");
    assert_eq!(body["error"], "plan_not_found");
}

#[tokio::test]
async fn simulate_purchase_requires_auth() {
    let app = test_app().await;
    let bogus = uuid::Uuid::new_v4();
    let (st, _body) = post_no_auth(
        &app,
        "/billing/simulate-purchase",
        serde_json::json!({"price_id": bogus}),
    ).await;
    assert_eq!(st, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn me_returns_active_subscription_after_purchase() {
    let app = test_app().await;
    let token = register(&app).await;
    // Initially empty
    let (st, body) = get_auth(&app, "/billing/me", &token).await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["subscription"].is_null(), "expected null subscription, got {body}");
    // Purchase
    let price_id = get_first_price_id_for(&app, "vibra_plus", "monthly").await;
    let (st, _body) = post_auth(
        &app,
        "/billing/simulate-purchase",
        serde_json::json!({"price_id": price_id}),
        &token,
    ).await;
    assert_eq!(st, StatusCode::CREATED);
    // Now non-null
    let (st, body) = get_auth(&app, "/billing/me", &token).await;
    assert_eq!(st, StatusCode::OK);
    let sub = body["subscription"].as_object().expect("subscription object");
    assert_eq!(sub["plan_code"], "vibra_plus");
    assert_eq!(sub["status"], "active");
    assert!(sub["days_remaining"].as_i64().unwrap() > 0);
}