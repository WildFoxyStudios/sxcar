use api::config::Config;
use api::{app, AppDeps};
use auth::{jwt::JwtConfig, notify::DevNotifier, notify::SmtpNotifier, oauth::DevOAuthVerifier, oauth::RealOAuthVerifier};
use std::sync::Arc;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .init();

    let config = Config::from_env()?;
    let pool = db::connect(&config.database_url).await?;

    // Subcomando: `api migrate` aplica migraciones y termina.
    if std::env::args().nth(1).as_deref() == Some("migrate") {
        db::migrate(&pool).await?;
        tracing::info!("migrations applied");
        return Ok(());
    }

    let deps = AppDeps {
        jwt: JwtConfig {
            secret: config.jwt_secret.clone(),
            access_ttl_secs: config.access_ttl_secs,
        },
        refresh_ttl_secs: config.refresh_ttl_secs,
        notifier: SmtpNotifier::from_env().map(Arc::new).unwrap_or_else(|| Arc::new(DevNotifier)),
        oauth: RealOAuthVerifier::from_env().map(Arc::new).unwrap_or_else(|| Arc::new(DevOAuthVerifier)),
    };

    let app = app(pool, deps);
    let listener = tokio::net::TcpListener::bind(&config.bind_addr).await?;
    tracing::info!("api listening on {}", config.bind_addr);
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<std::net::SocketAddr>(),
    )
    .await?;
    Ok(())
}
