use crate::Pool;
use sqlx::FromRow;

#[derive(Debug, FromRow, serde::Serialize)]
pub struct NearbyUserRow {
    pub id: uuid::Uuid,
    pub email: String,
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub profile_photo_id: Option<uuid::Uuid>,
    pub distance_m: f64,
}

/// Busca usuarios activos cerca de una ubicación, ordenados por distancia.
///
/// # Parámetros
/// - `lon`, `lat`: coordenadas del punto de referencia (WGS84)
/// - `radius_m`: radio de búsqueda en metros
/// - `current_user_id`: el ID del usuario que hace la consulta (se excluye de resultados)
/// - `limit`: máximo de resultados
pub async fn find_nearby_users(
    pool: &Pool,
    lon: f64,
    lat: f64,
    radius_m: f64,
    current_user_id: uuid::Uuid,
    limit: i64,
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
        ORDER BY distance_m ASC
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
