pub mod config;
pub mod health;
pub mod tarpit;

use axum::{
    routing::{any, get},
    Router,
};
use db::Pool;
use tarpit::{Tarpit, TarpitConfig};

#[derive(Clone)]
pub struct AppState {
    pub pool: Pool,
    pub tarpit: Tarpit,
}

pub fn app(pool: Pool) -> Router {
    let state = AppState {
        pool,
        tarpit: Tarpit::new(TarpitConfig::from_env()),
    };

    let mut router = Router::new().route("/health", get(health::health));
    for path in tarpit::HONEYPOT_PATHS {
        router = router.route(path, any(tarpit::handler));
    }
    router.with_state(state)
}
