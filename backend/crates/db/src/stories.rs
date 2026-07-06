use sqlx::FromRow;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Row types
// ---------------------------------------------------------------------------

#[derive(Debug, FromRow, serde::Serialize)]
pub struct StoryRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub media_key: String,
    pub media_type: String,
    pub caption: Option<String>,
    pub created_at: time::OffsetDateTime,
    pub expires_at: time::OffsetDateTime,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct StoryWithDisplayName {
    pub id: Uuid,
    pub user_id: Uuid,
    pub media_key: String,
    pub media_type: String,
    pub caption: Option<String>,
    pub created_at: time::OffsetDateTime,
    pub expires_at: time::OffsetDateTime,
    pub display_name: Option<String>,
    pub avatar_key: Option<String>,
}

// ---------------------------------------------------------------------------
// Stories CRUD
// ---------------------------------------------------------------------------

/// Insert a new story. Returns the created story id.
pub async fn create_story(
    pool: &sqlx::PgPool,
    user_id: Uuid,
    media_key: &str,
    media_type: &str,
    caption: Option<&str>,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO stories (user_id, media_key, media_type, caption)
           VALUES ($1, $2, $3, $4)
           RETURNING id"#,
    )
    .bind(user_id)
    .bind(media_key)
    .bind(media_type)
    .bind(caption)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

/// Get active (non-expired) stories for the given user ids.
/// Returns stories ordered by created_at DESC.
pub async fn get_active_stories(
    pool: &sqlx::PgPool,
    user_ids: &[Uuid],
) -> anyhow::Result<Vec<StoryWithDisplayName>> {
    let rows = sqlx::query_as::<_, StoryWithDisplayName>(
        r#"SELECT s.id, s.user_id, s.media_key, s.media_type, s.caption,
                  s.created_at, s.expires_at,
                  p.display_name,
                  ph.r2_key AS avatar_key
           FROM stories s
           LEFT JOIN profiles p ON p.user_id = s.user_id
           LEFT JOIN photos ph ON ph.id = p.profile_photo_id
           WHERE s.user_id = ANY($1)
             AND s.expires_at > now()
           ORDER BY s.user_id, s.created_at DESC"#,
    )
    .bind(user_ids)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Get a single story by id (regardless of expiry).
pub async fn get_story_by_id(
    pool: &sqlx::PgPool,
    story_id: Uuid,
) -> anyhow::Result<Option<StoryRow>> {
    let row = sqlx::query_as::<_, StoryRow>(
        r#"SELECT id, user_id, media_key, media_type, caption, created_at, expires_at
           FROM stories
           WHERE id = $1"#,
    )
    .bind(story_id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Delete a story by id. Returns the number of rows deleted.
pub async fn delete_story(
    pool: &sqlx::PgPool,
    story_id: Uuid,
    user_id: Uuid,
) -> anyhow::Result<u64> {
    let rows = sqlx::query(
        r#"DELETE FROM stories WHERE id = $1 AND user_id = $2"#,
    )
    .bind(story_id)
    .bind(user_id)
    .execute(pool)
    .await?
    .rows_affected();
    Ok(rows)
}

/// Get user's own active stories (for the stories bar — always include self).
pub async fn get_own_active_stories(
    pool: &sqlx::PgPool,
    user_id: Uuid,
) -> anyhow::Result<Vec<StoryWithDisplayName>> {
    let rows = sqlx::query_as::<_, StoryWithDisplayName>(
        r#"SELECT s.id, s.user_id, s.media_key, s.media_type, s.caption,
                  s.created_at, s.expires_at,
                  p.display_name,
                  ph.r2_key AS avatar_key
           FROM stories s
           LEFT JOIN profiles p ON p.user_id = s.user_id
           LEFT JOIN photos ph ON ph.id = p.profile_photo_id
           WHERE s.user_id = $1
             AND s.expires_at > now()
           ORDER BY s.created_at DESC"#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// Story views
// ---------------------------------------------------------------------------

/// Mark a story as viewed by a user. Idempotent (ON CONFLICT DO NOTHING).
pub async fn mark_viewed(
    pool: &sqlx::PgPool,
    story_id: Uuid,
    user_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO story_views (story_id, user_id)
           VALUES ($1, $2)
           ON CONFLICT DO NOTHING"#,
    )
    .bind(story_id)
    .bind(user_id)
    .execute(pool)
    .await?;
    Ok(())
}

/// Check if the current user has viewed a story.
pub async fn has_viewed(
    pool: &sqlx::PgPool,
    story_id: Uuid,
    user_id: Uuid,
) -> anyhow::Result<bool> {
    let exists: Option<(bool,)> = sqlx::query_as(
        r#"SELECT EXISTS(
               SELECT 1 FROM story_views WHERE story_id = $1 AND user_id = $2
           )"#,
    )
    .bind(story_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;
    Ok(exists.map(|r| r.0).unwrap_or(false))
}

/// Get the count of views for a story.
pub async fn view_count(
    pool: &sqlx::PgPool,
    story_id: Uuid,
) -> anyhow::Result<i64> {
    let count: (i64,) = sqlx::query_as(
        r#"SELECT COUNT(*) FROM story_views WHERE story_id = $1"#,
    )
    .bind(story_id)
    .fetch_one(pool)
    .await?;
    Ok(count.0)
}

/// Get connected user ids (users who share a conversation, excluding blocks).
pub async fn get_connected_user_ids(
    pool: &sqlx::PgPool,
    user_id: Uuid,
) -> anyhow::Result<Vec<Uuid>> {
    let rows: Vec<(Uuid,)> = sqlx::query_as(
        r#"SELECT DISTINCT cm2.user_id
           FROM conversation_members cm1
           JOIN conversation_members cm2 ON cm2.conversation_id = cm1.conversation_id
           WHERE cm1.user_id = $1
             AND cm2.user_id != $1
             AND cm2.user_id NOT IN (
                 SELECT target_id FROM blocks WHERE user_id = $1
                 UNION
                 SELECT user_id FROM blocks WHERE target_id = $1
             )"#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| r.0).collect())
}
