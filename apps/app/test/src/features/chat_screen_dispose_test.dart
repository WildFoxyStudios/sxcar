import 'dart:async';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/chat/chat_service.dart';
import 'package:app/src/chat/models.dart';
import 'package:app/src/features/chat_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A controllable fake [ChatService] whose async methods are gated by
/// [Completer]s, so the test can dispose the widget between the call and
/// the resolution to reproduce the original bug.
class _FakeChatService extends ChatService {
  Completer<List<Message>>? getMessagesCompleter;
  Completer<String>? sendMessageCompleter;

  // A parallel broadcast controller used to feed messages to the WS
  // listener, since the parent's _messageController is private.
  final _testMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  _FakeChatService() : super(Dio(), null);

  /// Inject a fake WebSocket message into the stream the screen listens to.
  void injectMessage(Map<String, dynamic> msg) {
    _testMessageController.add(msg);
  }

  @override
  Stream<Map<String, dynamic>> get messageStream => _testMessageController.stream;

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

Widget _emptyAfterDispose(_FakeChatService fake) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _AuthedNotifier()),
      chatServiceProvider.overrideWithValue(fake),
    ],
    child: const MaterialApp(home: SizedBox.shrink()),
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
      await tester.pump();

      // Dispose the widget tree by replacing it with an empty SizedBox.
      await tester.pumpWidget(_emptyAfterDispose(fake));
      await tester.pump();

      // Now resolve the in-flight getMessages request AFTER the widget is
      // disposed. Before the fix, the awaiting setState() would throw
      // "Looking up a deactivated widget's ancestor is unsafe" at this point.
      fake.getMessagesCompleter!.complete(const <Message>[]);
      await tester.pump();

      expect(tester.takeException(), isNull);
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
      await tester.pumpWidget(_emptyAfterDispose(fake));
      await tester.pump();

      // Resolve sendMessage after dispose.
      fake.sendMessageCompleter!.complete('m1');
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a WebSocket message arriving after dispose does not throw',
        (tester) async {
      final fake = _FakeChatService();

      // connectWebSocket in the fake pushes a message into the
      // service's broadcast stream — but it does so during the
      // widget's lifetime, which is fine for the pre-dispose test.
      // For the post-dispose test, we instead push a message via
      // fake.injectMessage(...) which writes to the same stream.
      await tester.pumpWidget(_wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // Dispose.
      await tester.pumpWidget(_emptyAfterDispose(fake));
      await tester.pump();

      // Push a WebSocket message after dispose.
      fake.injectMessage({
        'type': 'message',
        'id': 'm1',
        'conversation_id': 'c1',
        'sender_id': 'u2',
        'body': 'hi',
        'sent_at': '2025-01-01T00:00:00Z',
      });
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

