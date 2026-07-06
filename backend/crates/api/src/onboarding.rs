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
use serde::{Deserialize, Serialize};
use serde_json::json;
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

/// After a card is completed, check if all 4 required cards are now satisfied.
/// If yes, flip `onboarding_completed_at` so the user becomes visible on the grid.
async fn try_complete_onboarding(pool: &sqlx::PgPool, user_id: uuid::Uuid) -> Result<(), StatusCode> {
    sqlx::query(
        r#"
        UPDATE users SET onboarding_completed_at = NOW()
        WHERE id = $1
          AND onboarding_completed_at IS NULL
          AND EXISTS(SELECT 1 FROM photos WHERE user_id = $1)
          AND EXISTS(
              SELECT 1 FROM profiles
              WHERE user_id = $1
                AND COALESCE(NULLIF(display_name, ''), '') <> ''
          )
          AND dob IS NOT NULL
          AND EXISTS(
              SELECT 1 FROM profiles
              WHERE user_id = $1
                AND gender_identity IS NOT NULL
                AND position IS NOT NULL
          )
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(|e| {
        tracing::error!("try_complete_onboarding: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Card-specific bodies
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(tag = "card_id", rename_all = "snake_case")]
#[allow(dead_code)]
pub enum CompleteBody {
    ProfilePhoto { r2_key: String, is_nsfw: bool },
    DisplayName { display_name: String },
    Age { dob: String }, // parsed manually to time::Date
    GenderPosition { gender: String, position: String },
    LookingFor { looking_for: Vec<String> },
    Tribes { tribes: Vec<String> },
    Vaccines { vaccines: Vec<String> },
    Practices { practices: Vec<String> },
    AboutMe { about_me: String },
    Height { height_cm: i32 },
    Weight { weight_kg: i32 },
    RelationshipStatus { status: String },
    PositionPreference { position: String },
    Ethnicity { ethnicity: String },
    #[serde(other)]
    Unknown,
}

// ---------------------------------------------------------------------------
// POST /me/onboarding/cards/:card_id/complete
// ---------------------------------------------------------------------------

pub async fn complete_card(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Path(card_id): Path<String>,
    Json(raw): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let result = match card_id.as_str() {
        "profile_photo" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::ProfilePhoto { r2_key, is_nsfw } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            let blur_key = format!("{}.blur.jpg", r2_key);
            sqlx::query_scalar::<_, uuid::Uuid>(
                "INSERT INTO photos (user_id, r2_key, blur_key, is_nsfw) VALUES ($1, $2, $3, $4) RETURNING id",
            )
            .bind(user_id).bind(&r2_key).bind(&blur_key).bind(is_nsfw)
            .fetch_one(&state.pool).await
            .map_err(|e| { tracing::error!("insert photo: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "display_name" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::DisplayName { display_name } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            if display_name.trim().is_empty() { return Err(StatusCode::BAD_REQUEST); }
            sqlx::query(
                "INSERT INTO profiles (user_id, display_name) VALUES ($1, $2)
                 ON CONFLICT (user_id) DO UPDATE SET display_name = EXCLUDED.display_name",
            )
            .bind(user_id).bind(&display_name)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update display_name: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "age" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Age { dob } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            // Parse the date string; time::Date expects YYYY-MM-DD.
            let date_fmt = time::format_description::parse("[year]-[month]-[day]")
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let parsed_dob = time::Date::parse(&dob, &date_fmt)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            // Age-gate: must be 18+.
            let today = time::OffsetDateTime::now_utc().date();
            let age_years = (today - parsed_dob).whole_days() / 365;
            if age_years < 18 { return Err(StatusCode::UNPROCESSABLE_ENTITY); }
            sqlx::query("UPDATE users SET dob = $1 WHERE id = $2")
                .bind(parsed_dob).bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("update dob: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "gender_position" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::GenderPosition { gender, position } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query(
                "INSERT INTO profiles (user_id, gender_identity, position) VALUES ($1, $2, $3)
                 ON CONFLICT (user_id) DO UPDATE SET gender_identity = EXCLUDED.gender_identity, position = EXCLUDED.position",
            )
            .bind(user_id).bind(&gender).bind(&position)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update gender/position: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "looking_for" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::LookingFor { looking_for } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            if looking_for.is_empty() { return Err(StatusCode::BAD_REQUEST); }
            // Replace all entries.
            sqlx::query("DELETE FROM profile_looking_for WHERE user_id = $1")
                .bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("clear looking_for: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            for intent in &looking_for {
                sqlx::query("INSERT INTO profile_looking_for (user_id, intent) VALUES ($1, $2)")
                    .bind(user_id).bind(intent)
                    .execute(&state.pool).await
                    .map_err(|e| { tracing::error!("insert looking_for: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            }
            Ok(())
        }
        "tribes" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Tribes { tribes } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            if tribes.is_empty() { return Err(StatusCode::BAD_REQUEST); }
            sqlx::query("DELETE FROM profile_tribes WHERE user_id = $1")
                .bind(user_id)
                .execute(&state.pool).await
                .map_err(|e| { tracing::error!("clear tribes: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            for tribe in &tribes {
                sqlx::query("INSERT INTO profile_tribes (user_id, tribe) VALUES ($1, $2)")
                    .bind(user_id).bind(tribe)
                    .execute(&state.pool).await
                    .map_err(|e| { tracing::error!("insert tribe: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            }
            Ok(())
        }
        "vaccines" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Vaccines { vaccines } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            let val = serde_json::to_value(&vaccines).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            sqlx::query(
                "INSERT INTO profiles (user_id, details) VALUES ($1, jsonb_set('{}'::jsonb, '{vaccines}', $2::jsonb))
                 ON CONFLICT (user_id) DO UPDATE SET details = jsonb_set(COALESCE(profiles.details, '{}'::jsonb), '{vaccines}', $2::jsonb)",
            )
            .bind(user_id).bind(&val)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update vaccines: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "practices" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Practices { practices } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            let val = serde_json::to_value(&practices).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            sqlx::query(
                "INSERT INTO profiles (user_id, details) VALUES ($1, jsonb_set('{}'::jsonb, '{practices}', $2::jsonb))
                 ON CONFLICT (user_id) DO UPDATE SET details = jsonb_set(COALESCE(profiles.details, '{}'::jsonb), '{practices}', $2::jsonb)",
            )
            .bind(user_id).bind(&val)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update practices: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "about_me" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::AboutMe { about_me } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query(
                "INSERT INTO profiles (user_id, about) VALUES ($1, $2)
                 ON CONFLICT (user_id) DO UPDATE SET about = EXCLUDED.about",
            )
            .bind(user_id).bind(&about_me)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update about_me: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "height" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Height { height_cm } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            if !(50..=272).contains(&height_cm) { return Err(StatusCode::BAD_REQUEST); }
            sqlx::query(
                "INSERT INTO profiles (user_id, height_cm) VALUES ($1, $2)
                 ON CONFLICT (user_id) DO UPDATE SET height_cm = EXCLUDED.height_cm",
            )
            .bind(user_id).bind(height_cm)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update height: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "weight" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Weight { weight_kg } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            if !(20..=500).contains(&weight_kg) { return Err(StatusCode::BAD_REQUEST); }
            sqlx::query(
                "INSERT INTO profiles (user_id, weight_kg) VALUES ($1, $2)
                 ON CONFLICT (user_id) DO UPDATE SET weight_kg = EXCLUDED.weight_kg",
            )
            .bind(user_id).bind(weight_kg)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update weight: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "relationship_status" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::RelationshipStatus { status } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query(
                "INSERT INTO profiles (user_id, relationship_status) VALUES ($1, $2)
                 ON CONFLICT (user_id) DO UPDATE SET relationship_status = EXCLUDED.relationship_status",
            )
            .bind(user_id).bind(&status)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update relationship_status: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "position_preference" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::PositionPreference { position } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            let val = serde_json::json!(position);
            sqlx::query(
                "INSERT INTO profiles (user_id, details) VALUES ($1, jsonb_set('{}'::jsonb, '{position_preference}', $2::jsonb))
                 ON CONFLICT (user_id) DO UPDATE SET details = jsonb_set(COALESCE(profiles.details, '{}'::jsonb), '{position_preference}', $2::jsonb)",
            )
            .bind(user_id).bind(&val)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update position_preference: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        "ethnicity" => {
            let body: CompleteBody = serde_json::from_value(raw)
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            let CompleteBody::Ethnicity { ethnicity } = body else {
                return Err(StatusCode::BAD_REQUEST);
            };
            sqlx::query(
                "INSERT INTO profiles (user_id, ethnicity) VALUES ($1, $2)
                 ON CONFLICT (user_id) DO UPDATE SET ethnicity = EXCLUDED.ethnicity",
            )
            .bind(user_id).bind(&ethnicity)
            .execute(&state.pool).await
            .map_err(|e| { tracing::error!("update ethnicity: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;
            Ok(())
        }
        _ => Err(StatusCode::NOT_FOUND),
    };

    if result.is_ok() {
        try_complete_onboarding(&state.pool, user_id).await?;
    }

    result.map(|_| Json(json!({ "card_id": card_id, "completed": true })))
}

// ---------------------------------------------------------------------------
// POST /me/onboarding/skip
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct SkipBody { card_ids: Vec<String> }

pub async fn skip_cards(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Json(body): Json<SkipBody>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Validate that all card_ids are optional.
    let allowed: std::collections::HashSet<&str> = OPTIONAL_CARDS.iter().map(|(id, _, _)| *id).collect();
    for id in &body.card_ids {
        if !allowed.contains(id.as_str()) {
            return Err(StatusCode::BAD_REQUEST);
        }
    }

    // Append each card_id to the JSONB array, with timestamp.
    let now = OffsetDateTime::now_utc();
    let new_entries: Vec<serde_json::Value> = body.card_ids.iter().map(|id| {
        json!({ "card_id": id, "skipped_at": now })
    }).collect();

    let entries_val = serde_json::to_value(&new_entries).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    sqlx::query(
        r#"
        UPDATE users
        SET onboarding_skipped_cards = onboarding_skipped_cards || $1::jsonb
        WHERE id = $2
        "#,
    )
    .bind(&entries_val)
    .bind(user_id)
    .execute(&state.pool)
    .await
    .map_err(|e| { tracing::error!("skip cards: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;

    Ok(Json(json!({ "skipped": body.card_ids })))
}

// ---------------------------------------------------------------------------
// POST /me/onboarding/complete  (force-complete)
// ---------------------------------------------------------------------------

pub async fn force_complete(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let now = OffsetDateTime::now_utc();
    sqlx::query(
        "UPDATE users SET onboarding_completed_at = $1 WHERE id = $2 AND onboarding_completed_at IS NULL",
    )
    .bind(now).bind(user_id)
    .execute(&state.pool)
    .await
    .map_err(|e| { tracing::error!("force complete: {e}"); StatusCode::INTERNAL_SERVER_ERROR })?;

    Ok(Json(json!({ "onboarding_completed_at": now })))
}
