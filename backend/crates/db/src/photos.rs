//! DB helpers for the profile photo gallery (multi-photo feature).
//!
//! Uses runtime `sqlx::query` / `query_as` (NOT the `query!` macro) so that
//! the crate compiles with `SQLX_OFFLINE=true` without needing a live DB.

use crate::Pool;
use sqlx::FromRow;
use uuid::Uuid;

/// Minimal photo row used by the gallery endpoints.
#[derive(Debug, FromRow)]
pub struct GalleryPhotoRow {
    pub id: Uuid,
    pub r2_key: String,
    pub blur_key: Option<String>,
    pub is_primary: bool,
    pub position: i32,
}

/// Return all profile photos for a user, primary first, then by position.
pub async fn list_user_photos(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Vec<GalleryPhotoRow>> {
    let rows = sqlx::query_as::<_, GalleryPhotoRow>(
        r#"SELECT id, r2_key, blur_key, is_primary, position
           FROM photos
           WHERE user_id = $1
           ORDER BY is_primary DESC, position ASC"#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Count how many profile photos the user already has.
pub async fn count_user_photos(pool: &Pool, user_id: Uuid) -> anyhow::Result<i64> {
    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM photos WHERE user_id = $1")
            .bind(user_id)
            .fetch_one(pool)
            .await?;
    Ok(count)
}

/// Delete a photo that belongs to `user_id`.
///
/// Returns `true` if a row was deleted, `false` if not found / not owned.
///
/// If the deleted photo was the primary, the next photo (lowest position)
/// is promoted to primary and `profiles.profile_photo_key` is synced.
/// If no photos remain, `profiles.profile_photo_key` is cleared.
pub async fn delete_photo(
    pool: &Pool,
    user_id: Uuid,
    photo_id: Uuid,
) -> anyhow::Result<bool> {
    // Fetch the row first so we know if it was primary.
    let row: Option<(bool, String)> = sqlx::query_as(
        "SELECT is_primary, r2_key FROM photos WHERE id = $1 AND user_id = $2",
    )
    .bind(photo_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    let (was_primary, _) = match row {
        Some(r) => r,
        None => return Ok(false),
    };

    let mut tx = pool.begin().await?;

    sqlx::query("DELETE FROM photos WHERE id = $1 AND user_id = $2")
        .bind(photo_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

    if was_primary {
        // Promote the next photo (lowest position) if one exists.
        let next: Option<(Uuid, String)> = sqlx::query_as(
            "SELECT id, r2_key FROM photos WHERE user_id = $1 ORDER BY position ASC LIMIT 1",
        )
        .bind(user_id)
        .fetch_optional(&mut *tx)
        .await?;

        match next {
            Some((next_id, next_key)) => {
                sqlx::query(
                    "UPDATE photos SET is_primary = true WHERE id = $1",
                )
                .bind(next_id)
                .execute(&mut *tx)
                .await?;

                sqlx::query(
                    "UPDATE profiles SET profile_photo_key = $1 WHERE user_id = $2",
                )
                .bind(&next_key)
                .bind(user_id)
                .execute(&mut *tx)
                .await?;
            }
            None => {
                // No photos remain — clear the legacy field.
                sqlx::query(
                    "UPDATE profiles SET profile_photo_key = NULL WHERE user_id = $1",
                )
                .bind(user_id)
                .execute(&mut *tx)
                .await?;
            }
        }
    }

    tx.commit().await?;
    Ok(true)
}

/// Set one photo as primary for the user.
///
/// Uses a transaction:
/// 1. Unset all `is_primary` for the user.
/// 2. Set `is_primary = true` for the given photo (only if it belongs to user).
/// 3. Sync `profiles.profile_photo_key`.
///
/// Returns `true` on success, `false` if the photo doesn't exist or isn't owned
/// by `user_id`.
pub async fn set_primary_photo(
    pool: &Pool,
    user_id: Uuid,
    photo_id: Uuid,
) -> anyhow::Result<bool> {
    // Verify ownership first.
    let r2_key: Option<String> = sqlx::query_scalar(
        "SELECT r2_key FROM photos WHERE id = $1 AND user_id = $2",
    )
    .bind(photo_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    let key = match r2_key {
        Some(k) => k,
        None => return Ok(false),
    };

    let mut tx = pool.begin().await?;

    // Clear all primary flags for this user.
    sqlx::query("UPDATE photos SET is_primary = false WHERE user_id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

    // Set the chosen photo as primary.
    sqlx::query("UPDATE photos SET is_primary = true WHERE id = $1")
        .bind(photo_id)
        .execute(&mut *tx)
        .await?;

    // Sync the legacy field.
    sqlx::query("UPDATE profiles SET profile_photo_key = $1 WHERE user_id = $2")
        .bind(&key)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(true)
}
