/// A conversation between the current user and another user.
class Conversation {
  final String conversationId;
  final String otherUserId;
  final String? otherDisplayName;
  final String? lastMessagePreview;
  final String? lastMessageKind;
  final String? lastMessageAt;
  final int unreadCount;

  const Conversation({
    required this.conversationId,
    required this.otherUserId,
    this.otherDisplayName,
    this.lastMessagePreview,
    this.lastMessageKind,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      conversationId: json['conversation_id'] as String,
      otherUserId: json['other_user_id'] as String,
      otherDisplayName: json['other_display_name'] as String?,
      lastMessagePreview: json['last_message_preview'] as String?,
      lastMessageKind: json['last_message_kind'] as String?,
      lastMessageAt: json['last_message_at'] as String?,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A single emoji reaction from one user on a message.
///
/// The server enforces one reaction per user per message.
class MessageReaction {
  final String userId;
  final String emoji;

  const MessageReaction({required this.userId, required this.emoji});

  factory MessageReaction.fromJson(Map<String, dynamic> j) =>
      MessageReaction(
        userId: j['user_id'] as String,
        emoji: j['emoji'] as String,
      );
}

/// A single message within a conversation.
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String kind;
  final String? body;
  final String createdAt;

  /// R2 object key for photo messages; null for text messages.
  final String? mediaKey;

  /// MIME-type category — 'photo' for image messages; null for text.
  final String? mediaType;

  /// ISO-8601 timestamp set by the server when the recipient reads the
  /// conversation. Null until read. Parsed defensively (field may be absent).
  final String? readAt;

  /// ISO-8601 timestamp set by the server on the first view of an ephemeral
  /// photo by the recipient. Once set the photo is permanently expired.
  /// Null for non-ephemeral messages and un-viewed ephemeral ones.
  final String? ephemeralViewedAt;

  /// Reactions from other users on this message (or empty if none).
  ///
  /// Each reaction is a [MessageReaction] with userId + emoji. The server
  /// enforces one reaction per user; the client replaces on re-emoji.
  final List<MessageReaction> reactions;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.kind,
    this.body,
    required this.createdAt,
    this.mediaKey,
    this.mediaType,
    this.readAt,
    this.ephemeralViewedAt,
    this.reactions = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      kind: json['kind'] as String,
      body: json['body'] as String?,
      createdAt: json['created_at'] as String,
      mediaKey: json['media_key'] as String?,
      mediaType: json['media_type'] as String?,
      readAt: json['read_at'] as String?,
      ephemeralViewedAt: json['ephemeral_viewed_at'] as String?,
      reactions: (json['reactions'] as List<dynamic>?)
              ?.map((r) =>
                  MessageReaction.fromJson(r as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// Parse the WebSocket outgoing-message payload.
  ///
  /// WS payloads include `kind` and optionally `media_key`/`media_type`, but
  /// do NOT include viewed/read timestamps — those are REST-only fields.
  factory Message.fromWebSocketJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      kind: json['kind'] as String? ?? 'text',
      body: json['body'] as String?,
      createdAt: json['sent_at'] as String,
      mediaKey: json['media_key'] as String?,
      mediaType: json['media_type'] as String?,
      // WS payload does not include viewed/read timestamps — REST-only fields.
      readAt: null,
      ephemeralViewedAt: null,
      reactions: const [],
    );
  }

  /// Create a copy with optional field overrides.
  Message copyWith({
    List<MessageReaction>? reactions,
  }) {
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      kind: kind,
      body: body,
      createdAt: createdAt,
      mediaKey: mediaKey,
      mediaType: mediaType,
      readAt: readAt,
      ephemeralViewedAt: ephemeralViewedAt,
      reactions: reactions ?? this.reactions,
    );
  }
}
