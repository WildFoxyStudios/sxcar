use crate::Pool;
use serde_json::Value as JsonValue;
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

/// Resultado de intentar reclamar (revocar-y-quedarse) un refresh token de
/// forma atómica para la rotación.
pub enum RefreshClaim {
    /// El token se reclamó con éxito en esta operación (era válido y no
    /// revocado). Se devuelve el `user_id` y si estaba expirado.
    Claimed { user_id: uuid::Uuid, expired: bool },
    /// El token existe pero YA estaba revocado (reuse/double-spend detectado).
    /// Se devuelve el `user_id` para poder revocar toda la familia.
    AlreadyRevoked { user_id: uuid::Uuid },
    /// El token no existe.
    NotFound,
}

/// Bug 2 (P2): rotación atómica del refresh token.
///
/// Ejecuta un único `UPDATE ... WHERE revoked_at IS NULL RETURNING` de modo que
/// dos peticiones concurrentes con el mismo token NO puedan pasar ambas el
/// chequeo (evita double-spend / reuse race). Si el UPDATE no afecta filas,
/// se hace un SELECT para distinguir entre "ya revocado" (reuse) y "no existe".
///
/// Runtime query (`sqlx::query`), no macro, intencionalmente.
pub async fn revoke_and_claim_refresh(
    pool: &Pool,
    token_hash: &str,
) -> anyhow::Result<RefreshClaim> {
    // Reclamo atómico: solo una petición puede pasar de revoked_at NULL -> now().
    let claimed = sqlx::query_as::<_, (uuid::Uuid, bool)>(
        r#"UPDATE refresh_tokens
           SET revoked_at = now()
           WHERE token_hash = $1 AND revoked_at IS NULL
           RETURNING user_id, (expires_at < now()) AS expired"#,
    )
    .bind(token_hash)
    .fetch_optional(pool)
    .await?;

    if let Some((user_id, expired)) = claimed {
        return Ok(RefreshClaim::Claimed { user_id, expired });
    }

    // No se reclamó: o no existe, o ya estaba revocado (reuse).
    let existing = sqlx::query_scalar::<_, uuid::Uuid>(
        "SELECT user_id FROM refresh_tokens WHERE token_hash = $1",
    )
    .bind(token_hash)
    .fetch_optional(pool)
    .await?;

    Ok(match existing {
        Some(user_id) => RefreshClaim::AlreadyRevoked { user_id },
        None => RefreshClaim::NotFound,
    })
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
///
/// Bug 3 (P1) — mitigación de fuerza bruta de códigos de 6 dígitos.
/// La tabla `auth_codes` (migración 0010) NO tiene columna de intentos, y no
/// debemos inventar una migración aquí. Mitigación que encaja en el esquema
/// actual: si el código presentado es INCORRECTO, se invalidan (consumed_at)
/// todos los códigos vigentes de ese (user, kind). Así cada código emitido es
/// de un solo intento ("single-guess"): tras un fallo el usuario debe solicitar
/// uno nuevo, reduciendo la probabilidad de adivinar de ~n/1e6 a 1/1e6 por
/// código. La invalidación se hace en un único statement condicional para no
/// borrar el código en el camino feliz (acierto).
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
    if res.rows_affected() == 1 {
        return Ok(true);
    }
    // Fallo: invalida TODOS los códigos vigentes de este (user, kind) para que
    // el intento haya sido de una sola oportunidad. Runtime query (no macro).
    sqlx::query(
        r#"UPDATE auth_codes SET consumed_at = now()
           WHERE user_id = $1 AND kind = $2
             AND consumed_at IS NULL AND expires_at > now()"#,
    )
    .bind(user_id)
    .bind(kind)
    .execute(pool)
    .await?;
    Ok(false)
}

