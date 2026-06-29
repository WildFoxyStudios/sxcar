use crate::Pool;

/// UPSERT into profiles table. Only sets fields that are `Some(...)`.
/// Fields set to `None` keep their current DB value.
pub async fn upsert_profile(
    pool: &Pool,
    user_id: uuid::Uuid,
    display_name: Option<&str>,
    bio: Option<&str>,
    birthdate: Option<time::Date>,
    height_cm: Option<i32>,
    weight_kg: Option<i32>,
    body_type: Option<&str>,
    relationship_status: Option<&str>,
    position: Option<&str>,
    ethnicity: Option<&str>,
    pronouns: Option<&str>,
) -> anyhow::Result<()> {
    sqlx::query!(
        r#"INSERT INTO profiles (user_id, display_name, about, birthdate, height_cm, weight_kg,
                                 body_type, relationship_status, position, ethnicity, pronouns)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
           ON CONFLICT (user_id) DO UPDATE SET
             display_name         = COALESCE($2, profiles.display_name),
             about                = COALESCE($3, profiles.about),
             birthdate            = COALESCE($4, profiles.birthdate),
             height_cm            = COALESCE($5, profiles.height_cm),
             weight_kg            = COALESCE($6, profiles.weight_kg),
             body_type            = COALESCE($7, profiles.body_type),
             relationship_status  = COALESCE($8, profiles.relationship_status),
             position             = COALESCE($9, profiles.position),
             ethnicity            = COALESCE($10, profiles.ethnicity),
             pronouns             = COALESCE($11, profiles.pronouns)"#,
        user_id,
        display_name,
        bio,
        birthdate,
        height_cm,
        weight_kg,
        body_type,
        relationship_status,
        position,
        ethnicity,
        pronouns,
    )
    .execute(pool)
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Junction table helpers — tribes
// ---------------------------------------------------------------------------

pub async fn get_profile_tribes(pool: &Pool, user_id: uuid::Uuid) -> anyhow::Result<Vec<String>> {
    let rows = sqlx::query_scalar!(
        r#"SELECT tribe FROM profile_tribes WHERE user_id = $1 ORDER BY tribe"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn replace_profile_tribes(
    pool: &Pool,
    user_id: uuid::Uuid,
    tribes: &[String],
) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    sqlx::query!("DELETE FROM profile_tribes WHERE user_id = $1", user_id)
        .execute(&mut *tx)
        .await?;
    for tribe in tribes {
        sqlx::query!(
            "INSERT INTO profile_tribes (user_id, tribe) VALUES ($1, $2)",
            user_id,
            tribe
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Junction table helpers — looking_for
// ---------------------------------------------------------------------------

pub async fn get_profile_looking_for(
    pool: &Pool,
    user_id: uuid::Uuid,
) -> anyhow::Result<Vec<String>> {
    let rows = sqlx::query_scalar!(
        r#"SELECT intent FROM profile_looking_for WHERE user_id = $1 ORDER BY intent"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn replace_profile_looking_for(
    pool: &Pool,
    user_id: uuid::Uuid,
    looking_for: &[String],
) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    sqlx::query!("DELETE FROM profile_looking_for WHERE user_id = $1", user_id)
        .execute(&mut *tx)
        .await?;
    for item in looking_for {
        sqlx::query!(
            "INSERT INTO profile_looking_for (user_id, intent) VALUES ($1, $2)",
            user_id,
            item
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Junction table helpers — meet_at
// ---------------------------------------------------------------------------

pub async fn get_profile_meet_at(pool: &Pool, user_id: uuid::Uuid) -> anyhow::Result<Vec<String>> {
    let rows = sqlx::query_scalar!(
        r#"SELECT place FROM profile_meet_at WHERE user_id = $1 ORDER BY place"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn replace_profile_meet_at(
    pool: &Pool,
    user_id: uuid::Uuid,
    meet_at: &[String],
) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    sqlx::query!("DELETE FROM profile_meet_at WHERE user_id = $1", user_id)
        .execute(&mut *tx)
        .await?;
    for item in meet_at {
        sqlx::query!(
            "INSERT INTO profile_meet_at (user_id, place) VALUES ($1, $2)",
            user_id,
            item
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Junction table helpers — tags
// ---------------------------------------------------------------------------

pub async fn get_profile_tags(pool: &Pool, user_id: uuid::Uuid) -> anyhow::Result<Vec<String>> {
    let rows = sqlx::query_scalar!(
        r#"SELECT tag::text as "tag!" FROM profile_tags WHERE user_id = $1 ORDER BY tag"#,
        user_id
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn replace_profile_tags(
    pool: &Pool,
    user_id: uuid::Uuid,
    tags: &[String],
) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;
    sqlx::query!("DELETE FROM profile_tags WHERE user_id = $1", user_id)
        .execute(&mut *tx)
        .await?;
    for tag in tags {
        sqlx::query!(
            "INSERT INTO profile_tags (user_id, tag) VALUES ($1, $2)",
            user_id,
            tag
        )
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}
