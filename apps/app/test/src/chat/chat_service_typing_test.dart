import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/chat/chat_service.dart';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChatService.sendTyping', () {
    test('emits correct JSON frame via sendViaWebSocket', () {
      final captured = <Map<String, dynamic>>[];

      // Sub-class ChatService and override sendViaWebSocket to intercept.
      final service = _CapturingChatService(captured);

      service.sendTyping('conv-abc');

      expect(captured, hasLength(1));
      expect(captured.first['type'], equals('typing'));
      expect(captured.first['conversation_id'], equals('conv-abc'));
    });

    test('sendTyping with different conversationId encodes correctly', () {
      final captured = <Map<String, dynamic>>[];
      final service = _CapturingChatService(captured);

      service.sendTyping('conversation-xyz-123');

      expect(captured.first['conversation_id'], equals('conversation-xyz-123'));
      // Must NOT include user_id (that's added by the server on broadcast).
      expect(captured.first.containsKey('user_id'), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Test double — overrides sendViaWebSocket to capture without real socket.
// ---------------------------------------------------------------------------

class _CapturingChatService extends ChatService {
  final List<Map<String, dynamic>> _captured;

  _CapturingChatService(this._captured) : super(Dio(), null);

  @override
  void sendViaWebSocket(Map<String, dynamic> message) {
    _captured.add(Map<String, dynamic>.from(message));
  }
}
