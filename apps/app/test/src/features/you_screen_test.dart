import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/you_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Adapter that returns profile on /profile, albums on /albums, and
/// /profile/views can be customized via [viewers].
class _CombinedAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> viewers;

  _CombinedAdapter({this.viewers = const []});

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
  });
}
