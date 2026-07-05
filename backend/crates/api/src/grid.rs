use axum::extract::{Query, State};
use axum::http::StatusCode;
use serde::{Deserialize, Serialize};

use crate::auth::AuthUser;
use crate::AppState;

#[derive(Deserialize)]
pub struct NearbyQuery {
    pub lat: f64,
    pub lon: f64,
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
) -> Result<axum::Json<NearbyResponse>, StatusCode> {
    let users = db::geo::find_nearby_users(
        &state.pool,
        params.lon,
        params.lat,
        params.radius_m,
        current_user_id,
        params.limit,
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

    Ok(axum::Json(NearbyResponse { users }))
}
