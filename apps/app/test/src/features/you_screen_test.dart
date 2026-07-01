import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/you_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adapter that returns profile on /profile, albums on /albums, and
/// /profile/views can be customized via [viewers], and /boost/active can
/// be customized via [activeBoost].
class _CombinedAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> viewers;
  final Map<String, dynamic>? activeBoost;
  final List<Map<String, dynamic>> boostPosts = [];

  _CombinedAdapter({this.viewers = const [], this.activeBoost});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/profile') {
      final body = jsonEncode({
        'user': {
          'id': '00000000-0000-0000-0000-000000000001',
          'email': 'test@example.com',
          'email_verified': true,
          'status': 'active',
          'role': 'user',
          'created_at': '2025-01-01T00:00:00Z',
          'display_name': 'TestUser',
          'bio': 'Hello!',
          'profile_photo_id': null,
          'profile_photo_url': null,
          'tribes': [],
          'looking_for': [],
          'meet_at': [],
          'tags': [],
        },
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (options.path == '/albums') {
      final body = jsonEncode({'albums': <dynamic>[]});
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (options.path == '/profile/views') {
      final body = jsonEncode({'viewers': viewers});
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (options.path == '/boost/active') {
      if (activeBoost == null) {
        return ResponseBody.fromString(
          jsonEncode({'active': false, 'minutes_remaining': 0}),
          200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
        );
      }
      return ResponseBody.fromString(
        jsonEncode({'active': true, ...activeBoost!}),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (options.method == 'POST' && options.path == '/boost') {
      boostPosts.add({'method': 'POST', 'path': '/boost'});
      return ResponseBody.fromString(
        jsonEncode({
          'boost': {
            'id': 'new-boost',
            'expires_at': '2026-07-01T12:30:00Z',
            'minutes_remaining': 30,
          }
        }),
        201,
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
  group('YouScreen', () {
    testWidgets('shows user email and profile section', (tester) async {
      final dio = Dio()..httpClientAdapter = _CombinedAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('@test'), findsOneWidget);
    });

    testWidgets('shows Edit Profile button', (tester) async {
      final dio = Dio()..httpClientAdapter = _CombinedAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Edit Profile'), findsOneWidget);
    });

    testWidgets('shows logout option', (tester) async {
      final dio = Dio()..httpClientAdapter = _CombinedAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // The logout option is below the profile + viewed me section; scroll
      // down to find it.
      await tester.scrollUntilVisible(
        find.text('Logout'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('shows settings section', (tester) async {
      final dio = Dio()..httpClientAdapter = _CombinedAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Delete Account sits at the bottom of the scrollable area.
      await tester.scrollUntilVisible(
        find.text('Delete Account'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('shows Viewed Me empty state when no viewers', (tester) async {
      final dio = Dio()..httpClientAdapter = _CombinedAdapter(viewers: []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('VIEWED ME'), findsOneWidget);
      expect(find.text('No one has viewed you yet'), findsOneWidget);
    });

    testWidgets('shows Viewed Me section with viewer names', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _CombinedAdapter(viewers: [
          {
            'viewer_id': 'viewer-1',
            'viewed_at': '2026-07-01T10:00:00Z',
            'display_name': 'Bob',
            'profile_photo_url': null,
          },
          {
            'viewer_id': 'viewer-2',
            'viewed_at': '2026-07-01T09:00:00Z',
            'display_name': 'Alice',
            'profile_photo_url': null,
          },
        ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('VIEWED ME'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows Boost button when not active', (tester) async {
      final dio = Dio()..httpClientAdapter = _CombinedAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Boost'), findsOneWidget);
    });

    testWidgets('shows BOOSTED badge when active', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _CombinedAdapter(
          activeBoost: {
            'id': 'b-1',
            'expires_at': '2026-07-01T12:30:00Z',
            'minutes_remaining': 22,
          },
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // The badge appears on the profile photo AND the button shows
      // "BOOSTED · Nm left" — both contain "BOOSTED".
      expect(find.textContaining('BOOSTED'), findsNWidgets(2));
      expect(find.textContaining('22m left'), findsOneWidget);
    });

    testWidgets('tapping Boost calls POST /boost', (tester) async {
      final adapter = _CombinedAdapter();
      final dio = Dio()..httpClientAdapter = adapter;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Boost'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(adapter.boostPosts, hasLength(1));
    });
  });
}
