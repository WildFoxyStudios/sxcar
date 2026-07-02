//! AD3 — Moderacion: reports queue, photo moderation, CSAM queue.
//!
//! Queries para el panel admin de moderacion.
//! Usa `sqlx::query` (no macro) donde hay parametros opcionales con la
//! sintaxis `$1::text IS NULL`, y `query_as!` en consultas simples.

use crate::Pool;
use time::OffsetDateTime;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct ReportRow {
    pub id: Uuid,
    pub reporter_id: Uuid,
    pub target_user_id: Uuid,
    pub target_kind: String,
    pub target_id: Option<Uuid>,
    pub reason: Option<String>,
    pub status: String,
    pub created_at: OffsetDateTime,
    pub resolved_at: Option<OffsetDateTime>,
}

/// Crea un reporte de usuario (endpoint de cara al usuario, no admin).
/// `target_kind` ∈ ('profile','photo','message'). Devuelve el id creado.
pub async fn create_report(
    pool: &Pool,
    reporter_id: Uuid,
    target_user_id: Uuid,
    target_kind: &str,
    target_id: Option<Uuid>,
    reason: Option<&str>,
) -> anyhow::Result<Uuid> {
    let row = sqlx::query!(
        r#"INSERT INTO reports (reporter_id, target_user_id, target_kind, target_id, reason)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id"#,
        reporter_id,
        target_user_id,
        target_kind,
        target_id,
        reason,
    )
    .fetch_one(pool)
    .await?;
    Ok(row.id)
}

