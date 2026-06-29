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

/// GET /grid/nearby?lat=&lon=&radius_m=5000&limit=50
///
/// Devuelve los usuarios activos cercanos al punto dado, ordenados por distancia.
/// Requiere autenticación. Excluye automáticamente al usuario solicitante.
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
    )
    .await
    .map_err(|e| {
        tracing::error!("find_nearby_users error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(axum::Json(NearbyResponse { users }))
}
