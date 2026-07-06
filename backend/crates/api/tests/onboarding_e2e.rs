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

#[tokio::test]
async fn grid_nearby_excludes_unfinished_onboarding_users() {
    let app = common::spawn_app().await;
    let alice = common::register_user(&app, "alice@grid.test", "Pass123!aaa").await;
    let bob = common::register_user(&app, "bob@grid.test", "Pass123!aaa").await;

    // Alice completes onboarding via direct SQL (the /complete endpoint doesn't exist yet).
    let alice_id = common::user_id_from_token(&alice, &app.pool).await;
    sqlx::query("UPDATE users SET onboarding_completed_at = NOW() WHERE id = $1")
        .bind(alice_id)
        .execute(&app.pool)
        .await
        .unwrap();

    // Bob does NOT complete onboarding.
    let bob_id = common::user_id_from_token(&bob, &app.pool).await;

    // Ensure both users have profiles (registration does not create one automatically).
    sqlx::query("INSERT INTO profiles (user_id, display_name) VALUES ($1, 'Alice') ON CONFLICT (user_id) DO UPDATE SET display_name = 'Alice'")
        .bind(alice_id)
        .execute(&app.pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO profiles (user_id, display_name) VALUES ($1, 'Bob') ON CONFLICT (user_id) DO UPDATE SET display_name = 'Bob'")
        .bind(bob_id)
        .execute(&app.pool)
        .await
        .unwrap();

    // Insert locations so the grid query is meaningful.
    sqlx::query(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
    )
    .bind(alice_id)
    .bind(-3.7039) // lon
    .bind(40.4169) // lat
    .execute(&app.pool)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
         ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
    )
    .bind(bob_id)
    .bind(-3.7038) // lon
    .bind(40.4168) // lat
    .execute(&app.pool)
    .await
    .unwrap();

    // Alice queries /grid/nearby — she should NOT see bob (unfinished onboarding).
    let res = app
        .get("/grid/nearby?lat=40.4168&lon=-3.7038&radius_m=5000", &alice)
        .await;
    assert_eq!(res.status(), StatusCode::OK);
    let bytes = BodyExt::collect(res.into_body()).await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let users = body["users"].as_array().unwrap();
    let bob_visible = users
        .iter()
        .any(|u| u["id"].as_str() == Some(&bob_id.to_string()));
    assert!(
        !bob_visible,
        "bob (unfinished onboarding) should NOT be in alice's grid"
    );
}
