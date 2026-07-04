import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/grid_search_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockExploreAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> places;
  final Map<String, dynamic>? roamLocation;
  final List<String> paths = [];

  /// Optional ISO 8601 string injected as `created_at` on the canned user-1.
  /// If null, `created_at` is omitted from the response (preserves T5.10's
  /// pre-existing test fixture shape — no NUEVO badge by default).
  final String? user1CreatedAt;

  _MockExploreAdapter({
    this.places = const [],
    this.roamLocation,
    this.user1CreatedAt,
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add('${options.method} ${options.path}');

    if (options.path == '/grid/nearby') {
      final user1 = <String, dynamic>{
        'id': 'user-1',
        'email': 'global1@test.com',
        'display_name': 'GlobalUser1',
        'bio': 'Far away',
        'profile_photo_id': null,
        'distance_m': 250000,
      };
      if (user1CreatedAt != null) user1['created_at'] = user1CreatedAt;
      final body = jsonEncode({
        'users': [
          user1,
          {
            'id': 'user-2',
            'email': 'global2@test.com',
            'display_name': 'GlobalUser2',
            'bio': 'Very far',
            'profile_photo_id': null,
            'distance_m': 500000,
          },
        ],
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }

    if (options.path == '/me/location' && options.method == 'GET') {
      return ResponseBody.fromString(
        jsonEncode({'location': roamLocation}),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }

    if (options.path == '/me/location' && options.method == 'PUT') {
      return ResponseBody.fromString(
        jsonEncode({'location': options.data}),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }

    if (options.path == '/places' && options.method == 'GET') {
      return ResponseBody.fromString(
        jsonEncode({'places': places}),
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }

    if (options.path == '/places' && options.method == 'POST') {
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : options.data as Map<String, dynamic>;
      return ResponseBody.fromString(
        jsonEncode({
          'place': {
            'id': 'new-place-id',
            'name': body['name'] as String,
            'lat': body['lat'] as num,
            'lon': body['lon'] as num,
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
  group('GridSearchScreen', () {
    testWidgets('loads and displays global grid', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockExploreAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: GridSearchScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('GlobalUser1'), findsOneWidget);
      expect(find.text('GlobalUser2'), findsOneWidget);
      expect(find.byIcon(Icons.explore_outlined), findsOneWidget);
    });

    testWidgets('opens roam bottom sheet on icon tap', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockExploreAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: GridSearchScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the Roam icon in the app bar.
      await tester.tap(find.byIcon(Icons.explore_outlined));
      await tester.pumpAndSettle();

      // Bottom sheet header is visible.
      expect(find.text('Roam'), findsOneWidget);
      expect(find.text('Use real location'), findsOneWidget);
      expect(find.text('Add new place'), findsOneWidget);
    });

    testWidgets('lists saved places in roam sheet', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _MockExploreAdapter(places: [
          {'id': 'place-1', 'name': 'Coffee Shop', 'lat': 19.4, 'lon': -99.1},
        ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: GridSearchScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.explore_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Coffee Shop'), findsOneWidget);
    });

    testWidgets('applies persisted roam location on first build',
        (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _MockExploreAdapter(
          roamLocation: {
            'lat': 40.7128,
            'lon': -74.0060,
            'name': 'NYC',
            'is_roam': true,
          },
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: GridSearchScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Title should show the persisted location name.
      expect(find.textContaining('NYC'), findsOneWidget);
    });

    // T5.10: first end-to-end unitsProvider round-trip. Seeds the
    // SharedPreferences value (the only seam into the real
    // `UnitsNotifier.build()`), then pumps the screen and asserts the
    // rendered distance label switches units with the seed.
    testWidgets(
        'explore_card_uses_units_provider_for_distance_label',
        (tester) async {
      // Seed imperial (1). UnitsNotifier.build() will hydrate from prefs
      // and emit 1 → grid_search passes it into _ExploreUserCard → the
      // 250 000 m / 500 000 m canned fixtures render as miles.
      SharedPreferences.setMockInitialValues({'settings_units': 1});
      final dio = Dio()..httpClientAdapter = _MockExploreAdapter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: GridSearchScreen(),
          ),
        ),
      );
      // Hydration is async — pump until the pref-read settles.
      await tester.pumpAndSettle();
      // 250 km / 1.609 ≈ 155 mi; 500 km / 1.609 ≈ 310 mi.
      expect(find.textContaining('mi'), findsWidgets,
          reason: 'imperial units must render "mi" suffixes');
      // No metric units in the labels.
      expect(find.textContaining(' km'), findsNothing,
          reason: 'imperial units must not render "km" suffixes');
    });

    testWidgets('explore_card_shows_nuevo_badge_for_recent_user',
        (tester) async {
      // Account created 1 day ago — within the <7d "isNew" window.
      final created = DateTime.now()
          .subtract(const Duration(days: 1))
          .toUtc()
          .toIso8601String();
      final dio = Dio()
        ..httpClientAdapter = _MockExploreAdapter(user1CreatedAt: created);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: GridSearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 'NUEVO' is the es-locale badgeNew string.
      expect(find.text('NUEVO'), findsOneWidget,
          reason: 'account <7d old must render the NUEVO badge');
    });

    testWidgets('explore_card_hides_nuevo_badge_for_old_user',
        (tester) async {
      // Account created 30 days ago — outside the <7d "isNew" window.
      final created = DateTime.now()
          .subtract(const Duration(days: 30))
          .toUtc()
          .toIso8601String();
      final dio = Dio()
        ..httpClientAdapter = _MockExploreAdapter(user1CreatedAt: created);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('es'),
            home: GridSearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NUEVO'), findsNothing,
          reason: 'account ≥7d old must NOT render the NUEVO badge');
    });
  });
}
