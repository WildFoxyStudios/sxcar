import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../auth/auth_provider.dart';
import '../config.dart';
import '../media/media_service.dart';
import 'models.dart';

/// Provider for a ChatService instance tied to the auth state.
final chatServiceProvider = Provider<ChatService>((ref) {
  final dio = ref.watch(dioProvider);
  final authState = ref.watch(authStateProvider);
  return ChatService(dio, authState.accessToken);
});

/// Service for chat operations: REST endpoints + WebSocket connection.
class ChatService {
  final Dio _dio;
  final String? _accessToken;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  /// Stream controller for incoming WebSocket messages.
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  // ── Reconnect state ──────────────────────────────────────────────────────
  //
  // When the WebSocket drops (network blip, server restart) we automatically
  // retry with exponential backoff: 1s, 2s, 4s, 8s, … capped at 30s. A clean
  // shutdown via [disconnect] sets [_userDisconnected] so onDone does NOT
  // schedule a new reconnect.

  /// Pending reconnect timer; null when no reconnect is scheduled.
  Timer? _reconnectTimer;

  /// True while a reconnect is already pending, so onDone/onError never arm
  /// more than one timer at a time.
  bool _isReconnecting = false;

  /// Current backoff delay (doubles on each failed attempt, capped at 30s).
  Duration _reconnectDelay = const Duration(seconds: 1);

  /// Set by [disconnect] to suppress auto-reconnect on the resulting onDone.
  /// Cleared again by [connectWebSocket] for a fresh session.
  bool _userDisconnected = false;

  ChatService(this._dio, this._accessToken);

  /// Stream of raw JSON messages from the WebSocket.
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// REST: list conversations for the current user.
  Future<List<Conversation>> listConversations() async {
    final response = await _dio.get<Map<String, dynamic>>('/chat/conversations');
    final data = response.data!;
    final list = data['conversations'] as List<dynamic>;
    return list
        .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// REST: create a new conversation with another user.
  Future<String> createConversation(String participantId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/conversations',
      data: {'participant_id': participantId},
    );
    return response.data!['conversation_id'] as String;
  }

