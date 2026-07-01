//! Chat module: WebSocket real-time messaging + REST conversation management.
//!
//! WebSocket endpoint: `/ws/chat?token=<jwt>` (auth via query param)
//! REST endpoints:     `/chat/conversations`, `/chat/conversations/:id/messages`, etc. (auth via Bearer header)

use axum::{
    extract::{Path, Query, State, WebSocketUpgrade, ws::{Message, WebSocket}},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};

use uuid::Uuid;

use crate::auth::AuthUser;
use crate::AppState;

// ---------------------------------------------------------------------------
// WebSocket — auth via query param
// ---------------------------------------------------------------------------

/// Query params for WebSocket upgrade: `?token=<jwt>`
#[derive(Deserialize)]
pub struct WsQuery {
    pub token: String,
}

/// GET /ws/chat?token=<jwt>
pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<AppState>,
    Query(query): Query<WsQuery>,
) -> Result<impl IntoResponse, StatusCode> {
    // Validate the JWT from the query param
    let claims =
        auth::jwt::verify_access(&query.token, &state.jwt).map_err(|_| StatusCode::UNAUTHORIZED)?;
    let user_id = claims
        .sub
        .parse::<Uuid>()
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    Ok(ws.on_upgrade(move |socket| handle_socket(socket, state, user_id)))
}

/// Per-connection WebSocket loop.
async fn handle_socket(socket: WebSocket, state: AppState, user_id: Uuid) {
    let (mut sender, mut receiver) = socket.split();

    // Subscribe to broadcast channel
    let mut rx = state.chat_broker.subscribe().await;

    // Spawn a task to forward broadcast messages to this client
    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.next().await {
            if sender.send(Message::Text(msg)).await.is_err() {
                break;
            }
        }
    });

    // Read incoming messages from this client
    while let Some(Ok(msg)) = receiver.next().await {
        if let Message::Text(text) = msg {
            match serde_json::from_str::<IncomingMessage>(&text) {
                Ok(incoming) => {
                    if let Err(e) = handle_incoming(&state, user_id, incoming).await {
                        tracing::error!("handle_incoming error: {e}");
                    }
                }
                Err(e) => {
                    tracing::warn!("invalid WS message: {e}");
                }
            }
        }
    }

    // If receiver drops, the send_task will notice the channel is closed
    send_task.abort();
}

/// Message types the client can send over WebSocket.
#[derive(Deserialize)]
#[serde(tag = "type")]
pub enum IncomingMessage {
    #[serde(rename = "send")]
    Send {
        conversation_id: String,
        text: String,
    },
    #[serde(rename = "typing")]
    Typing {
        conversation_id: String,
    },
}

