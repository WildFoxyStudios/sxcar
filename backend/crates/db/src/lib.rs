use std::time::Duration;

use sqlx::postgres::PgPoolOptions;

pub type Pool = sqlx::PgPool;

pub mod albums;
pub mod chat;
pub mod config;
pub mod enterprise;
pub mod events;
pub mod geo;
pub mod moderation;
pub mod notifications;
pub mod photos;
pub mod plans;
pub mod social;
pub mod stories;
pub mod profiles;
pub mod staff;
pub mod support;
pub mod tier2;
pub mod tier3;
pub mod users;
pub mod verification;

/// Crea un pool de conexiones a Postgres.
///
/// Tuned for a remote, serverless (Neon) database.
///
/// Neon closes idle connections and auto-suspends compute, so a pooled
/// connection can go stale between requests. `test_before_acquire` MUST stay on
/// (the sqlx default): it pings before handing out a connection and transparently
/// replaces a dead one, so a stale connection never fails a live request. We
/// learned this the hard way — turning it OFF made the first request after an
/// idle period fail intermittently (register then mislabeled it "email already
/// registered"). The perf that matters comes instead from a warm floor of
/// connections (`min_connections`, avoids the ~1s TLS+channel-binding handshake
/// per acquire) plus concurrent round-trips in the hot handlers (see the
/// `tokio::try_join!` in profile.rs). A short-ish `idle_timeout` recycles
/// connections before Neon kills them, so most pings hit a live socket.
/// All sizes overridable via env for the VPS.
pub async fn connect(database_url: &str) -> anyhow::Result<Pool> {
    fn env_u32(key: &str, default: u32) -> u32 {
        std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
    }
    let max = env_u32("DB_MAX_CONNECTIONS", 10);
    let min = env_u32("DB_MIN_CONNECTIONS", 2).min(max);

    let pool = PgPoolOptions::new()
        .max_connections(max)
        .min_connections(min)
        // REQUIRED for Neon: ping before acquire so a connection Neon closed
        // while idle is detected and replaced instead of failing the request.
        .test_before_acquire(true)
        // Recycle idle connections before Neon's idle-close so pings rarely fail.
        .idle_timeout(Duration::from_secs(180))
        .max_lifetime(Duration::from_secs(1800))
        // Fail fast rather than hang if the pool is saturated.
        .acquire_timeout(Duration::from_secs(8))
        .connect(database_url)
        .await?;
    Ok(pool)
}

/// Comprobación de salud de la base de datos.
pub async fn ping(pool: &Pool) -> anyhow::Result<()> {
    sqlx::query("SELECT 1").execute(pool).await?;
    Ok(())
}

/// Aplica todas las migraciones embebidas (carpeta backend/migrations).
pub async fn migrate(pool: &Pool) -> anyhow::Result<()> {
    sqlx::migrate!("../../migrations").run(pool).await?;
    Ok(())
}
