mod common;
use common::{setup_test_db, teardown_test_db};
use db::users::{
    count_users_by_status, create_user, find_user_by_id, find_user_full, search_users,
    update_user_status, NewUser,
};
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async fn insert_user(pool: &db::Pool, email: &str) -> Uuid {
    create_user(
        pool,
        NewUser {
            email: email.to_string(),
            password_hash: Some("hash".into()),
        },
    )
    .await
    .unwrap()
}

async fn insert_user_with_status(pool: &db::Pool, email: &str, status: &str) -> Uuid {
    let id = insert_user(pool, email).await;
    sqlx::query("UPDATE users SET status = $1 WHERE id = $2")
        .bind(status)
        .bind(id)
        .execute(pool)
        .await
        .unwrap();
    id
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[tokio::test]
async fn search_users_finds_by_email() {
    let (pool, name) = setup_test_db().await;
    insert_user(&pool, "alice@example.com").await;
    insert_user(&pool, "bob@example.com").await;

    let (rows, total) = search_users(&pool, "alice", 10, 0).await.unwrap();
    assert_eq!(rows.len(), 1, "should find 1 user by email");
    assert_eq!(total, 1, "total count should be 1");
    assert_eq!(rows[0].email, "alice@example.com");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn search_users_finds_by_display_name() {
    let (pool, name) = setup_test_db().await;
    let id = insert_user(&pool, "jane@example.com").await;
    sqlx::query("INSERT INTO profiles (user_id, display_name) VALUES ($1, $2)")
        .bind(id)
        .bind("Janet Doe")
        .execute(&pool)
        .await
        .unwrap();

    let (rows, _total) = search_users(&pool, "Janet", 10, 0).await.unwrap();
    assert_eq!(rows.len(), 1, "should find user by display_name");
    assert_eq!(rows[0].email, "jane@example.com");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn search_users_pagination() {
    let (pool, name) = setup_test_db().await;
    for i in 0..5 {
        insert_user(&pool, &format!("user{i}@test.com")).await;
    }

    let (rows, total) = search_users(&pool, "user", 2, 0).await.unwrap();
    assert_eq!(rows.len(), 2, "should return 2 rows with limit=2");
    assert_eq!(total, 5, "total_count should be 5");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn update_user_status_changes_status() {
    let (pool, name) = setup_test_db().await;
    let id = insert_user(&pool, "status@test.com").await;

    update_user_status(&pool, id, "banned").await.unwrap();

    let user = find_user_by_id(&pool, id)
        .await
        .unwrap()
        .expect("user found");
    assert_eq!(user.status, "banned");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn find_user_full_with_profile() {
    let (pool, name) = setup_test_db().await;
    let id = insert_user(&pool, "profile@test.com").await;

    sqlx::query("INSERT INTO profiles (user_id, display_name, about) VALUES ($1, $2, $3)")
        .bind(id)
        .bind("Test User")
        .bind("Hello world")
        .execute(&pool)
        .await
        .unwrap();

    let full = find_user_full(&pool, id)
        .await
        .unwrap()
        .expect("should find user");
    assert_eq!(full.display_name.as_deref(), Some("Test User"));
    assert_eq!(full.bio.as_deref(), Some("Hello world"));
    assert_eq!(full.email, "profile@test.com");
    assert!(full.profile_photo_url.is_none(), "no photo so should be None");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn find_user_full_no_profile() {
    let (pool, name) = setup_test_db().await;
    let id = insert_user(&pool, "noprofile@test.com").await;

    let full = find_user_full(&pool, id)
        .await
        .unwrap()
        .expect("should find user even without profile");
    assert!(full.display_name.is_none(), "no profile so display_name should be None");
    assert!(full.bio.is_none(), "no profile so bio should be None");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn count_users_by_status_works() {
    let (pool, name) = setup_test_db().await;
    insert_user_with_status(&pool, "a1@test.com", "active").await;
    insert_user_with_status(&pool, "a2@test.com", "active").await;
    insert_user_with_status(&pool, "b1@test.com", "banned").await;

    let counts = count_users_by_status(&pool).await.unwrap();
    let active_count = counts
        .iter()
        .find(|c| c.status == "active")
        .map(|c| c.count)
        .unwrap_or(0);
    let banned_count = counts
        .iter()
        .find(|c| c.status == "banned")
        .map(|c| c.count)
        .unwrap_or(0);
    assert_eq!(active_count, 2, "should have 2 active users");
    assert_eq!(banned_count, 1, "should have 1 banned user");

    teardown_test_db(pool, &name).await;
}

#[tokio::test]
async fn update_user_status_shadowbanned() {
    let (pool, name) = setup_test_db().await;
    let id = insert_user(&pool, "shadow@test.com").await;

    update_user_status(&pool, id, "shadowbanned").await.unwrap();

    let user = find_user_by_id(&pool, id)
        .await
        .unwrap()
        .expect("user found");
    assert_eq!(user.status, "shadowbanned");

    teardown_test_db(pool, &name).await;
}
