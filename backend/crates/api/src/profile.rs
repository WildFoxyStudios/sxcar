use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use serde::Deserialize;
use serde_json::{json, Value};

use crate::auth::AuthUser;
use crate::AppState;

/// Convierte UserFullRow + arrays opcionales a un Value JSON completo.
fn user_full_to_json(
    u: db::users::UserFullRow,
    tribes: Vec<String>,
    looking_for: Vec<String>,
    meet_at: Vec<String>,
    tags: Vec<String>,
) -> Value {
    json!({
        "id": u.id,
        "email": u.email,
        "email_verified": u.email_verified,
        "verified": u.verified,
        "status": u.status,
        "role": u.role,
        "created_at": u.created_at.to_string(),
        "display_name": u.display_name,
        "bio": u.bio,
        "birthdate": u.birthdate.map(|d| d.to_string()),
        "height_cm": u.height_cm,
        "weight_kg": u.weight_kg,
        "body_type": u.body_type,
        "relationship_status": u.relationship_status,
        "position": u.position,
        "ethnicity": u.ethnicity,
        "pronouns": u.pronouns,
        "profile_photo_id": u.profile_photo_id,
        "profile_photo_url": u.profile_photo_url,
        "tribes": tribes,
        "looking_for": looking_for,
        "meet_at": meet_at,
        "tags": tags,
    })
}

/// Recupera el perfil completo del usuario autenticado.
///
/// GET /profile
pub async fn get_own(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let user = db::users::find_user_full(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("find_user_full error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    let tribes = db::profiles::get_profile_tribes(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_tribes error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let looking_for = db::profiles::get_profile_looking_for(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_looking_for error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let meet_at = db::profiles::get_profile_meet_at(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_meet_at error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let tags = db::profiles::get_profile_tags(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_tags error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "user": user_full_to_json(user, tribes, looking_for, meet_at, tags)
    })))
}

// ---------------------------------------------------------------------------
// PUT /profile
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct UpdateProfileReq {
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub birthdate: Option<String>, // YYYY-MM-DD
    pub height_cm: Option<i32>,
    pub weight_kg: Option<i32>,
    pub body_type: Option<String>,
    pub relationship_status: Option<String>,
    pub position: Option<String>,
    pub ethnicity: Option<String>,
    pub pronouns: Option<String>,
    pub tribes: Option<Vec<String>>,
    pub looking_for: Option<Vec<String>>,
    pub meet_at: Option<Vec<String>>,
    pub tags: Option<Vec<String>>,
}

/// Actualiza el perfil del usuario autenticado.
///
/// PUT /profile
pub async fn update_own(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(body): Json<UpdateProfileReq>,
) -> Result<Json<Value>, StatusCode> {
    // Parse birthdate string → time::Date
    let birthdate = match &body.birthdate {
        Some(s) => {
            let fmt = time::format_description::parse_borrowed::<2>("[year]-[month]-[day]")
                .map_err(|_| StatusCode::BAD_REQUEST)?;
            Some(time::Date::parse(s, &fmt).map_err(|_| StatusCode::BAD_REQUEST)?)
        }
        None => None,
    };

    db::profiles::upsert_profile(
        &state.pool,
        user_id,
        body.display_name.as_deref(),
        body.bio.as_deref(),
        birthdate,
        body.height_cm,
        body.weight_kg,
        body.body_type.as_deref(),
        body.relationship_status.as_deref(),
        body.position.as_deref(),
        body.ethnicity.as_deref(),
        body.pronouns.as_deref(),
    )
    .await
    .map_err(|e| {
        tracing::error!("upsert_profile error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    // Replace junction tables
    if let Some(tribes) = &body.tribes {
        db::profiles::replace_profile_tribes(&state.pool, user_id, tribes)
            .await
            .map_err(|e| {
                tracing::error!("replace_profile_tribes error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
    }
    if let Some(looking_for) = &body.looking_for {
        db::profiles::replace_profile_looking_for(&state.pool, user_id, looking_for)
            .await
            .map_err(|e| {
                tracing::error!("replace_profile_looking_for error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
    }
    if let Some(meet_at) = &body.meet_at {
        db::profiles::replace_profile_meet_at(&state.pool, user_id, meet_at)
            .await
            .map_err(|e| {
                tracing::error!("replace_profile_meet_at error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
    }
    if let Some(tags) = &body.tags {
        db::profiles::replace_profile_tags(&state.pool, user_id, tags)
            .await
            .map_err(|e| {
                tracing::error!("replace_profile_tags error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
    }

    // Return updated full profile
    let user = db::users::find_user_full(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("find_user_full error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    let tribes = db::profiles::get_profile_tribes(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_tribes error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let looking_for = db::profiles::get_profile_looking_for(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_looking_for error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let meet_at = db::profiles::get_profile_meet_at(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_meet_at error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let tags = db::profiles::get_profile_tags(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_tags error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "user": user_full_to_json(user, tribes, looking_for, meet_at, tags)
    })))
}

// ---------------------------------------------------------------------------
// GET /profile/:id
// ---------------------------------------------------------------------------

/// Devuelve el perfil público de otro usuario.
///
/// GET /profile/:id
pub async fn get_by_id(
    AuthUser(_current_user_id): AuthUser,
    State(state): State<AppState>,
    Path(user_id): Path<uuid::Uuid>,
) -> Result<Json<Value>, StatusCode> {
    let user = db::users::find_user_full(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("find_user_full error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    let tribes = db::profiles::get_profile_tribes(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_tribes error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let looking_for = db::profiles::get_profile_looking_for(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_looking_for error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let meet_at = db::profiles::get_profile_meet_at(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_meet_at error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let tags = db::profiles::get_profile_tags(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_profile_tags error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "user": user_full_to_json(user, tribes, looking_for, meet_at, tags)
    })))
}
