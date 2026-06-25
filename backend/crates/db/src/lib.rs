use sqlx::postgres::PgPoolOptions;

pub type Pool = sqlx::PgPool;

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
