use db::{connect, ping};

fn test_db_url() -> String {
    std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://dev:dev@localhost:5432/appdb".to_string())
}

#[tokio::test]
async fn connect_and_ping_succeeds() {
    let pool = connect(&test_db_url()).await.expect("should connect to postgres");
    ping(&pool).await.expect("ping should succeed");
}
