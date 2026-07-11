use axum::extract::{Query, State};
use axum::http::StatusCode;
use serde::{Deserialize, Serialize};

use crate::auth::AuthUser;
use crate::AppState;

#[derive(Deserialize)]
pub struct NearbyQuery {
    /// Optional — when omitted, the server checks for an active Travel Pass.
    /// If no travel pass is active, a 400 Bad Request is returned.
    pub lat: Option<f64>,
    /// Optional — paired with `lat`.
    pub lon: Option<f64>,
    #[serde(default = "default_radius")]
    pub radius_m: f64,
    #[serde(default = "default_limit")]
    pub limit: i64,
    pub min_age: Option<i32>,
    pub max_age: Option<i32>,
    pub tribe: Option<String>,
    #[serde(rename = "looking_for")]
    pub looking_for: Option<String>,
    pub body_type: Option<String>,
    pub q: Option<String>,
    pub favorites_only: Option<bool>,
    pub online_only: Option<bool>,
    pub right_now: Option<bool>,
    pub photos_only: Option<bool>,
    pub position: Option<String>,
    pub not_chatted: Option<bool>,
}

fn default_radius() -> f64 {
    5000.0
}

fn default_limit() -> i64 {
    50
}

#[derive(Serialize)]
pub struct NearbyResponse {
    pub users: Vec<db::geo::NearbyUserRow>,
}

/// GET /grid/nearby?lat=&lon=&radius_m=5000&limit=50&min_age=&max_age=&tribe=&looking_for=&body_type=&q=&favorites_only=&online_only=&right_now=&photos_only=&position=&not_chatted=
///
/// Devuelve los usuarios activos cercanos al punto dado, ordenados por distancia.
/// Requiere autenticación. Excluye automáticamente al usuario solicitante.
/// Soporta filtros opcionales: min_age, max_age, tribe, looking_for, body_type, q,
/// favorites_only (solo favoritos del solicitante), online_only (activos <5min),
/// right_now (activos <30min), photos_only (solo usuarios con foto de perfil),
/// position (posición sexual exacta del perfil), not_chatted (excluye usuarios con los
/// que el solicitante ya tiene una conversación).
pub async fn nearby(
    AuthUser(current_user_id): AuthUser,
    State(state): State<AppState>,
    Query(params): Query<NearbyQuery>,
) -> Result<axum::Json<serde_json::Value>, StatusCode> {
    // Resolve effective coordinates: if lat/lon not provided, check travel pass.
    let (lon, lat) = match (params.lon, params.lat) {
        (Some(lon), Some(lat)) => (lon, lat),
        _ => {
            // No explicit coordinates — try the user's active travel pass.
            let travel = crate::travel::resolve_travel_location(&state.pool, current_user_id)
                .await
                .map_err(|e| {
                    tracing::error!("travel resolution error: {e}");
                    StatusCode::INTERNAL_SERVER_ERROR
                })?;
            match travel {
                Some((tlat, tlon)) => (tlon, tlat),
                None => {
                    return Err(StatusCode::BAD_REQUEST);
                }
            }
        }
    };

    // SECURITY: reject non-finite or out-of-range coordinates before they
    // reach PostGIS ST_MakePoint — NaN/Infinity produce garbage or errors.
    if !lat.is_finite() || !lon.is_finite()
        || !(-90.0..=90.0).contains(&lat)
        || !(-180.0..=180.0).contains(&lon)
    {
        return Err(StatusCode::BAD_REQUEST);
    }

    // P2: clamp the client-supplied limit so a caller can't request an
    // unbounded page size.
    let limit = params.limit.clamp(1, 200);

    let users = db::geo::find_nearby_users(
        &state.pool,
        lon,
        lat,
        params.radius_m,
        current_user_id,
        limit,
        params.min_age,
        params.max_age,
        params.tribe.as_deref(),
        params.looking_for.as_deref(),
        params.body_type.as_deref(),
        params.q.as_deref(),
        params.favorites_only.unwrap_or(false),
        params.online_only.unwrap_or(false),
        params.right_now.unwrap_or(false),
        params.photos_only.unwrap_or(false),
        params.position.as_deref(),
        params.not_chatted.unwrap_or(false),
    )
    .await
    .map_err(|e| {
        tracing::error!("find_nearby_users error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    // Generate presigned photo URLs. Priority:
    // 1. profiles.profile_photo_key (R2 text key from profile edits)
    // 2. photos.r2_key (legacy photos table, stored in profile_photo_url)
    //
    // SECURITY (P0): only presign profile photos that have been approved by
    // moderation. A pending photo must NOT be visible to other users in the
    // grid. Collect all candidate keys, bulk-query which are approved, and
    // null out any that aren't.
    let candidate_keys: Vec<String> = users
        .iter()
        .filter_map(|u| {
            u.profile_photo_key.clone().or_else(|| u.profile_photo_url.clone())
        })
        .collect();
    let approved_keys: std::collections::HashSet<String> = if candidate_keys.is_empty() {
        std::collections::HashSet::new()
    } else {
        let rows: Result<Vec<String>, _> = sqlx::query_scalar(
            "SELECT DISTINCT r2_key FROM photos \
             WHERE r2_key = ANY($1) AND moderation_status = 'approved'",
        )
        .bind(&candidate_keys)
        .fetch_all(&state.pool)
        .await;
        match rows {
            Ok(v) => v.into_iter().collect(),
            Err(e) => {
                tracing::error!("approved-photo lookup failed: {e}");
                std::collections::HashSet::new()
            }
        }
    };

    let users_with_photos: Vec<serde_json::Value> = users
        .iter()
        .map(|u| {
            let mut j = serde_json::to_value(u).unwrap_or_default();
            // Location privacy: never expose the raw distance — snap to bucket.
            j["distance_m"] = serde_json::json!(db::geo::fuzz_distance(u.distance_m));
            let r2_key = u.profile_photo_key.as_deref()
                .or(u.profile_photo_url.as_deref());
            if let Some(key) = r2_key {
                if approved_keys.contains(key) {
                    if let Some(ref r2) = state.r2 {
                        let now = time::OffsetDateTime::now_utc();
                        let url = crate::media::presign(
                            r2, "GET", &r2.bucket_media,
                            key, 604800, now,
                        );
                        j["profile_photo_url"] = serde_json::Value::String(url);
                    }
                } else {
                    // Not approved (or not found) — do not expose the photo.
                    j["profile_photo_url"] = serde_json::Value::Null;
                }
            }
            if j.get("profile_photo_url").is_none() {
                j["profile_photo_url"] = serde_json::Value::Null;
            }
            j
        })
        .collect();

    Ok(axum::Json(serde_json::json!({ "users": users_with_photos })))
}
