import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/chat_list_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake adapter that returns a canned conversation list.
class _MockConversationAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({
      'conversations': [
        {
          'conversation_id': 'conv-1',
          'other_user_id': 'user-2',
          'other_display_name': 'Bob',
          'last_message_preview': 'Hey there!',
          'last_message_kind': 'text',
          'last_message_at': '2025-01-01T00:00:00Z',
          'unread_count': 2,
        },
        {
          'conversation_id': 'conv-2',
          'other_user_id': 'user-3',
          'other_display_name': 'Alice',
          'last_message_preview': 'See you later',
          'last_message_kind': 'text',
          'last_message_at': '2025-01-01T01:00:00Z',
          'unread_count': 0,
        },
      ],
    });
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ChatListScreen', () {
    testWidgets('loads and displays conversations', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockConversationAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ChatListScreen()),
        ),
      );

      // Initially shows loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for data to load
      await tester.pumpAndSettle();

      // Should show both conversations
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Hey there!'), findsOneWidget);
      expect(find.text('See you later'), findsOneWidget);

      // Unread badge for Bob
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('shows empty state when no conversations', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _MockEmptyAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ChatListScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No conversations yet'), findsOneWidget);
    });
  });
}

class _MockEmptyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({'conversations': <dynamic>[]});
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _AuthenticatedNotifier extends AuthNotifier {
  _AuthenticatedNotifier() : super();

  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test-token',
        email: 'test@example.com',
      );

  @override
  Future<void> logout() async {}
}
