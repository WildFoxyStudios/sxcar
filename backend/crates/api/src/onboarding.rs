//! Onboarding wizard state machine.
//!
//! A user is "onboarding" from registration until they complete the wizard
//! (or force-skip it). Onboarding users are hidden from `/grid/nearby` for
//! everyone else; their own profile detail still works.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::Serialize;
use sqlx::Row;
use time::OffsetDateTime;

use crate::auth::AuthUser;
use crate::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/me/onboarding", get(get_state))
        .route(
            "/me/onboarding/cards/:card_id/complete",
            post(complete_card),
        )
        .route("/me/onboarding/skip", post(skip_cards))
        .route("/me/onboarding/complete", post(force_complete))
}

#[derive(Serialize)]
pub struct OnboardingCard {
    pub id: String,
    pub label: String,
    pub kind: String,
    pub completed: bool,
    pub skipped_at: Option<OffsetDateTime>,
    pub cta_label: String,
}

#[derive(Serialize)]
pub struct OnboardingState {
    pub onboarding_completed: bool,
    pub onboarding_completed_at: Option<OffsetDateTime>,
    pub cards: Vec<OnboardingCard>,
}

const REQUIRED_CARDS: &[(&str, &str, &str)] = &[
    ("profile_photo", "Profile photo", "Add a photo"),
    ("display_name", "Display name", "Set your name"),
    ("age", "Age", "Confirm your age"),
    ("gender_position", "Gender & position", "Set your gender and position"),
];

const OPTIONAL_CARDS: &[(&str, &str, &str)] = &[
    ("looking_for", "Looking for", "What are you looking for"),
    ("tribes", "Tribes", "Pick your tribes"),
    ("vaccines", "Health & vaccines", "Share your health info"),
    ("practices", "Practices", "Add your practices"),
    ("about_me", "About me", "Write a short bio"),
    ("height", "Height", "Add your height"),
    ("weight", "Weight", "Add your weight"),
    ("relationship_status", "Relationship status", "Set your status"),
    ("position_preference", "Position preference", "Set your position"),
    ("ethnicity", "Ethnicity", "Add your ethnicity"),
];

struct UserProfileSnapshot {
    has_profile_photo: bool,
    display_name: String,
    dob: Option<time::Date>,
    gender: Option<String>,
    position: Option<String>,
    has_looking_for: bool,
    has_tribes: bool,
    details: Option<sqlx::types::Json<serde_json::Value>>,
    about_me: Option<String>,
    height_cm: Option<i32>,
    weight_kg: Option<i32>,
    relationship_status: Option<String>,
    position_preference: Option<String>,
    ethnicity: Option<String>,
}

pub async fn get_state(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<OnboardingState>, StatusCode> {
    let main_row = sqlx::query(
        "SELECT onboarding_completed_at, onboarding_skipped_cards FROM users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("onboarding load completed_at: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let completed_at: Option<OffsetDateTime> = main_row.get("onboarding_completed_at");
    let skipped_value: sqlx::types::Json<serde_json::Value> =
        main_row.get("onboarding_skipped_cards");
    let skipped: Vec<String> = skipped_value
        .0
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.get("card_id").and_then(|c| c.as_str()).map(String::from))
                .collect()
        })
        .unwrap_or_default();

    let profile_row = sqlx::query(
        r#"
        SELECT
            EXISTS(SELECT 1 FROM photos WHERE user_id = $1) AS "has_profile_photo",
            COALESCE(p.display_name, '') AS "display_name",
            u.dob,
            p.gender_identity AS "gender",
            p.position,
            EXISTS(SELECT 1 FROM profile_looking_for WHERE user_id = $1) AS "has_looking_for",
            EXISTS(SELECT 1 FROM profile_tribes WHERE user_id = $1) AS "has_tribes",
            p.details,
            p.about AS "about_me",
            p.height_cm,
            p.weight_kg,
            p.relationship_status,
            p.details->>'position_preference' AS "position_preference",
            p.ethnicity
        FROM users u
        LEFT JOIN profiles p ON p.user_id = u.id
        WHERE u.id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("onboarding load profile: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let snapshot = UserProfileSnapshot {
        has_profile_photo: profile_row.get("has_profile_photo"),
        display_name: profile_row.get("display_name"),
        dob: profile_row.get("dob"),
        gender: profile_row.get("gender"),
        position: profile_row.get("position"),
        has_looking_for: profile_row.get("has_looking_for"),
        has_tribes: profile_row.get("has_tribes"),
        details: profile_row.get("details"),
        about_me: profile_row.get("about_me"),
        height_cm: profile_row.get("height_cm"),
        weight_kg: profile_row.get("weight_kg"),
        relationship_status: profile_row.get("relationship_status"),
        position_preference: profile_row.get("position_preference"),
        ethnicity: profile_row.get("ethnicity"),
    };

    let mut cards = Vec::new();
    for (id, label, cta) in REQUIRED_CARDS {
        cards.push(OnboardingCard {
            id: id.to_string(),
            label: label.to_string(),
            kind: "required".into(),
            completed: card_completed(&snapshot, id),
            skipped_at: None,
            cta_label: cta.to_string(),
        });
    }
    for (id, label, cta) in OPTIONAL_CARDS {
        if skipped.iter().any(|s| s == id) {
            continue;
        }
        cards.push(OnboardingCard {
            id: id.to_string(),
            label: label.to_string(),
            kind: "optional".into(),
            completed: card_completed(&snapshot, id),
            skipped_at: None,
            cta_label: cta.to_string(),
        });
    }

    Ok(Json(OnboardingState {
        onboarding_completed: completed_at.is_some(),
        onboarding_completed_at: completed_at,
        cards,
    }))
}

fn card_completed(s: &UserProfileSnapshot, id: &str) -> bool {
    match id {
        "profile_photo" => s.has_profile_photo,
        "display_name" => !s.display_name.is_empty(),
        "age" => s.dob.is_some(),
        "gender_position" => s.gender.is_some() && s.position.is_some(),
        "looking_for" => s.has_looking_for,
        "tribes" => s.has_tribes,
        "vaccines" => s
            .details
            .as_ref()
            .map_or(false, |d| d.0.get("vaccines").and_then(|v| v.as_array()).map_or(false, |a| !a.is_empty())),
        "practices" => s
            .details
            .as_ref()
            .map_or(false, |d| d.0.get("practices").and_then(|v| v.as_array()).map_or(false, |a| !a.is_empty())),
        "about_me" => s.about_me.as_deref().map_or(false, |x| !x.is_empty()),
        "height" => s.height_cm.is_some(),
        "weight" => s.weight_kg.is_some(),
        "relationship_status" => s.relationship_status.is_some(),
        "position_preference" => s.position_preference.as_deref().map_or(false, |x| !x.is_empty()),
        "ethnicity" => s.ethnicity.is_some(),
        _ => false,
    }
}

pub async fn complete_card(
    State(_state): State<AppState>,
    AuthUser(_user_id): AuthUser,
    Path(_card_id): Path<String>,
    Json(_body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Task 9 implements this.
    Err(StatusCode::NOT_IMPLEMENTED)
}

pub async fn skip_cards(
    State(_state): State<AppState>,
    AuthUser(_user_id): AuthUser,
    Json(_body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Task 9 implements this.
    Err(StatusCode::NOT_IMPLEMENTED)
}

pub async fn force_complete(
    State(_state): State<AppState>,
    AuthUser(_user_id): AuthUser,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Task 9 implements this.
    Err(StatusCode::NOT_IMPLEMENTED)
}
