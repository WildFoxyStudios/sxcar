//! Vibra Tier 2 backend: boosts, saved phrases, saved places, Roam location pref.
//!
//! All queries use `query!` / `query_as!` macros so that the SQL is checked
//! against the live schema at compile time.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::Pool;

// ---------------------------------------------------------------------------
// Row types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SavedPhraseRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub phrase: String,
    pub position: i32,
    pub created_at: time::OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SavedPlaceRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub is_default: bool,
    pub created_at: time::OffsetDateTime,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoamPrefRow {
    pub user_id: Uuid,
    pub lat: f64,
    pub lon: f64,
    pub place_name: Option<String>,
    pub is_roam: bool,
    pub updated_at: time::OffsetDateTime,
}

// ---------------------------------------------------------------------------
// Boosts
// ---------------------------------------------------------------------------

/// Insert a boost that expires `duration_secs` seconds from now.
/// `source` must be one of 'manual' | 'package' | 'trial'.
/// Returns the boost row id.
pub async fn create_boost(
    pool: &Pool,
    user_id: Uuid,
    duration_secs: i64,
    source: &str,
) -> anyhow::Result<Uuid> {
    let row = sqlx::query!(
        r#"INSERT INTO boosts (user_id, expires_at, source)
           VALUES ($1, now() + ($2::bigint || ' seconds')::interval, $3)
           RETURNING id"#,
        user_id,
        duration_secs,
        source,
    )
    .fetch_one(pool)
    .await?;
    Ok(row.id)
}

/// List active (non-expired) boosts across all users.
/// Returns (user_id, expires_at) pairs for cascade boost overlay.
pub async fn list_active_boosts(
    pool: &Pool,
    now: time::OffsetDateTime,
) -> anyhow::Result<Vec<(Uuid, time::OffsetDateTime)>> {
    let rows = sqlx::query!(
        r#"SELECT user_id, expires_at
           FROM boosts
           WHERE expires_at > $1
           ORDER BY expires_at DESC"#,
        now
    )
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().map(|r| (r.user_id, r.expires_at)).collect())
}

/// True iff the user has at least one non-expired boost.
pub async fn is_user_boosted(
    pool: &Pool,
    user_id: Uuid,
    now: time::OffsetDateTime,
) -> anyhow::Result<bool> {
    let row = sqlx::query!(
        r#"SELECT EXISTS(
             SELECT 1 FROM boosts
             WHERE user_id = $1 AND expires_at > $2
           ) AS "exists!""#,
        user_id,
        now
    )
    .fetch_one(pool)
    .await?;
    Ok(row.exists)
}

// ---------------------------------------------------------------------------
// Saved phrases
// ---------------------------------------------------------------------------

/// List a user's saved phrases ordered by position.
pub async fn list_saved_phrases(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Vec<SavedPhraseRow>> {
    let rows = sqlx::query_as!(
        SavedPhraseRow,
        r#"SELECT id, user_id, phrase, position, created_at
           FROM saved_phrases
           WHERE user_id = $1
           ORDER BY position ASC, created_at ASC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Add a phrase at position = max(existing) + 1.
/// Returns the new phrase id.
pub async fn add_saved_phrase(
    pool: &Pool,
    user_id: Uuid,
    phrase: &str,
) -> anyhow::Result<Uuid> {
    let row = sqlx::query!(
        r#"INSERT INTO saved_phrases (user_id, phrase, position)
           VALUES (
             $1,
             $2,
             COALESCE(
               (SELECT MAX(position) FROM saved_phrases WHERE user_id = $1),
               -1
             ) + 1
           )
           RETURNING id"#,
        user_id,
        phrase
    )
    .fetch_one(pool)
    .await?;
    Ok(row.id)
}

/// Delete a saved phrase owned by the user.
pub async fn delete_saved_phrase(
    pool: &Pool,
    user_id: Uuid,
    phrase_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"DELETE FROM saved_phrases WHERE id = $1 AND user_id = $2"#,
        phrase_id,
        user_id
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// Reorder a user's phrases: the IDs in `ids_in_order` will be assigned
/// positions 0..N-1. Phrases owned by the user that are not listed are left
/// with their existing positions (caller is responsible for completeness).
pub async fn reorder_saved_phrases(
    pool: &Pool,
    user_id: Uuid,
    ids_in_order: &[Uuid],
) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    for (idx, pid) in ids_in_order.iter().enumerate() {
        sqlx::query!(
            r#"UPDATE saved_phrases
               SET position = $3
               WHERE id = $1 AND user_id = $2"#,
            pid,
            user_id,
            idx as i32,
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Saved places
// ---------------------------------------------------------------------------

/// List a user's saved places ordered by is_default DESC, created_at ASC.
pub async fn list_saved_places(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Vec<SavedPlaceRow>> {
    let rows = sqlx::query_as!(
        SavedPlaceRow,
        r#"SELECT id, user_id, name, lat, lon, is_default, created_at
           FROM saved_places
           WHERE user_id = $1
           ORDER BY is_default DESC, created_at ASC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Add a saved place. Returns the new place id.
pub async fn add_saved_place(
    pool: &Pool,
    user_id: Uuid,
    name: &str,
    lat: f64,
    lon: f64,
) -> anyhow::Result<Uuid> {
    let row = sqlx::query!(
        r#"INSERT INTO saved_places (user_id, name, lat, lon)
           VALUES ($1, $2, $3, $4)
           RETURNING id"#,
        user_id,
        name,
        lat,
        lon,
    )
    .fetch_one(pool)
    .await?;
    Ok(row.id)
}

/// Delete a saved place owned by the user.
pub async fn delete_saved_place(
    pool: &Pool,
    user_id: Uuid,
    place_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"DELETE FROM saved_places WHERE id = $1 AND user_id = $2"#,
        place_id,
        user_id
    )
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Roam (user_location_pref)
// ---------------------------------------------------------------------------

/// Get the user's current roam preference, if any.
pub async fn get_roam_pref(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Option<RoamPrefRow>> {
    let row = sqlx::query_as!(
        RoamPrefRow,
        r#"SELECT user_id, lat, lon, place_name, is_roam, updated_at
           FROM user_location_pref
           WHERE user_id = $1"#,
        user_id
    )
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Upsert the user's roam preference.
pub async fn set_roam_pref(
    pool: &Pool,
    user_id: Uuid,
    lat: f64,
    lon: f64,
    place_name: Option<&str>,
    is_roam: bool,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"INSERT INTO user_location_pref
             (user_id, lat, lon, place_name, is_roam, updated_at)
           VALUES ($1, $2, $3, $4, $5, now())
           ON CONFLICT (user_id) DO UPDATE SET
             lat        = EXCLUDED.lat,
             lon        = EXCLUDED.lon,
             place_name = EXCLUDED.place_name,
             is_roam    = EXCLUDED.is_roam,
             updated_at = now()"#,
        user_id,
        lat,
        lon,
        place_name,
        is_roam,
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// Clear (delete) the user's roam preference.
pub async fn clear_roam_pref(pool: &Pool, user_id: Uuid) -> anyhow::Result<()> {
    sqlx::query!(
        r#"DELETE FROM user_location_pref WHERE user_id = $1"#,
        user_id
    )
    .execute(pool)
    .await?;
    Ok(())
}