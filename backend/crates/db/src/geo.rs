use crate::Pool;
use sqlx::FromRow;

pub async fn upsert_location(pool: &Pool, user_id: uuid::Uuid, lon: f64, lat: f64) -> anyhow::Result<()> {
    sqlx::query(
        r#"INSERT INTO locations (user_id, geog)
           VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography)
           ON CONFLICT (user_id) DO UPDATE SET
             geog = EXCLUDED.geog"#,
    )
    .bind(user_id)
    .bind(lon)
    .bind(lat)
    .execute(pool)
    .await?;
    Ok(())
}

#[derive(Debug, FromRow, serde::Serialize)]
pub struct NearbyUserRow {
    pub id: uuid::Uuid,
    pub email: String,
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub profile_photo_id: Option<uuid::Uuid>,
    pub distance_m: f64,
}

/// Busca usuarios activos cerca de una ubicación, ordenados por distancia,
/// con filtros opcionales de búsqueda.
///
/// # Parámetros
/// - `lon`, `lat`: coordenadas del punto de referencia (WGS84)
/// - `radius_m`: radio de búsqueda en metros
/// - `current_user_id`: el ID del usuario que hace la consulta (se excluye de resultados)
/// - `limit`: máximo de resultados
/// - `min_age` / `max_age`: filtro por edad (usando profiles.birthdate, NULL no excluye)
/// - `tribe`: filtro por tribus (comma-separated, OR)
/// - `looking_for`: filtro por intenciones (comma-separated, OR)
/// - `body_type`: filtro por tipo de cuerpo
/// - `q`: búsqueda ILIKE sobre display_name y bio
pub async fn find_nearby_users(
    pool: &Pool,
    lon: f64,
    lat: f64,
    radius_m: f64,
    current_user_id: uuid::Uuid,
    limit: i64,
    min_age: Option<i32>,
    max_age: Option<i32>,
    tribe: Option<&str>,
    looking_for: Option<&str>,
    body_type: Option<&str>,
    q: Option<&str>,
) -> anyhow::Result<Vec<NearbyUserRow>> {
    let rows = sqlx::query_as::<_, NearbyUserRow>(
        r#"
        SELECT u.id, u.email::text AS email,
               p.display_name,
               p.about AS bio,
               (SELECT id FROM photos WHERE user_id = u.id AND is_primary = true LIMIT 1) AS profile_photo_id,
               ST_Distance(l.geog, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography)::float8 AS distance_m
        FROM users u
        JOIN profiles p ON p.user_id = u.id
        JOIN locations l ON l.user_id = u.id
        WHERE u.status = 'active'
          AND ST_DWithin(l.geog, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3::float8)
          AND u.id != $4
          AND u.id NOT IN (SELECT target_id FROM blocks WHERE user_id = $4)
          AND u.id NOT IN (SELECT user_id FROM blocks WHERE target_id = $4)
          AND ($6::int IS NULL OR p.birthdate IS NULL OR EXTRACT(YEAR FROM AGE(p.birthdate)) >= $6::int)
          AND ($7::int IS NULL OR p.birthdate IS NULL OR EXTRACT(YEAR FROM AGE(p.birthdate)) <= $7::int)
          AND ($8::text IS NULL OR EXISTS (
              SELECT 1 FROM profile_tribes pt WHERE pt.user_id = u.id AND pt.tribe = ANY(string_to_array($8, ','))
          ))
          AND ($9::text IS NULL OR EXISTS (
              SELECT 1 FROM profile_looking_for plf WHERE plf.user_id = u.id AND plf.intent = ANY(string_to_array($9, ','))
          ))
          AND ($10::text IS NULL OR p.body_type = $10)
          AND ($11::text IS NULL OR p.display_name ILIKE '%' || $11 || '%' OR p.about ILIKE '%' || $11 || '%')
        ORDER BY distance_m ASC
        LIMIT $5
        "#,
    )
    .bind(lon)
    .bind(lat)
    .bind(radius_m)
    .bind(current_user_id)
    .bind(limit)
    .bind(min_age)
    .bind(max_age)
    .bind(tribe)
    .bind(looking_for)
    .bind(body_type)
    .bind(q)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}
