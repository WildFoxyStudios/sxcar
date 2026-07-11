use axum::extract::{Query, State};
use axum::http::StatusCode;
use serde::Deserialize;

use crate::auth::AuthUser;
use crate::AppState;

#[derive(Deserialize)]
pub struct DiscoverQuery {
    /// Optional — when omitted, the server checks for an active Travel Pass.
    /// If no travel pass is active, a 400 Bad Request is returned.
    pub lat: Option<f64>,
    /// Optional — paired with `lat`.
    pub lon: Option<f64>,
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

/// GET /discover?lat=&lon=&radius_m=5000&limit=50
///
/// Returns a curated feed of nearby users sorted by profile completeness
/// and recent activity (`last_seen_at DESC`) rather than pure distance.
/// Only includes users who:
///   - have completed onboarding
///   - have at least one primary profile photo
///   - are not blocked by / have not blocked the requesting user
pub async fn list(
    AuthUser(current_user_id): AuthUser,
    State(state): State<AppState>,
    Query(params): Query<DiscoverQuery>,
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

    // P2: clamp the client-supplied limit so a caller can't request an
    // unbounded page size.
    let limit = params.limit.clamp(1, 200);

    let rows = sqlx::query_as::<_, db::geo::NearbyUserRow>(
        r#"
        SELECT u.id, u.email::text AS email,
               p.display_name,
               NULL::text AS bio,
               (SELECT id FROM photos WHERE user_id = u.id AND is_primary = true LIMIT 1) AS profile_photo_id,
               p.profile_photo_key,
               (SELECT r2_key FROM photos WHERE user_id = u.id AND is_primary = true LIMIT 1) AS profile_photo_url,
               ST_Distance(l.geog, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography)::float8 AS distance_m
        FROM users u
        JOIN profiles p ON p.user_id = u.id
        JOIN locations l ON l.user_id = u.id
        WHERE u.status = 'active'
          AND u.onboarding_completed_at IS NOT NULL
          -- Incognito users are hidden from discover too (see [[grid]] geo.rs).
          AND p.incognito = false
          AND ST_DWithin(l.geog, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3::float8)
          AND u.id != $4
          AND u.id NOT IN (SELECT target_id FROM blocks WHERE user_id = $4)
          AND u.id NOT IN (SELECT user_id FROM blocks WHERE target_id = $4)
          AND (p.profile_photo_key IS NOT NULL
               OR EXISTS (SELECT 1 FROM photos ph WHERE ph.user_id = u.id AND ph.is_primary = true))
        ORDER BY u.last_seen_at DESC NULLS LAST
        LIMIT $5
        "#,
    )
    .bind(lon)
    .bind(lat)
    .bind(params.radius_m)
    .bind(current_user_id)
    .bind(limit)
    .fetch_all(&state.pool)
    .await
    .map_err(|e| {
        tracing::error!("discover query error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    // Generate presigned photo URLs. Priority:
    // 1. profiles.profile_photo_key (R2 text key from profile edits)
    // 2. photos.r2_key (legacy photos table, stored in profile_photo_url)
    //
    // SECURITY (P0): only presign profile photos that have been approved by
    // moderation. Pending photos must not appear in the discover feed.
    let candidate_keys: Vec<String> = rows
        .iter()
        .filter_map(|u| {
            u.profile_photo_key.clone().or_else(|| u.profile_photo_url.clone())
        })
        .collect();
    let approved_keys: std::collections::HashSet<String> = if candidate_keys.is_empty() {
        std::collections::HashSet::new()
    } else {
        let fetched: Result<Vec<String>, _> = sqlx::query_scalar(
            "SELECT DISTINCT r2_key FROM photos \
             WHERE r2_key = ANY($1) AND moderation_status = 'approved'",
        )
        .bind(&candidate_keys)
        .fetch_all(&state.pool)
        .await;
        match fetched {
            Ok(v) => v.into_iter().collect(),
            Err(e) => {
                tracing::error!("approved-photo lookup failed: {e}");
                std::collections::HashSet::new()
            }
        }
    };

    let users_with_photos: Vec<serde_json::Value> = rows
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
