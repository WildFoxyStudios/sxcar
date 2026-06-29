import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../auth/auth_provider.dart';
import '../config.dart';
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
  Future<String> sendMessage(String conversationId, String text) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/conversations/$conversationId/messages',
      data: {'text': text},
    );
    return response.data!['message_id'] as String;
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

  /// REST: mark conversation as read.
  Future<void> markRead(String conversationId) async {
    await _dio.post('/chat/conversations/$conversationId/read', data: {});
  }

  /// Connect to the WebSocket for real-time messaging.
  /// The auth token is passed as a query parameter.
  void connectWebSocket() {
    final token = _accessToken;
    if (token == null) return;

    final wsUrl = apiUrl.replaceFirst('https://', 'wss://');
    final uri = Uri.parse('$wsUrl/ws/chat?token=$token');
    _channel = WebSocketChannel.connect(uri);

    _subscription = _channel!.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          _messageController.add(json);
        } catch (_) {
          // Ignore malformed messages
        }
      },
      onError: (error) {
        // Reconnect logic could be added here
      },
      onDone: () {
        // Connection closed
      },
    );
  }

  /// Send a message over the WebSocket (redundant with REST, but available).
  void sendViaWebSocket(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  /// Close the WebSocket connection.
  void disconnectWebSocket() {
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  /// Dispose resources.
  void dispose() {
    disconnectWebSocket();
    _messageController.close();
  }
}
