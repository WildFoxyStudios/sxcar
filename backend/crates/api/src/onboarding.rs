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

pub async fn get_state(
    State(_state): State<AppState>,
    AuthUser(_user_id): AuthUser,
) -> Result<Json<OnboardingState>, StatusCode> {
    // Task 7 implements this.
    Err(StatusCode::NOT_IMPLEMENTED)
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
