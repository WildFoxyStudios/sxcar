pub mod admin;
pub mod albums;
pub mod auth;
pub mod chat;
pub mod config;
pub mod cors;
pub mod dev;
pub mod fcm;
pub mod grid;
pub mod health;
pub mod media;
pub mod msgpack;
pub mod notifications;
pub mod profile;
pub mod chat_broker;
pub mod ratelimit;
pub mod social;
pub mod tarpit;
pub mod well_known;

use std::sync::Arc;

use ::auth::{jwt::JwtConfig, notify::Notifier, oauth::OAuthVerifier};
use axum::{
    routing::{any, delete, get, post},
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
    pub limiter: Arc<ratelimit::Limiter>,
    pub r2: Option<Arc<media::R2Config>>,
    pub chat_broker: chat_broker::ChatBroker,
}

pub struct AppDeps {
    pub jwt: JwtConfig,
    pub refresh_ttl_secs: i64,
    pub notifier: Arc<dyn Notifier>,
    pub oauth: Arc<dyn OAuthVerifier>,
}

pub fn app(pool: Pool, deps: AppDeps) -> Router {
    let admin_jwt_secret = deps.jwt.secret.clone();
    let chat_broker = chat_broker::ChatBroker::from_env_or(256);
    let state = AppState {
        pool,
        tarpit: Tarpit::new(TarpitConfig::from_env()),
        jwt: deps.jwt,
        admin_jwt_secret,
        refresh_ttl_secs: deps.refresh_ttl_secs,
        notifier: deps.notifier,
        oauth: deps.oauth,
        limiter: Arc::new(ratelimit::Limiter::from_env_or(10.0, 1.0)),
        r2: media::R2Config::from_env().map(Arc::new),
        chat_broker,
    };

    let auth_routes = auth::router().route_layer(axum::middleware::from_fn_with_state(
        state.clone(),
        ratelimit::auth_limiter,
    ));

    let mut router = Router::new()
        .route("/health", get(health::health))
        .route("/.well-known/apple-app-site-association", get(well_known::apple_site_association))
        .route("/.well-known/assetlinks.json", get(well_known::assetlinks))
        .route("/grid/nearby", get(grid::nearby))
        .route("/profile", get(profile::get_own).put(profile::update_own))
        .route("/profile/:id", get(profile::get_by_id))
        .route("/chat/conversations", get(chat::list_conversations).post(chat::create_conversation))
        .route("/chat/conversations/:id/messages", get(chat::list_messages).post(chat::send_message))
        .route("/chat/conversations/:id/read", post(chat::mark_read))
        .route("/ws/chat", get(chat::ws_handler))
        .route("/albums", get(albums::list).post(albums::create))
        .route("/albums/shared", get(albums::shared))
        .route(
            "/albums/:id",
            get(albums::get).put(albums::update).delete(albums::delete),
        )
        .route("/albums/:id/photos", post(albums::add_photos))
        .route("/albums/:id/photos/:photo_id", delete(albums::remove_photo))
        .route("/albums/:id/share", post(albums::share))
        .route("/albums/:id/share/:user_id", delete(albums::unshare))
        .route("/notifications/register", post(notifications::register_device))
        .route("/notifications/preferences", get(notifications::get_preferences).put(notifications::update_preferences))
        .route("/taps", post(social::create_tap))
        .route("/taps/received", get(social::list_taps_received))
        .route("/taps/sent", get(social::list_taps_sent))
        .route("/favorites", get(social::list_favorites).post(social::add_favorite))
        .route("/favorites/:user_id", delete(social::remove_favorite))
        .route("/blocks", get(social::list_blocks).post(social::block_user))
        .route("/blocks/:user_id", delete(social::unblock_user))
        .merge(auth_routes)
        .merge(admin::router(state.clone()))
        .merge(media::router());
    for path in tarpit::HONEYPOT_PATHS {
        router = router.route(path, any(tarpit::handler));
    }
    // Dev seed endpoint (gated by DEV_SEED_ENABLED env var at request time)
    router = router.route("/dev/seed", dev::seed_service());
    // CORS como capa externa: resuelve el preflight OPTIONS antes del rate-limiter.
    router.layer(cors::cors_layer()).with_state(state)
}
