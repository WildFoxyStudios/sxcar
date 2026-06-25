pub mod config;
pub mod health;

use axum::{routing::get, Router};
use db::Pool;

#[derive(Clone)]
pub struct AppState {
    pub pool: Pool,
}

pub fn app(pool: Pool) -> Router {
    let state = AppState { pool };
    Router::new()
        .route("/health", get(health::health))
        .with_state(state)
}
