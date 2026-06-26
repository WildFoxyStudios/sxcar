mod common;
use common::{setup_test_db, teardown_test_db};
use db::users::{
    add_auth_identity, consume_auth_code, create_user, create_user_full, find_refresh_token,
    find_user_by_email, find_user_by_id, issue_auth_code, record_consent, revoke_refresh_token,
    set_email_verified, store_refresh_token, NewUser,
};
use time::{Duration, OffsetDateTime};

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

#[tokio::test]
async fn user_create_find_roundtrip() {
    let (pool, name) = setup_test_db().await;
    let id = create_user(
        &pool,
        NewUser {
            email: "a@b.com".into(),
            password_hash: Some("h".into()),
        },
    )
    .await
    .unwrap();
    let found = find_user_by_email(&pool, "a@b.com")
        .await
        .unwrap()
        .expect("user found");
    assert_eq!(found.id, id);
    assert_eq!(found.email, "a@b.com");
    add_auth_identity(&pool, id, "password", &id.to_string())
        .await
        .unwrap();
    record_consent(&pool, id, "tos", "1.0").await.unwrap();
    // email único
    let dup = create_user(
        &pool,
        NewUser {
            email: "a@b.com".into(),
            password_hash: None,
        },
    )
    .await;
    assert!(dup.is_err(), "duplicate email should fail");
    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn auth_repos_roundtrip() {
    let (pool, name) = setup_test_db().await;
    let uid = create_user_full(&pool, "auth@test.com", Some("hash"), None, true)
        .await
        .unwrap();
    assert!(find_user_by_id(&pool, uid).await.unwrap().is_some());
    set_email_verified(&pool, uid).await.unwrap();

    let exp = OffsetDateTime::now_utc() + Duration::days(30);
    store_refresh_token(&pool, uid, "th1", exp).await.unwrap();
    let r = find_refresh_token(&pool, "th1").await.unwrap().unwrap();
    assert_eq!(r.user_id, uid);
    assert!(!r.revoked && !r.expired);
    revoke_refresh_token(&pool, "th1").await.unwrap();
    assert!(
        find_refresh_token(&pool, "th1")
            .await
            .unwrap()
            .unwrap()
            .revoked
    );

    let cexp = OffsetDateTime::now_utc() + Duration::minutes(15);
    issue_auth_code(&pool, uid, "email_verify", "ch1", cexp)
        .await
        .unwrap();
    assert!(consume_auth_code(&pool, uid, "email_verify", "ch1")
        .await
        .unwrap());
    // segundo consumo falla (ya usado)
    assert!(!consume_auth_code(&pool, uid, "email_verify", "ch1")
        .await
        .unwrap());
    teardown_test_db(pool, &name).await;
}
