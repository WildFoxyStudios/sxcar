import 'dart:async';

import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/chat/chat_service.dart';
import 'package:app/src/chat/models.dart';
import 'package:app/src/features/chat_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/l10n/gen/app_localizations.dart';

// ---------------------------------------------------------------------------
// Fake ChatService — controllable WS stream + seeded messages.
// ---------------------------------------------------------------------------

class _FakeChatService extends ChatService {
  final _ctrl = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final List<Message> _seeded;
  bool unsendCalled = false;
  String? unsendMessageId;

  _FakeChatService(this._seeded) : super(Dio(), null);

  void injectWs(Map<String, dynamic> msg) => _ctrl.add(msg);

  @override
  Stream<Map<String, dynamic>> get messageStream => _ctrl.stream;

  @override
  Future<List<Message>> getMessages(
    String conversationId, {
    int limit = 50,
    String? before,
  }) =>
      Future.value(List<Message>.from(_seeded));

  @override
  void connectWebSocket() {}

  @override
  Future<void> unsendMessage(String messageId) async {
    unsendCalled = true;
    unsendMessageId = messageId;
  }

  @override
  void dispose() {
    _ctrl.close();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Auth stub — userId is 'me-user-id'.
// ---------------------------------------------------------------------------

// JWT: {"alg":"HS256","typ":"JWT"}.{"sub":"me-user-id","exp":9999999999}.fake-sig
const _kTestToken =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJzdWIiOiJtZS11c2VyLWlkIiwiZXhwIjo5OTk5OTk5OTk5fQ'
    '.fake-sig';

class _AuthedNotifier extends AuthNotifier {
  _AuthedNotifier() : super();
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: _kTestToken,
        email: 'test@example.com',
      );
  @override
  Future<void> logout() async {}
}

// ---------------------------------------------------------------------------
// Widget harness with localization delegates.
// ---------------------------------------------------------------------------

Widget _wrap(Widget child, _FakeChatService fake) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _AuthedNotifier()),
      chatServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ChatScreen — unsend WS frame', () {
    testWidgets('unsend WS frame sets unsentAt on the message', (tester) async {
      final seeded = [
        Message(
          id: 'msg-1',
          conversationId: 'c1',
          senderId: 'other-user',
          kind: 'text',
          body: 'hello',
          createdAt: '2025-01-01T12:00:00Z',
        ),
      ];
      final fake = _FakeChatService(seeded);

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // The message body should be visible initially.
      expect(find.text('hello'), findsOneWidget);

      // Inject an unsend frame.
      fake.injectWs({
        'type': 'unsend',
        'message_id': 'msg-1',
        'conversation_id': 'c1',
      });
      await tester.pumpAndSettle();

      // The original body should be gone, placeholder should appear.
      expect(find.text('hello'), findsNothing);
      expect(find.text('[Message unsent]'), findsOneWidget);
    });

    testWidgets('unsend WS frame for unknown message is silent',
        (tester) async {
      final seeded = [
        Message(
          id: 'msg-1',
          conversationId: 'c1',
          senderId: 'other-user',
          kind: 'text',
          body: 'hello',
          createdAt: '2025-01-01T12:00:00Z',
        ),
      ];
      final fake = _FakeChatService(seeded);

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // Inject unsend for a different message.
      fake.injectWs({
        'type': 'unsend',
        'message_id': 'unknown-msg',
        'conversation_id': 'c1',
      });
      await tester.pump();

      // No crash, original message still visible.
      expect(find.text('hello'), findsOneWidget);
    });
  });

  group('ChatScreen — unsend option in action sheet', () {
    testWidgets('own message shows unsend option on long press',
        (tester) async {
      final seeded = [
        Message(
          id: 'msg-1',
          conversationId: 'c1',
          senderId: 'me-user-id',
          kind: 'text',
          body: 'my message',
          createdAt: '2025-01-01T12:00:00Z',
        ),
      ];
      final fake = _FakeChatService(seeded);

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // Long-press on the bubble.
      await tester.longPress(find.text('my message'));
      await tester.pumpAndSettle();

      // The unsend option should be visible in the bottom sheet.
      expect(find.text('Unsend'), findsOneWidget);
    });

    testWidgets('other user message does not show unsend option',
        (tester) async {
      final seeded = [
        Message(
          id: 'msg-1',
          conversationId: 'c1',
          senderId: 'other-user',
          kind: 'text',
          body: 'their message',
          createdAt: '2025-01-01T12:00:00Z',
        ),
      ];
      final fake = _FakeChatService(seeded);

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('their message'));
      await tester.pumpAndSettle();

      // The unsend option should NOT appear for other user's messages.
      expect(find.text('Unsend'), findsNothing);
    });

    testWidgets('already unsent own message does not show unsend option',
        (tester) async {
      final seeded = [
        Message(
          id: 'msg-1',
          conversationId: 'c1',
          senderId: 'me-user-id',
          kind: 'text',
          body: 'already unsent',
          createdAt: '2025-01-01T12:00:00Z',
          unsentAt: '2025-01-01T12:01:00Z',
        ),
      ];
      final fake = _FakeChatService(seeded);

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // The bubble should show placeholder, not the body.
      expect(find.text('already unsent'), findsNothing);
      expect(find.text('[Message unsent]'), findsOneWidget);

      // Long-press on the placeholder.
      await tester.longPress(find.text('[Message unsent]'));
      await tester.pumpAndSettle();

      // The unsend option should NOT appear for already-unsent messages.
      expect(find.text('Unsend'), findsNothing);
    });
  });
}
