pub mod admin;
pub mod auth;
pub mod config;
pub mod cors;
pub mod health;
pub mod media;
pub mod msgpack;
pub mod ratelimit;
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
    pub admin_jwt_secret: String,
    pub refresh_ttl_secs: i64,
    pub notifier: Arc<dyn Notifier>,
    pub oauth: Arc<dyn OAuthVerifier>,
    pub limiter: Arc<ratelimit::RateLimiter>,
    pub r2: Option<Arc<media::R2Config>>,
}

pub struct AppDeps {
    pub jwt: JwtConfig,
    pub refresh_ttl_secs: i64,
    pub notifier: Arc<dyn Notifier>,
    pub oauth: Arc<dyn OAuthVerifier>,
}

pub fn app(pool: Pool, deps: AppDeps) -> Router {
    let admin_jwt_secret = deps.jwt.secret.clone();
    let state = AppState {
        pool,
        tarpit: Tarpit::new(TarpitConfig::from_env()),
        jwt: deps.jwt,
        admin_jwt_secret,
        refresh_ttl_secs: deps.refresh_ttl_secs,
        notifier: deps.notifier,
        oauth: deps.oauth,
        limiter: Arc::new(ratelimit::RateLimiter::new(10.0, 1.0)),
        r2: media::R2Config::from_env().map(Arc::new),
    };

    let auth_routes = auth::router().route_layer(axum::middleware::from_fn_with_state(
        state.clone(),
        ratelimit::auth_limiter,
    ));

    let mut router = Router::new()
        .route("/health", get(health::health))
        .merge(auth_routes)
        .merge(admin::router(state.clone()))
        .merge(media::router());
    for path in tarpit::HONEYPOT_PATHS {
        router = router.route(path, any(tarpit::handler));
    }
    // CORS como capa externa: resuelve el preflight OPTIONS antes del rate-limiter.
    router.layer(cors::cors_layer()).with_state(state)
}
