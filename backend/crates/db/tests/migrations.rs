mod common;
use common::{setup_test_db, teardown_test_db};

#[tokio::test]
async fn migrations_apply_and_are_idempotent() {
    let (pool, name) = setup_test_db().await;
    // re-aplicar no debe fallar
    db::migrate(&pool).await.expect("re-migrate idempotent");
    // extensión postgis presente
    let has_postgis: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname='postgis')")
            .fetch_one(&pool)
            .await
            .unwrap();
    assert!(has_postgis, "postgis extension should exist");
    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn identity_tables_exist() {
    let (pool, name) = setup_test_db().await;
    for table in [
        "users",
        "auth_identities",
        "devices",
        "refresh_tokens",
        "consent_records",
        "data_requests",
    ] {
        let exists: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name=$1)",
        )
        .bind(table)
        .fetch_one(&pool)
        .await
        .unwrap();
        assert!(exists, "table {table} should exist");
    }
    teardown_test_db(pool, &name).await;
}
