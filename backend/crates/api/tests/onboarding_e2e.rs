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

#[tokio::test]
async fn get_onboarding_reflects_completed_cards() {
    let app = common::spawn_app().await;
    let token = common::register_user(&app, "bob@onb.test", "Pass123!aaa").await;

    let user_id: uuid::Uuid = common::user_id_from_token(&token, &app.pool).await;

    // Complete profile_photo card by inserting a photo row directly.
    sqlx::query("INSERT INTO photos (user_id, r2_key, blur_key, is_nsfw) VALUES ($1, $2, $3, $4)")
        .bind(user_id)
        .bind("profile/test/test.jpg")
        .bind("profile/test/test.blur.jpg")
        .bind(false)
        .execute(&app.pool)
        .await
        .expect("insert photo");

    // Ensure display_name is set on the profile (register doesn't set it).
    sqlx::query(
        "INSERT INTO profiles (user_id, display_name) VALUES ($1, $2)
         ON CONFLICT (user_id) DO UPDATE SET display_name = $2",
    )
    .bind(user_id)
    .bind("Test User")
    .execute(&app.pool)
    .await
    .expect("upsert profile display_name");

    let res = app.get("/me/onboarding", &token).await;
    assert_eq!(res.status(), StatusCode::OK);
    let bytes = BodyExt::collect(res.into_body()).await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let cards = body["cards"].as_array().unwrap();

    let profile_photo = cards.iter().find(|c| c["id"] == "profile_photo").unwrap();
    assert_eq!(profile_photo["completed"], json!(true));

    let display_name = cards.iter().find(|c| c["id"] == "display_name").unwrap();
    assert_eq!(display_name["completed"], json!(true));

    let age = cards.iter().find(|c| c["id"] == "age").unwrap();
    assert_eq!(age["completed"], json!(true)); // set by register (dob)

    let gender_pos = cards
        .iter()
        .find(|c| c["id"] == "gender_position")
        .unwrap();
    assert_eq!(gender_pos["completed"], json!(false)); // not set
}
