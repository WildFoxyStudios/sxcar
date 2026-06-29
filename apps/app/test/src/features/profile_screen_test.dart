import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/profile_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal fake response interceptor that always returns the canned profile.
class _MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // Return a canned profile response for any request
    final body = jsonEncode({
      'user': {
        'id': '00000000-0000-0000-0000-000000000001',
        'email': 'test@example.com',
        'email_verified': true,
        'status': 'active',
        'role': 'user',
        'created_at': '2025-01-01T00:00:00Z',
        'display_name': 'TestUser',
        'bio': 'Hello from test',
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
        'looking_for': ['chat'],
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

void main() {
  group('ProfileScreen (own profile)', () {
    late Dio dio;

    setUp(() {
      dio = Dio()..httpClientAdapter = _MockAdapter();
    });

    testWidgets('loads and displays profile data', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _AuthenticatedNotifier(),
            ),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );

      // Initially shows loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for the profile to load
      await tester.pumpAndSettle();

      // Verify profile data is displayed
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('TestUser'), findsOneWidget);
      expect(find.text('Hello from test'), findsOneWidget);
      expect(find.text('180 cm'), findsOneWidget);
      expect(find.text('75 kg'), findsOneWidget);
      expect(find.text('athletic'), findsOneWidget);
      expect(find.text('single'), findsOneWidget);
      expect(find.text('versatile'), findsOneWidget);
      expect(find.text('latino'), findsOneWidget);
      expect(find.text('he/him'), findsOneWidget);
      expect(find.text('1995-06-15'), findsOneWidget);

      // Verify chip arrays (use skipOffstage: false for off-screen items)
      expect(find.text('Tribes'), findsOneWidget);
      expect(find.text('geek', skipOffstage: false), findsOneWidget);
      expect(find.text('bear', skipOffstage: false), findsOneWidget);
      expect(find.text('chat', skipOffstage: false), findsOneWidget);
      expect(find.text('bar', skipOffstage: false), findsOneWidget);
      expect(find.text('fitness', skipOffstage: false), findsOneWidget);
    });

    testWidgets('shows edit button for own profile', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _AuthenticatedNotifier(),
            ),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Edit button should be visible
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });
  });

  group('ProfileScreen (other user)', () {
    late Dio dio;

    setUp(() {
      dio = Dio()..httpClientAdapter = _MockAdapter();
    });

    testWidgets('loads and displays other user profile', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _AuthenticatedNotifier(),
            ),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            home: ProfileScreen(userId: 'some-other-user-id'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show 'Profile' not 'My Profile' for other users
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('TestUser'), findsOneWidget);
      // No edit button for other user's profile
      expect(find.byIcon(Icons.edit), findsNothing);
    });
  });
}

class _AuthenticatedNotifier extends AuthNotifier {
  _AuthenticatedNotifier() : super();

  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'token',
        email: 'test@example.com',
      );

  @override
  Future<void> logout() async {}
}
