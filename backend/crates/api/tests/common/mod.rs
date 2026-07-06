//! Shared test fixtures for the api crate's e2e tests.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::Router;
use http_body_util::BodyExt;
use sqlx::PgPool;
use tower::ServiceExt;

/// Start a test app, register a user, and return `(router, access_token)`.
///
/// Requires `TEST_DATABASE_URL` to point at a throwaway Postgres.
pub async fn setup() -> (Router, String) {
    let url = std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:audit@localhost:55433/postgres".to_string());
    let pool = db::connect(&url).await.unwrap();
    db::migrate(&pool).await.unwrap();

    let (router, _state) = build_test_app(pool).await;

    let email = format!(
        "alice-{:x}@onb.test",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let body = serde_json::json!({
        "email": email,
        "password": "Pass123!aaa",
        "display_name": "Test User",
        "dob": "1995-06-15"
    });
    let req = axum::http::Request::builder()
        .method("POST")
        .uri("/auth/register")
        .header("content-type", "application/json")
        .body(axum::body::Body::from(body.to_string()))
        .unwrap();
    let res = router.clone().oneshot(req).await.unwrap();
    assert_eq!(
        res.status(),
        axum::http::StatusCode::CREATED,
        "register failed"
    );
    let bytes = BodyExt::collect(res.into_body()).await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let token = body["access"].as_str().unwrap().to_string();
    (router, token)
}

/// Build a minimal test router with only the routes the e2e tests need.
async fn build_test_app(pool: PgPool) -> (Router, api::AppState) {
    let state = api::AppState {
        pool,
        tarpit: api::tarpit::Tarpit::new(api::tarpit::TarpitConfig::default()),
        jwt: auth::jwt::JwtConfig {
            secret: "test-secret-do-not-use-in-prod".into(),
            access_ttl_secs: 900,
        },
        admin_jwt_secret: "test-admin-secret".into(),
        refresh_ttl_secs: 86_400,
        notifier: Arc::new(auth::notify::DevNotifier),
        oauth: Arc::new(auth::oauth::DevOAuthVerifier),
        limiter: Arc::new(api::ratelimit::Limiter::from_env_or(10.0, 1.0)),
        r2: None,
        chat_broker: api::chat_broker::ChatBroker::from_env_or(256),
        fcm: None,
        revenuecat_webhook_secret: None,
    };

    let router = Router::new()
        .merge(api::onboarding::router())
        .merge(api::auth::router())
        .with_state(state.clone());

    (router, state)
}
