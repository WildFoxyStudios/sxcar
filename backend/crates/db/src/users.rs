use crate::Pool;

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
