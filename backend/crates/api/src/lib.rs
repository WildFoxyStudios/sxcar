pub mod auth;
pub mod config;
pub mod health;
pub mod tarpit;

use std::sync::Arc;

use ::auth::{jwt::JwtConfig, notify::Notifier, oauth::OAuthVerifier};
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
    pub jwt: JwtConfig,
    pub refresh_ttl_secs: i64,
    pub notifier: Arc<dyn Notifier>,
    pub oauth: Arc<dyn OAuthVerifier>,
}

pub struct AppDeps {
    pub jwt: JwtConfig,
    pub refresh_ttl_secs: i64,
    pub notifier: Arc<dyn Notifier>,
    pub oauth: Arc<dyn OAuthVerifier>,
}

pub fn app(pool: Pool, deps: AppDeps) -> Router {
    let state = AppState {
        pool,
        tarpit: Tarpit::new(TarpitConfig::from_env()),
        jwt: deps.jwt,
        refresh_ttl_secs: deps.refresh_ttl_secs,
        notifier: deps.notifier,
        oauth: deps.oauth,
    };

    let mut router = Router::new()
        .route("/health", get(health::health))
        .merge(auth::router());
    for path in tarpit::HONEYPOT_PATHS {
        router = router.route(path, any(tarpit::handler));
    }
    router.with_state(state)
}
