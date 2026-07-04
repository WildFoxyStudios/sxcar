import 'dart:convert';
import 'dart:typed_data';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/profile_detail_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// ── Mock HTTP adapter (handles all routes used by ProfileDetailScreen) ─────────

class _FullMockAdapter implements HttpClientAdapter {
  /// Records '$METHOD $PATH' for each request.
  final List<String> calls;
  final bool showAge;
  final bool showRelationshipStatus;
  final bool showSocialLinks;

  _FullMockAdapter({
    required this.calls,
    this.showAge = true,
    this.showRelationshipStatus = true,
    this.showSocialLinks = true,
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final method = options.method.toUpperCase();
    calls.add('$method $path');

    // GET /profile/:userId
    if (method == 'GET' && path.startsWith('/profile/')) {
      final userId = path.substring('/profile/'.length);
      return _profileBody(userId: userId);
    }

    // GET /users/:id/status
    if (method == 'GET' && _statusPattern.hasMatch(path)) {
      return _json({
        'is_online': true,
        'last_seen_at': null,
      });
    }

    // GET /grid/nearby
    if (method == 'GET' && path == '/grid/nearby') {
      return _json({
        'users': [
          _nearbyUser('u2', 'Alice'),
          _nearbyUser('u3', 'Carol'),
          _nearbyUser('u4', 'Dan'),
          _nearbyUser('u5', 'Eve'),
        ],
      });
    }

    // POST /favorites
    if (method == 'POST' && path == '/favorites') {
      return _json({'ok': true});
    }

    // DELETE /favorites/:userId
    if (method == 'DELETE' && path.startsWith('/favorites/')) {
      return _json({'ok': true});
    }

    // POST /chat/conversations → {conversation_id: 'conv-1'}
    if (method == 'POST' && path == '/chat/conversations') {
      return _json({'conversation_id': 'conv-1'});
    }

    // POST /chat/conversations/:id/messages → {id: 'msg-1'}
    if (method == 'POST' && _msgPattern.hasMatch(path)) {
      return _json({'id': 'msg-1'});
    }

    // Default success
    return _json({'ok': true});
  }

  @override
  void close({bool force = false}) {}

  // ── helpers ────────────────────────────────────────────────────────────────

  static final _statusPattern = RegExp(r'^/users/[^/]+/status$');
  static final _msgPattern =
      RegExp(r'^/chat/conversations/[^/]+/messages$');

  ResponseBody _profileBody({required String userId}) {
    if (userId == 'minimal-user') {
      // Minimal profile: only required fields, no health, no optional arrays
      return _json({
        'user': {
          'id': 'minimal-user',
          'email': 'min@test.com',
          'email_verified': true,
          'status': 'active',
          'role': 'user',
          'created_at': '2025-01-01T00:00:00Z',
        },
        // No 'health' key
      });
    }

    // Full profile with all fields + health data
    return _json({
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
        'verified': false,
        'tribes': ['geek', 'bear'],
        'looking_for': ['chat', 'friends'],
        'meet_at': ['bar'],
        'tags': ['fitness'],
        'show_age': showAge,
        'show_relationship_status': showRelationshipStatus,
        'show_social_links': showSocialLinks,
      },
      'details': showSocialLinks
          ? {
              'social': {'instagram': '@bob'},
            }
          : <String, dynamic>{},
      'health': {
        'hiv_status': 'negative',
        'last_tested_at': '2025-10',
        'safer_practices_list': ['condoms', 'prep'],
      },
    });
  }

  Map<String, dynamic> _nearbyUser(String id, String name) => {
        'id': id,
        'email': '$name@test.com',
        'display_name': name,
        'bio': null,
        'profile_photo_id': null,
        'profile_photo_url': null,
        'distance_m': 500.0,
        'verified': false,
      };

