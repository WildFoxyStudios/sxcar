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

/// A single message within a conversation.
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String kind;
  final String? body;
  final String createdAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.kind,
    this.body,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      kind: json['kind'] as String,
      body: json['body'] as String?,
      createdAt: json['created_at'] as String,
    );
  }

  /// Parse the WebSocket outgoing message format.
  factory Message.fromWebSocketJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      kind: 'text',
      body: json['body'] as String?,
      createdAt: json['sent_at'] as String,
    );
  }
}
