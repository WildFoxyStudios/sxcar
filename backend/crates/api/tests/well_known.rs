use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use std::sync::Arc;
use tower::ServiceExt;

fn test_db_url() -> String {
    std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://dev:dev@localhost:5433/appdb".to_string())
}

async fn test_deps() -> api::AppDeps {
    api::AppDeps {
        jwt: auth::jwt::JwtConfig {
            secret: "test".into(),
            access_ttl_secs: 900,
        },
        refresh_ttl_secs: 3600,
        notifier: Arc::new(auth::notify::DevNotifier),
        oauth: Arc::new(auth::oauth::DevOAuthVerifier),
    }
}

#[tokio::test]
async fn apple_app_site_association_returns_200_and_correct_json() {
    let pool = db::connect(&test_db_url()).await.expect("connect");
    let deps = test_deps().await;
    let app = api::app(pool, deps);

    let response = app
        .oneshot(
            Request::builder()
                .uri("/.well-known/apple-app-site-association")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    assert!(
        content_type.contains("json"),
        "expected JSON content type, got: {}",
        content_type
    );

    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    assert_eq!(json["applinks"]["apps"], serde_json::json!([]));
    assert_eq!(
        json["applinks"]["details"][0]["appID"],
        "CHANGE_ME_APPLE_TEAM_ID.com.proyectox.app"
    );
    assert_eq!(
        json["applinks"]["details"][0]["paths"],
        serde_json::json!(["/profile/*", "/chat/*", "/"])
    );
}

#[tokio::test]
async fn assetlinks_returns_200_and_correct_json() {
    let pool = db::connect(&test_db_url()).await.expect("connect");
    let deps = test_deps().await;
    let app = api::app(pool, deps);

    let response = app
        .oneshot(
            Request::builder()
                .uri("/.well-known/assetlinks.json")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    assert!(
        content_type.contains("json"),
        "expected JSON content type, got: {}",
        content_type
    );

    let bytes = response.into_body().collect().await.unwrap().to_bytes();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let entry = &json[0];

    assert_eq!(
        entry["relation"],
        serde_json::json!(["delegate_permission/common.handle_all_urls"])
    );
    assert_eq!(entry["target"]["namespace"], "android_app");
    assert_eq!(entry["target"]["package_name"], "com.proyectox.app");
    assert_eq!(
        entry["target"]["sha256_cert_fingerprints"],
        serde_json::json!(["CHANGE_ME_ANDROID_SHA256"])
    );
}
