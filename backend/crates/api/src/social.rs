//! Social interactions: Taps, Favorites, Blocks.
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
// Shared helpers
// ---------------------------------------------------------------------------

/// Check if the current user has blocked the target (or vice versa).
/// Returns 403 if blocked.
async fn check_not_blocked(state: &AppState, current_user: Uuid, target_user: Uuid) -> Result<(), StatusCode> {
    if db::social::is_blocked(&state.pool, current_user, target_user)
        .await
        .map_err(|e| {
            tracing::error!("is_blocked error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })? {
        return Err(StatusCode::FORBIDDEN);
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Taps
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct CreateTapRequest {
    pub to_user_id: Uuid,
    pub tap_type: String,
}

#[derive(Serialize)]
pub struct CreateTapResponse {
    pub id: String,
}

#[derive(Serialize)]
pub struct TapResponse {
    pub id: String,
    pub from_user_id: String,
    pub from_display_name: Option<String>,
    pub tap_type: Option<String>,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct TapListResponse {
    pub taps: Vec<TapResponse>,
}

/// POST /taps
pub async fn create_tap(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<CreateTapRequest>,
) -> Result<(StatusCode, Json<CreateTapResponse>), StatusCode> {
    if req.to_user_id == user_id {
        return Err(StatusCode::BAD_REQUEST);
    }
    // Validate tap_type
    match req.tap_type.as_str() {
        "fire" | "wave" | "smile" | "hello" => {}
        _ => return Err(StatusCode::BAD_REQUEST),
    }

    check_not_blocked(&state, user_id, req.to_user_id).await?;

    let id = db::social::create_tap(&state.pool, user_id, req.to_user_id, &req.tap_type)
        .await
        .map_err(|e| {
            tracing::error!("create_tap error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // TODO: send push notification to recipient (stub)
    tracing::info!("tap from {user_id} to {} (type: {})", req.to_user_id, req.tap_type);

    Ok((
        StatusCode::CREATED,
        Json(CreateTapResponse {
            id: id.to_string(),
        }),
    ))
}

/// GET /taps/received
pub async fn list_taps_received(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<TapListResponse>, StatusCode> {
    let rows = db::social::list_taps_received(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_taps_received error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let taps = rows
        .into_iter()
        .map(|r| TapResponse {
            id: r.id.to_string(),
            from_user_id: r.from_user.to_string(),
            from_display_name: r.display_name,
            tap_type: r.tap_type,
            created_at: r
                .created_at
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default(),
        })
        .collect();

    Ok(Json(TapListResponse { taps }))
}

/// GET /taps/sent
pub async fn list_taps_sent(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<TapListResponse>, StatusCode> {
    let rows = db::social::list_taps_sent(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_taps_sent error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let taps = rows
        .into_iter()
        .map(|r| TapResponse {
            id: r.id.to_string(),
            from_user_id: r.from_user.to_string(),
            from_display_name: r.display_name,
            tap_type: r.tap_type,
            created_at: r
                .created_at
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default(),
        })
        .collect();

    Ok(Json(TapListResponse { taps }))
}

// ---------------------------------------------------------------------------
// Favorites
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct AddFavoriteRequest {
    pub user_id: Uuid,
}

#[derive(Serialize)]
pub struct FavoriteListResponse {
    pub favorites: Vec<FavoriteJson>,
}

#[derive(Serialize)]
pub struct FavoriteJson {
    pub user_id: String,
    pub display_name: Option<String>,
    pub created_at: String,
}

/// POST /favorites
pub async fn add_favorite(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<AddFavoriteRequest>,
) -> Result<StatusCode, StatusCode> {
    if req.user_id == user_id {
        return Err(StatusCode::BAD_REQUEST);
    }
    check_not_blocked(&state, user_id, req.user_id).await?;

    db::social::add_favorite(&state.pool, user_id, req.user_id)
        .await
        .map_err(|e| {
            tracing::error!("add_favorite error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(StatusCode::CREATED)
}

/// DELETE /favorites/:user_id
pub async fn remove_favorite(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(target_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    db::social::remove_favorite(&state.pool, user_id, target_id)
        .await
        .map_err(|e| {
            tracing::error!("remove_favorite error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(StatusCode::NO_CONTENT)
}

/// GET /favorites
pub async fn list_favorites(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<FavoriteListResponse>, StatusCode> {
    let rows = db::social::list_favorites(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_favorites error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let favorites = rows
        .into_iter()
        .map(|r| FavoriteJson {
            user_id: r.target_id.to_string(),
            display_name: r.display_name,
            created_at: r
                .created_at
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default(),
        })
        .collect();

    Ok(Json(FavoriteListResponse { favorites }))
}

// ---------------------------------------------------------------------------
// Blocks
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct BlockUserRequest {
    pub user_id: Uuid,
    pub reason: Option<String>,
}

#[derive(Serialize)]
pub struct BlockListResponse {
    pub blocks: Vec<BlockJson>,
}

#[derive(Serialize)]
pub struct BlockJson {
    pub user_id: String,
    pub display_name: Option<String>,
    pub reason: Option<String>,
    pub created_at: String,
}

/// POST /blocks
pub async fn block_user(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<BlockUserRequest>,
) -> Result<StatusCode, StatusCode> {
    if req.user_id == user_id {
        return Err(StatusCode::BAD_REQUEST);
    }

    // Block the user
    db::social::block_user(&state.pool, user_id, req.user_id, req.reason.as_deref())
        .await
        .map_err(|e| {
            tracing::error!("block_user error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // Delete any existing conversation between the two users
    db::social::delete_conversation_between(&state.pool, user_id, req.user_id)
        .await
        .map_err(|e| {
            tracing::error!("delete_conversation_between error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(StatusCode::CREATED)
}

/// DELETE /blocks/:user_id
pub async fn unblock_user(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(target_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    db::social::unblock_user(&state.pool, user_id, target_id)
        .await
        .map_err(|e| {
            tracing::error!("unblock_user error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(StatusCode::NO_CONTENT)
}

/// GET /blocks
pub async fn list_blocks(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<BlockListResponse>, StatusCode> {
    let rows = db::social::list_blocks(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_blocks error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let blocks = rows
        .into_iter()
        .map(|r| BlockJson {
            user_id: r.target_id.to_string(),
            display_name: r.display_name,
            reason: r.reason,
            created_at: r
                .created_at
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default(),
        })
        .collect();

    Ok(Json(BlockListResponse { blocks }))
}
