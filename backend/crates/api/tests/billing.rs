//! Integration tests for the GET /billing/plans endpoint (Phase 1 / T1.3).

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