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
  group('ChatScreen — reaction WS frames', () {
    testWidgets('incoming reaction frame renders a chip', (tester) async {
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

      // No reaction chips initially.
      expect(find.text('❤️'), findsNothing);
      expect(find.text('😂'), findsNothing);

      // Inject a reaction frame from another user.
      fake.injectWs({
        'type': 'reaction',
        'message_id': 'msg-1',
        'user_id': 'other-user',
        'emoji': '❤️',
      });
      await tester.pump();

      // The ❤️ emoji should now be rendered as a reaction chip.
      expect(find.text('❤️'), findsOneWidget);
    });

    testWidgets(
        'reaction frame with emoji:null removes an existing chip',
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

      // Add a reaction via WS.
      fake.injectWs({
        'type': 'reaction',
        'message_id': 'msg-1',
        'user_id': 'other-user',
        'emoji': '😂',
      });
      await tester.pump();
      expect(find.text('😂'), findsOneWidget);

      // Remove it via null emoji.
      fake.injectWs({
        'type': 'reaction',
        'message_id': 'msg-1',
        'user_id': 'other-user',
        'emoji': null,
      });
      await tester.pump();

      expect(find.text('😂'), findsNothing);
    });

    testWidgets(
        'reaction frame for unknown message is silently ignored',
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

      // Reaction for a message NOT in the list.
      fake.injectWs({
        'type': 'reaction',
        'message_id': 'unknown-msg',
        'user_id': 'other-user',
        'emoji': '🔥',
      });
      await tester.pump();

      // No crash, no chips.
      expect(find.text('🔥'), findsNothing);
    });

    testWidgets(
        'same user sending new emoji replaces the previous one',
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

      // Add reaction A.
      fake.injectWs({
        'type': 'reaction',
        'message_id': 'msg-1',
        'user_id': 'other-user',
        'emoji': '❤️',
      });
      await tester.pump();
      expect(find.text('❤️'), findsOneWidget);
      expect(find.text('😢'), findsNothing);

      // Replace with reaction B from the same user.
      fake.injectWs({
        'type': 'reaction',
        'message_id': 'msg-1',
        'user_id': 'other-user',
        'emoji': '😢',
      });
      await tester.pump();

      // Old emoji gone, new one present.
      expect(find.text('❤️'), findsNothing);
      expect(find.text('😢'), findsOneWidget);
    });

    testWidgets('reaction chips show count when >1 user',
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

      // User A reacts.
      fake.injectWs({
        'type': 'reaction',
        'message_id': 'msg-1',
        'user_id': 'user-a',
        'emoji': '👍',
      });
      await tester.pump();
      // Single reactor: just the emoji, no count number.
      expect(find.text('👍'), findsOneWidget);
      // There should also NOT be text containing "👍 1" — just the bare emoji.
      expect(find.text('👍 1'), findsNothing);

      // User B reacts with the same emoji.
      fake.injectWs({
        'type': 'reaction',
        'message_id': 'msg-1',
        'user_id': 'user-b',
        'emoji': '👍',
      });
      await tester.pump();

      // With 2 reactors, the chip should show "👍 2".
      expect(find.text('👍 2'), findsOneWidget);
    });
  });
}
