import 'dart:async';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/chat/chat_service.dart';
import 'package:app/src/chat/models.dart';
import 'package:app/src/features/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A controllable fake [ChatService] whose async methods are gated by
/// [Completer]s, so the test can dispose the widget between the call and
/// the resolution to reproduce the original bug.
class _FakeChatService implements ChatService {
  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Completer gating [getMessages]. If non-null, the next [getMessages]
  /// call returns this future. Test can resolve it to control timing.
  Completer<List<Message>>? getMessagesCompleter;

  /// Completer gating [sendMessage].
  Completer<String>? sendMessageCompleter;

  @override
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  @override
  Future<List<Message>> getMessages(String conversationId,
      {int limit = 50, String? before}) {
    if (getMessagesCompleter != null) {
      return getMessagesCompleter!.future;
    }
    return Future.value(const <Message>[]);
  }

  @override
  Future<String> sendMessage(String conversationId, String text) {
    if (sendMessageCompleter != null) {
      return sendMessageCompleter!.future;
    }
    return Future.value('msg-id');
  }

  @override
  void connectWebSocket() {}

  @override
  void disconnectWebSocket() {}

  @override
  void sendViaWebSocket(Map<String, dynamic> message) {}

  @override
  Future<List<Conversation>> listConversations() async => const [];
  @override
  Future<String> createConversation(String participantId) async => 'c';
  @override
  Future<void> deleteConversation(String conversationId) async {}
  @override
  Future<void> markRead(String conversationId) async {}

  @override
  WebSocketChannel? get _channel => null;

  @override
  StreamSubscription<dynamic>? get _subscription => null;
  @override
  set _subscription(StreamSubscription<dynamic>? v) {}

  @override
  set _channel(WebSocketChannel? v) {}

  @override
  void dispose() {
    _messageController.close();
  }
}

class _AuthedNotifier extends AuthNotifier {
  _AuthedNotifier() : super();
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test-token',
        email: 'test@example.com',
      );
  @override
  Future<void> logout() async {}
}

Widget _wrap(Widget child, _FakeChatService fake) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _AuthedNotifier()),
      chatServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  group('ChatScreen dispose-during-async regression', () {
    testWidgets(
        'disposing widget while getMessages is in flight does not throw',
        (tester) async {
      final fake = _FakeChatService();
      fake.getMessagesCompleter = Completer<List<Message>>();

      await tester.pumpWidget(_wrap(const ChatScreen(conversationId: 'c1'), fake));

      // Let initState -> _loadMessages run; the completer is still open.
      await tester.pump();

      // Dispose the widget tree by replacing it with an empty SizedBox.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthedNotifier()),
            chatServiceProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      // Now resolve the in-flight getMessages request AFTER the widget is
      // disposed. Before the fix, the awaiting setState() would throw
      // "Looking up a deactivated widget's ancestor is unsafe" (or the
      // binding.dart:509 assertion) at this point.
      fake.getMessagesCompleter!.complete(const <Message>[]);
      await tester.pump();

      expect(tester.takeException(), isNull);
      await fake._messageController.close();
    });

    testWidgets(
        'disposing widget while sendMessage is in flight does not throw',
        (tester) async {
      final fake = _FakeChatService();
      fake.sendMessageCompleter = Completer<String>();

      await tester.pumpWidget(_wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // Enter text and trigger _sendMessage.
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Dispose mid-send.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthedNotifier()),
            chatServiceProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      // Resolve sendMessage after dispose.
      fake.sendMessageCompleter!.complete('m1');
      await tester.pump();

      expect(tester.takeException(), isNull);
      await fake._messageController.close();
    });

    testWidgets(
        'a WebSocket message arriving after dispose does not throw',
        (tester) async {
      final fake = _FakeChatService();

      await tester.pumpWidget(_wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // Dispose.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthedNotifier()),
            chatServiceProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pump();

      // Push a WebSocket message after dispose.
      fake._messageController.add({
        'type': 'message',
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 'u2',
        'body': 'hi',
        'sent_at': '2025-01-01T00:00:00Z',
      });
      await tester.pump();

      expect(tester.takeException(), isNull);
      await fake._messageController.close();
    });
  });
}
