mod common;
use common::{setup_test_db, teardown_test_db};

#[tokio::test]
async fn postgis_location_within_distance() {
    let (pool, name) = setup_test_db().await;
    // un usuario
    let uid: uuid::Uuid =
        sqlx::query_scalar("INSERT INTO users (email) VALUES ('geo@test.com') RETURNING id")
            .fetch_one(&pool)
            .await
            .unwrap();
    // su ubicación (lon, lat)
    sqlx::query("INSERT INTO locations (user_id, geog) VALUES ($1, ST_SetSRID(ST_MakePoint($2,$3),4326)::geography)")
        .bind(uid).bind(-3.7038_f64).bind(40.4168_f64) // Madrid
        .execute(&pool).await.unwrap();
    // buscar dentro de 1km de un punto a ~100m
    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM locations WHERE ST_DWithin(geog, ST_SetSRID(ST_MakePoint($1,$2),4326)::geography, 1000)")
        .bind(-3.7040_f64).bind(40.4170_f64)
        .fetch_one(&pool).await.unwrap();
    assert_eq!(count, 1, "location should be within 1km");
    teardown_test_db(pool, &name).await;
}
