use axum::{extract::State, http::StatusCode, Json};
use serde::Serialize;

use crate::AppState;

#[derive(Serialize)]
pub struct Health {
    pub status: &'static str,
    pub db: &'static str,
}

pub async fn health(State(state): State<AppState>) -> (StatusCode, Json<Health>) {
    match db::ping(&state.pool).await {
        Ok(()) => (
            StatusCode::OK,
            Json(Health {
                status: "ok",
                db: "up",
            }),
        ),
        Err(_) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(Health {
                status: "degraded",
                db: "down",
            }),
        ),
    }
}