/// Process an incoming WebSocket message: store in DB + broadcast to channel.
async fn handle_incoming(
    state: &AppState,
    sender_id: Uuid,
    msg: IncomingMessage,
) -> anyhow::Result<()> {
    match msg {
        IncomingMessage::Send {
            conversation_id,
            text,
        } => {
            let conversation_id: Uuid = conversation_id.parse()?;
            let row = db::chat::insert_message(
                &state.pool,
                conversation_id,
                sender_id,
                db::chat::InsertMessage {
                    kind: "text",
                    body: Some(&text),
                    media_key: None,
                    media_type: None,
                    caption: None,
                    lat: None,
                    lon: None,
                },
            )
            .await?;

            // Build outgoing JSON and broadcast
            let outgoing = serde_json::json!({
                "type": "message",
                "id": row.id.to_string(),
                "conversation_id": row.conversation_id.to_string(),
                "sender_id": row.sender_id.to_string(),
                "kind": row.kind,
                "body": row.body,
                "media_key": row.media_key,
                "media_type": row.media_type,
                "caption": row.caption,
                "lat": row.lat,
                "lon": row.lon,
                "created_at": row.created_at,
            });
            let payload = serde_json::to_string(&outgoing)?;
            let _ = state.chat_broker.publish("chat", &payload);
        }
        IncomingMessage::Typing { conversation_id } => {
            let typing = serde_json::json!({
                "type": "typing",
                "conversation_id": conversation_id,
                "user_id": sender_id.to_string(),
            });
            let typing_str = typing.to_string();
            state.chat_broker.publish("chat", &typing_str);
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Outgoing message format (WebSocket frames)
// ---------------------------------------------------------------------------

#[derive(Serialize)]
pub struct OutgoingMessage {
    pub r#type: String,
    pub id: String,
    pub conversation_id: String,
    pub sender_id: String,
    pub body: Option<String>,
    pub sent_at: time::OffsetDateTime,
}

// ---------------------------------------------------------------------------
// REST: list conversations
// ---------------------------------------------------------------------------

#[derive(Serialize)]
pub struct ListConversationsResponse {
    pub conversations: Vec<ConversationJson>,
}

#[derive(Serialize)]
pub struct ConversationJson {
    pub conversation_id: String,
    pub other_user_id: String,
    pub other_display_name: Option<String>,
    pub last_message_preview: Option<String>,
    pub last_message_kind: Option<String>,
    pub last_message_at: Option<String>,
    pub unread_count: i64,
}

/// GET /chat/conversations
pub async fn list_conversations(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> Result<Json<ListConversationsResponse>, StatusCode> {
    let rows = db::chat::list_conversations(&state.pool, user_id)
        .await
        .map_err(|e| {
            tracing::error!("list_conversations error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let conversations = rows
        .into_iter()
        .map(|r| ConversationJson {
            conversation_id: r.conversation_id.to_string(),
            other_user_id: r.other_user_id.to_string(),
            other_display_name: r.other_display_name,
            last_message_preview: r.last_message_preview,
            last_message_kind: r.last_message_kind,
            last_message_at: r.last_message_at.map(|t| {
                t.format(&time::format_description::well_known::Rfc3339)
                    .unwrap_or_default()
            }),
            unread_count: r.unread_count,
        })
        .collect();

    Ok(Json(ListConversationsResponse { conversations }))
}

// ---------------------------------------------------------------------------
// REST: create conversation
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct CreateConversationRequest {
    pub participant_id: Uuid,
}

#[derive(Serialize)]
pub struct CreateConversationResponse {
    pub conversation_id: String,
}

/// POST /chat/conversations
pub async fn create_conversation(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<CreateConversationRequest>,
) -> Result<(StatusCode, Json<CreateConversationResponse>), StatusCode> {
    if req.participant_id == user_id {
        return Err(StatusCode::BAD_REQUEST);
    }

    let conversation_id = db::chat::create_conversation(&state.pool, user_id, req.participant_id)
        .await
        .map_err(|e| {
            tracing::error!("create_conversation error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok((
        StatusCode::CREATED,
        Json(CreateConversationResponse {
            conversation_id: conversation_id.to_string(),
        }),
    ))
}

// ---------------------------------------------------------------------------
// REST: send message (POST /chat/conversations/:id/messages)
// ---------------------------------------------------------------------------

/// Payload for sending a text or media message. At least one of `text`,
/// `media_key` or `caption` must be present.
#[derive(Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub struct SendMessageRequest {
    pub text: Option<String>,
    pub media_key: Option<String>,
    pub media_type: Option<String>,
    pub caption: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
}

#[derive(Serialize)]
pub struct SendMessageResponse {
    pub id: String,
    pub kind: String,
}

fn classify_kind(req: &SendMessageRequest) -> Option<&'static str> {
    if req.media_key.is_some() {
        // DB CHECK constraint allows only 'photo' or 'location' kinds for media
        Some("photo")
    } else if req.lat.is_some() && req.lon.is_some() {
        Some("location")
    } else if req.text.is_some() {
        Some("text")
    } else {
        None
    }
}

/// POST /chat/conversations/:id/messages
pub async fn send_message(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(conversation_id): Path<Uuid>,
    Json(req): Json<SendMessageRequest>,
) -> Result<(StatusCode, Json<SendMessageResponse>), StatusCode> {
    // Verify user is a member of this conversation
    let is_member = sqlx::query_scalar!(
        r#"SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2)"#,
        conversation_id,
        user_id
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    .unwrap_or(false);

    if !is_member {
        return Err(StatusCode::FORBIDDEN);
    }

    let kind = match classify_kind(&req) {
        Some(k) => k,
        None => return Err(StatusCode::BAD_REQUEST),
    };

    // Reject empty bodies for text/location (media alone is OK).
    if matches!(kind, "text" | "location") {
        let empty = req
            .text
            .as_deref()
            .map(|t| t.trim().is_empty())
            .unwrap_or(true);
        if empty {
            return Err(StatusCode::BAD_REQUEST);
        }
    }

    // For media messages, validate media_type
    if matches!(kind, "media") {
        let mt = req.media_type.as_deref().unwrap_or("");
        if !matches!(mt, "photo") {
            return Err(StatusCode::BAD_REQUEST);
        }
    }

    let insert = db::chat::InsertMessage {
        kind,
        body: req.text.as_deref().or(req.caption.as_deref()),
        media_key: req.media_key.as_deref(),
        media_type: req.media_type.as_deref(),
        caption: req.caption.as_deref(),
        lat: req.lat,
        lon: req.lon,
    };

    let row = db::chat::insert_message(&state.pool, conversation_id, user_id, insert)
        .await
        .map_err(|e| {
            tracing::error!("insert_message error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // Broadcast via WebSocket
    let outgoing = serde_json::json!({
        "type": "message",
        "id": row.id.to_string(),
        "conversation_id": row.conversation_id.to_string(),
        "sender_id": row.sender_id.to_string(),
        "kind": row.kind,
        "body": row.body,
        "media_key": row.media_key,
        "media_type": row.media_type,
        "caption": row.caption,
        "lat": row.lat,
        "lon": row.lon,
        "created_at": row.created_at,
    });
    if let Ok(payload) = serde_json::to_string(&outgoing) {
        state.chat_broker.publish("chat", &payload);
    }

    Ok((
        StatusCode::CREATED,
        Json(SendMessageResponse {
            id: row.id.to_string(),
            kind: row.kind.clone(),
        }),
    ))
}

// ---------------------------------------------------------------------------
// REST: list messages
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct ListMessagesQuery {
    pub before: Option<String>,
    #[serde(default = "default_limit")]
    pub limit: i64,
}

fn default_limit() -> i64 {
    50
}

#[derive(Serialize)]
pub struct ListMessagesResponse {
    pub messages: Vec<MessageJson>,
}

#[derive(Serialize)]
pub struct MessageJson {
    pub id: String,
    pub conversation_id: String,
    pub sender_id: String,
    pub kind: String,
    pub body: Option<String>,
    pub media_key: Option<String>,
    pub media_type: Option<String>,
    pub caption: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    pub read_at: Option<String>,
    pub created_at: String,
}

/// GET /chat/conversations/:id/messages?before=&limit=50
pub async fn list_messages(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(conversation_id): Path<Uuid>,
    Query(query): Query<ListMessagesQuery>,
) -> Result<Json<ListMessagesResponse>, StatusCode> {
    // Verify membership
    let is_member = sqlx::query_scalar!(
        r#"SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2)"#,
        conversation_id,
        user_id
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    .unwrap_or(false);

    if !is_member {
        return Err(StatusCode::FORBIDDEN);
    }

    let before_ts = match query.before {
        Some(ts) => Some(
            time::OffsetDateTime::parse(&ts, &time::format_description::well_known::Rfc3339)
                .map_err(|_| StatusCode::BAD_REQUEST)?,
        ),
        None => None,
    };

    let rows = db::chat::list_messages(&state.pool, conversation_id, before_ts, query.limit)
        .await
        .map_err(|e| {
            tracing::error!("list_messages error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    let messages = rows
        .into_iter()
        .map(|r| MessageJson {
            id: r.id.to_string(),
            conversation_id: r.conversation_id.to_string(),
            sender_id: r.sender_id.to_string(),
            kind: r.kind,
            body: r.body,
            media_key: r.media_key,
            media_type: r.media_type,
            caption: r.caption,
            lat: r.lat,
            lon: r.lon,
            read_at: r.read_at.map(|t| {
                t.format(&time::format_description::well_known::Rfc3339)
                    .unwrap_or_default()
            }),
            created_at: r
                .created_at
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default(),
        })
        .collect();

    Ok(Json(ListMessagesResponse { messages }))
}

// ---------------------------------------------------------------------------
// REST: delete conversation
// ---------------------------------------------------------------------------

/// DELETE /chat/conversations/:id
pub async fn delete_conversation(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(conversation_id): Path<Uuid>,
) -> Result<StatusCode, StatusCode> {
    let deleted = db::chat::delete_conversation(&state.pool, conversation_id, user_id)
        .await
        .map_err(|e| {
            tracing::error!("delete_conversation error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if !deleted {
        return Err(StatusCode::NOT_FOUND);
    }

    Ok(StatusCode::NO_CONTENT)
}

/// POST /chat/conversations/:id/read
///
/// Marks all messages from the *other* participant as read (sets messages.read_at)
/// and updates the caller's `conversation_members.last_read_at`.
/// Returns how many messages were newly marked read.
pub async fn mark_read(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(conversation_id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    // Verify membership
    let is_member = sqlx::query_scalar!(
        r#"SELECT EXISTS(SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND user_id = $2)"#,
        conversation_id,
        user_id
    )
    .fetch_one(&state.pool)
    .await
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    .unwrap_or(false);

    if !is_member {
        return Err(StatusCode::FORBIDDEN);
    }

    // Per-message read receipt timestamps
    let marked = db::chat::mark_messages_read(&state.pool, conversation_id, user_id)
        .await
        .map_err(|e| {
            tracing::error!("mark_messages_read error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // Membership last_read_at (used for unread counts)
    db::chat::mark_read(&state.pool, conversation_id, user_id)
        .await
        .map_err(|e| {
            tracing::error!("mark_read error: {e}");
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(serde_json::json!({ "marked": marked })))
}