/// Busca un reporte por ID.
pub async fn find_report_by_id(
    pool: &Pool,
    id: Uuid,
) -> anyhow::Result<Option<ReportRow>> {
    let row = sqlx::query_as!(
        ReportRow,
        r#"SELECT id,
                  reporter_id,
                  target_user_id,
                  target_kind,
                  target_id,
                  reason,
                  status,
                  created_at,
                  resolved_at
           FROM reports
           WHERE id = $1"#,
        id
    )
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Lista reportes con filtro opcional por status. Paginado.
///
/// Retorna (rows, total_count).
pub async fn list_reports(
    pool: &Pool,
    status: Option<&str>,
    limit: i64,
    offset: i64,
) -> anyhow::Result<(Vec<ReportRow>, i64)> {
    use sqlx::Row;

    let raw = sqlx::query(
        r#"SELECT id,
                  reporter_id,
                  target_user_id,
                  target_kind,
                  target_id,
                  reason,
                  status,
                  created_at,
                  resolved_at
           FROM reports
           WHERE ($1::text IS NULL OR status = $1)
           ORDER BY created_at DESC
           LIMIT $2 OFFSET $3"#,
    )
    .bind(status)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    let rows: Vec<ReportRow> = raw
        .iter()
        .map(|r| ReportRow {
            id: r.get("id"),
            reporter_id: r.get("reporter_id"),
            target_user_id: r.get("target_user_id"),
            target_kind: r.get("target_kind"),
            target_id: r.get("target_id"),
            reason: r.get("reason"),
            status: r.get("status"),
            created_at: r.get("created_at"),
            resolved_at: r.get("resolved_at"),
        })
        .collect();

    let total = sqlx::query_scalar::<_, i64>(
        r#"SELECT COUNT(*) as "count!"
           FROM reports
           WHERE ($1::text IS NULL OR status = $1)"#,
    )
    .bind(status)
    .fetch_one(pool)
    .await?;

    Ok((rows, total))
}

/// Actualiza el status de un reporte. No toca `resolved_at`.
pub async fn update_report_status(
    pool: &Pool,
    id: Uuid,
    status: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE reports SET status = $2 WHERE id = $1",
        id,
        status
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// Resuelve un reporte: actualiza status y fija `resolved_at = now()`.
pub async fn resolve_report(
    pool: &Pool,
    id: Uuid,
    status: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE reports SET status = $2, resolved_at = now() WHERE id = $1",
        id,
        status
    )
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Moderation Actions
// ---------------------------------------------------------------------------

/// Crea un registro en `moderation_actions` asociado al staff moderator.
///
/// Usa `query_scalar` (no macro) porque la columna `note` es nullable y el
/// macro require manejo explicito de Option<&str>.
pub async fn create_moderation_action(
    pool: &Pool,
    staff_id: Uuid,
    target_user_id: Uuid,
    action: &str,
    note: Option<&str>,
) -> anyhow::Result<Uuid> {
    let id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO moderation_actions
               (staff_id, moderator_id, target_user_id, action, note)
           VALUES ($1, NULL, $2, $3, $4)
           RETURNING id"#,
    )
    .bind(staff_id)
    .bind(target_user_id)
    .bind(action)
    .bind(note)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

// ---------------------------------------------------------------------------
// Photo Moderation
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct PhotoModerationRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub r2_key: String,
    pub is_nsfw: bool,
    pub moderation_status: String,
    pub created_at: OffsetDateTime,
}

/// Lista fotos con `moderation_status = 'pending'`, ordenadas ASC por fecha
/// (las mas antiguas primero). Paginado.
///
/// Retorna (rows, total_count).
pub async fn list_pending_photos(
    pool: &Pool,
    limit: i64,
    offset: i64,
) -> anyhow::Result<(Vec<PhotoModerationRow>, i64)> {
    let rows = sqlx::query_as!(
        PhotoModerationRow,
        r#"SELECT id,
                  user_id,
                  r2_key,
                  is_nsfw,
                  moderation_status,
                  created_at
           FROM photos
           WHERE moderation_status = 'pending'
           ORDER BY created_at ASC
           LIMIT $1 OFFSET $2"#,
        limit,
        offset
    )
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar!(
        r#"SELECT COUNT(*) as "count!" FROM photos WHERE moderation_status = 'pending'"#,
    )
    .fetch_one(pool)
    .await?;

    Ok((rows, total))
}

/// Actualiza el `moderation_status` de una foto.
pub async fn update_photo_moderation(
    pool: &Pool,
    id: Uuid,
    status: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE photos SET moderation_status = $2 WHERE id = $1",
        id,
        status
    )
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// CSAM
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct CsamRow {
    pub id: Uuid,
    pub photo_id: Option<Uuid>,
    pub hash: Option<String>,
    pub source: Option<String>,
    pub status: String,
    pub matched_at: OffsetDateTime,
    pub reported_to_authority_at: Option<OffsetDateTime>,
    pub notes: Option<String>,
}

/// Lista hits de CSAM con filtro opcional por status. Paginado.
///
/// Retorna (rows, total_count).
pub async fn list_csam_hits(
    pool: &Pool,
    status: Option<&str>,
    limit: i64,
    offset: i64,
) -> anyhow::Result<(Vec<CsamRow>, i64)> {
    use sqlx::Row;

    let raw = sqlx::query(
        r#"SELECT id,
                  photo_id,
                  hash,
                  source,
                  status,
                  matched_at,
                  reported_to_authority_at,
                  notes
           FROM csam_hits
           WHERE ($1::text IS NULL OR status = $1)
           ORDER BY matched_at DESC
           LIMIT $2 OFFSET $3"#,
    )
    .bind(status)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    let rows: Vec<CsamRow> = raw
        .iter()
        .map(|r| CsamRow {
            id: r.get("id"),
            photo_id: r.get("photo_id"),
            hash: r.get("hash"),
            source: r.get("source"),
            status: r.get("status"),
            matched_at: r.get("matched_at"),
            reported_to_authority_at: r.get("reported_to_authority_at"),
            notes: r.get("notes"),
        })
        .collect();

    let total = sqlx::query_scalar::<_, i64>(
        r#"SELECT COUNT(*) as "count!"
           FROM csam_hits
           WHERE ($1::text IS NULL OR status = $1)"#,
    )
    .bind(status)
    .fetch_one(pool)
    .await?;

    Ok((rows, total))
}

/// Actualiza el status de un hit de CSAM.
pub async fn update_csam_status(
    pool: &Pool,
    id: Uuid,
    status: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE csam_hits SET status = $2 WHERE id = $1",
        id,
        status
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// Marca un hit de CSAM como reportado a la autoridad.
///
/// Setea `status = 'reported'`, `reported_to_authority_at = now()`, y
/// actualiza `notes` si se proporciona.
pub async fn report_csam_hit(
    pool: &Pool,
    id: Uuid,
    notes: Option<&str>,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"UPDATE csam_hits
           SET status = 'reported',
               reported_to_authority_at = now(),
               notes = COALESCE($2, notes)
           WHERE id = $1"#,
        id,
        notes
    )
    .execute(pool)
    .await?;
    Ok(())
}
