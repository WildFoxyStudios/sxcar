import 'dart:async';

import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/chat/chat_service.dart';
import 'package:app/src/chat/models.dart';
import 'package:app/src/features/chat_screen.dart';
import 'package:app/src/screenshots/screenshots_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/l10n/gen/app_localizations.dart';

class _FakeScreenshotsService extends ScreenshotsService {
  _FakeScreenshotsService() : super(Dio());
  @override
  Future<void> report(String conversationId) async {}
  @override
  Future<List<ScreenshotAlert>> list() async => const [];
}

// ---------------------------------------------------------------------------
// Fake ChatService — controllable WS stream, no real network.
// ---------------------------------------------------------------------------

class _FakeChatService extends ChatService {
  // sync: true ensures events are delivered synchronously when add() is called,
  // so a single tester.pump() is sufficient to trigger setState + rebuild.
  final _ctrl = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final List<Map<String, dynamic>> sentTypingFrames = [];

  _FakeChatService() : super(Dio(), null);

  void injectWs(Map<String, dynamic> msg) => _ctrl.add(msg);

  @override
  Stream<Map<String, dynamic>> get messageStream => _ctrl.stream;

  @override
  Future<List<Message>> getMessages(
    String conversationId, {
    int limit = 50,
    String? before,
  }) =>
      Future.value(const <Message>[]);

  @override
  void connectWebSocket() {}

  @override
  void sendTyping(String conversationId) {
    sentTypingFrames.add({'type': 'typing', 'conversation_id': conversationId});
  }

  @override
  void dispose() {
    _ctrl.close();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Auth stub — userId is 'me-user-id'.
// The access token is a real (but unsigned) JWT whose sub claim is
// 'me-user-id', so that jwtSubject() returns the right value.
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
      screenshotsServiceProvider
          .overrideWithValue(_FakeScreenshotsService()),
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
  group('ChatScreen — typing indicator', () {
    testWidgets(
        'typing frame from another user in current convo shows indicator',
        (tester) async {
      final fake = _FakeChatService();

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // Indicator is hidden initially.
      expect(find.text('typing…'), findsNothing);
      expect(find.text('escribiendo…'), findsNothing);

      // Inject a typing frame from another user in the same conversation.
      fake.injectWs({
        'type': 'typing',
        'conversation_id': 'c1',
        'user_id': 'other-user',
      });
      await tester.pump();

      // Indicator should now be visible (en locale: "typing…").
      expect(
        find.text('typing…').evaluate().length +
            find.text('escribiendo…').evaluate().length,
        greaterThan(0),
        reason: 'typing indicator text should be shown',
      );
    });

    testWidgets(
        'typing frame with my own user_id does NOT show indicator',
        (tester) async {
      final fake = _FakeChatService();

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // Inject a frame as if coming from ourselves (shouldn't show).
      fake.injectWs({
        'type': 'typing',
        'conversation_id': 'c1',
        'user_id': 'me-user-id', // same as auth userId
      });
      await tester.pump();

      expect(find.text('typing…'), findsNothing);
      expect(find.text('escribiendo…'), findsNothing);
    });

    testWidgets(
        'typing frame for a DIFFERENT conversation does NOT show indicator',
        (tester) async {
      final fake = _FakeChatService();

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // Frame is for conv c2, not c1.
      fake.injectWs({
        'type': 'typing',
        'conversation_id': 'c2',
        'user_id': 'other-user',
      });
      await tester.pump();

      expect(find.text('typing…'), findsNothing);
      expect(find.text('escribiendo…'), findsNothing);
    });

    testWidgets(
        'typing indicator auto-hides after ~4 s (timer fires)',
        (tester) async {
      final fake = _FakeChatService();

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // Show the indicator.
      fake.injectWs({
        'type': 'typing',
        'conversation_id': 'c1',
        'user_id': 'other-user',
      });
      await tester.pump();

      // Indicator visible.
      expect(
        find.text('typing…').evaluate().length +
            find.text('escribiendo…').evaluate().length,
        greaterThan(0),
        reason: 'typing indicator should be visible after typing frame',
      );

      // Advance fake time past the 4-second auto-hide timer.
      await tester.pump(const Duration(seconds: 5));

      // Indicator should be gone.
      expect(find.text('typing…'), findsNothing);
      expect(find.text('escribiendo…'), findsNothing);
    });

    testWidgets(
        'each new typing frame resets the auto-hide timer',
        (tester) async {
      final fake = _FakeChatService();

      await tester.pumpWidget(
          _wrap(const ChatScreen(conversationId: 'c1'), fake));
      await tester.pumpAndSettle();

      // First frame.
      fake.injectWs({
        'type': 'typing',
        'conversation_id': 'c1',
        'user_id': 'other-user',
      });
      await tester.pump();

      // Advance 3 s (less than hide timer).
      await tester.pump(const Duration(seconds: 3));

      // Second frame resets the timer.
      fake.injectWs({
        'type': 'typing',
        'conversation_id': 'c1',
        'user_id': 'other-user',
      });
      await tester.pump();

      // Still visible (the new timer hasn't fired yet).
      expect(
        find.text('typing…').evaluate().length +
            find.text('escribiendo…').evaluate().length,
        greaterThan(0),
        reason: 'indicator should still be shown after reset',
      );

      // Advance past the reset timer.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('typing…'), findsNothing);
      expect(find.text('escribiendo…'), findsNothing);
    });
  });
}
