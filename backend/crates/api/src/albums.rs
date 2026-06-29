use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::AppState;

// ---------------------------------------------------------------------------
// Request / Response types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct CreateAlbumReq {
    pub name: String,
    pub description: Option<String>,
    pub is_private: bool,
}

#[derive(Serialize)]
pub struct AlbumResponse {
    pub id: Uuid,
    pub name: Option<String>,
    pub description: Option<String>,
    pub is_private: bool,
    pub photo_count: i64,
    pub cover_photo_url: Option<String>,
    pub created_at: String,
}

impl AlbumResponse {
    fn from_row(row: db::albums::AlbumRow) -> Self {
        Self {
            id: row.id,
            name: row.name,
            description: row.description,
            is_private: row.is_private,
            photo_count: row.photo_count.unwrap_or(0),
            cover_photo_url: row.cover_photo_url,
            created_at: row.created_at.to_string(),
        }
    }
}

#[derive(Serialize)]
pub struct ListAlbumsResponse {
    pub albums: Vec<AlbumResponse>,
}

#[derive(Serialize)]
pub struct CreateAlbumResponse {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub is_private: bool,
}

#[derive(Deserialize)]
pub struct UpdateAlbumReq {
    pub name: Option<String>,
    pub description: Option<String>,
    pub is_private: Option<bool>,
}

#[derive(Deserialize)]
pub struct AddPhotosReq {
    pub photo_keys: Vec<String>,
}

#[derive(Serialize)]
pub struct AddPhotosResponse {
    pub added: i64,
}

#[derive(Serialize)]
pub struct AlbumPhotoResponse {
    pub id: Uuid,
    pub r2_key: String,
    pub blur_key: Option<String>,
    pub is_nsfw: bool,
    pub position: i32,
}

#[derive(Serialize)]
pub struct GetAlbumResponse {
    pub album: AlbumResponse,
    pub photos: Vec<AlbumPhotoResponse>,
}

#[derive(Deserialize)]
pub struct ShareReq {
    pub user_id: Uuid,
    pub expires_at: Option<String>,
}

