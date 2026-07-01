//! Vibra Tier 2 endpoints:
//! - Boost (`POST /boost`, `GET /boost/active`)
//! - Saved phrases (`GET /phrases`, `POST /phrases`, `DELETE /phrases/:id`, `PUT /phrases/order`)
//! - Saved places (`GET /places`, `POST /places`, `DELETE /places/:id`)
//! - Roam location preference (`GET /me/location`, `PUT /me/location`)
//!
//! All endpoints require authentication via the `AuthUser` extractor.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{delete, get, post, put},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::auth::AuthUser;
use crate::AppState;

/// Default boost duration: 30 minutes.
const BOOST_DURATION_SECS: i64 = 30 * 60;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/boost", post(create_boost))
        .route("/boost/active", get(boost_active))
        .route("/phrases", get(list_phrases).post(add_phrase))
        .route("/phrases/order", put(reorder_phrases))
        .route("/phrases/:id", delete(delete_phrase))
        .route("/places", get(list_places).post(add_place))
        .route("/places/:id", delete(delete_place))
        .route("/me/location", get(get_location).put(set_location))
}

// ---------------------------------------------------------------------------
// Boosts
// ---------------------------------------------------------------------------

/// POST /boost
///
/// Creates a 30-minute boost for the current user. Source is 'manual'.
pub async fn create_boost(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let id = db::tier2::create_boost(&state.pool, user_id, BOOST_DURATION_SECS, "manual")
        .await
        .map_err(|e| {
            tracing::error!("create_boost error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let now = time::OffsetDateTime::now_utc();
    Ok(Json(json!({
        "id": id.to_string(),
        "user_id": user_id.to_string(),
        "duration_secs": BOOST_DURATION_SECS,
        "started_at": now.to_string(),
        "expires_at": (now + time::Duration::seconds(BOOST_DURATION_SECS)).to_string(),
        "source": "manual",
    })))
}

/// GET /boost/active
///
/// Returns whether the current user is currently boosted + remaining seconds.
pub async fn boost_active(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let now = time::OffsetDateTime::now_utc();
    let boosted = db::tier2::is_user_boosted(&state.pool, user_id, now)
        .await
        .map_err(|e| {
            tracing::error!("is_user_boosted error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let mut remaining_secs: i64 = 0;
    if boosted {
        // Find the latest expiry for the response.
        let rows = sqlx::query!(
            r#"SELECT MAX(expires_at) AS "expires_at"
               FROM boosts
               WHERE user_id = $1 AND expires_at > $2"#,
            user_id,
            now,
        )
        .fetch_one(&state.pool)
        .await
        .map_err(|e| {
            tracing::error!("boost_active fetch error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
        if let Some(expires_at) = rows.expires_at {
            let diff = (expires_at - now).whole_seconds();
            remaining_secs = diff.max(0);
        }
    }

    Ok(Json(json!({
        "is_boosted": boosted,
        "remaining_secs": remaining_secs,
    })))
}

// ---------------------------------------------------------------------------
// Saved phrases
// ---------------------------------------------------------------------------

/// GET /phrases
pub async fn list_phrases(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let rows = db::tier2::list_saved_phrases(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_saved_phrases error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let phrases: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id.to_string(),
                "phrase": r.phrase,
                "position": r.position,
                "created_at": r.created_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({ "phrases": phrases })))
}

#[derive(Deserialize)]
pub struct AddPhraseReq {
    pub phrase: String,
}

/// POST /phrases
pub async fn add_phrase(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(body): Json<AddPhraseReq>,
) -> Result<Json<Value>, StatusCode> {
    let phrase = body.phrase.trim();
    if phrase.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let id = db::tier2::add_saved_phrase(&state.pool, user_id, phrase)
        .await
        .map_err(|e| {
            tracing::error!("add_saved_phrase error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "id": id.to_string(),
        "phrase": phrase,
    })))
}

/// DELETE /phrases/:id
pub async fn delete_phrase(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    db::tier2::delete_saved_phrase(&state.pool, user_id, id)
        .await
        .map_err(|e| {
            tracing::error!("delete_saved_phrase error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
pub struct ReorderPhrasesReq {
    pub ids: Vec<Uuid>,
}

/// PUT /phrases/order
pub async fn reorder_phrases(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(body): Json<ReorderPhrasesReq>,
) -> Result<Json<Value>, StatusCode> {
    db::tier2::reorder_saved_phrases(&state.pool, user_id, &body.ids)
        .await
        .map_err(|e| {
            tracing::error!("reorder_saved_phrases error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    Ok(Json(json!({ "ok": true, "count": body.ids.len() })))
}

// ---------------------------------------------------------------------------
// Saved places
// ---------------------------------------------------------------------------

/// GET /places
pub async fn list_places(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    let rows = db::tier2::list_saved_places(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_saved_places error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let places: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.id.to_string(),
                "name": r.name,
                "lat": r.lat,
                "lon": r.lon,
                "is_default": r.is_default,
                "created_at": r.created_at.to_string(),
            })
        })
        .collect();

    Ok(Json(json!({ "places": places })))
}

#[derive(Deserialize)]
pub struct AddPlaceReq {
    pub name: String,
    pub lat: f64,
    pub lon: f64,
}

/// POST /places
pub async fn add_place(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(body): Json<AddPlaceReq>,
) -> Result<Json<Value>, StatusCode> {
    let name = body.name.trim();
    if name.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let id = db::tier2::add_saved_place(&state.pool, user_id, name, body.lat, body.lon)
        .await
        .map_err(|e| {
            tracing::error!("add_saved_place error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "id": id.to_string(),
        "name": name,
        "lat": body.lat,
        "lon": body.lon,
    })))
}

/// DELETE /places/:id
pub async fn delete_place(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    db::tier2::delete_saved_place(&state.pool, user_id, id)
        .await
        .map_err(|e| {
            tracing::error!("delete_saved_place error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------
// Roam location preference (/me/location)
// ---------------------------------------------------------------------------

/// GET /me/location
pub async fn get_location(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<Value>, StatusCode> {
    match db::tier2::get_roam_pref(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("get_roam_pref error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })? {
        Some(row) => Ok(Json(json!({
            "lat": row.lat,
            "lon": row.lon,
            "place_name": row.place_name,
            "is_roam": row.is_roam,
            "updated_at": row.updated_at.to_string(),
        }))),
        None => Ok(Json(json!({
            "lat": serde_json::Value::Null,
            "lon": serde_json::Value::Null,
            "place_name": serde_json::Value::Null,
            "is_roam": false,
        }))),
    }
}

#[derive(Deserialize)]
pub struct SetLocationReq {
    pub lat: f64,
    pub lon: f64,
    pub place_name: Option<String>,
    pub is_roam: bool,
}

/// PUT /me/location
pub async fn set_location(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(body): Json<SetLocationReq>,
) -> Result<Json<Value>, StatusCode> {
    let place_name_trimmed = body.place_name.as_deref().map(str::trim);
    let name_opt = place_name_trimmed.filter(|s| !s.is_empty());

    db::tier2::set_roam_pref(&state.pool, user_id, body.lat, body.lon, name_opt, body.is_roam)
        .await
        .map_err(|e| {
            tracing::error!("set_roam_pref error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(json!({
        "ok": true,
        "lat": body.lat,
        "lon": body.lon,
        "place_name": name_opt,
        "is_roam": body.is_roam,
    })))
}