  /// REST: send a message in a conversation.
  ///
  /// The server responds with `{id, kind}` (the Tier 1 media-message change
  /// renamed the field from `message_id` to `id`).
  Future<String> sendMessage(String conversationId, String text) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/conversations/$conversationId/messages',
      data: {'text': text},
    );
    return response.data!['id'] as String;
  }

  /// REST: get message history for a conversation.
  Future<List<Message>> getMessages(
    String conversationId, {
    int limit = 50,
    String? before,
  }) async {
    final queryParams = <String, dynamic>{'limit': limit};
    if (before != null) {
      queryParams['before'] = before;
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/chat/conversations/$conversationId/messages',
      queryParameters: queryParams,
    );
    final data = response.data!;
    final list = data['messages'] as List<dynamic>;
    return list
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  /// REST: delete a conversation.
  Future<void> deleteConversation(String conversationId) async {
    await _dio.delete('/chat/conversations/$conversationId');
  }

  /// REST: mark conversation as read.
  Future<void> markRead(String conversationId) async {
    await _dio.post('/chat/conversations/$conversationId/read', data: {});
  }

  /// REST: send a photo message in a conversation.
  ///
  /// Set [ephemeral] to true for a view-once photo. When false, the field is
  /// omitted from the request body per the backend contract.
  Future<String> sendPhotoMessage(
    String conversationId, {
    required String mediaKey,
    bool ephemeral = false,
  }) async {
    final data = <String, dynamic>{
      'media_key': mediaKey,
      'media_type': 'photo',
    };
    if (ephemeral) data['ephemeral'] = true;

    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/conversations/$conversationId/messages',
      data: data,
    );
    return response.data!['id'] as String;
  }

  /// REST: get a presigned GET URL for a media key.
  ///
  /// Calls `GET /media/get-url?key=…&kind=…` and returns the
  /// `get_url` string (valid for 3600 s). Default kind is "album".
  Future<String> getMediaUrl(String key, {String kind = 'album'}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/media/get-url',
      queryParameters: {'key': key, 'kind': kind},
    );
    return response.data!['get_url'] as String;
  }

  /// Record audio file, upload to R2, then send as voice message.
  ///
  /// Returns the message ID from the server.
  /// Optionally accepts an [r2Client] Dio for testing (R2 uploads use a
  /// separate HTTP client).
  Future<String> sendVoiceMessage(
    String conversationId,
    String audioFilePath, {
    String? mimeType,
    Dio? r2Client,
  }) async {
    final mediaService = MediaService(_dio, r2Client: r2Client);
    final uploadUrl = await mediaService.getUploadUrl(kind: 'album', ext: 'm4a');

    final file = File(audioFilePath);
    final bytes = await file.readAsBytes();
    await mediaService.uploadToR2(
      uploadUrl.putUrl,
      bytes,
      contentType: mimeType ?? 'audio/mp4',
    );

    final resp = await _dio.post<Map<String, dynamic>>(
      '/chat/conversations/$conversationId/messages',
      data: {
        'media_key': uploadUrl.key,
        'media_type': 'audio',
      },
    );
    return resp.data!['id'] as String;
  }

  /// REST: set (or replace) the caller's reaction on a message.
  ///
  /// The server enforces one reaction per user — a subsequent call with a
  /// different emoji replaces the previous one.
  Future<void> setReaction(String messageId, String emoji) async {
    await _dio.put('/chat/messages/$messageId/reaction', data: {'emoji': emoji});
  }

  /// REST: remove the caller's reaction from a message.
  Future<void> removeReaction(String messageId) async {
    await _dio.delete('/chat/messages/$messageId/reaction');
  }

  /// REST: unsend (soft-delete) a message by id.
  ///
  /// Only the original sender can unsend their own message. Returns 404
  /// if the message doesn't exist, is already unsent, or belongs to
  /// a different sender.
  Future<void> unsendMessage(String messageId) async {
    await _dio.post('/chat/messages/$messageId/unsend');
  }

  /// REST: mark an ephemeral photo as viewed by the recipient.
  ///
  /// Returns `true` only on the *first* call for this message. Subsequent
  /// calls return `false` (photo already expired).
  Future<bool> markEphemeralViewed(
    String conversationId,
    String messageId,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/conversations/$conversationId/messages/$messageId/viewed',
      data: {},
    );
    return response.data!['viewed'] as bool;
  }

  /// Connect to the WebSocket for real-time messaging.
  /// The auth token is passed as a query parameter.
  void connectWebSocket() {
    final token = _accessToken;
    if (token == null) return;

    // Fresh connect attempt → clear the user-disconnect flag so the new
    // socket's onDone will be eligible for auto-reconnect.
    _userDisconnected = false;
    _isReconnecting = false;

    final wsUrl = apiUrl.replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl/ws/chat?token=$token');
    _channel = WebSocketChannel.connect(uri);

    _subscription = _channel!.stream.listen(
      (data) {
        // First frame received ⇒ the connection is live. Reset the backoff
        // so the next drop starts again at 1s instead of the last delay.
        _resetReconnect();

        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          _messageController.add(json);
        } catch (_) {
          // Ignore malformed messages
        }
      },
      onError: (error) {
        debugPrint('[ChatService] WebSocket onError: $error');
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint('[ChatService] WebSocket onDone: connection closed');
        _scheduleReconnect();
      },
    );
  }

  // ── Reconnect machinery ────────────────────────────────────────────────────

  /// Schedule a reconnect with exponential backoff (1→2→4→8→… capped at 30s).
  ///
  /// No-op when the service has been [disconnect]ed by the user (clean
  /// shutdown) or when a reconnect is already pending.
  void _scheduleReconnect() {
    if (_userDisconnected) return;
    if (_isReconnecting) return;

    _isReconnecting = true;
    final delay = _reconnectDelay;
    debugPrint(
      '[ChatService] scheduling WebSocket reconnect in ${delay.inSeconds}s',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _isReconnecting = false;

      // The user may have called [disconnect] while the timer was pending.
      if (_userDisconnected) return;

      // Bump the backoff for the *next* failure (cap at 30s).
      _reconnectDelay = Duration(
        seconds: (_reconnectDelay.inSeconds * 2).clamp(1, 30),
      );

      debugPrint('[ChatService] attempting WebSocket reconnect…');
      // Tear down the old subscription/channel before opening a new one so
      // we never leak a half-closed stream listener.
      _subscription?.cancel();
      _channel?.sink.close();
      connectWebSocket();
    });
  }

  /// Reset the backoff after a successful (re)connect.
  void _resetReconnect() {
    if (_reconnectDelay != const Duration(seconds: 1) || _isReconnecting) {
      debugPrint('[ChatService] connection live — resetting backoff');
    }
    _isReconnecting = false;
    _reconnectDelay = const Duration(seconds: 1);
  }

  /// Clean shutdown: cancel the in-flight reconnect timer and mark the
  /// service as user-disconnected so the socket's onDone does NOT arm a new
  /// reconnect. Call this when leaving the chat (ChatScreen.dispose).
  void disconnect() {
    _userDisconnected = true;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  /// Send a message over the WebSocket (redundant with REST, but available).
  void sendViaWebSocket(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  /// Notify the server (and thus the peer) that we are typing in [conversationId].
  /// Fire-and-forget; server broadcasts {"type":"typing", conversation_id, user_id}.
  void sendTyping(String conversationId) {
    sendViaWebSocket({'type': 'typing', 'conversation_id': conversationId});
  }

  // -------------------------------------------------------------------------
  // Group (Circle) API methods
  // -------------------------------------------------------------------------

  /// REST: create a new group conversation.
  Future<String> createGroup({
    required String name,
    required List<String> memberIds,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/groups',
      data: {
        'name': name,
        'member_ids': memberIds,
      },
    );
    return response.data!['group_id'] as String;
  }

  /// REST: list all groups the current user is a member of.
  Future<List<Map<String, dynamic>>> listGroups() async {
    final response = await _dio.get<Map<String, dynamic>>('/chat/groups');
    final data = response.data!;
    final list = data['groups'] as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  /// REST: rename a group (creator only).
  Future<void> updateGroupName(String groupId, String name) async {
    await _dio.put('/chat/groups/$groupId/name', data: {'name': name});
  }

  /// REST: add a member to a group.
  Future<void> addGroupMember(String groupId, String userId) async {
    await _dio.post('/chat/groups/$groupId/members', data: {'user_id': userId});
  }

  /// REST: remove a member from a group (creator can remove anyone; self-removal allowed).
  Future<void> removeGroupMember(String groupId, String userId) async {
    await _dio.delete('/chat/groups/$groupId/members/$userId');
  }

  /// REST: list members of a group.
  Future<List<Map<String, dynamic>>> listGroupMembers(String groupId) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/chat/groups/$groupId/members');
    final data = response.data!;
    final list = data['members'] as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  /// Close the WebSocket connection.
  ///
  /// Prefer [disconnect] for a clean shutdown (it also suppresses
  /// auto-reconnect). This thin wrapper is retained for callers that only
  /// want to close the socket without touching the reconnect state.
  void disconnectWebSocket() {
    _userDisconnected = true;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  /// Dispose resources.
  void dispose() {
    disconnect();
    _messageController.close();
  }
}
