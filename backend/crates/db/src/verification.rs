//! Profile photo verification: submit a pose photo, track approval, expose the
//! `verified` badge. Admin approves/rejects via the moderation surface.

use crate::Pool;
use uuid::Uuid;

/// Current verification state for a user.
#[derive(Debug)]
pub struct VerificationStatus {
    pub verified: bool,
    pub pending: bool,
}

/// Submit a verification photo. Records a pending request and stamps
/// `profiles.verification_submitted_at`. Idempotent-ish: a new submission
/// simply adds another pending request.
pub async fn submit_verification(
    pool: &Pool,
    user_id: Uuid,
    photo_key: &str,
) -> anyhow::Result<Uuid> {
    let mut tx = pool.begin().await?;
    let row = sqlx::query!(
        r#"INSERT INTO verification_requests (user_id, photo_key)
           VALUES ($1, $2)
           RETURNING id"#,
        user_id,
        photo_key,
    )
    .fetch_one(&mut *tx)
    .await?;
    sqlx::query!(
        r#"UPDATE profiles SET verification_submitted_at = now() WHERE user_id = $1"#,
        user_id,
    )
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(row.id)
}

/// Get the verification status for a user: whether the profile is verified,
/// and whether there is a pending (not-yet-reviewed) request.
pub async fn get_verification_status(
    pool: &Pool,
    user_id: Uuid,
) -> anyhow::Result<VerificationStatus> {
    let verified = sqlx::query_scalar!(
        r#"SELECT verified FROM profiles WHERE user_id = $1"#,
        user_id,
    )
    .fetch_optional(pool)
    .await?
    .unwrap_or(false);

    let pending = sqlx::query_scalar!(
        r#"SELECT EXISTS(
             SELECT 1 FROM verification_requests
             WHERE user_id = $1 AND status = 'pending'
           )"#,
        user_id,
    )
    .fetch_one(pool)
    .await?
    .unwrap_or(false);

    Ok(VerificationStatus { verified, pending })
}

/// Admin: approve a verification request and flip the profile's verified flag.
pub async fn approve_verification(pool: &Pool, request_id: Uuid) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    let row = sqlx::query!(
        r#"UPDATE verification_requests
           SET status = 'approved', reviewed_at = now()
           WHERE id = $1 AND status = 'pending'
           RETURNING user_id"#,
        request_id,
    )
    .fetch_optional(&mut *tx)
    .await?;
    if let Some(r) = row {
        sqlx::query!(
            r#"UPDATE profiles SET verified = true WHERE user_id = $1"#,
            r.user_id,
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}