/// Devuelve el `status` de un usuario (active, banned, suspended, deleted,
/// shadowbanned) o `None` si el usuario no existe. Consulta ligera usada en el
/// hot path de auth (extractor / refresh / oauth) para bloquear cuentas no
/// activas. Usa `query_scalar` runtime (no macro) intencionalmente.
pub async fn user_status(pool: &Pool, id: uuid::Uuid) -> anyhow::Result<Option<String>> {
    let s = sqlx::query_scalar::<_, String>("SELECT status FROM users WHERE id = $1")
        .bind(id)
        .fetch_optional(pool)
        .await?;
    Ok(s)
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
    pub profile_photo_key: Option<String>,
    pub verified: bool,
    // NEW (T4.2):
    pub details: JsonValue,
    pub show_age: bool,
    pub show_role: bool,
    pub show_tribes: bool,
    pub show_position: bool,
    pub show_ethnicity: bool,
    pub show_relationship_status: bool,
    pub show_social_links: bool,
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
                  p.profile_photo_key,
                  (SELECT r2_key FROM photos WHERE user_id = u.id AND is_primary = true LIMIT 1)
                    as "profile_photo_url",
                  COALESCE(p.verified, false) as "verified!",
                  COALESCE(p.details, '{}'::jsonb) as "details!",
                  COALESCE(p.show_age, true)                  as "show_age!",
                  COALESCE(p.show_role, true)                as "show_role!",
                  COALESCE(p.show_tribes, true)              as "show_tribes!",
                  COALESCE(p.show_position, true)            as "show_position!",
                  COALESCE(p.show_ethnicity, true)           as "show_ethnicity!",
                  COALESCE(p.show_relationship_status, true) as "show_relationship_status!",
                  COALESCE(p.show_social_links, true)        as "show_social_links!"
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

// ---------------------------------------------------------------------------
// Online indicator / last_seen
// ---------------------------------------------------------------------------

/// Update `users.last_seen_at` for a user to "now()". Idempotent.
pub async fn touch_last_seen(pool: &Pool, user_id: uuid::Uuid) -> anyhow::Result<()> {
    sqlx::query!(
        "UPDATE users SET last_seen_at = now() WHERE id = $1",
        user_id
    )
    .execute(pool)
    .await?;
    Ok(())
}

#[derive(Debug, serde::Serialize)]
pub struct UserStatusRow {
    pub user_id: uuid::Uuid,
    pub is_online: bool,
    pub last_seen_at: Option<time::OffsetDateTime>,
}

/// Returns online/last_seen status for one user. `is_online` is true if
/// `last_seen_at` is within the last 5 minutes.
pub async fn get_user_status(
    pool: &Pool,
    user_id: uuid::Uuid,
) -> anyhow::Result<Option<UserStatusRow>> {
    let row = sqlx::query!(
        r#"SELECT id as "user_id!", last_seen_at
           FROM users WHERE id = $1"#,
        user_id
    )
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| {
        let is_online = r
            .last_seen_at
            .map(|t| (time::OffsetDateTime::now_utc() - t).whole_seconds() < 300)
            .unwrap_or(false);
        UserStatusRow {
            user_id: r.user_id,
            is_online,
            last_seen_at: r.last_seen_at,
        }
    }))
}

/// Returns online/last_seen for many users in one query. Useful for grid.
pub async fn get_user_statuses(
    pool: &Pool,
    user_ids: &[uuid::Uuid],
) -> anyhow::Result<Vec<UserStatusRow>> {
    if user_ids.is_empty() {
        return Ok(vec![]);
    }
    let rows = sqlx::query!(
        r#"SELECT id as "user_id!", last_seen_at
           FROM users WHERE id = ANY($1)"#,
        user_ids
    )
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|r| {
            let is_online = r
                .last_seen_at
                .map(|t| (time::OffsetDateTime::now_utc() - t).whole_seconds() < 300)
                .unwrap_or(false);
            UserStatusRow {
                user_id: r.user_id,
                is_online,
                last_seen_at: r.last_seen_at,
            }
        })
        .collect())
}

/// Anonymizes a user's PII and marks the account as deleted (soft-delete).
/// Sets `deleted_at` to now() and returns the scheduled deletion date
/// (30 days from now, after which a hard-delete can be considered).
///
/// GDPR: data is kept for 30 days after anonymization per audit trail policy.
pub async fn anonymize_user(pool: &Pool, user_id: uuid::Uuid) -> anyhow::Result<time::OffsetDateTime> {
    let anonymized_email = format!("deleted_{user_id}@anonymized");
    let deletion_date = time::OffsetDateTime::now_utc() + time::Duration::days(30);

    sqlx::query!(
        r#"
        WITH
          upd_users AS (
            UPDATE users
            SET email            = $2,
                password_hash    = NULL,
                phone            = NULL,
                phone_verified   = false,
                email_verified   = false,
                status           = 'deleted',
                deleted_at       = now()
            WHERE id = $1
          )
        UPDATE profiles
        SET display_name       = NULL,
            about              = NULL,
            position           = NULL,
            body_type          = NULL,
            height_cm          = NULL,
            weight_kg          = NULL,
            relationship_status = NULL,
            gender_identity    = NULL,
            pronouns           = NULL,
            hiv_status         = NULL,
            last_tested_on     = NULL,
            prep               = NULL,
            profile_photo_id   = NULL,
            profile_photo_key  = NULL,
            details            = '{}'::jsonb
        WHERE user_id = $1
        "#,
        user_id,
        anonymized_email
    )
    .execute(pool)
    .await?;

    // P0-3: elimina las identidades OAuth para que el `sub` de Google/Apple ya
    // no pueda resolver esta cuenta muerta (evita "resurrección" vía OAuth login).
    // Runtime query (no macro) intencionalmente.
    sqlx::query("DELETE FROM auth_identities WHERE user_id = $1")
        .bind(user_id)
        .execute(pool)
        .await?;

    Ok(deletion_date)
}
