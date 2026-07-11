use axum::extract::{Path, Query, State};
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
pub struct NearbyEventsQuery {
    pub lat: f64,
    pub lon: f64,
    #[serde(default = "default_radius")]
    pub radius_m: f64,
    #[serde(default = "default_limit")]
    pub limit: i64,
}

fn default_radius() -> f64 { 50_000.0 } // 50 km default
fn default_limit() -> i64 { 50 }

#[derive(Deserialize)]
pub struct CreateEventReq {
    pub title: String,
    pub description: Option<String>,
    pub location_name: String,
    pub lat: f64,
    pub lon: f64,
    pub starts_at: String, // ISO 8601
    pub ends_at: Option<String>, // ISO 8601
    pub max_attendees: Option<i32>,
}

#[derive(Serialize)]
pub struct EventResponse {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub location_name: String,
    pub lat: f64,
    pub lon: f64,
    pub starts_at: String,
    pub ends_at: Option<String>,
    pub max_attendees: i32,
    pub created_at: String,
    pub attendee_count: i64,
    pub distance_m: Option<f64>,
    pub my_status: Option<String>,
}

impl EventResponse {
    fn from_row(
        row: db::events::EventWithAttendeeCount,
        my_status: Option<String>,
    ) -> Self {
        Self {
            id: row.id,
            creator_id: row.creator_id,
            title: row.title,
            description: row.description,
            location_name: row.location_name,
            lat: row.lat,
            lon: row.lon,
            starts_at: row.starts_at.to_string(),
            ends_at: row.ends_at.map(|t| t.to_string()),
            max_attendees: row.max_attendees,
            created_at: row.created_at.to_string(),
            attendee_count: row.attendee_count,
            distance_m: row.distance_m,
            my_status,
        }
    }
}

#[derive(Serialize)]
pub struct ListEventsResponse {
    pub events: Vec<EventResponse>,
}

#[derive(Serialize)]
pub struct CreateEventResponse {
    pub id: Uuid,
}

#[derive(Deserialize)]
pub struct AttendReq {
    pub status: String, // going, maybe
}

#[derive(Serialize)]
pub struct AttendResponse {
    pub status: String,
}

#[derive(Serialize)]
pub struct EventDetailResponse {
    pub event: EventResponse,
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

/// GET /events?lat=&lon=&radius_m=
pub async fn list_nearby(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Query(query): Query<NearbyEventsQuery>,
) -> Result<Json<ListEventsResponse>, StatusCode> {
    // PERFORMANCE: clamp the client-supplied limit so a caller can't request
    // an unbounded page size (max 200 events per page).
    let limit = query.limit.clamp(1, 200);

    let rows = db::events::find_nearby_events(
        &state.pool,
        query.lon,
        query.lat,
        query.radius_m,
        user_id,
        limit,
    )
    .await
    .map_err(|e| {
        tracing::error!("find_nearby_events error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    // PERFORMANCE: batch the per-event attendee-status lookup (previously
    // 1 query × N events = N round-trips) into a single query using
    // ANY($1) on the caller's id.
    let event_ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let mut status_map: std::collections::HashMap<Uuid, String> =
        std::collections::HashMap::new();
    if !event_ids.is_empty() {
        let status_rows: Vec<(Uuid, String)> = sqlx::query_as(
            r#"SELECT event_id, status FROM event_attendees
               WHERE user_id = $1 AND event_id = ANY($2)"#,
        )
        .bind(user_id)
        .bind(&event_ids)
        .fetch_all(&state.pool)
        .await
        .unwrap_or_default();
        status_map = status_rows.into_iter().map(|r| (r.0, r.1)).collect();
    }

    let events = rows
        .into_iter()
        .map(|row| {
            let my_status = status_map.remove(&row.id);
            EventResponse::from_row(row, my_status)
        })
        .collect();

    Ok(Json(ListEventsResponse { events }))
}

/// POST /events
pub async fn create(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<CreateEventReq>,
) -> Result<(StatusCode, Json<CreateEventResponse>), StatusCode> {
    if req.title.trim().is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    if req.location_name.trim().is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    // SECURITY (P1): enforce max-length limits on user-provided text.
    if req.title.len() > 200 {
        return Err(StatusCode::BAD_REQUEST);
    }
    if let Some(ref desc) = req.description {
        if desc.len() > 2000 {
            return Err(StatusCode::BAD_REQUEST);
        }
    }
    if req.location_name.len() > 200 {
        return Err(StatusCode::BAD_REQUEST);
    }

    let starts_at = time::OffsetDateTime::parse(
        &req.starts_at,
        &time::format_description::well_known::Rfc3339,
    )
    .map_err(|_| StatusCode::BAD_REQUEST)?;

    let ends_at = match req.ends_at {
        Some(ref s) if !s.is_empty() => Some(
            time::OffsetDateTime::parse(s, &time::format_description::well_known::Rfc3339)
                .map_err(|_| StatusCode::BAD_REQUEST)?,
        ),
        _ => None,
    };

    let max_attendees = req.max_attendees.unwrap_or(0).max(0);

    let id = db::events::create_event(
        &state.pool,
        user_id,
        req.title.trim(),
        req.description.as_deref(),
        req.location_name.trim(),
        req.lat,
        req.lon,
        &starts_at,
        ends_at.as_ref(),
        max_attendees,
    )
    .await
    .map_err(|e| {
        tracing::error!("create_event error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok((
        StatusCode::CREATED,
        Json(CreateEventResponse { id }),
    ))
}

/// GET /events/:id
pub async fn get_by_id(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(event_id): Path<Uuid>,
) -> Result<Json<EventDetailResponse>, StatusCode> {
    let row = db::events::get_event_by_id(&state.pool, event_id)
        .await
        .map_err(|e| {
            tracing::error!("get_event_by_id error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    let my_status = db::events::get_attendee_status(&state.pool, event_id, user_id)
        .await
        .unwrap_or(None);

    Ok(Json(EventDetailResponse {
        event: EventResponse::from_row(row, my_status),
    }))
}

/// POST /events/:id/attend
pub async fn attend(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(event_id): Path<Uuid>,
    Json(req): Json<AttendReq>,
) -> Result<Json<AttendResponse>, StatusCode> {
    // Validate status
    match req.status.as_str() {
        "going" | "maybe" => {}
        _ => return Err(StatusCode::BAD_REQUEST),
    }

    // Verify event exists
    let _event = db::events::get_event_by_id(&state.pool, event_id)
        .await
        .map_err(|e| {
            tracing::error!("get_event_by_id error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?
        .ok_or(StatusCode::NOT_FOUND)?;

    // Check capacity (only for "going" status)
    if req.status == "going" {
        let full = db::events::is_event_full(&state.pool, event_id)
            .await
            .map_err(|e| {
                tracing::error!("is_event_full error: {e}");
                StatusCode::INTERNAL_SERVER_ERROR
            })?;
        if full {
            return Err(StatusCode::GONE); // 410 — event is full
        }
    }

    db::events::upsert_attendee(&state.pool, event_id, user_id, &req.status)
        .await
        .map_err(|e| {
            tracing::error!("upsert_attendee error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(AttendResponse {
        status: req.status,
    }))
}

/// DELETE /events/:id
pub async fn delete(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(event_id): Path<Uuid>,
) -> StatusCode {
    match db::events::delete_event(&state.pool, event_id, user_id).await {
        Ok(n) if n > 0 => StatusCode::NO_CONTENT,
        Ok(_) => StatusCode::NOT_FOUND,
        Err(e) => {
            tracing::error!("delete_event error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        }
    }
}
