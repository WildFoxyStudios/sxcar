//! Travel Pass — virtual location override for users to explore other cities.
//!
//! Endpoints:
//! - `POST /me/travel`   — set a virtual location (max 24h expiry)
//! - `GET  /me/travel`   — get current active travel pass (or 404)
//! - `DELETE /me/travel` — cancel/clear the travel pass

use axum::{extract::State, http::StatusCode, Json};
use serde::Deserialize;
use serde_json::{json, Value};
use time::OffsetDateTime;

use crate::auth::AuthUser;
use crate::AppState;

/// Maximum allowed hours for a travel pass.
const MAX_TRAVEL_HOURS: f64 = 24.0;

// ---------------------------------------------------------------------------
// Request types
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct SetTravelRequest {
    pub lat: f64,
    pub lon: f64,
    #[serde(default)]
    pub city_name: Option<String>,
    /// Duration in hours (max 24, default 24 if absent or 0).
    #[serde(default = "default_expires_in")]
    pub expires_in_hours: f64,
}

fn default_expires_in() -> f64 {
    MAX_TRAVEL_HOURS
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// POST /me/travel
///
/// Set or update the current user's travel pass (virtual location override).
/// `expires_in_hours` is capped at 24; if 0 or omitted, defaults to 24.
/// The backend does NOT require a paid subscription for MVP — this is pure
/// infrastructure that can be gated behind a purchase later.
pub async fn set_travel(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
    Json(body): Json<SetTravelRequest>,
) -> Result<Json<Value>, StatusCode> {
    // Validate coordinates before any DB write: reject NaN/Infinity and
    // out-of-range values so they can't later feed ST_MakePoint in
    // grid/discover (which would produce garbage distances or PostGIS 500s).
    if !body.lat.is_finite()
        || !body.lon.is_finite()
        || !(-90.0..=90.0).contains(&body.lat)
        || !(-180.0..=180.0).contains(&body.lon)
    {
        return Err(StatusCode::BAD_REQUEST);
    }

    let hours = if body.expires_in_hours <= 0.0 {
        MAX_TRAVEL_HOURS
    } else if body.expires_in_hours > MAX_TRAVEL_HOURS {
        MAX_TRAVEL_HOURS
    } else {
        body.expires_in_hours
    };

    let expires_at = OffsetDateTime::now_utc()
        + time::Duration::seconds((hours * 3600.0) as i64);

    // Travel Pass columns are provisioned by migration (see
    // 0040_travel_pass.sql / 0047_travel_columns_idempotent.sql), so no
    // per-request ALTER TABLE is needed here.
    sqlx::query(
        "UPDATE users
         SET travel_lat = $1,
             travel_lon = $2,
             travel_city_name = $3,
             travel_expires_at = $4
         WHERE id = $5",
    )
    .bind(body.lat)
    .bind(body.lon)
    .bind(&body.city_name)
    .bind(expires_at)
    .bind(user_id)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("travel set error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(json!({
        "status": "ok",
        "lat": body.lat,
        "lon": body.lon,
        "city_name": body.city_name,
        "expires_at": expires_at.to_string(),
        "expires_in_hours": hours,
    })))
}

/// GET /me/travel
///
/// Returns the current active travel pass, or 404 if none is set or expired.
pub async fn get_travel(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<Value>, StatusCode> {
    let row = sqlx::query(
        "SELECT travel_lat, travel_lon, travel_city_name, travel_expires_at
         FROM users
         WHERE id = $1
           AND travel_lat IS NOT NULL
           AND travel_lon IS NOT NULL
           AND travel_expires_at IS NOT NULL
           AND travel_expires_at > now()",
    )
    .bind(user_id)
    .fetch_optional(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("travel get error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    match row {
        Some(r) => {
            // Use sqlx::Row to extract columns dynamically
            use sqlx::Row;
            let lat: f64 = r.try_get("travel_lat").map_err(|_| StatusCode::NOT_FOUND)?;
            let lon: f64 = r.try_get("travel_lon").map_err(|_| StatusCode::NOT_FOUND)?;
            let city_name: Option<String> = r.try_get("travel_city_name").unwrap_or(None);
            let expires_at: OffsetDateTime = r.try_get("travel_expires_at").map_err(|_| StatusCode::NOT_FOUND)?;
            let now = OffsetDateTime::now_utc();
            let remaining_hours = if expires_at > now {
                (expires_at - now).whole_seconds() as f64 / 3600.0
            } else {
                0.0
            };

            Ok(Json(json!({
                "lat": lat,
                "lon": lon,
                "city_name": city_name,
                "expires_at": expires_at.to_string(),
                "expires_in_hours": (remaining_hours * 100.0).round() / 100.0,
            })))
        }
        None => Err(StatusCode::NOT_FOUND),
    }
}

/// DELETE /me/travel
///
/// Cancel the active travel pass. The user returns to real GPS location.
pub async fn delete_travel(
    State(state): State<AppState>,
    AuthUser(user_id): AuthUser,
) -> Result<Json<Value>, StatusCode> {
    sqlx::query(
        "UPDATE users
         SET travel_lat = NULL,
             travel_lon = NULL,
             travel_city_name = NULL,
             travel_expires_at = NULL
         WHERE id = $1",
    )
    .bind(user_id)
    .execute(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("travel delete error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(json!({ "status": "ok" })))
}

// ---------------------------------------------------------------------------
// Travel coordinates resolution (used by grid/discover)
// ---------------------------------------------------------------------------

/// Resolve the effective location for a user: if an active travel pass exists,
/// return the travel coordinates. Otherwise return `None`, meaning the caller
/// should use the client-provided GPS coordinates.
///
/// Used by `/grid/nearby` and `/discover` so they automatically respect the
/// user's virtual location override.
pub async fn resolve_travel_location(
    pool: &sqlx::PgPool,
    user_id: uuid::Uuid,
) -> Result<Option<(f64, f64)>, sqlx::Error> {
    let row = sqlx::query(
        "SELECT travel_lat, travel_lon
         FROM users
         WHERE id = $1
           AND travel_lat IS NOT NULL
           AND travel_lon IS NOT NULL
           AND travel_expires_at IS NOT NULL
           AND travel_expires_at > now()",
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    Ok(row.and_then(|r| {
        use sqlx::Row;
        let lat: f64 = r.try_get("travel_lat").ok()?;
        let lon: f64 = r.try_get("travel_lon").ok()?;
        Some((lat, lon))
    }))
}
