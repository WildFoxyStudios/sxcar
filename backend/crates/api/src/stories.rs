//! Stories: ephemeral photo/video with 24h expiry.
//!
//! All endpoints require authentication via Bearer token.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::AppState;

// ---------------------------------------------------------------------------
// Request / Response types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct CreateStoryRequest {
    /// R2 key of the uploaded media (e.g. "story/uuid/uuid.jpg").
    pub media_key: String,
    /// "photo" or "video".
    pub media_type: String,
    pub caption: Option<String>,
}

#[derive(Serialize)]
pub struct CreateStoryResponse {
    pub id: Uuid,
}

#[derive(Serialize, Clone)]
pub struct StoryJson {
    pub id: Uuid,
    pub user_id: Uuid,
    pub media_key: String,
    pub media_type: String,
    pub caption: Option<String>,
    pub display_name: Option<String>,
    pub avatar_key: Option<String>,
    pub created_at: String,
    pub expires_at: String,
    pub viewed: bool,
    pub view_count: i64,
}

#[derive(Serialize)]
pub struct StoryListResponse {
    pub stories: Vec<StoryJson>,
    /// Grouped by user_id so the client can display "stories by user"
    pub grouped: Vec<StoryGroupJson>,
}

#[derive(Serialize)]
pub struct StoryGroupJson {
    pub user_id: Uuid,
    pub display_name: Option<String>,
    pub avatar_key: Option<String>,
    pub stories: Vec<StoryJson>,
    pub all_viewed: bool,
}

// ---------------------------------------------------------------------------
// POST /stories
// ---------------------------------------------------------------------------

