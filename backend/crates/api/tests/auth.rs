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
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .header("content-type", "application/json")
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

fn unique_email() -> String {
    format!("u{}@test.com", uuid::Uuid::new_v4().simple())
}

#[tokio::test]
async fn register_login_flow() {
    let app = test_app().await;
    let email = unique_email();
    let (st, body) = post(&app, "/auth/register", serde_json::json!({
        "email": email, "password": "supersecret", "dob": "1990-01-01", "consents": ["tos","privacy"]
    })).await;
    assert_eq!(st, StatusCode::CREATED, "register should 201");
    assert!(body["access"].is_string() && body["refresh"].is_string());

    let (st, body) = post(
        &app,
        "/auth/login",
        serde_json::json!({"email": email, "password": "supersecret"}),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["access"].is_string());

    // password incorrecta → 401 genérico
    let (st, _) = post(
        &app,
        "/auth/login",
        serde_json::json!({"email": email, "password": "nope"}),
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn register_under_18_rejected() {
    let app = test_app().await;
    let (st, _) = post(
        &app,
        "/auth/register",
        serde_json::json!({
            "email": unique_email(), "password": "supersecret", "dob": "2020-01-01"
        }),
    )
    .await;
    assert_eq!(st, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn refresh_rotates_and_old_is_invalid() {
    let app = test_app().await;
    let (_, body) = post(
        &app,
        "/auth/register",
        serde_json::json!({
            "email": unique_email(), "password": "supersecret", "dob": "1990-01-01"
        }),
    )
    .await;
    let refresh = body["refresh"].as_str().unwrap().to_string();
    // refresh OK
    let (st, body2) = post(
        &app,
        "/auth/refresh",
        serde_json::json!({"refresh": refresh}),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(body2["refresh"].is_string());
    // el viejo ya no vale
    let (st, _) = post(
        &app,
        "/auth/refresh",
        serde_json::json!({"refresh": refresh}),
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn reset_request_always_200() {
    let app = test_app().await;
    let st = post(
        &app,
        "/auth/password/reset-request",
        serde_json::json!({"email": "nobody@nowhere.com"}),
    )
    .await
    .0;
    assert_eq!(st, StatusCode::OK);
}

#[tokio::test]
async fn oauth_find_or_create() {
    let app = test_app().await;
    let uid = format!("uid-{}", uuid::Uuid::new_v4().simple());
    let token = format!("dev:{uid}:{uid}@oauth.com");
    let (st, b1) = post(
        &app,
        "/auth/oauth/google",
        serde_json::json!({"id_token": token}),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(b1["access"].is_string());
    // segunda vez reusa el mismo usuario (no falla por email duplicado)
    let (st, _) = post(
        &app,
        "/auth/oauth/google",
        serde_json::json!({"id_token": token}),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    // token inválido → 401
    let (st, _) = post(
        &app,
        "/auth/oauth/google",
        serde_json::json!({"id_token": "garbage"}),
    )
    .await;
    assert_eq!(st, StatusCode::UNAUTHORIZED);
}
