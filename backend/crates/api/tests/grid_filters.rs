//! Integration tests for grid nearby filters (age, tribe, looking_for, body_type, search).
//!
//! Each test seeds 2 target users with specific profile attributes, plus a
//! neutral "seeker" user whose token is used for the API call (the nearby
//! endpoint always excludes the requesting user).
//!
//! Filters: min_age, max_age, tribe, looking_for, body_type, q.

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

async fn get(app: &axum::Router, uri: &str, token: &str) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
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
    format!("gridf_{}@test.com", uuid::Uuid::new_v4().simple())
}

/// Decodifica el payload de un JWT (segundo segmento base64url) y devuelve
/// el valor del campo `sub` (user_id).
fn user_id_from_token(token: &str) -> uuid::Uuid {
    use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
    let parts: Vec<&str> = token.split('.').collect();
    assert_eq!(parts.len(), 3, "JWT should have 3 parts");
    let payload = URL_SAFE_NO_PAD
        .decode(parts[1])
        .expect("JWT payload should be valid base64url");
    let json: serde_json::Value =
        serde_json::from_slice(&payload).expect("JWT payload should be valid JSON");
    let sub = json["sub"].as_str().expect("JWT should have 'sub' claim");
    uuid::Uuid::parse_str(sub).expect("sub should be a valid UUID")
}

/// Register a user and insert a profile row + location.
/// Returns (token, user_id).
async fn seed_user(
    app: &axum::Router,
    pool: &db::Pool,
    email: &str,
    display_name: &str,
    bio: &str,
    dob: &str,
    birthdate: Option<&str>,
    body_type: Option<&str>,
) -> (String, uuid::Uuid) {
    let (st, body) = post(
        app,
        "/auth/register",
        serde_json::json!({
            "email": email,
            "password": "secret123",
            "dob": dob,
            "consents": ["tos", "privacy"]
        }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "register {} should 201", email);
    let token = body["access"].as_str().unwrap().to_string();
    let user_id = user_id_from_token(&token);

    let bd: Option<time::Date> = match birthdate {
        Some(s) => {
            let fmt = time::macros::format_description!("[year]-[month]-[day]");
            Some(time::Date::parse(s, &fmt).expect("invalid birthdate"))
        }
        None => None,
    };

    let bt = body_type.unwrap_or("average");
    sqlx::query!(
        r#"INSERT INTO profiles (user_id, display_name, about, body_type, birthdate)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (user_id) DO UPDATE SET
             display_name = $2, about = $3, body_type = $4, birthdate = $5"#,
        user_id,
        display_name,
        bio,
        bt,
        bd,
    )
    .execute(pool)
    .await
    .unwrap();

    // Insert location near Mexico City
    sqlx::query!(
        r#"INSERT INTO locations (user_id, geog)
           VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
           ON CONFLICT (user_id) DO UPDATE SET geog = EXCLUDED.geog"#,
        user_id,
        -99.1332_f64,
        19.4326_f64,
    )
    .execute(pool)
    .await
    .unwrap();

    (token, user_id)
}

/// Register a "seeker" – a neutral user whose token we use for API calls
/// so that the target users are NOT excluded as the requesting user.
async fn seed_seeker(app: &axum::Router, pool: &db::Pool) -> String {
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
    )
    .await;
    assert_eq!(st, StatusCode::CREATED);
    let token = body["access"].as_str().unwrap().to_string();
    let user_id = user_id_from_token(&token);

    // Insert minimal profile + location so the seeker is visible
    sqlx::query!(
        r#"INSERT INTO profiles (user_id, display_name, about)
           VALUES ($1, 'Seeker', 'Looking around')
           ON CONFLICT (user_id) DO NOTHING"#,
        user_id,
    )
    .execute(pool)
    .await
    .unwrap();

    sqlx::query!(
        r#"INSERT INTO locations (user_id, geog)
           VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
           ON CONFLICT (user_id) DO NOTHING"#,
        user_id,
        -99.1332_f64,
        19.4326_f64,
    )
    .execute(pool)
    .await
    .unwrap();

    token
}

/// Helper: add a tribe entry for a user.
async fn add_tribe(pool: &db::Pool, user_id: uuid::Uuid, tribe: &str) {
    sqlx::query!(
        "INSERT INTO profile_tribes (user_id, tribe) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        user_id,
        tribe,
    )
    .execute(pool)
    .await
    .unwrap();
}

/// Helper: add a looking_for entry for a user.
async fn add_looking_for(pool: &db::Pool, user_id: uuid::Uuid, intent: &str) {
    sqlx::query!(
        "INSERT INTO profile_looking_for (user_id, intent) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        user_id,
        intent,
    )
    .execute(pool)
    .await
    .unwrap();
}