/// Create a new story. The client must first upload media to R2 via
/// `POST /media/upload-url` (kind="story") then pass the resulting key here.
pub async fn create_story(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<CreateStoryRequest>,
) -> Result<(StatusCode, Json<CreateStoryResponse>), StatusCode> {
    // Validate media_type
    match req.media_type.as_str() {
        "photo" | "video" => {}
        _ => return Err(StatusCode::BAD_REQUEST),
    }

    if req.media_key.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    // SECURITY (P1): `media_key` is stored verbatim and later handed to
    // `get_url` (kind=story) for presigning. Story upload keys are minted by
    // `POST /media/upload-url` (kind=story) as `story/<owner-user-id>/<uuid>.<ext>`.
    // Require the caller's id in the owner position so an attacker can't publish
    // a story that points at another user's / arbitrary R2 object. Also reject
    // path traversal.
    let owned_prefix = format!("story/{user_id}/");
    if req.media_key.contains("..") || !req.media_key.starts_with(&owned_prefix) {
        return Err(StatusCode::FORBIDDEN);
    }

    let id = db::stories::create_story(
        &state.pool,
        user_id,
        &req.media_key,
        &req.media_type,
        req.caption.as_deref(),
    )
    .await
    .map_err(|e| {
        tracing::error!("create_story error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok((
        StatusCode::CREATED,
        Json(CreateStoryResponse { id }),
    ))
}

// ---------------------------------------------------------------------------
// GET /stories
// ---------------------------------------------------------------------------

/// Get active stories for the current user and their connected users.
/// Optionally filtered by `include_expired=false` (default).
pub async fn list_stories(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<StoryListResponse>, StatusCode> {
    // Get connected user ids
    let mut user_ids = db::stories::get_connected_user_ids(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_connected_user_ids error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // Always include own stories
    user_ids.push(user_id);

    // Get active stories for all these users
    let rows = db::stories::get_active_stories(&state.pool, &user_ids)
        .await
        .map_err(|e| {
            tracing::error!("get_active_stories error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // PERFORMANCE: batch the per-story `has_viewed` + `view_count` lookups
    // (previously 2 queries × N stories = 2N round-trips) into 2 batched
    // queries total using ANY($1) + GROUP BY story_id.
    let story_ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();

    // 1) which stories the caller has viewed
    let mut viewed_set: std::collections::HashSet<Uuid> = std::collections::HashSet::new();
    if !story_ids.is_empty() {
        let viewed_rows: Vec<(Uuid,)> = sqlx::query_as(
            r#"SELECT DISTINCT story_id FROM story_views
               WHERE user_id = $1 AND story_id = ANY($2)"#,
        )
        .bind(user_id)
        .bind(&story_ids)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default();
        viewed_set = viewed_rows.into_iter().map(|r| r.0).collect();
    }

    // 2) view counts per story
    let mut view_counts: std::collections::HashMap<Uuid, i64> =
        std::collections::HashMap::new();
    if !story_ids.is_empty() {
        let count_rows: Vec<(Uuid, i64)> = sqlx::query_as(
            r#"SELECT story_id, COUNT(*)::int8 AS cnt FROM story_views
               WHERE story_id = ANY($1) GROUP BY story_id"#,
        )
        .bind(&story_ids)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default();
        view_counts = count_rows.into_iter().map(|r| (r.0, r.1)).collect();
    }

    // Build response with viewed status
    let mut user_stories: Vec<StoryJson> = Vec::new();
    let mut last_user_id: Option<Uuid> = None;
    let mut groups: Vec<StoryGroupJson> = Vec::new();

    for row in rows {
        let has_viewed = viewed_set.contains(&row.id);
        let count = view_counts.get(&row.id).copied().unwrap_or(0);

        let sj = StoryJson {
            id: row.id,
            user_id: row.user_id,
            media_key: row.media_key,
            media_type: row.media_type,
            caption: row.caption,
            display_name: row.display_name.clone(),
            avatar_key: row.avatar_key.clone(),
            created_at: row
                .created_at
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default(),
            expires_at: row
                .expires_at
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default(),
            viewed: has_viewed,
            view_count: count,
        };

        // Group by user
        if last_user_id != Some(row.user_id) {
            // Finalize previous group
            if !user_stories.is_empty() {
                let all_viewed = user_stories.iter().all(|s| s.viewed);
                groups.push(StoryGroupJson {
                    user_id: last_user_id.unwrap(),
                    display_name: user_stories[0].display_name.clone(),
                    avatar_key: user_stories[0].avatar_key.clone(),
                    stories: user_stories,
                    all_viewed,
                });
                user_stories = Vec::new();
            }
            last_user_id = Some(row.user_id);
        }

        user_stories.push(sj);
    }

    // Finalize last group
    if !user_stories.is_empty() {
        let all_viewed = user_stories.iter().all(|s| s.viewed);
        if let Some(uid) = last_user_id {
            groups.push(StoryGroupJson {
                user_id: uid,
                display_name: user_stories[0].display_name.clone(),
                avatar_key: user_stories[0].avatar_key.clone(),
                stories: user_stories,
                all_viewed,
            });
        }
    }

    // Flatten all stories into a single list too
    let all_stories: Vec<StoryJson> = groups
        .iter()
        .flat_map(|g| g.stories.clone())
        .collect();

    Ok(Json(StoryListResponse {
        stories: all_stories,
        grouped: groups,
    }))
}

// ---------------------------------------------------------------------------
// DELETE /stories/:id
// ---------------------------------------------------------------------------

/// Delete your own story.
pub async fn delete_story(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(story_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    let rows = db::stories::delete_story(&state.pool, story_id, user_id)
        .await
        .map_err(|e| {
            tracing::error!("delete_story error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if rows == 0 {
        return Err(StatusCode::NOT_FOUND);
    }

    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------
// GET /stories/:id/view
// ---------------------------------------------------------------------------

/// Mark a story as viewed by the current user. Idempotent.
pub async fn view_story(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(story_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    // Verify story exists
    let story = db::stories::get_story_by_id(&state.pool, story_id)
        .await
        .map_err(|e| {
            tracing::error!("get_story_by_id error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    match story {
        Some(s) => {
            // Don't count own views
            if s.user_id == user_id {
                return Ok(StatusCode::OK);
            }
        }
        None => return Err(StatusCode::NOT_FOUND),
    }

    db::stories::mark_viewed(&state.pool, story_id, user_id)
        .await
        .map_err(|e| {
            tracing::error!("mark_viewed error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(StatusCode::OK)
}
