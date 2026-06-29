//! AD4 — Support + GDPR + LER queries.
//!
//! Entitlements, Data Requests (DSAR), Access Events,
//! Legal Holds, and Legal Dossier.

use crate::Pool;
use time::OffsetDateTime;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Entitlements
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct SubscriptionRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub tier: String,
    pub store: Option<String>,
    pub revenuecat_id: Option<String>,
    pub status: Option<String>,
    pub current_period_end: Option<OffsetDateTime>,
}

#[derive(Debug)]
pub struct EntitlementRow {
    pub user_id: Uuid,
    pub feature: String,
    pub enabled: bool,
}

pub async fn list_subscriptions(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Vec<SubscriptionRow>> {
    let rows = sqlx::query_as!(
        SubscriptionRow,
        r#"SELECT id, user_id, tier, store, revenuecat_id, status, current_period_end
           FROM subscriptions
           WHERE user_id = $1
           ORDER BY created_at DESC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn list_entitlements(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Vec<EntitlementRow>> {
    let rows = sqlx::query_as!(
        EntitlementRow,
        r#"SELECT user_id, feature, enabled
           FROM entitlements
           WHERE user_id = $1"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn grant_entitlement(
    pool: &Pool,
    user_id: Uuid,
    feature: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"INSERT INTO entitlements (user_id, feature, enabled)
           VALUES ($1, $2, true)
           ON CONFLICT (user_id, feature) DO UPDATE SET enabled = true"#,
        user_id,
        feature
    )
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn revoke_entitlement(
    pool: &Pool,
    user_id: Uuid,
    feature: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"UPDATE entitlements SET enabled = false
           WHERE user_id = $1 AND feature = $2"#,
        user_id,
        feature
    )
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Data requests (DSAR)
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct DataRequestRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub kind: String,
    pub status: String,
    pub requested_at: OffsetDateTime,
    pub completed_at: Option<OffsetDateTime>,
}

pub async fn list_data_requests(
    pool: &Pool,
    status: Option<&str>,
    limit: i64,
    offset: i64,
) -> anyhow::Result<(Vec<DataRequestRow>, i64)> {
    use sqlx::Row;

    let raw = sqlx::query(
        r#"SELECT id, user_id, kind, status, requested_at, completed_at
           FROM data_requests
           WHERE ($1::text IS NULL OR status = $1)
           ORDER BY requested_at DESC
           LIMIT $2 OFFSET $3"#,
    )
    .bind(status)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    let rows: Vec<DataRequestRow> = raw
        .iter()
        .map(|r| DataRequestRow {
            id: r.get("id"),
            user_id: r.get("user_id"),
            kind: r.get("kind"),
            status: r.get("status"),
            requested_at: r.get("requested_at"),
            completed_at: r.get("completed_at"),
        })
        .collect();

    let total = sqlx::query_scalar::<_, i64>(
        r#"SELECT COUNT(*) as "count!"
           FROM data_requests
           WHERE ($1::text IS NULL OR status = $1)"#,
    )
    .bind(status)
    .fetch_one(pool)
    .await?;

    Ok((rows, total))
}

pub async fn update_data_request(
    pool: &Pool,
    id: Uuid,
    status: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"UPDATE data_requests
           SET status = $2,
               completed_at = CASE WHEN $2 IN ('completed','rejected') THEN now() ELSE completed_at END
           WHERE id = $1"#,
        id,
        status
    )
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Access events (LER)
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct AccessEventRow {
    pub id: Uuid,
    pub event: String,
    pub ip: Option<String>,
    pub user_agent: Option<String>,
    pub created_at: OffsetDateTime,
}

pub async fn list_access_events(
    pool: &Pool,
    user_id: Uuid,
    limit: i64,
) -> anyhow::Result<Vec<AccessEventRow>> {
    let rows = sqlx::query_as!(
        AccessEventRow,
        r#"SELECT id, event, ip::text as "ip?", user_agent, created_at
           FROM access_events
           WHERE user_id = $1
           ORDER BY created_at DESC
           LIMIT $2"#,
        user_id,
        limit
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// Legal holds
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct LegalHoldRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub reason: String,
    pub reference: Option<String>,
    pub placed_by: Uuid,
    pub placed_at: OffsetDateTime,
    pub released_at: Option<OffsetDateTime>,
}

pub async fn place_legal_hold(
    pool: &Pool,
    user_id: Uuid,
    placed_by: Uuid,
    reason: &str,
    reference: Option<&str>,
) -> anyhow::Result<Uuid> {
    let id = sqlx::query_scalar(
        r#"INSERT INTO legal_holds (user_id, placed_by, reason, reference)
           VALUES ($1, $2, $3, $4)
           RETURNING id"#,
    )
    .bind(user_id)
    .bind(placed_by)
    .bind(reason)
    .bind(reference)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

pub async fn release_legal_hold(
    pool: &Pool,
    id: Uuid,
    released_by: Uuid,
    reason: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"UPDATE legal_holds
           SET released_at = now(), released_by = $2, release_reason = $3
           WHERE id = $1 AND released_at IS NULL"#,
        id,
        released_by,
        reason
    )
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn list_legal_holds(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<Vec<LegalHoldRow>> {
    let rows = sqlx::query_as!(
        LegalHoldRow,
        r#"SELECT id, user_id, reason, reference, placed_by, placed_at, released_at
           FROM legal_holds
           WHERE user_id = $1
           ORDER BY placed_at DESC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

// ---------------------------------------------------------------------------
// Legal dossier (LER full export)
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct ProfileRow {
    pub user_id: Uuid,
    pub display_name: Option<String>,
    pub about: Option<String>,
    pub gender_identity: Option<String>,
    pub relationship_status: Option<String>,
    pub created_at: OffsetDateTime,
}

#[derive(Debug)]
pub struct DeviceRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub platform: Option<String>,
    pub last_seen_at: Option<OffsetDateTime>,
    pub created_at: OffsetDateTime,
}

#[derive(Debug)]
pub struct PhotoRow {
    pub id: Uuid,
    pub user_id: Uuid,
    pub r2_key: String,
    pub is_primary: bool,
    pub is_nsfw: bool,
    pub moderation_status: String,
    pub created_at: OffsetDateTime,
}

#[derive(Debug)]
pub struct ConsentRow {
    pub id: Uuid,
    pub kind: String,
    pub version: String,
    pub granted_at: OffsetDateTime,
}

#[derive(Debug)]
pub struct LegalDossier {
    pub user: crate::users::UserRow,
    pub profile: Option<ProfileRow>,
    pub devices: Vec<DeviceRow>,
    pub access_events: Vec<AccessEventRow>,
    pub photos: Vec<PhotoRow>,
    pub subscriptions: Vec<SubscriptionRow>,
    pub reports_against: Vec<crate::moderation::ReportRow>,
    pub reports_by: Vec<crate::moderation::ReportRow>,
    pub consent_records: Vec<ConsentRow>,
    pub legal_holds: Vec<LegalHoldRow>,
}

/// Construye un dossier legal completo para un usuario.
///
/// Ejecuta consultas separadas por cada categoria y las ensambla.
/// Retorna error si el usuario no existe.
pub async fn build_legal_dossier(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<LegalDossier> {
    let user = crate::users::find_user_by_id(pool, user_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("user not found: {user_id}"))?;

    let profile = sqlx::query_as!(
        ProfileRow,
        r#"SELECT user_id, display_name, about, gender_identity,
                  relationship_status, created_at
           FROM profiles
           WHERE user_id = $1"#,
        user_id
    )
    .fetch_optional(pool)
    .await?;

    let devices = sqlx::query_as!(
        DeviceRow,
        r#"SELECT id, user_id, platform, last_seen_at, created_at
           FROM devices
           WHERE user_id = $1
           ORDER BY created_at DESC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;

    let access_events = list_access_events(pool, user_id, 100).await?;

    let photos = sqlx::query_as!(
        PhotoRow,
        r#"SELECT id, user_id, r2_key, is_primary, is_nsfw,
                  moderation_status, created_at
           FROM photos
           WHERE user_id = $1
           ORDER BY created_at DESC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;

    let subscriptions = list_subscriptions(pool, user_id).await?;

    let reports_against = sqlx::query_as!(
        crate::moderation::ReportRow,
        r#"SELECT id, reporter_id, target_user_id, target_kind,
                  target_id, reason, status, created_at, resolved_at
           FROM reports
           WHERE target_user_id = $1
           ORDER BY created_at DESC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;

    let reports_by = sqlx::query_as!(
        crate::moderation::ReportRow,
        r#"SELECT id, reporter_id, target_user_id, target_kind,
                  target_id, reason, status, created_at, resolved_at
           FROM reports
           WHERE reporter_id = $1
           ORDER BY created_at DESC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;

    let consent_records = sqlx::query_as!(
        ConsentRow,
        r#"SELECT id, kind, version, granted_at
           FROM consent_records
           WHERE user_id = $1
           ORDER BY granted_at DESC"#,
        user_id
    )
    .fetch_all(pool)
    .await?;

    let legal_holds = list_legal_holds(pool, user_id).await?;

    Ok(LegalDossier {
        user,
        profile,
        devices,
        access_events,
        photos,
        subscriptions,
        reports_against,
        reports_by,
        consent_records,
        legal_holds,
    })
}
