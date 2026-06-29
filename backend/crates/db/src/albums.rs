use crate::Pool;
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, FromRow, serde::Serialize)]
pub struct AlbumRow {
    pub id: Uuid,
    pub owner_id: Uuid,
    pub name: Option<String>,
    pub description: Option<String>,
    pub is_private: bool,
    pub created_at: time::OffsetDateTime,
    pub photo_count: Option<i64>,
    pub cover_photo_url: Option<String>,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct PhotoRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub r2_key: String,
    pub blur_key: Option<String>,
    pub position: i32,
    pub is_primary: bool,
    pub is_nsfw: bool,
    pub moderation_status: String,
    pub width: Option<i32>,
    pub height: Option<i32>,
    pub created_at: time::OffsetDateTime,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct AlbumPhotoRow {
    pub album_id: Uuid,
    pub photo_id: Uuid,
    pub position: i32,
}

/// List all albums owned by the user, with photo count and optional cover photo.
pub async fn list_albums(pool: &Pool, user_id: Uuid) -> anyhow::Result<Vec<AlbumRow>> {
    let rows = sqlx::query_as::<_, AlbumRow>(
        r#"
        SELECT a.id, a.owner_id, a.name, a.description, a.is_private, a.created_at,
               COUNT(ap.photo_id) AS photo_count,
               (SELECT p.r2_key FROM album_photos ap2
                JOIN photos p ON p.id = ap2.photo_id
                WHERE ap2.album_id = a.id
                ORDER BY ap2.position LIMIT 1) AS cover_photo_url
        FROM albums a
        LEFT JOIN album_photos ap ON ap.album_id = a.id
        WHERE a.owner_id = $1
        GROUP BY a.id
        ORDER BY a.created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Create a new album. Returns the new album ID.
pub async fn create_album(
    pool: &Pool,
    user_id: Uuid,
    name: &str,
    description: Option<&str>,
    is_private: bool,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"
        INSERT INTO albums (owner_id, name, description, is_private)
        VALUES ($1, $2, $3, $4)
        RETURNING id
        "#,
    )
    .bind(user_id)
    .bind(name)
    .bind(description)
    .bind(is_private)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

/// Update album fields. Only non-None fields are updated.
pub async fn update_album(
    pool: &Pool,
    id: Uuid,
    owner_id: Uuid,
    name: Option<&str>,
    description: Option<&str>,
    is_private: Option<bool>,
) -> anyhow::Result<bool> {
    let result = sqlx::query(
        r#"
        UPDATE albums
        SET name = COALESCE($3, name),
            description = COALESCE($4, description),
            is_private = COALESCE($5, is_private)
        WHERE id = $1 AND owner_id = $2
        "#,
    )
    .bind(id)
    .bind(owner_id)
    .bind(name)
    .bind(description)
    .bind(is_private)
    .execute(pool)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Delete an album (cascades to album_photos). Returns true if deleted.
pub async fn delete_album(pool: &Pool, id: Uuid, owner_id: Uuid) -> anyhow::Result<bool> {
    let result = sqlx::query("DELETE FROM albums WHERE id = $1 AND owner_id = $2")
        .bind(id)
        .bind(owner_id)
        .execute(pool)
        .await?;
    Ok(result.rows_affected() > 0)
}

/// Get a single album by ID. Returns None if not found.
pub async fn get_album(pool: &Pool, id: Uuid) -> anyhow::Result<Option<AlbumRow>> {
    let row = sqlx::query_as::<_, AlbumRow>(
        r#"
        SELECT a.id, a.owner_id, a.name, a.description, a.is_private, a.created_at,
               (SELECT COUNT(*) FROM album_photos WHERE album_id = a.id) AS photo_count,
               (SELECT p.r2_key FROM album_photos ap2
                JOIN photos p ON p.id = ap2.photo_id
                WHERE ap2.album_id = a.id
                ORDER BY ap2.position LIMIT 1) AS cover_photo_url
        FROM albums a
        WHERE a.id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Get all photos in an album, ordered by position.
pub async fn get_album_photos(pool: &Pool, album_id: Uuid) -> anyhow::Result<Vec<PhotoRow>> {
    let rows = sqlx::query_as::<_, PhotoRow>(
        r#"
        SELECT p.id, p.user_id, p.r2_key, p.blur_key,
               ap.position, p.is_primary, p.is_nsfw,
               p.moderation_status, p.width, p.height, p.created_at
        FROM photos p
        JOIN album_photos ap ON ap.photo_id = p.id
        WHERE ap.album_id = $1
        ORDER BY ap.position ASC
        "#,
    )
    .bind(album_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Add multiple photos to an album. Each r2_key creates a new photo entry,
/// then links it to the album. Wrapped in a transaction.
/// Returns the number of photos added.
pub async fn add_photos_to_album(
    pool: &Pool,
    album_id: Uuid,
    user_id: Uuid,
    r2_keys: &[String],
) -> anyhow::Result<i64> {
    if r2_keys.is_empty() {
        return Ok(0);
    }

    let mut tx = pool.begin().await?;
    let mut count: i64 = 0;

    for key in r2_keys {
        let photo_id: Uuid = sqlx::query_scalar(
            "INSERT INTO photos (user_id, r2_key) VALUES ($1, $2) RETURNING id",
        )
        .bind(user_id)
        .bind(key)
        .fetch_one(&mut *tx)
        .await?;

        sqlx::query(
            "INSERT INTO album_photos (album_id, photo_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
        )
        .bind(album_id)
        .bind(photo_id)
        .execute(&mut *tx)
        .await?;

        count += 1;
    }

    tx.commit().await?;
    Ok(count)
}

/// Remove a photo from an album. Does NOT delete the photo itself.
pub async fn remove_photo_from_album(
    pool: &Pool,
    album_id: Uuid,
    photo_id: Uuid,
) -> anyhow::Result<bool> {
    let result = sqlx::query("DELETE FROM album_photos WHERE album_id = $1 AND photo_id = $2")
        .bind(album_id)
        .bind(photo_id)
        .execute(pool)
        .await?;
    Ok(result.rows_affected() > 0)
}

/// Share an album with another user.
pub async fn share_album(
    pool: &Pool,
    album_id: Uuid,
    shared_with_user_id: Uuid,
    expires_at: Option<time::OffsetDateTime>,
) -> anyhow::Result<bool> {
    let result = sqlx::query(
        r#"
        INSERT INTO album_shares (album_id, shared_with_user_id, expires_at)
        VALUES ($1, $2, $3)
        ON CONFLICT (album_id, shared_with_user_id)
        DO UPDATE SET revoked_at = NULL, expires_at = COALESCE($3, album_shares.expires_at), granted_at = now()
        "#,
    )
    .bind(album_id)
    .bind(shared_with_user_id)
    .bind(expires_at)
    .execute(pool)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// Unshare an album (sets revoked_at instead of deleting).
pub async fn unshare_album(
    pool: &Pool,
    album_id: Uuid,
    shared_with_user_id: Uuid,
) -> anyhow::Result<bool> {
    let result = sqlx::query(
        r#"
        UPDATE album_shares
        SET revoked_at = now()
        WHERE album_id = $1 AND shared_with_user_id = $2 AND revoked_at IS NULL
        "#,
    )
    .bind(album_id)
    .bind(shared_with_user_id)
    .execute(pool)
    .await?;
    Ok(result.rows_affected() > 0)
}

/// List albums shared with this user (not revoked, not expired).
pub async fn list_shared_albums(pool: &Pool, user_id: Uuid) -> anyhow::Result<Vec<AlbumRow>> {
    let rows = sqlx::query_as::<_, AlbumRow>(
        r#"
        SELECT a.id, a.owner_id, a.name, a.description, a.is_private, a.created_at,
               COUNT(ap.photo_id) AS photo_count,
               (SELECT p.r2_key FROM album_photos ap2
                JOIN photos p ON p.id = ap2.photo_id
                WHERE ap2.album_id = a.id
                ORDER BY ap2.position LIMIT 1) AS cover_photo_url
        FROM albums a
        JOIN album_shares s ON s.album_id = a.id
        LEFT JOIN album_photos ap ON ap.album_id = a.id
        WHERE s.shared_with_user_id = $1
          AND s.revoked_at IS NULL
          AND (s.expires_at IS NULL OR s.expires_at > now())
        GROUP BY a.id
        ORDER BY a.created_at DESC
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}
