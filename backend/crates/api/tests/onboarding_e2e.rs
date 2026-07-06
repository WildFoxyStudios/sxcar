//! End-to-end tests for the onboarding wizard state machine.

use axum::http::StatusCode;
use http_body_util::BodyExt;
use serde_json::json;
use tower::ServiceExt;

mod common;

#[tokio::test]
async fn get_onboarding_state_for_fresh_user() {
    let (app, token) = common::setup().await;

    let req = axum::http::Request::builder()
        .method("GET")
        .uri("/me/onboarding")
        .header("authorization", format!("Bearer {token}"))
        .body(axum::body::Body::empty())
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let bytes = BodyExt::collect(res.into_body()).await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    assert_eq!(body["onboarding_completed"], json!(false));
    let cards = body["cards"].as_array().expect("cards array");
    // 4 required + 10 optional = 14
    assert_eq!(cards.len(), 14);
    let required = cards.iter().filter(|c| c["kind"] == "required").count();
    let optional = cards.iter().filter(|c| c["kind"] == "optional").count();
    assert_eq!(required, 4);
    assert_eq!(optional, 10);
}
