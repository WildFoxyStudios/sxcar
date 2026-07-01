import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/interest_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockTapsAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.path;
    if (uri.contains('/taps/received')) {
      final body = jsonEncode({
        'taps': [
          {
            'id': 'tap-1',
            'sender_id': 'user-1',
            'sender_display_name': 'Bob',
            'sender_photo_url': null,
            'kind': '👋',
            'created_at': '2025-01-01T00:00:00Z',
          },
          {
            'id': 'tap-2',
            'sender_id': 'user-2',
            'sender_display_name': 'Alice',
            'sender_photo_url': null,
            'kind': '🔥',
            'created_at': '2025-01-01T01:00:00Z',
          },
        ],
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (uri.contains('/favorites')) {
      final body = jsonEncode({
        'favorites': [
          {
            'id': 'fav-1',
            'user_id': 'user-3',
            'display_name': 'Charlie',
            'photo_url': null,
          },
        ],
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    return ResponseBody.fromString(
      '{}',
      404,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
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

void main() {
  group('InterestScreen', () {
    testWidgets('shows Taps and Favorites tabs', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockTapsAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: InterestScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Should show tab labels
      expect(find.text('Taps'), findsWidgets);
      expect(find.text('Favorites'), findsWidgets);

      // Should show tap senders
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows Favorites tab content when tapped', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockTapsAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: InterestScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on Favorites tab
      await tester.tap(find.text('Favorites').last);
      await tester.pumpAndSettle();

      // Should show Charlie in favorites
      expect(find.text('Charlie'), findsOneWidget);
    });
  });
}