#[derive(Serialize)]
pub struct ShareResponse {
    pub album_id: Uuid,
    pub shared_with_user_id: Uuid,
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// GET /albums — list albums owned by the authenticated user.
pub async fn list(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<ListAlbumsResponse>, StatusCode> {
    let rows = db::albums::list_albums(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_albums error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    let albums: Vec<AlbumResponse> = rows.into_iter().map(AlbumResponse::from_row).collect();
    Ok(Json(ListAlbumsResponse { albums }))
}

/// POST /albums — create a new album.
pub async fn create(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<CreateAlbumReq>,
) -> Result<(StatusCode, Json<CreateAlbumResponse>), StatusCode> {
    if req.name.trim().is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    let id = db::albums::create_album(
        &state.pool,
        user_id,
        req.name.trim(),
        req.description.as_deref(),
        req.is_private,
    )
    .await
    .map_err(|e| {
        tracing::error!("create_album error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;
    Ok((
        StatusCode::CREATED,
        Json(CreateAlbumResponse {
            id,
            name: req.name.trim().to_string(),
            description: req.description,
            is_private: req.is_private,
        }),
    ))
}

/// PUT /albums/:id — update album.
pub async fn update(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(album_id): Path<Uuid>,
    Json(req): Json<UpdateAlbumReq>,
) -> StatusCode {
    match db::albums::update_album(
        &state.pool,
        album_id,
        user_id,
        req.name.as_deref(),
        req.description.as_deref(),
        req.is_private,
    )
    .await
    {
        Ok(true) => StatusCode::OK,
        Ok(false) => StatusCode::NOT_FOUND,
        Err(e) => {
            tracing::error!("update_album error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}

/// DELETE /albums/:id — delete album (cascades album_photos).
pub async fn delete(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(album_id): Path<Uuid>,
) -> StatusCode {
    match db::albums::delete_album(&state.pool, album_id, user_id).await {
        Ok(true) => StatusCode::NO_CONTENT,
        Ok(false) => StatusCode::NOT_FOUND,
        Err(e) => {
            tracing::error!("delete_album error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}

/// GET /albums/:id — get album with photos.
pub async fn get(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(album_id): Path<Uuid>,
) -> Result<Json<GetAlbumResponse>, StatusCode> {
    let row = db::albums::get_album(&state.pool, album_id)
        .await
        .map_err(|e| {
            tracing::error!("get_album error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    // Only owner or shared user can see
    if row.owner_id != user_id {
        return Err(StatusCode::FORBIDDEN);
    }

    let photos = db::albums::get_album_photos(&state.pool, album_id)
        .await
        .map_err(|e| {
            tracing::error!("get_album_photos error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let photos_resp: Vec<AlbumPhotoResponse> = photos
        .into_iter()
        .map(|p| AlbumPhotoResponse {
            id: p.id,
            r2_key: p.r2_key,
            blur_key: p.blur_key,
            is_nsfw: p.is_nsfw,
            position: p.position,
        })
        .collect();

    Ok(Json(GetAlbumResponse {
        album: AlbumResponse::from_row(row),
        photos: photos_resp,
    }))
}

/// POST /albums/:id/photos — add photos to album.
pub async fn add_photos(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(album_id): Path<Uuid>,
    Json(req): Json<AddPhotosReq>,
) -> Result<(StatusCode, Json<AddPhotosResponse>), StatusCode> {
    if req.photo_keys.is_empty() {
        return Ok((StatusCode::OK, Json(AddPhotosResponse { added: 0 })));
    }

    // Verify ownership
    let album = db::albums::get_album(&state.pool, album_id)
        .await
        .map_err(|e| {
            tracing::error!("get_album error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    if album.owner_id != user_id {
        return Err(StatusCode::FORBIDDEN);
    }

    let added = db::albums::add_photos_to_album(&state.pool, album_id, user_id, &req.photo_keys)
        .await
        .map_err(|e| {
            tracing::error!("add_photos_to_album error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok((StatusCode::OK, Json(AddPhotosResponse { added })))
}

/// DELETE /albums/:id/photos/:photo_id — remove photo from album.
pub async fn remove_photo(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path((album_id, photo_id)): Path<(Uuid, Uuid)>,
) -> StatusCode {
    // Verify ownership
    let album = match db::albums::get_album(&state.pool, album_id).await {
        Ok(Some(a)) => a,
        Ok(None) => return StatusCode::NOT_FOUND,
        Err(e) => {
            tracing::error!("get_album error: {e}");
            return StatusCode::INTERNAL_SERVER_ERROR;
        }
    };

    if album.owner_id != user_id {
        return StatusCode::FORBIDDEN;
    }

    match db::albums::remove_photo_from_album(&state.pool, album_id, photo_id).await {
        Ok(true) => StatusCode::NO_CONTENT,
        Ok(false) => StatusCode::NOT_FOUND,
        Err(e) => {
            tracing::error!("remove_photo_from_album error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}

/// POST /albums/:id/share — share album with another user.
pub async fn share(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(album_id): Path<Uuid>,
    Json(req): Json<ShareReq>,
) -> Result<(StatusCode, Json<ShareResponse>), StatusCode> {
    // Verify ownership
    let album = db::albums::get_album(&state.pool, album_id)
        .await
        .map_err(|e| {
            tracing::error!("get_album error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    if album.owner_id != user_id {
        return Err(StatusCode::FORBIDDEN);
    }

    let expires_at = match req.expires_at {
        Some(ref s) => Some(
            time::OffsetDateTime::parse(s, &time::format_description::well_known::Rfc3339)
                .map_err(|_| StatusCode::BAD_REQUEST)?,
        ),
        None => None,
    };

    db::albums::share_album(&state.pool, album_id, req.user_id, expires_at)
        .await
        .map_err(|e| {
            tracing::error!("share_album error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok((
        StatusCode::CREATED,
        Json(ShareResponse {
            album_id,
            shared_with_user_id: req.user_id,
        }),
    ))
}

/// DELETE /albums/:id/share/:user_id — unshare album.
pub async fn unshare(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path((album_id, target_user_id)): Path<(Uuid, Uuid)>,
) -> StatusCode {
    // Verify ownership
    let album = match db::albums::get_album(&state.pool, album_id).await {
        Ok(Some(a)) => a,
        Ok(None) => return StatusCode::NOT_FOUND,
        Err(e) => {
            tracing::error!("get_album error: {e}");
            return StatusCode::INTERNAL_SERVER_ERROR;
        }
    };

    if album.owner_id != user_id {
        return StatusCode::FORBIDDEN;
    }

    match db::albums::unshare_album(&state.pool, album_id, target_user_id).await {
        Ok(true) => StatusCode::NO_CONTENT,
        Ok(false) => StatusCode::NOT_FOUND,
        Err(e) => {
            tracing::error!("unshare_album error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}

/// GET /albums/shared — albums shared with the authenticated user.
pub async fn shared(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<ListAlbumsResponse>, StatusCode> {
    let rows = db::albums::list_shared_albums(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_shared_albums error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    let albums: Vec<AlbumResponse> = rows.into_iter().map(AlbumResponse::from_row).collect();
    Ok(Json(ListAlbumsResponse { albums }))
}
