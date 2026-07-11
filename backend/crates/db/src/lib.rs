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
/// Tuned for a remote (Neon) database where each new TCP+TLS+channel-binding
/// handshake costs ~1s. The big win is `test_before_acquire(false)`: by default
/// sqlx runs a `SELECT 1` ping on EVERY checkout, which doubles the round-trips
/// of any multi-query handler (e.g. PUT /profile did ~10 sequential ops, each
/// paying ping + query → multi-second saves that tripped the client's 10s
/// timeout). Keeping a warm floor of connections (`min_connections`) avoids
/// re-establishing TLS on each acquire. All overridable via env for the VPS.
pub async fn connect(database_url: &str) -> anyhow::Result<Pool> {
    fn env_u32(key: &str, default: u32) -> u32 {
        std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default)
    }
    let max = env_u32("DB_MAX_CONNECTIONS", 10);
    let min = env_u32("DB_MIN_CONNECTIONS", 2).min(max);

    let pool = PgPoolOptions::new()
        .max_connections(max)
        .min_connections(min)
        // Skip the per-acquire `SELECT 1` ping — halves round-trips on every
        // multi-query request. Broken connections surface as a normal query
        // error and the pool reconnects.
        .test_before_acquire(false)
        // Keep connections warm so acquires don't pay the Neon TLS handshake.
        .idle_timeout(Duration::from_secs(600))
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