/// Helper: verify that a user_id appears in the grid response.
fn user_in_results(body: &serde_json::Value, user_id: uuid::Uuid) -> bool {
    body["users"]
        .as_array()
        .map(|users| {
            users
                .iter()
                .any(|u| u["id"] == serde_json::json!(user_id.to_string()))
        })
        .unwrap_or(false)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn filter_by_age_range() {
    let app = test_app().await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    // Neutral seeker
    let seeker_token = seed_seeker(&app, &pool).await;

    // User A: 30 years old (birthdate ~1996-06-30)
    let (_token_a, uid_a) = seed_user(
        &app, &pool,
        &unique_email(), "YoungAlice", "Young",
        "1996-06-30", Some("1996-06-30"), None,
    ).await;

    // User B: 50 years old (birthdate ~1976-06-30)
    let (_token_b, uid_b) = seed_user(
        &app, &pool,
        &unique_email(), "OldBob", "Old",
        "1976-06-30", Some("1976-06-30"), None,
    ).await;

    // Filter for age >= 40 -> only Bob
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&min_age=40",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(!user_in_results(&body, uid_a), "Alice should NOT be in min_age=40 results");
    assert!(user_in_results(&body, uid_b), "Bob should be in min_age=40 results");

    // Filter for age <= 35 -> only Alice
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&max_age=35",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "Alice should be in max_age=35 results");
    assert!(!user_in_results(&body, uid_b), "Bob should NOT be in max_age=35 results");

    // Filter for age between 25 and 35 -> only Alice
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&min_age=25&max_age=35",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "Alice should be in age range 25-35");
    assert!(!user_in_results(&body, uid_b), "Bob should NOT be in age range 25-35");
}

#[tokio::test]
async fn filter_null_birthdate_not_excluded_by_age() {
    let app = test_app().await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    let seeker_token = seed_seeker(&app, &pool).await;

    // User A: with birthdate
    let (_token_a, uid_a) = seed_user(
        &app, &pool,
        &unique_email(), "Alice", "Has birthdate",
        "1996-06-30", Some("1996-06-30"), None,
    ).await;

    // User B: NULL birthdate (should not be excluded by age filters)
    let (_token_b, uid_b) = seed_user(
        &app, &pool,
        &unique_email(), "Bob", "No birthdate",
        "1996-06-30", None, None,
    ).await;

    // min_age=40: Alice excluded (too young), Bob should appear (NULL birthdate not excluded)
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&min_age=40",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(!user_in_results(&body, uid_a), "Alice should NOT be in results");
    assert!(user_in_results(&body, uid_b), "Bob (NULL birthdate) should be in results");
}

#[tokio::test]
async fn filter_by_tribe() {
    let app = test_app().await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    let seeker_token = seed_seeker(&app, &pool).await;

    let (_token_a, uid_a) = seed_user(
        &app, &pool,
        &unique_email(), "BearUser", "I am a bear",
        "1990-01-01", Some("1990-01-01"), None,
    ).await;
    let (_token_b, uid_b) = seed_user(
        &app, &pool,
        &unique_email(), "TwinkUser", "I am a twink",
        "1990-01-01", Some("1990-01-01"), None,
    ).await;

    add_tribe(&pool, uid_a, "bear").await;
    add_tribe(&pool, uid_b, "twink").await;

    // Filter by tribe=bear -> only BearUser
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&tribe=bear",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "BearUser should be in tribe=bear results");
    assert!(!user_in_results(&body, uid_b), "TwinkUser should NOT be in tribe=bear results");

    // Filter by tribe=twink -> only TwinkUser
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&tribe=twink",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(!user_in_results(&body, uid_a), "BearUser should NOT be in tribe=twink results");
    assert!(user_in_results(&body, uid_b), "TwinkUser should be in tribe=twink results");

    // Filter by tribe=bear,twink -> both appear (OR logic)
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&tribe=bear,twink",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "BearUser should be in tribe=bear,twink results");
    assert!(user_in_results(&body, uid_b), "TwinkUser should be in tribe=bear,twink results");
}

#[tokio::test]
async fn filter_by_looking_for() {
    let app = test_app().await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    let seeker_token = seed_seeker(&app, &pool).await;

    let (_token_a, uid_a) = seed_user(
        &app, &pool,
        &unique_email(), "ChatUser", "Looking for chat",
        "1990-01-01", Some("1990-01-01"), None,
    ).await;
    let (_token_b, uid_b) = seed_user(
        &app, &pool,
        &unique_email(), "DatesUser", "Looking for dates",
        "1990-01-01", Some("1990-01-01"), None,
    ).await;

    add_looking_for(&pool, uid_a, "chat").await;
    add_looking_for(&pool, uid_b, "dates").await;

    // Filter by looking_for=chat -> only ChatUser
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&looking_for=chat",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "ChatUser should be in looking_for=chat results");
    assert!(!user_in_results(&body, uid_b), "DatesUser should NOT be in looking_for=chat results");

    // Filter by looking_for=chat,dates -> both appear (OR logic)
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&looking_for=chat,dates",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "ChatUser should be in OR results");
    assert!(user_in_results(&body, uid_b), "DatesUser should be in OR results");
}

#[tokio::test]
async fn filter_by_body_type() {
    let app = test_app().await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    let seeker_token = seed_seeker(&app, &pool).await;

    let (_token_a, uid_a) = seed_user(
        &app, &pool,
        &unique_email(), "AthleticUser", "Fit",
        "1990-01-01", Some("1990-01-01"), Some("athletic"),
    ).await;
    let (_token_b, uid_b) = seed_user(
        &app, &pool,
        &unique_email(), "AverageUser", "Regular",
        "1990-01-01", Some("1990-01-01"), Some("average"),
    ).await;

    // Filter by body_type=athletic -> only AthleticUser
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&body_type=athletic",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "AthleticUser should be in body_type=athletic results");
    assert!(!user_in_results(&body, uid_b), "AverageUser should NOT be in body_type=athletic results");

    // Filter by body_type=average -> only AverageUser
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&body_type=average",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(!user_in_results(&body, uid_a), "AthleticUser should NOT be in body_type=average results");
    assert!(user_in_results(&body, uid_b), "AverageUser should be in body_type=average results");
}

#[tokio::test]
async fn filter_by_search_text() {
    let app = test_app().await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    let seeker_token = seed_seeker(&app, &pool).await;

    let (_token_a, uid_a) = seed_user(
        &app, &pool,
        &unique_email(), "AliceWonder", "Software developer from NYC",
        "1990-01-01", Some("1990-01-01"), None,
    ).await;
    let (_token_b, uid_b) = seed_user(
        &app, &pool,
        &unique_email(), "BobMarley", "Musician and reggae lover",
        "1990-01-01", Some("1990-01-01"), None,
    ).await;

    // Search by display_name: "alice" -> AliceWonder (case-insensitive)
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&q=alice",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "AliceWonder should be in q=alice results");
    assert!(!user_in_results(&body, uid_b), "BobMarley should NOT be in q=alice results");

    // Search by bio: "developer" -> AliceWonder
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&q=developer",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "AliceWonder should be in q=developer results");

    // Search by bio: "reggae" -> BobMarley
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&q=reggae",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_b), "BobMarley should be in q=reggae results");

    // Search that matches no one -> empty
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&q=zzzzzznonexistent",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(body["users"].as_array().unwrap().is_empty(),
        "q=zzzzzznonexistent should return empty");
}

