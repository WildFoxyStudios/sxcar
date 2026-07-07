use sqlx::FromRow;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Row types
// ---------------------------------------------------------------------------

#[derive(Debug, FromRow, serde::Serialize)]
pub struct EventRow {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub location_name: String,
    pub lat: f64,
    pub lon: f64,
    pub starts_at: time::OffsetDateTime,
    pub ends_at: Option<time::OffsetDateTime>,
    pub max_attendees: i32,
    pub created_at: time::OffsetDateTime,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct EventWithAttendeeCount {
    pub id: Uuid,
    pub creator_id: Uuid,
    pub title: String,
    pub description: Option<String>,
    pub location_name: String,
    pub lat: f64,
    pub lon: f64,
    pub starts_at: time::OffsetDateTime,
    pub ends_at: Option<time::OffsetDateTime>,
    pub max_attendees: i32,
    pub created_at: time::OffsetDateTime,
    pub attendee_count: i64,
    pub distance_m: Option<f64>,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct EventAttendeeRow {
    pub event_id: Uuid,
    pub user_id: Uuid,
    pub status: String,
    pub created_at: time::OffsetDateTime,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct MyAttendeeStatus {
    pub status: Option<String>,
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct CreatorDisplayName {
    pub display_name: Option<String>,
}

// ---------------------------------------------------------------------------
// Events CRUD
// ---------------------------------------------------------------------------

pub async fn create_event(
    pool: &sqlx::PgPool,
    creator_id: Uuid,
    title: &str,
    description: Option<&str>,
    location_name: &str,
    lat: f64,
    lon: f64,
    starts_at: &time::OffsetDateTime,
    ends_at: Option<&time::OffsetDateTime>,
    max_attendees: i32,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO events (creator_id, title, description, location_name, lat, lon, starts_at, ends_at, max_attendees)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           RETURNING id"#,
    )
    .bind(creator_id)
    .bind(title)
    .bind(description)
    .bind(location_name)
    .bind(lat)
    .bind(lon)
    .bind(starts_at)
    .bind(ends_at)
    .bind(max_attendees)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

/// Find events near a location, ordered by distance.
pub async fn find_nearby_events(
    pool: &sqlx::PgPool,
    lon: f64,
    lat: f64,
    radius_m: f64,
    current_user_id: Uuid,
    limit: i64,
) -> anyhow::Result<Vec<EventWithAttendeeCount>> {
    let rows = sqlx::query_as::<_, EventWithAttendeeCount>(
        r#"
        SELECT e.id, e.creator_id, e.title, e.description, e.location_name,
               e.lat, e.lon, e.starts_at, e.ends_at, e.max_attendees, e.created_at,
               COALESCE(a.attendee_count, 0) AS attendee_count,
               ST_Distance(
                   ST_SetSRID(ST_MakePoint(e.lon, e.lat), 4326)::geography,
                   ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography
               )::float8 AS distance_m
        FROM events e
        LEFT JOIN (
            SELECT event_id, COUNT(*) AS attendee_count
            FROM event_attendees
            WHERE status IN ('going', 'maybe')
            GROUP BY event_id
        ) a ON a.event_id = e.id
        WHERE e.ends_at IS NULL OR e.ends_at > now()
          AND e.starts_at > now() - interval '24 hours'
          AND ST_DWithin(
              ST_SetSRID(ST_MakePoint(e.lon, e.lat), 4326)::geography,
              ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
              $3::float8
          )
        ORDER BY distance_m ASC, e.starts_at ASC
        LIMIT $5
        "#,
    )
    .bind(lon)
    .bind(lat)
    .bind(radius_m)
    .bind(current_user_id)
    .bind(limit)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

/// Get a single event by id with attendee count.
pub async fn get_event_by_id(
    pool: &sqlx::PgPool,
    event_id: Uuid,
) -> anyhow::Result<Option<EventWithAttendeeCount>> {
    let row = sqlx::query_as::<_, EventWithAttendeeCount>(
        r#"
        SELECT e.id, e.creator_id, e.title, e.description, e.location_name,
               e.lat, e.lon, e.starts_at, e.ends_at, e.max_attendees, e.created_at,
               COALESCE(a.attendee_count, 0) AS attendee_count,
               NULL::float8 AS distance_m
        FROM events e
        LEFT JOIN (
            SELECT event_id, COUNT(*) AS attendee_count
            FROM event_attendees
            WHERE status IN ('going', 'maybe')
            GROUP BY event_id
        ) a ON a.event_id = e.id
        WHERE e.id = $1
        "#,
    )
    .bind(event_id)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Delete an event (only the creator can delete).
pub async fn delete_event(
    pool: &sqlx::PgPool,
    event_id: Uuid,
    creator_id: Uuid,
) -> anyhow::Result<u64> {
    let rows = sqlx::query(
        r#"DELETE FROM events WHERE id = $1 AND creator_id = $2"#,
    )
    .bind(event_id)
    .bind(creator_id)
    .execute(pool)
    .await?
    .rows_affected();
    Ok(rows)
}

// ---------------------------------------------------------------------------
// RSVP / Attendee
// ---------------------------------------------------------------------------

/// Upsert an attendee status (going, maybe, not_going).
pub async fn upsert_attendee(
    pool: &sqlx::PgPool,
    event_id: Uuid,
    user_id: Uuid,
    status: &str,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO event_attendees (event_id, user_id, status)
           VALUES ($1, $2, $3)
           ON CONFLICT (event_id, user_id) DO UPDATE SET status = EXCLUDED.status"#,
    )
    .bind(event_id)
    .bind(user_id)
    .bind(status)
    .execute(pool)
    .await?;
    Ok(())
}

/// Get the current user's attendee status for an event.
pub async fn get_attendee_status(
    pool: &sqlx::PgPool,
    event_id: Uuid,
    user_id: Uuid,
) -> anyhow::Result<Option<String>> {
    let row: Option<(String,)> = sqlx::query_as(
        r#"SELECT status FROM event_attendees WHERE event_id = $1 AND user_id = $2"#,
    )
    .bind(event_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| r.0))
}

/// Check if the event has reached its max attendee capacity.
pub async fn is_event_full(
    pool: &sqlx::PgPool,
    event_id: Uuid,
) -> anyhow::Result<bool> {
    let row: Option<(i32, i64)> = sqlx::query_as(
        r#"SELECT e.max_attendees, COALESCE(COUNT(ea.user_id), 0) AS attendee_count
           FROM events e
           LEFT JOIN event_attendees ea ON ea.event_id = e.id AND ea.status IN ('going', 'maybe')
           WHERE e.id = $1
           GROUP BY e.id, e.max_attendees"#,
    )
    .bind(event_id)
    .fetch_optional(pool)
    .await?;
    match row {
        Some((max, count)) => Ok(max > 0 && count >= max as i64),
        None => Ok(false),
    }
}
