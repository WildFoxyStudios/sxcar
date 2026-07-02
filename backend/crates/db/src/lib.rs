use sqlx::postgres::PgPoolOptions;

pub type Pool = sqlx::PgPool;

pub mod albums;
pub mod chat;
pub mod config;
pub mod enterprise;
pub mod geo;
pub mod moderation;
pub mod notifications;
pub mod plans;
pub mod social;
pub mod profiles;
pub mod staff;
pub mod support;
pub mod tier2;
pub mod tier3;
pub mod users;
pub mod verification;

/// Crea un pool de conexiones a Postgres.
pub async fn connect(database_url: &str) -> anyhow::Result<Pool> {
    let pool = PgPoolOptions::new()
        .max_connections(10)
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
