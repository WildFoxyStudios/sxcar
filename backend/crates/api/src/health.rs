use axum::{
    extract::{State},
    http::{HeaderMap, StatusCode},
};
use serde::Serialize;

use crate::{msgpack, AppState};

#[derive(Serialize)]
pub struct Health {
    pub status: &'static str,
    pub db: &'static str,
}

pub async fn health(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> axum::response::Response {
    let h = match db::ping(&state.pool).await {
        Ok(()) => Health {
            status: "ok",
            db: "up",
        },
        Err(_) => Health {
            status: "degraded",
            db: "down",
        },
    };

    let status = if h.status == "ok" {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };

    msgpack::respond_with_status(status, &h, &headers)
}