#[tokio::test]
async fn filter_combined() {
    let app = test_app().await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    let seeker_token = seed_seeker(&app, &pool).await;

    // User A: athletic, bear tribe, looking for chat, age ~36
    let (_token_a, uid_a) = seed_user(
        &app, &pool,
        &unique_email(), "TargetUser", "Looking for chat, bear athletic",
        "1990-01-01", Some("1990-01-01"), Some("athletic"),
    ).await;

    // User B: average, no tribe, looking for dates, age ~36
    let (_token_b, uid_b) = seed_user(
        &app, &pool,
        &unique_email(), "OtherUser", "Just browsing",
        "1990-01-01", Some("1990-01-01"), Some("average"),
    ).await;

    add_tribe(&pool, uid_a, "bear").await;
    add_looking_for(&pool, uid_a, "chat").await;

    // Combined: tribe=bear, looking_for=chat, body_type=athletic -> only TargetUser
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&tribe=bear&looking_for=chat&body_type=athletic",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "TargetUser should match all filters");
    assert!(!user_in_results(&body, uid_b), "OtherUser should NOT match combined filters");

    // Combined with age: min_age=30, max_age=40 -> TargetUser still matches
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&tribe=bear&looking_for=chat&body_type=athletic&min_age=30&max_age=40",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "TargetUser should match all filters with age range");

    // Combined with search text -> TargetUser matches by bio
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999&q=bear+athletic&tribe=bear&looking_for=chat",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    assert!(user_in_results(&body, uid_a), "TargetUser should match combined search + filters");
}

#[tokio::test]
async fn filters_are_optional_and_default_to_no_filter() {
    let app = test_app().await;
    let pool = db::connect(&test_db_url()).await.unwrap();

    let seeker_token = seed_seeker(&app, &pool).await;

    let (_token_a, _uid_a) = seed_user(
        &app, &pool,
        &unique_email(), "Alice", "Test",
        "1990-01-01", Some("1990-01-01"), None,
    ).await;
    let (_token_b, _uid_b) = seed_user(
        &app, &pool,
        &unique_email(), "Bob", "Test",
        "1990-01-01", Some("1990-01-01"), None,
    ).await;

    // No filters -> should return users
    let (st, body) = get(
        &app,
        "/grid/nearby?lat=19.4326&lon=-99.1332&radius_m=5000&limit=9999",
        &seeker_token,
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let users = body["users"].as_array().unwrap();
    assert!(!users.is_empty(), "no filters should return users");
}
