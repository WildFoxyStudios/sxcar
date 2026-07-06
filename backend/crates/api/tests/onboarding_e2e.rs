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

#[tokio::test]
async fn complete_required_card_updates_state() {
    let app = common::spawn_app().await;
    let token = common::register_user(&app, "carol@onb.test", "Pass123!aaa").await;

    // Complete display_name card (serde tag requires "card_id" in body).
    let body = json!({ "card_id": "display_name", "display_name": "Carol Updated" });
    let req = axum::http::Request::builder()
        .method("POST")
        .uri("/me/onboarding/cards/display_name/complete")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {token}"))
        .header(axum::http::header::CONTENT_TYPE, "application/json")
        .body(axum::body::Body::from(serde_json::to_vec(&body).unwrap()))
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), axum::http::StatusCode::OK);

    // Verify GET /me/onboarding reflects it.
    let res = app.get("/me/onboarding", &token).await;
    let bytes = BodyExt::collect(res.into_body()).await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let card = body["cards"].as_array().unwrap()
        .iter().find(|c| c["id"] == "display_name").unwrap();
    assert_eq!(card["completed"], json!(true));
}

#[tokio::test]
async fn skip_records_in_skipped_cards() {
    let app = common::spawn_app().await;
    let token = common::register_user(&app, "dave@onb.test", "Pass123!aaa").await;

    let body = json!({ "card_ids": ["tribes", "vaccines"] });
    let req = axum::http::Request::builder()
        .method("POST")
        .uri("/me/onboarding/skip")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {token}"))
        .header(axum::http::header::CONTENT_TYPE, "application/json")
        .body(axum::body::Body::from(serde_json::to_vec(&body).unwrap()))
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), axum::http::StatusCode::OK);

    // Verify GET /me/onboarding no longer shows those cards.
    let res = app.get("/me/onboarding", &token).await;
    let bytes = BodyExt::collect(res.into_body()).await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let cards = body["cards"].as_array().unwrap();
    assert!(!cards.iter().any(|c| c["id"] == "tribes"), "tribes should be hidden after skip");
    assert!(!cards.iter().any(|c| c["id"] == "vaccines"), "vaccines should be hidden after skip");
}

#[tokio::test]
async fn force_complete_marks_user_visible() {
    let app = common::spawn_app().await;
    let alice = common::register_user(&app, "alice-fc@onb.test", "Pass123!aaa").await;
    let bob = common::register_user(&app, "bob-fc@onb.test", "Pass123!aaa").await;

    let alice_id = common::user_id_from_token(&alice, &app.pool).await;
    let bob_id = common::user_id_from_token(&bob, &app.pool).await;

    // Both need profiles (grid JOINs profiles).
    for uid in [alice_id, bob_id] {
        sqlx::query(
            "INSERT INTO profiles (user_id, display_name) VALUES ($1, 'Test')
             ON CONFLICT (user_id) DO UPDATE SET display_name = 'Test'",
        )
        .bind(uid)
        .execute(&app.pool)
        .await
        .unwrap();
    }

    // Both at the same location (grid uses locations table with PostGIS).
    for uid in [alice_id, bob_id] {
        sqlx::query(
            "INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint(-3.7038, 40.4168), 4326)::geography)
             ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog",
        )
        .bind(uid)
        .execute(&app.pool)
        .await
        .unwrap();
    }

    // Bob force-completes.
    let req = axum::http::Request::builder()
        .method("POST")
        .uri("/me/onboarding/complete")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {bob}"))
        .body(axum::body::Body::empty())
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), axum::http::StatusCode::OK);

    // Bob queries grid — Alice (still onboarding) should NOT be visible.
    let req = axum::http::Request::builder()
        .method("GET")
        .uri("/grid/nearby?lat=40.4168&lon=-3.7038&radius_m=5000")
        .header(axum::http::header::AUTHORIZATION, format!("Bearer {bob}"))
        .body(axum::body::Body::empty())
        .unwrap();
    let res = app.router.clone().oneshot(req).await.unwrap();
    let bytes = BodyExt::collect(res.into_body()).await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let users = body["users"].as_array().unwrap();
    let alice_visible = users.iter().any(|u| u["id"].as_str() == Some(&alice_id.to_string()));
    assert!(!alice_visible, "alice (still onboarding) should NOT be visible");
}

#[tokio::test]
async fn completing_all_required_triggers_onboarding_completed_at() {
    let app = common::spawn_app().await;
    let token = common::register_user(&app, "eve@onb.test", "Pass123!aaa").await;
    let user_id = common::user_id_from_token(&token, &app.pool).await;

    // Insert a photo to satisfy profile_photo.
    sqlx::query("INSERT INTO photos (user_id, r2_key, blur_key, is_nsfw) VALUES ($1, $2, $3, $4)")
        .bind(user_id)
        .bind("profile/test/test.jpg")
        .bind("profile/test/test.blur.jpg")
        .bind(false)
        .execute(&app.pool).await.unwrap();

    // Complete display_name, age (dob already set by register), gender_position.
    for (path, body) in [
        ("/me/onboarding/cards/display_name/complete", json!({"card_id": "display_name", "display_name": "Eve"})),
        ("/me/onboarding/cards/age/complete",          json!({"card_id": "age", "dob": "1995-06-15"})),
        ("/me/onboarding/cards/gender_position/complete", json!({"card_id": "gender_position", "gender": "male", "position": "top"})),
    ] {
        let req = axum::http::Request::builder()
            .method("POST")
            .uri(path)
            .header(axum::http::header::AUTHORIZATION, format!("Bearer {token}"))
            .header(axum::http::header::CONTENT_TYPE, "application/json")
            .body(axum::body::Body::from(serde_json::to_vec(&body).unwrap()))
            .unwrap();
        let res = app.router.clone().oneshot(req).await.unwrap();
        assert_eq!(res.status(), axum::http::StatusCode::OK, "card {path} failed");
    }

    // Now GET /me/onboarding should report onboarding_completed=true.
    let res = app.get("/me/onboarding", &token).await;
    let bytes = BodyExt::collect(res.into_body()).await.unwrap().to_bytes();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["onboarding_completed"], json!(true));
    assert!(!body["onboarding_completed_at"].is_null(), "onboarding_completed_at should not be null");
}
