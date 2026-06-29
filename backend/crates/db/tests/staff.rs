mod common;
use common::{setup_test_db, teardown_test_db};
use db::staff::{
    create_session, find_active_session, find_staff_by_email, increment_failed_login,
    revoke_session, update_last_login, update_session_last_seen,
};
use db::Pool;
use time::{Duration, OffsetDateTime};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Inserta una fila en `staff` con los valores mínimos requeridos.
async fn insert_staff(
    pool: &Pool,
    email: &str,
    role: &str,
    failed_count: i32,
) -> uuid::Uuid {
    sqlx::query_scalar::<_, uuid::Uuid>(
        r#"INSERT INTO staff
             (email, password_hash, totp_secret_enc, totp_enabled_at,
              recovery_codes_hash, role, failed_login_count)
           VALUES ($1, $2, $3, now(), $4, $5, $6)
           RETURNING id"#,
    )
    .bind(email)
    .bind("argon2-hash")
    .bind(vec![0x12u8, 0x34u8])
    .bind(vec!["rc_hash_1".to_string()])
    .bind(role)
    .bind(failed_count)
    .fetch_one(pool)
    .await
    .unwrap()
}

async fn insert_staff_default(pool: &Pool, email: &str) -> uuid::Uuid {
    insert_staff(pool, email, "admin", 0).await
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn find_by_email_existing_and_nonexistent() {
    let (pool, name) = setup_test_db().await;
    let id = insert_staff_default(&pool, "staff1@test.com").await;

    let found = find_staff_by_email(&pool, "staff1@test.com")
        .await
        .unwrap()
        .expect("should find staff by email");
    assert_eq!(found.id, id);
    assert_eq!(found.email, "staff1@test.com");
    assert_eq!(found.role, "admin");

    let not_found = find_staff_by_email(&pool, "nonexistent@test.com")
        .await
        .unwrap();
    assert!(not_found.is_none(), "nonexistent email should return None");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn update_last_login_sets_fields() {
    let (pool, name) = setup_test_db().await;
    let id = insert_staff_default(&pool, "staff2@test.com").await;

    // Bump failed count so we can verify it gets reset
    sqlx::query("UPDATE staff SET failed_login_count = 3 WHERE id = $1")
        .bind(id)
        .execute(&pool)
        .await
        .unwrap();

    update_last_login(&pool, id, Some("10.0.0.1"))
        .await
        .unwrap();

    // Verify DB state
    let row = sqlx::query_as::<_, (Option<OffsetDateTime>, Option<String>, i32)>(
        r#"SELECT last_login_at,
                  last_login_ip::text,
                  failed_login_count
           FROM staff WHERE id = $1"#,
    )
    .bind(id)
    .fetch_one(&pool)
    .await
    .unwrap();

    assert!(row.0.is_some(), "last_login_at should be set");
    // PG añade /32 al castear inet a text (IPv4 netmask implícita)
    assert_eq!(
        row.1.as_deref(),
        Some("10.0.0.1/32"),
        "last_login_ip"
    );
    assert_eq!(row.2, 0, "failed_login_count should reset to 0");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn increment_failed_locks_after_5_attempts() {
    let (pool, name) = setup_test_db().await;
    let id = insert_staff(&pool, "staff3@test.com", "admin", 4).await;

    let locked = increment_failed_login(&pool, id)
        .await
        .unwrap();

    assert!(
        locked.is_some(),
        "should return Some(locked_until) after 5 failures"
    );

    // Verify the DB has locked_until set
    let db_locked: Option<OffsetDateTime> =
        sqlx::query_scalar("SELECT locked_until FROM staff WHERE id = $1")
            .bind(id)
            .fetch_one(&pool)
            .await
            .unwrap();

    assert!(db_locked.is_some(), "locked_until should be persisted");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn create_and_find_active_session() {
    let (pool, name) = setup_test_db().await;
    let staff_id = insert_staff_default(&pool, "staff4@test.com").await;

    // Session that expires in the future → should be found
    let future = OffsetDateTime::now_utc() + Duration::hours(8);
    let session_id =
        create_session(&pool, staff_id, future, Some("10.0.0.2"), Some("test-agent"))
            .await
            .unwrap();

    let found = find_active_session(&pool, session_id)
        .await
        .unwrap()
        .expect("active session should be found");
    assert_eq!(found.staff_id, staff_id);

    // Session already expired → should NOT be found
    let past = OffsetDateTime::now_utc() - Duration::hours(1);
    let expired_id = create_session(&pool, staff_id, past, None, None)
        .await
        .unwrap();

    let expired = find_active_session(&pool, expired_id).await.unwrap();
    assert!(expired.is_none(), "expired session should not be found");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn revoke_session_marks_revoked() {
    let (pool, name) = setup_test_db().await;
    let staff_id = insert_staff_default(&pool, "staff5@test.com").await;

    let session_id = create_session(
        &pool,
        staff_id,
        OffsetDateTime::now_utc() + Duration::hours(8),
        None,
        None,
    )
    .await
    .unwrap();

    // Confirm it is active first
    assert!(
        find_active_session(&pool, session_id)
            .await
            .unwrap()
            .is_some()
    );

    revoke_session(&pool, session_id, "logout").await.unwrap();

    // After revoke it must not be found
    let after = find_active_session(&pool, session_id).await.unwrap();
    assert!(after.is_none(), "revoked session should not be found");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn session_update_last_seen_ok() {
    let (pool, name) = setup_test_db().await;
    let staff_id = insert_staff_default(&pool, "staff6@test.com").await;

    let session_id = create_session(
        &pool,
        staff_id,
        OffsetDateTime::now_utc() + Duration::hours(8),
        None,
        None,
    )
    .await
    .unwrap();

    update_session_last_seen(&pool, session_id)
        .await
        .unwrap();

    // Verify last_seen_at is set
    let last_seen: Option<OffsetDateTime> =
        sqlx::query_scalar("SELECT last_seen_at FROM staff_sessions WHERE id = $1")
            .bind(session_id)
            .fetch_one(&pool)
            .await
            .unwrap();

    assert!(last_seen.is_some(), "last_seen_at should be set");

    teardown_test_db(pool, &name).await;
}
