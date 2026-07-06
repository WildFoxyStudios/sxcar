use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Deserializer};
use serde_json::{json, Value};

/// Tri-state deserializer for `details`: distinguishes JSON `null` from absent.
/// serde's default `Option<Option<T>>` flattens JSON `null` to `None` (outer),
/// collapsing the two states we need to differentiate for PUT validation.
fn deserialize_tri_state<'de, D>(de: D) -> Result<Option<Option<Value>>, D::Error>
where
    D: Deserializer<'de>,
{
    let opt: Option<Value> = Option::deserialize(de)?;
    Ok(Some(opt))
}

use crate::auth::AuthUser;
use crate::AppState;

/// Max serialized size for the `details` jsonb blob. Reject updates that exceed
/// this with HTTP 413 (Payload Too Large).
const DETAILS_MAX_BYTES: usize = 8 * 1024; // 8 KB

/// Convierte UserFullRow + arrays opcionales a un Value JSON completo.
///
/// `apply_privacy_filter`: cuando `true` (público / GET /profile/:id) strips
/// campos según las flags `show_*` del perfil. Cuando `false` (owner
/// autenticado en GET /profile o respuesta de PUT /profile) devuelve todo
/// sin filtrar para que EditProfileScreen pueda repoblar el formulario.
fn user_full_to_json(
    u: db::users::UserFullRow,
    tribes: Vec<String>,
    looking_for: Vec<String>,
    meet_at: Vec<String>,
    tags: Vec<String>,
    apply_privacy_filter: bool,
) -> Value {
    let mut user = json!({
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
        "details": u.details,
        // Las flags siempre se exponen para que el owner sepa qué configuró.
        "show_age": u.show_age,
        "show_role": u.show_role,
        "show_tribes": u.show_tribes,
        "show_position": u.show_position,
        "show_ethnicity": u.show_ethnicity,
        "show_relationship_status": u.show_relationship_status,
        "show_social_links": u.show_social_links,
    });

    if apply_privacy_filter {
        let obj = user.as_object_mut().unwrap();
        // show_age (pre-existente desde migración 0003, no estaba cableado
        // todavía — se enchufa aquí junto con las nuevas flags T4.2):
        if !u.show_age { obj.remove("birthdate"); }
        if !u.show_role { obj.remove("role"); }
        if !u.show_tribes { obj.remove("tribes"); }
        if !u.show_position { obj.remove("position"); }
        if !u.show_ethnicity { obj.remove("ethnicity"); }
        if !u.show_relationship_status { obj.remove("relationship_status"); }
    }

    user
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
        "user": user_full_to_json(user, tribes, looking_for, meet_at, tags, false)
    })))
}

// ---------------------------------------------------------------------------
// PUT /profile
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct UpdateProfileReq {
    pub profile_photo_key: Option<String>,
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
    // NEW (T4.2):
    #[serde(default, deserialize_with = "deserialize_tri_state")]
    pub details: Option<Option<Value>>,
    pub show_age: Option<bool>,
    pub show_role: Option<bool>,
    pub show_tribes: Option<bool>,
    pub show_position: Option<bool>,
    pub show_ethnicity: Option<bool>,
    pub show_relationship_status: Option<bool>,
    pub show_social_links: Option<bool>,
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

    // Validate details: must be a JSON object (not array/scalar) and <= 8 KB
    // serialized. Returns 422 if not an object or if explicit null, 413 if too large.
    // We use `Option<Option<Value>>` so that "field omitted" (outer None) and
    // "field set to null" (Some(None)) are distinguishable: omitted is a no-op,
    // explicit null is a validation error.
    let details: Option<&Value> = match &body.details {
        None => None,
        Some(None) => return Err(StatusCode::UNPROCESSABLE_ENTITY),
        Some(Some(v)) => {
            if !v.is_object() {
                return Err(StatusCode::UNPROCESSABLE_ENTITY);
            }
            let serialized = serde_json::to_vec(v).map_err(|_| StatusCode::BAD_REQUEST)?;
            if serialized.len() > DETAILS_MAX_BYTES {
                return Err(StatusCode::PAYLOAD_TOO_LARGE);
            }
            Some(v)
        }
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

    // Profile photo upload: store the R2 key and generate a presigned URL.
    if let Some(ref key) = body.profile_photo_key {
        let bucket = &state.r2.bucket_media;
        let now = time::OffsetDateTime::now_utc();
        // 7-day presigned URL — regenerated on each profile update.
        let url = crate::media::presign(&state.r2, "GET", bucket, key, 604800, now);
        sqlx::query(
            "UPDATE users SET profile_photo_id = $1, profile_photo_url = $2 WHERE id = $3",
        )
        .bind(key)
        .bind(&url)
        .bind(user_id)
        .execute(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!("profile photo update error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    }

    // Persist details jsonb + show_* privacy flags (T4.2).
    db::profiles::patch_profile_meta(
        &state.pool,
        user_id,
        details,
        body.show_age,
        body.show_role,
        body.show_tribes,
        body.show_position,
        body.show_ethnicity,
        body.show_relationship_status,
        body.show_social_links,
    )
    .await
    .map_err(|e| {
        tracing::error!("patch_profile_meta error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

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
        "user": user_full_to_json(user, tribes, looking_for, meet_at, tags, false)
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
        "user": user_full_to_json(user, tribes, looking_for, meet_at, tags, true)
    })))
}

// ---------------------------------------------------------------------------
// GET /profile/views/count
// ---------------------------------------------------------------------------

/// GET /profile/views/count
///
/// Returns the number of distinct users who viewed the authenticated user's profile.
/// `COUNT(DISTINCT viewer_id)` — a single user viewing many times counts as 1.
/// Used by the Interest screen header counter.
pub async fn get_profile_views_count(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let count = db::profiles::count_profile_views(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("count_profile_views error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    Ok(Json(json!({ "count": count })))
}
