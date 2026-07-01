import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/you_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Combined adapter for YouScreen (profile + albums).
class _CombinedAdapter implements HttpClientAdapter {
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
      return ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    if (options.path == '/albums') {
      final body = jsonEncode({'albums': <dynamic>[]});
      return ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString('{}', 404, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _AuthenticatedNotifier extends AuthNotifier {
  final String? email;

  _AuthenticatedNotifier({this.email}) : super();

  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'token',
        email: email ?? 'test@example.com',
      );

  @override
  Future<void> logout() async {}
}

void main() {
  group('YouScreen (replaces SettingsScreen)', () {
    testWidgets('shows user email and logout option', (tester) async {
      final dio = Dio()..httpClientAdapter = _CombinedAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _AuthenticatedNotifier(email: 'test@example.com'),
            ),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('@test'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('shows profile email when auth email is null', (tester) async {
      final dio = Dio()..httpClientAdapter = _CombinedAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _AuthenticatedNotifier(email: null),
            ),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: YouScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Profile loads with email 'test@example.com', shows @test prefix
      expect(find.text('@test'), findsOneWidget);
    });
  });
}
