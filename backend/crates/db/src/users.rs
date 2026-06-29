use crate::Pool;
use time::{Date, OffsetDateTime};

#[derive(Debug)]
pub struct NewUser {
    pub email: String,
    pub password_hash: Option<String>,
}

#[derive(Debug)]
pub struct UserRow {
    pub id: uuid::Uuid,
    pub email: String,
    pub email_verified: bool,
    pub status: String,
    pub role: String,
    pub created_at: time::OffsetDateTime,
}

pub async fn create_user(pool: &Pool, new: NewUser) -> anyhow::Result<uuid::Uuid> {
    let id = sqlx::query_scalar!(
        "INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id",
        new.email,
        new.password_hash
    )
    .fetch_one(pool)
    .await?;
    Ok(id)
}

/// Busca un usuario por email (case-insensitive vía citext).
///
/// NOTA: no filtra `deleted_at`. La visibilidad de cuentas con soft-delete se
/// decide en la capa de aplicación (F0.3+), caso por caso (p. ej. recuperación
/// de cuenta vs. login); se añadirá un helper "solo activos" en su fase.
pub async fn find_user_by_email(pool: &Pool, email: &str) -> anyhow::Result<Option<UserRow>> {
    let row = sqlx::query_as!(
        UserRow,
        r#"SELECT id, email::text as "email!", email_verified, status, role, created_at
           FROM users WHERE email = $1"#,
        email
    )
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

pub async fn add_auth_identity(
    pool: &Pool,
    user_id: uuid::Uuid,
    provider: &str,
    provider_uid: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        "INSERT INTO auth_identities (user_id, provider, provider_uid) VALUES ($1, $2, $3)",
        user_id,
        provider,
        provider_uid
    )
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn record_consent(
    pool: &Pool,
    user_id: uuid::Uuid,
    kind: &str,
    version: &str,
) -> anyhow::Result<()> {
    sqlx::query!(
        "INSERT INTO consent_records (user_id, kind, version) VALUES ($1, $2, $3)",
        user_id,
        kind,
        version
    )
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn create_user_full(
    pool: &Pool,
    email: &str,
    password_hash: Option<&str>,
    dob: Option<Date>,
    age_verified: bool,
) -> anyhow::Result<uuid::Uuid> {
    let id = sqlx::query_scalar!(
        "INSERT INTO users (email, password_hash, dob, age_verified)
         VALUES ($1, $2, $3, $4) RETURNING id",
        email,
        password_hash,
        dob,
        age_verified
    )
    .fetch_one(pool)
    .await?;
    Ok(id)
}

pub async fn find_user_by_id(pool: &Pool, id: uuid::Uuid) -> anyhow::Result<Option<UserRow>> {
    let row = sqlx::query_as!(
        UserRow,
        r#"SELECT id, email::text as "email!", email_verified, status, role, created_at
           FROM users WHERE id = $1"#,
        id
    )
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

pub async fn set_email_verified(pool: &Pool, id: uuid::Uuid) -> anyhow::Result<()> {
    sqlx::query!("UPDATE users SET email_verified = true WHERE id = $1", id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn set_phone_verified(pool: &Pool, id: uuid::Uuid) -> anyhow::Result<()> {
    sqlx::query!("UPDATE users SET phone_verified = true WHERE id = $1", id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn update_password(pool: &Pool, id: uuid::Uuid, hash: &str) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE users SET password_hash = $2 WHERE id = $1",
        id,
        hash
    )
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn find_auth_identity(
    pool: &Pool,
    provider: &str,
    provider_uid: &str,
) -> anyhow::Result<Option<uuid::Uuid>> {
    let id = sqlx::query_scalar!(
        "SELECT user_id FROM auth_identities WHERE provider = $1 AND provider_uid = $2",
        provider,
        provider_uid
    )
    .fetch_optional(pool)
    .await?;
    Ok(id)
}

pub struct RefreshRow {
    pub user_id: uuid::Uuid,
    pub revoked: bool,
    pub expired: bool,
}

pub async fn store_refresh_token(
    pool: &Pool,
    user_id: uuid::Uuid,
    token_hash: &str,
    expires_at: OffsetDateTime,
) -> anyhow::Result<()> {
    sqlx::query!(
        "INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)",
        user_id,
        token_hash,
        expires_at
    )
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn find_refresh_token(
    pool: &Pool,
    token_hash: &str,
) -> anyhow::Result<Option<RefreshRow>> {
    let row = sqlx::query!(
        r#"SELECT user_id,
                  (revoked_at IS NOT NULL) as "revoked!",
                  (expires_at < now()) as "expired!"
           FROM refresh_tokens WHERE token_hash = $1"#,
        token_hash
    )
    .fetch_optional(pool)
    .await?;
    Ok(row.map(|r| RefreshRow {
        user_id: r.user_id,
        revoked: r.revoked,
        expired: r.expired,
    }))
}

pub async fn revoke_refresh_token(pool: &Pool, token_hash: &str) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE refresh_tokens SET revoked_at = now() WHERE token_hash = $1 AND revoked_at IS NULL",
        token_hash
    )
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn revoke_all_refresh(pool: &Pool, user_id: uuid::Uuid) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL",
        user_id
    )
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn issue_auth_code(
    pool: &Pool,
    user_id: uuid::Uuid,
    kind: &str,
    code_hash: &str,
    expires_at: OffsetDateTime,
) -> anyhow::Result<()> {
    sqlx::query!(
        "INSERT INTO auth_codes (user_id, kind, code_hash, expires_at) VALUES ($1,$2,$3,$4)",
        user_id,
        kind,
        code_hash,
        expires_at
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// Marca consumido el código válido (no usado, no expirado) más reciente. Devuelve true si lo encontró.
pub async fn consume_auth_code(
    pool: &Pool,
    user_id: uuid::Uuid,
    kind: &str,
    code_hash: &str,
) -> anyhow::Result<bool> {
    let res = sqlx::query!(
        r#"UPDATE auth_codes SET consumed_at = now()
           WHERE id = (
             SELECT id FROM auth_codes
             WHERE user_id = $1 AND kind = $2 AND code_hash = $3
               AND consumed_at IS NULL AND expires_at > now()
             ORDER BY created_at DESC LIMIT 1
           )"#,
        user_id,
        kind,
        code_hash
    )
    .execute(pool)
    .await?;
    Ok(res.rows_affected() == 1)
}

pub async fn password_hash_for(pool: &Pool, id: uuid::Uuid) -> anyhow::Result<Option<String>> {
    let h = sqlx::query_scalar!("SELECT password_hash FROM users WHERE id = $1", id)
        .fetch_optional(pool)
        .await?
        .flatten();
    Ok(h)
}

// ---------------------------------------------------------------------------
// AD2 — Administración de usuarios
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct UserFullRow {
    pub id: uuid::Uuid,
    pub email: String,
    pub email_verified: bool,
    pub status: String,
    pub role: String,
    pub created_at: time::OffsetDateTime,
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub birthdate: Option<time::Date>,
    pub height_cm: Option<i32>,
    pub weight_kg: Option<i32>,
    pub body_type: Option<String>,
    pub relationship_status: Option<String>,
    pub position: Option<String>,
    pub ethnicity: Option<String>,
    pub pronouns: Option<String>,
    pub profile_photo_id: Option<uuid::Uuid>,
    pub profile_photo_url: Option<String>,
}

#[derive(Debug)]
pub struct StatusCount {
    pub status: String,
    pub count: i64,
}

/// Busca usuarios por email o display_name (ILIKE). Paginado.
///
/// Retorna (rows, total_count). El total se calcula solo sobre email
/// (sin JOIN, más rápido) — puede diferir ligeramente del número real
/// de resultados cuando la coincidencia es solo por display_name.
pub async fn search_users(
    pool: &Pool,
    query: &str,
    limit: i64,
    offset: i64,
) -> anyhow::Result<(Vec<UserRow>, i64)> {
    let rows = sqlx::query_as!(
        UserRow,
        r#"SELECT u.id, u.email::text as "email!",
                  u.email_verified, u.status, u.role, u.created_at
           FROM users u
           LEFT JOIN profiles p ON p.user_id = u.id
           WHERE u.email ILIKE '%' || $1 || '%' OR p.display_name ILIKE '%' || $1 || '%'
           ORDER BY u.created_at DESC
           LIMIT $2 OFFSET $3"#,
        query,
        limit,
        offset
    )
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar!(
        r#"SELECT COUNT(*) as "count!" FROM users WHERE email ILIKE '%' || $1 || '%'"#,
        query
    )
    .fetch_one(pool)
    .await?;

    Ok((rows, total))
}

/// Actualiza el status de un usuario. Confía en el CHECK constraint de la DB
/// para validar el valor (active, banned, suspended, deleted, shadowbanned).
pub async fn update_user_status(pool: &Pool, id: uuid::Uuid, status: &str) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE users SET status = $2 WHERE id = $1",
        id,
        status
    )
    .execute(pool)
    .await?;
    Ok(())
}

/// Obtiene un usuario con datos combinados de perfil (display_name, bio,
/// profile_photo_url). JOIN users + profiles + photos. Si no tiene perfil
/// o foto, los campos opcionales son NULL.
pub async fn find_user_full(
    pool: &Pool,
    id: uuid::Uuid,
) -> anyhow::Result<Option<UserFullRow>> {
    let row = sqlx::query_as!(
        UserFullRow,
        r#"SELECT u.id, u.email::text as "email!",
                  u.email_verified, u.status, u.role, u.created_at,
                  p.display_name, p.about as "bio",
                  p.birthdate, p.height_cm, p.weight_kg,
                  p.body_type, p.relationship_status, p.position,
                  p.ethnicity, p.pronouns, p.profile_photo_id,
                  (SELECT r2_key FROM photos WHERE user_id = u.id AND is_primary = true LIMIT 1)
                    as "profile_photo_url"
           FROM users u
           LEFT JOIN profiles p ON p.user_id = u.id
           WHERE u.id = $1"#,
        id
    )
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

/// Cuenta usuarios agrupados por status (active, banned, suspended, etc.).
pub async fn count_users_by_status(pool: &Pool) -> anyhow::Result<Vec<StatusCount>> {
    let rows = sqlx::query_as!(
        StatusCount,
        r#"SELECT status, COUNT(*) as "count!" FROM users GROUP BY status"#
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}
