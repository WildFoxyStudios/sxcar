use crate::Pool;
use time::OffsetDateTime;

#[derive(Debug)]
pub struct StaffRow {
    pub id: uuid::Uuid,
    pub email: String,
    pub password_hash: String,
    pub totp_secret_enc: Vec<u8>,
    pub recovery_codes_hash: Vec<String>,
    pub role: String,
    pub status: String,
    pub failed_login_count: i32,
    pub locked_until: Option<OffsetDateTime>,
    pub last_login_at: Option<OffsetDateTime>,
    pub last_login_ip: Option<String>,
    pub created_at: OffsetDateTime,
}

#[derive(Debug)]
pub struct StaffSessionRow {
    pub id: uuid::Uuid,
    pub staff_id: uuid::Uuid,
    pub expires_at: OffsetDateTime,
    pub revoked_at: Option<OffsetDateTime>,
    pub ip: Option<String>,
}

/// Busca un miembro del staff por email (case-insensitive vía citext).
/// Devuelve todas las columnas del row type o `None` si no existe.
pub async fn find_staff_by_email(
    pool: &Pool,
    email: &str,
) -> anyhow::Result<Option<StaffRow>> {
    let row = sqlx::query_as!(
        StaffRow,
        r#"SELECT id,
                  email::text as "email!",
                  password_hash,
                  totp_secret_enc,
                  recovery_codes_hash,
                  role,
                  status,
                  failed_login_count,
                  locked_until,
                  last_login_at,
                  last_login_ip::text as "last_login_ip?",
                  created_at
           FROM staff
           WHERE email = $1"#,
        email
    )
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Actualiza `last_login_at`, `last_login_ip` y resetea `failed_login_count` a 0.
///
/// Nota: usa `sqlx::query` (no macro) porque `$2::inet` requiere el feature
/// `ipnetwork` que no está habilitado en el workspace.
pub async fn update_last_login(
    pool: &Pool,
    staff_id: uuid::Uuid,
    ip: Option<&str>,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"UPDATE staff
           SET last_login_at = now(),
               last_login_ip = $2::inet,
               failed_login_count = 0
           WHERE id = $1"#,
    )
    .bind(staff_id)
    .bind(ip)
    .execute(pool)
    .await?;
    Ok(())
}

/// Incrementa `failed_login_count` en 1. Si el contador llega a >= 5,
/// establece `locked_until = now() + 15 minutes`.
///
/// Devuelve `Some(locked_until)` si la cuenta está lockeada (locked_until > now()),
/// o `None` si no lo está.
pub async fn increment_failed_login(
    pool: &Pool,
    staff_id: uuid::Uuid,
) -> anyhow::Result<Option<OffsetDateTime>> {
    let locked = sqlx::query_scalar!(
        r#"UPDATE staff
           SET failed_login_count = failed_login_count + 1,
               locked_until = CASE
                 WHEN failed_login_count + 1 >= 5 THEN now() + interval '15 minutes'
                 ELSE locked_until
               END
           WHERE id = $1
           RETURNING locked_until"#,
        staff_id
    )
    .fetch_optional(pool)
    .await?
    .flatten();
    Ok(locked)
}

/// Crea una nueva sesión de staff en `staff_sessions` y devuelve el `id` generado.
///
/// Nota: usa `sqlx::query_scalar` (no macro) porque `$3::inet` requiere el
/// feature `ipnetwork` que no está habilitado en el workspace.
pub async fn create_session(
    pool: &Pool,
    staff_id: uuid::Uuid,
    expires_at: OffsetDateTime,
    ip: Option<&str>,
    user_agent: Option<&str>,
) -> anyhow::Result<uuid::Uuid> {
    let id: uuid::Uuid = sqlx::query_scalar(
        r#"INSERT INTO staff_sessions (staff_id, expires_at, ip, user_agent)
           VALUES ($1, $2, $3::inet, $4)
           RETURNING id"#,
    )
    .bind(staff_id)
    .bind(expires_at)
    .bind(ip)
    .bind(user_agent)
    .fetch_one(pool)
    .await?;
    Ok(id)
}

/// Busca una sesión activa por `id`. Se considera activa si `revoked_at IS NULL`
/// y `expires_at > now()`. Devuelve el row type o `None`.
pub async fn find_active_session(
    pool: &Pool,
    session_id: uuid::Uuid,
) -> anyhow::Result<Option<StaffSessionRow>> {
    let row = sqlx::query_as!(
        StaffSessionRow,
        r#"SELECT id,
                  staff_id,
                  expires_at,
                  revoked_at,
                  ip::text as "ip?"
           FROM staff_sessions
           WHERE id = $1 AND revoked_at IS NULL AND expires_at > now()"#,
        session_id
    )
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Revoca una sesión de staff: marca `revoked_at = now()` y almacena el motivo.
pub async fn revoke_session(
    pool: &Pool,
    session_id: uuid::Uuid,
    reason: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"UPDATE staff_sessions
           SET revoked_at = now(),
               revoked_reason = $2
           WHERE id = $1"#,
        session_id,
        reason
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// Actualiza `last_seen_at` de una sesión de staff a `now()`.
pub async fn update_session_last_seen(
    pool: &Pool,
    session_id: uuid::Uuid,
) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE staff_sessions SET last_seen_at = now() WHERE id = $1",
        session_id
    )
    .execute(pool)
    .await?;
    Ok(())
}
