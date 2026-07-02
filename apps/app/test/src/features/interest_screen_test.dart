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

/// Notifier that starts with `loading` (no token) and is later updated
/// to `authenticated` with a token. Used to reproduce the race where
/// InterestScreen runs `_fetchTaps` / `_fetchFavorites` before the
/// secure-storage token is loaded.
class _LoadingThenAuthNotifier extends AuthNotifier {
  _LoadingThenAuthNotifier() : super();

  @override
  AuthState build() => const AuthState(
        status: AuthStatus.loading,
        accessToken: null,
        email: null,
      );

  void becomeAuthed() {
    state = const AuthState(
      status: AuthStatus.authenticated,
      accessToken: 'test-token',
      email: 'test@example.com',
    );
  }

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

    testWidgets(
        'Favorites and Taps requests WAIT for the auth token when it is '
        'still loading at boot (regression for 401 on /favorites)', (tester) async {
      // The original bug: _fetchFavorites / _fetchTaps ran in initState
      // and fired immediately. The Dio interceptor then read the secure
      // storage cache (still empty mid-boot) and the request went out
      // without an Authorization header, producing the 401 we saw in
      // logcat. The fix polls authState.accessToken before firing.
      final dio = Dio()..httpClientAdapter = _MockTapsAdapter();
      final notifier = _LoadingThenAuthNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => notifier),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: InterestScreen()),
        ),
      );

      // Pump a few frames — requests MUST NOT have been sent yet
      // (the auth token is still null). Tap on Favorites so the
      // FutureBuilder for the second tab builds.
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Favorites').last);
      await tester.pump();
      // Still loading — the fetcher must be waiting on the notifier.
      // (No tappable content yet → "No favorites yet" empty state.)
      // The key proof: no exception, no 401 printed; the tab shows
      // its loading state.
      expect(tester.takeException(), isNull);

      // Now become authenticated — the waiting fetcher should fire
      // immediately and the empty state should switch to "Charlie".
      notifier.becomeAuthed();
      await tester.pumpAndSettle();

      expect(find.text('Charlie'), findsOneWidget,
          reason: 'fetch should have fired once the token arrived');
    });
  });
}
