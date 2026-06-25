use api::config::Config;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .init();

    let config = Config::from_env()?;
    let pool = db::connect(&config.database_url).await?;
    let app = api::app(pool);

    let listener = tokio::net::TcpListener::bind(&config.bind_addr).await?;
    tracing::info!("api listening on {}", config.bind_addr);
    axum::serve(listener, app).await?;
    Ok(())
}
