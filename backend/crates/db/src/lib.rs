use sqlx::postgres::PgPoolOptions;

pub type Pool = sqlx::PgPool;

pub mod config;
pub mod moderation;
pub mod staff;
pub mod support;
pub mod users;

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
