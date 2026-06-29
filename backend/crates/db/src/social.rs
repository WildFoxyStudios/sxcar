use sqlx::FromRow;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Row types
// ---------------------------------------------------------------------------

#[derive(Debug, FromRow, serde::Serialize)]
pub struct TapRow {
    pub id: Uuid,
    pub from_user: Uuid,
    pub to_user: Uuid,
    pub tap_type: Option<String>,
    pub created_at: time::OffsetDateTime,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct TapWithDisplayName {
    pub id: Uuid,
    pub from_user: Uuid,
    pub to_user: Uuid,
    pub tap_type: Option<String>,
    pub created_at: time::OffsetDateTime,
    pub display_name: Option<String>,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct FavoriteRow {
    pub user_id: Uuid,
    pub target_id: Uuid,
    pub created_at: time::OffsetDateTime,
    pub display_name: Option<String>,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct BlockRow {
    pub user_id: Uuid,
    pub target_id: Uuid,
    pub reason: Option<String>,
    pub created_at: time::OffsetDateTime,
    pub display_name: Option<String>,
}

// ---------------------------------------------------------------------------
// Taps
// ---------------------------------------------------------------------------

pub async fn create_tap(
    pool: &sqlx::PgPool,
    from_user: Uuid,
    to_user: Uuid,
    tap_type: &str,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO taps (from_user, to_user, tap_type)
           VALUES ($1, $2, $3)
           RETURNING id"#,
    )
    .bind(from_user)
    .bind(to_user)
    .bind(tap_type)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

pub async fn list_taps_received(
    pool: &sqlx::PgPool,
    user_id: Uuid,
) -> anyhow::Result<Vec<TapWithDisplayName>> {
    let rows = sqlx::query_as::<_, TapWithDisplayName>(
        r#"SELECT t.id, t.from_user, t.to_user, t.tap_type, t.created_at,
                  p.display_name
           FROM taps t
           LEFT JOIN profiles p ON p.user_id = t.from_user
           WHERE t.to_user = $1
           ORDER BY t.created_at DESC"#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn list_taps_sent(
    pool: &sqlx::PgPool,
    user_id: Uuid,
) -> anyhow::Result<Vec<TapWithDisplayName>> {
    let rows = sqlx::query_as::<_, TapWithDisplayName>(
        r#"SELECT t.id, t.from_user, t.to_user, t.tap_type, t.created_at,
                  p.display_name
           FROM taps t
           LEFT JOIN profiles p ON p.user_id = t.to_user
           WHERE t.from_user = $1
           ORDER BY t.created_at DESC"#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// Favorites
// ---------------------------------------------------------------------------

pub async fn add_favorite(
    pool: &sqlx::PgPool,
    user_id: Uuid,
    target_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO favorites (user_id, target_id)
           VALUES ($1, $2)
           ON CONFLICT DO NOTHING"#,
    )
    .bind(user_id)
    .bind(target_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn remove_favorite(
    pool: &sqlx::PgPool,
    user_id: Uuid,
    target_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"DELETE FROM favorites WHERE user_id = $1 AND target_id = $2"#,
    )
    .bind(user_id)
    .bind(target_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn list_favorites(
    pool: &sqlx::PgPool,
    user_id: Uuid,
) -> anyhow::Result<Vec<FavoriteRow>> {
    let rows = sqlx::query_as::<_, FavoriteRow>(
        r#"SELECT f.user_id, f.target_id, f.created_at,
                  p.display_name
           FROM favorites f
           LEFT JOIN profiles p ON p.user_id = f.target_id
           WHERE f.user_id = $1
           ORDER BY f.created_at DESC"#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// Blocks
// ---------------------------------------------------------------------------

pub async fn block_user(
    pool: &sqlx::PgPool,
    blocker_id: Uuid,
    blocked_id: Uuid,
    reason: Option<&str>,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO blocks (user_id, target_id, reason)
           VALUES ($1, $2, $3)
           ON CONFLICT DO NOTHING"#,
    )
    .bind(blocker_id)
    .bind(blocked_id)
    .bind(reason)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn unblock_user(
    pool: &sqlx::PgPool,
    blocker_id: Uuid,
    blocked_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"DELETE FROM blocks WHERE user_id = $1 AND target_id = $2"#,
    )
    .bind(blocker_id)
    .bind(blocked_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn list_blocks(
    pool: &sqlx::PgPool,
    user_id: Uuid,
) -> anyhow::Result<Vec<BlockRow>> {
    let rows = sqlx::query_as::<_, BlockRow>(
        r#"SELECT b.user_id, b.target_id, b.reason, b.created_at,
                  p.display_name
           FROM blocks b
           LEFT JOIN profiles p ON p.user_id = b.target_id
           WHERE b.user_id = $1
           ORDER BY b.created_at DESC"#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Check if either user has blocked the other.
pub async fn is_blocked(
    pool: &sqlx::PgPool,
    user_a: Uuid,
    user_b: Uuid,
) -> anyhow::Result<bool> {
    let row: Option<(bool,)> = sqlx::query_as(
        r#"SELECT EXISTS(
               SELECT 1 FROM blocks
               WHERE (user_id = $1 AND target_id = $2)
                  OR (user_id = $2 AND target_id = $1)
           )"#,
    )
    .bind(user_a)
    .bind(user_b)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| r.0).unwrap_or(false))
}

/// Delete conversations where both users are members (used when blocking).
pub async fn delete_conversation_between(
    pool: &sqlx::PgPool,
    user_a: Uuid,
    user_b: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"DELETE FROM conversations WHERE id IN (
               SELECT cm1.conversation_id
               FROM conversation_members cm1
               JOIN conversation_members cm2 ON cm1.conversation_id = cm2.conversation_id
               WHERE cm1.user_id = $1 AND cm2.user_id = $2
           )"#,
    )
    .bind(user_a)
    .bind(user_b)
    .execute(pool)
    .await?;
    Ok(())
}
