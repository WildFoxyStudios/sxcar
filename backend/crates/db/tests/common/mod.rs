use db::Pool;
use sqlx::{Connection, Executor, PgConnection};

fn base_url() -> String {
    std::env::var("TEST_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://dev:dev@localhost:5433/appdb".to_string())
}

fn with_db(url: &str, db: &str) -> String {
    // reemplaza el nombre de DB final de la URL
    let (head, _) = url.rsplit_once('/').unwrap();
    format!("{head}/{db}")
}

// Contador para nombres únicos por test (los tests de un binario corren en paralelo).
static COUNTER: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

/// Crea una DB temporal, aplica migraciones, y devuelve (pool, nombre_db).
pub async fn setup_test_db() -> (Pool, String) {
    let base = base_url();
    let n = COUNTER.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    let name = format!("appdb_test_{}_{}", std::process::id(), n);
    let mut admin = PgConnection::connect(&base).await.expect("admin connect");
    let _ = admin
        .execute(format!("DROP DATABASE IF EXISTS {name} WITH (FORCE)").as_str())
        .await;
    admin
        .execute(format!("CREATE DATABASE {name}").as_str())
        .await
        .expect("create db");
    let url = with_db(&base, &name);
    let pool = db::connect(&url).await.expect("connect test db");
    db::migrate(&pool).await.expect("migrate");
    (pool, name)
}

/// Dropea la DB temporal (llamar al final del test).
pub async fn teardown_test_db(pool: Pool, name: &str) {
    pool.close().await;
    let base = base_url();
    let mut admin = PgConnection::connect(&base).await.expect("admin connect");
    let _ = admin
        .execute(format!("DROP DATABASE IF EXISTS {name} WITH (FORCE)").as_str())
        .await;
}
