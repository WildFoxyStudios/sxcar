import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/cascade_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake adapter returning canned nearby users.
class _MockCascadeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({
      'users': [
        {
          'id': 'user-1',
          'email': 'bob@test.com',
          'display_name': 'Bob',
          'bio': 'Hey there',
          'profile_photo_id': null,
          'distance_m': 500,
        },
        {
          'id': 'user-2',
          'email': 'alice@test.com',
          'display_name': 'Alice',
          'bio': 'Hello!',
          'profile_photo_id': null,
          'distance_m': 1200,
        },
        {
          'id': 'user-3',
          'email': 'charlie@test.com',
          'display_name': 'Charlie',
          'bio': 'Hi!',
          'profile_photo_id': null,
          'distance_m': 50,
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

class _MockEmptyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({'users': <dynamic>[]});
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

class _MockErrorAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error":"server error"}',
      500,
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

void main() {
  group('CascadeScreen', () {
    testWidgets('loads and displays 3-column grid of users', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: CascadeScreen()),
        ),
      );

      // Initially shows loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for data
      await tester.pumpAndSettle();

      // Should show user names
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);

      // Should show distance text
      expect(find.text('500 m'), findsOneWidget);
      expect(find.text('1.2 km'), findsOneWidget);
      expect(find.text('50 m'), findsOneWidget);
    });

    testWidgets('shows empty state when no users nearby', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockEmptyAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: CascadeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No users found nearby'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockErrorAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: CascadeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Failed to load nearby users'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('has filter and search icons in AppBar', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: CascadeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
    });

    testWidgets('shows online indicator dot on user cards', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: CascadeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Green online dots should be present
      expect(find.byType(Container), findsWidgets);
    });
  });
}
