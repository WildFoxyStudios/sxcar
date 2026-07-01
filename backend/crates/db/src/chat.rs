use sqlx::FromRow;
use uuid::Uuid;

/// Row returned by list_conversations.
#[derive(Debug, FromRow)]
pub struct ConversationRow {
    pub conversation_id: Uuid,
    pub other_user_id: Uuid,
    pub other_display_name: Option<String>,
    pub last_message_preview: Option<String>,
    pub last_message_kind: Option<String>,
    pub last_message_at: Option<time::OffsetDateTime>,
    pub unread_count: i64,
}

/// Row returned by list_messages and insert_message.
#[derive(Debug, FromRow, serde::Serialize)]
pub struct MessageRow {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub kind: String,
    pub body: Option<String>,
    pub media_key: Option<String>,
    pub media_type: Option<String>,
    pub caption: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    pub read_at: Option<time::OffsetDateTime>,
    pub created_at: time::OffsetDateTime,
}

/// Input for inserting a message (text or media).
#[derive(Debug, Default)]
pub struct InsertMessage<'a> {
    pub kind: &'a str,
    pub body: Option<&'a str>,
    pub media_key: Option<&'a str>,
    pub media_type: Option<&'a str>,
    pub caption: Option<&'a str>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
}

/// List all conversations for a user, with last message preview and unread count.
pub async fn list_conversations(
    pool: &sqlx::PgPool,
    user_id: Uuid,
) -> anyhow::Result<Vec<ConversationRow>> {
    let rows = sqlx::query_as::<_, ConversationRow>(
        r#"
        WITH my_memberships AS (
            SELECT cm.conversation_id, cm.last_read_at
            FROM conversation_members cm
            WHERE cm.user_id = $1
        )
        SELECT
            c.id AS conversation_id,
            other.user_id AS other_user_id,
            p.display_name AS other_display_name,
            m.body AS last_message_preview,
            m.kind AS last_message_kind,
            c.last_message_at,
            COALESCE((
                SELECT COUNT(*)::bigint
                FROM messages msg
                WHERE msg.conversation_id = c.id
                  AND msg.sender_id != $1
                  AND (mm.last_read_at IS NULL OR msg.created_at > mm.last_read_at)
            ), 0) AS unread_count
        FROM my_memberships mm
        JOIN conversations c ON c.id = mm.conversation_id
        JOIN LATERAL (
            SELECT cm2.user_id
            FROM conversation_members cm2
            WHERE cm2.conversation_id = c.id AND cm2.user_id != $1
            LIMIT 1
        ) other ON true
        LEFT JOIN profiles p ON p.user_id = other.user_id
        LEFT JOIN LATERAL (
            SELECT m.body, m.kind
            FROM messages m
            WHERE m.conversation_id = c.id
            ORDER BY m.created_at DESC
            LIMIT 1
        ) m ON true
        ORDER BY c.last_message_at DESC NULLS LAST
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

/// Create a new conversation between two users. Returns the conversation id.
pub async fn create_conversation(
    pool: &sqlx::PgPool,
    user1: Uuid,
    user2: Uuid,
) -> anyhow::Result<Uuid> {
    let mut tx = pool.begin().await?;

    let conversation_id: Uuid = sqlx::query_scalar(
        r#"INSERT INTO conversations (id) VALUES (gen_random_uuid()) RETURNING id"#,
    )
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query(
        r#"INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)"#,
    )
    .bind(conversation_id)
    .bind(user1)
    .bind(user2)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(conversation_id)
}

/// List messages in a conversation, paginated (newest last after reversal).
pub async fn list_messages(
    pool: &sqlx::PgPool,
    conversation_id: Uuid,
    before: Option<time::OffsetDateTime>,
    limit: i64,
) -> anyhow::Result<Vec<MessageRow>> {
    let mut rows = if let Some(before_ts) = before {
        sqlx::query_as::<_, MessageRow>(
            r#"
            SELECT id, conversation_id, sender_id, kind, body,
                   media_key, media_type, caption, lat, lon,
                   read_at, created_at
            FROM messages
            WHERE conversation_id = $1 AND created_at < $2
            ORDER BY created_at DESC
            LIMIT $3
            "#,
        )
        .bind(conversation_id)
        .bind(before_ts)
        .bind(limit)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, MessageRow>(
            r#"
            SELECT id, conversation_id, sender_id, kind, body,
                   media_key, media_type, caption, lat, lon,
                   read_at, created_at
            FROM messages
            WHERE conversation_id = $1
            ORDER BY created_at DESC
            LIMIT $2
            "#,
        )
        .bind(conversation_id)
        .bind(limit)
        .fetch_all(pool)
        .await?
    };

    // Return in chronological order
    rows.reverse();
    Ok(rows)
}

/// Insert a message (text or media) into a conversation.
pub async fn insert_message(
    pool: &sqlx::PgPool,
    conversation_id: Uuid,
    sender_id: Uuid,
    msg: InsertMessage<'_>,
) -> anyhow::Result<MessageRow> {
    let mut tx = pool.begin().await?;

    let row = sqlx::query_as::<_, MessageRow>(
        r#"
        INSERT INTO messages (conversation_id, sender_id, kind, body,
                              media_key, media_type, caption, lat, lon)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING id, conversation_id, sender_id, kind, body,
                  media_key, media_type, caption, lat, lon,
                  read_at, created_at
        "#,
    )
    .bind(conversation_id)
    .bind(sender_id)
    .bind(msg.kind)
    .bind(msg.body)
    .bind(msg.media_key)
    .bind(msg.media_type)
    .bind(msg.caption)
    .bind(msg.lat)
    .bind(msg.lon)
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query(r#"UPDATE conversations SET last_message_at = now() WHERE id = $1"#)
        .bind(conversation_id)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(row)
}

/// Mark all unread messages from `other_user_id` as read for the calling user.
/// Returns the count of messages newly marked read.
pub async fn mark_messages_read(
    pool: &sqlx::PgPool,
    conversation_id: Uuid,
    reader_id: Uuid,
) -> anyhow::Result<u64> {
    let res = sqlx::query(
        r#"UPDATE messages
           SET read_at = COALESCE(read_at, now())
           WHERE conversation_id = $1
             AND sender_id != $2
             AND read_at IS NULL"#,
    )
    .bind(conversation_id)
    .bind(reader_id)
    .execute(pool)
    .await?;
    Ok(res.rows_affected())
}

/// Mark all messages as read for a user in a conversation (member-level).
pub async fn mark_read(
    pool: &sqlx::PgPool,
    conversation_id: Uuid,
    user_id: Uuid,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"
        UPDATE conversation_members
        SET last_read_at = now()
        WHERE conversation_id = $1 AND user_id = $2
        "#,
    )
    .bind(conversation_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Delete a conversation (only if the user is a member).
/// Also cascades to messages and conversation_members via FK.
pub async fn delete_conversation(
    pool: &sqlx::PgPool,
    conversation_id: Uuid,
    user_id: Uuid,
) -> anyhow::Result<bool> {
    // Verify the user is a member first
    let is_member: Option<(bool,)> = sqlx::query_as(
        r#"SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2)"#,
    )
    .bind(conversation_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    if !is_member.map(|r| r.0).unwrap_or(false) {
        return Ok(false);
    }

    // Delete messages first (FK constraint), then members, then conversation
    let mut tx = pool.begin().await?;
    sqlx::query("DELETE FROM messages WHERE conversation_id = $1")
        .bind(conversation_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM conversation_members WHERE conversation_id = $1")
        .bind(conversation_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM conversations WHERE id = $1")
        .bind(conversation_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    Ok(true)
}