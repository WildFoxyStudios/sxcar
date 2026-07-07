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
    let rows = db::events::find_nearby_events(
        &state.pool,
        query.lon,
        query.lat,
        query.radius_m,
        user_id,
        query.limit,
    )
    .await
    .map_err(|e| {
        tracing::error!("find_nearby_events error: {e}");
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let mut events = Vec::with_capacity(rows.len());
    for row in rows {
        let my_status = db::events::get_attendee_status(&state.pool, row.id, user_id)
            .await
            .unwrap_or(None);
        events.push(EventResponse::from_row(row, my_status));
    }

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