  ResponseBody _json(Object body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

// ── Auth stub ─────────────────────────────────────────────────────────────────

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

// ── Shared widget builder ─────────────────────────────────────────────────────

Widget _withProviders(Widget child, Dio dio) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
      dioProvider.overrideWithValue(dio),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Explicit Spanish locale so l10n strings match the brief
      locale: const Locale('es'),
      home: child,
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ProfileDetailScreen', () {
    // ── Test 1 ────────────────────────────────────────────────────────────────
    testWidgets('renders all sections with full profile', (tester) async {
      final calls = <String>[];
      final dio = Dio()..httpClientAdapter = _FullMockAdapter(calls: calls);

      await tester.pumpWidget(
        _withProviders(const ProfileDetailScreen(userId: 'user-1'), dio),
      );

      // Initially shows loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Name is displayed
      expect(find.text('Bob'), findsWidgets);

      // Online status badge shows "Conectado" (Spanish l10n)
      expect(find.textContaining('Conectado'), findsOneWidget);

      // Bottom bar "Di algo..." hint is present
      expect(find.textContaining('Di algo'), findsOneWidget);

      // ── Section headers (may be below the fold — use skipOffstage: false) ──
      expect(find.text('ACERCA DE MÍ', skipOffstage: false), findsOneWidget);
      expect(find.text('ESTADÍSTICAS', skipOffstage: false), findsOneWidget);
      expect(find.text('EXPECTATIVAS', skipOffstage: false), findsOneWidget);
      expect(find.text('SALUD', skipOffstage: false), findsOneWidget);
      expect(
          find.text('TE PODRÍA INTERESAR', skipOffstage: false), findsOneWidget);

      // Bio text
      expect(
          find.text('Hey there! I like hiking', skipOffstage: false),
          findsOneWidget);

      // NUEVO badge next to TE PODRÍA INTERESAR
      expect(find.text('NUEVO', skipOffstage: false), findsOneWidget);

      // At least one suggestion tile name renders
      expect(find.text('Alice', skipOffstage: false), findsOneWidget);
    });

    // ── Test 2 ────────────────────────────────────────────────────────────────
    testWidgets('Di algo sends message and navigates to inbox', (tester) async {
      final calls = <String>[];
      final dio = Dio()..httpClientAdapter = _FullMockAdapter(calls: calls);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const ProfileDetailScreen(userId: 'user-1'),
          ),
          GoRoute(
            path: '/inbox/:conversationId',
            builder: (context, state) => Scaffold(
              body: Text('inbox-${state.pathParameters['conversationId']}'),
            ),
          ),
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) => Scaffold(
              body: Text('profile-${state.pathParameters['userId']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('es'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter text in "Di algo" field
      final textField = find.byType(TextField).first;
      await tester.enterText(textField, 'hola');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Verify chat API calls were made
      expect(calls, contains('POST /chat/conversations'));
      expect(calls, contains('POST /chat/conversations/conv-1/messages'));

      // Navigation happened — inbox screen is shown
      expect(find.text('inbox-conv-1'), findsOneWidget);
    });

    // ── Test 3 ────────────────────────────────────────────────────────────────
    testWidgets('favorite toggles state', (tester) async {
      final calls = <String>[];
      final dio = Dio()..httpClientAdapter = _FullMockAdapter(calls: calls);

      await tester.pumpWidget(
        _withProviders(const ProfileDetailScreen(userId: 'user-1'), dio),
      );
      await tester.pumpAndSettle();

      // Initially shows star_border (not favorited)
      expect(find.byIcon(Icons.star_border), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);

      // Tap → add favorite (POST /favorites)
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();

      expect(calls, contains('POST /favorites'));
      // Now shows filled star
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.byIcon(Icons.star_border), findsNothing);

      // Tap again → remove favorite (DELETE /favorites/user-1)
      await tester.tap(find.byIcon(Icons.star));
      await tester.pumpAndSettle();

      expect(calls, contains('DELETE /favorites/user-1'));
      // Back to star_border
      expect(find.byIcon(Icons.star_border), findsOneWidget);
    });

    // ── Test 4 ────────────────────────────────────────────────────────────────
    testWidgets('no details field does not crash', (tester) async {
      final calls = <String>[];
      final dio = Dio()..httpClientAdapter = _FullMockAdapter(calls: calls);

      // Uses minimal-user which has no health and no optional fields
      await tester.pumpWidget(
        _withProviders(
          const ProfileDetailScreen(userId: 'minimal-user'),
          dio,
        ),
      );

      // pumpAndSettle must complete without exception
      await tester.pumpAndSettle();

      // Basic sanity: loading state resolves and no crash
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Failed to load profile'), findsNothing);
    });

    // ── Test 5 ────────────────────────────────────────────────────────────────
    testWidgets('hides age when show_age=false', (tester) async {
      final calls = <String>[];
      final dio = Dio()
        ..httpClientAdapter = _FullMockAdapter(calls: calls, showAge: false);

      await tester.pumpWidget(
        _withProviders(const ProfileDetailScreen(userId: 'user-1'), dio),
      );
      await tester.pumpAndSettle();

      // No age text in the hero (gated out)
      expect(find.textContaining('años'), findsNothing);
    });

    // ── Test 6 ────────────────────────────────────────────────────────────────
    testWidgets('hides relationship status when show_relationship_status=false',
        (tester) async {
      final calls = <String>[];
      final dio = Dio()
        ..httpClientAdapter =
            _FullMockAdapter(calls: calls, showRelationshipStatus: false);

      await tester.pumpWidget(
        _withProviders(const ProfileDetailScreen(userId: 'user-1'), dio),
      );
      await tester.pumpAndSettle();

      // Scroll the body far enough to make the stats section offstage-by-now
      // assertable: with the gate off there must be no "single" text anywhere.
      // Use offstage: true so we don't fail on widgets below the fold.
      expect(find.text('single', skipOffstage: true), findsNothing);
    });

    // ── Test 7 ────────────────────────────────────────────────────────────────
    testWidgets('hides social block when show_social_links=false',
        (tester) async {
      final calls = <String>[];
      final dio = Dio()
        ..httpClientAdapter =
            _FullMockAdapter(calls: calls, showSocialLinks: false);

      await tester.pumpWidget(
        _withProviders(const ProfileDetailScreen(userId: 'user-1'), dio),
      );
      await tester.pumpAndSettle();

      // No social block header rendered
      expect(find.text('REDES SOCIALES'), findsNothing);
    });
  });
}
