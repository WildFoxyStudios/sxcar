import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/profile_detail_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockProfileDetailAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final regExp = RegExp(r'^/users/([^/]+)/status$');
    final statusMatch = regExp.firstMatch(options.path);
    if (options.method == 'GET' && statusMatch != null) {
      final body = jsonEncode({
        'is_online': true,
        'last_seen_at': '2026-07-01T00:00:00Z',
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    final body = jsonEncode({
      'user': {
        'id': 'user-1',
        'email': 'bob@test.com',
        'email_verified': true,
        'status': 'active',
        'role': 'user',
        'created_at': '2025-01-01T00:00:00Z',
        'display_name': 'Bob',
        'bio': 'Hey there! I like hiking',
        'birthdate': '1995-06-15',
        'height_cm': 180,
        'weight_kg': 75,
        'body_type': 'athletic',
        'relationship_status': 'single',
        'position': 'versatile',
        'ethnicity': 'latino',
        'pronouns': 'he/him',
        'profile_photo_id': null,
        'profile_photo_url': null,
        'tribes': ['geek', 'bear'],
        'looking_for': ['chat', 'friends'],
        'meet_at': ['bar'],
        'tags': ['fitness'],
      },
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

class _MockErrorAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error":"not found"}',
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
  group('ProfileDetailScreen', () {
    testWidgets('loads and displays user profile', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockProfileDetailAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            home: ProfileDetailScreen(userId: 'user-1'),
          ),
        ),
      );

      // Initially loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Profile info
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Hey there! I like hiking'), findsOneWidget);

      // Stats
      expect(find.text('180 cm'), findsOneWidget);
      expect(find.text('75 kg'), findsOneWidget);
      expect(find.text('athletic'), findsOneWidget);
      expect(find.text('single'), findsOneWidget);
      expect(find.text('versatile'), findsOneWidget);
      expect(find.text('latino'), findsOneWidget);
      expect(find.text('he/him'), findsOneWidget);

      // Tribe chips
      expect(find.text('geek', skipOffstage: false), findsOneWidget);
      expect(find.text('bear', skipOffstage: false), findsOneWidget);
    });

    testWidgets('shows action buttons: Chat, Tap, Favorite, Block',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockProfileDetailAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            home: ProfileDetailScreen(userId: 'user-1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Action buttons
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Tap'), findsOneWidget);
      expect(find.text('Favorite'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockErrorAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            home: ProfileDetailScreen(userId: 'nonexistent'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load profile'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows Online badge when user is online', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockProfileDetailAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            home: ProfileDetailScreen(userId: 'user-1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Online'), findsOneWidget);
    });
  });
}
