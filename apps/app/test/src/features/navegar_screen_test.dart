import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/cascade_screen.dart';
import 'package:app/src/location/location_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Shared fake GPS helpers
// ---------------------------------------------------------------------------

final _fakePosition = Position(
  latitude: 37.7749,
  longitude: -122.4194,
  timestamp: DateTime(2026),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// A [LocationService] that immediately returns [_fakePosition] for any call.
LocationService get _gpsAvailableService => LocationService(
      checkPermission: () async => LocationPermission.whileInUse,
      requestPermission: () async => LocationPermission.whileInUse,
      isLocationServiceEnabled: () async => true,
      doGetCurrentPosition: () async => _fakePosition,
      doGetLastKnownPosition: () async => null,
    );

/// A [LocationService] that returns null for every call (GPS denied).
LocationService get _gpsDeniedService => LocationService(
      checkPermission: () async => LocationPermission.deniedForever,
      requestPermission: () async => LocationPermission.deniedForever,
      isLocationServiceEnabled: () async => false,
      doGetCurrentPosition: () async => null,
      doGetLastKnownPosition: () async => null,
    );

// ---------------------------------------------------------------------------
// Mock HTTP adapters
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Adapter that records query params for each /grid/nearby request.
// ---------------------------------------------------------------------------

class _RecordingCascadeAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> requests;

  _RecordingCascadeAdapter(this.requests);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/grid/nearby') {
      final params = <String, dynamic>{};
      options.queryParameters.forEach((k, v) {
        if (v != null) params[k] = v;
      });
      requests.add(params);
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
    return ResponseBody.fromString(
      '{}',
      404,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Widget _wrap(Widget child, Dio dio,
    {LocationService? location, int units = 0}) {
  // T5.9: seed SharedPreferences with the requested units value so the real
  // UnitsNotifier (which reads from prefs in build()) yields the test value.
  SharedPreferences.setMockInitialValues({'settings_units': units});
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
      locationServiceProvider
          .overrideWithValue(location ?? _gpsAvailableService),
      dioProvider.overrideWithValue(dio),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('es'),
      home: child,
    ),
  );
}

void main() {
  group('NavegarScreen (Grindr grid)', () {
    testWidgets('loads and displays the full-bleed grid of users',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(
          _wrap(const NavegarScreen(), dio));

      // Initially no user data yet (shimmer skeletons).
      expect(find.text('Bob'), findsNothing);

      await tester.pumpAndSettle();

      // Tiles show ONLY the display name overlay (no distance, no age).
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('500 m'), findsNothing);
    });

    testWidgets('shows the Grindr header: search pill + filter chips',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(
          _wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      // Search pill hint (l10n es).
      expect(find.text('Explorar más perfiles'), findsOneWidget);
      // Filter chips row.
      expect(find.text('Filtros'), findsOneWidget);
      expect(find.text('Favoritos'), findsOneWidget);
      expect(find.text('En línea'), findsOneWidget);
      expect(find.text('Right Now'), findsWidgets); // chip + FAB pill
    });

    testWidgets('shows empty state when no users nearby', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockEmptyAdapter();

      await tester.pumpWidget(
          _wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      expect(find.text('No one nearby yet'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockErrorAdapter();

      await tester.pumpWidget(
          _wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load nearby users'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('"En línea" chip re-queries with online_only=true',
        (tester) async {
      final requests = <Map<String, dynamic>>[];
      final dio = Dio()..httpClientAdapter = _RecordingCascadeAdapter(requests);

      await tester.pumpWidget(
          _wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      expect(requests, isNotEmpty);
      expect(requests.first.containsKey('online_only'), isFalse,
          reason: 'initial query must not filter by online');

      await tester.tap(find.text('En línea'));
      await tester.pumpAndSettle();

      expect(requests.last['online_only'], anyOf(true, 'true'),
          reason: 'tapping the chip must re-query with online_only');
    });

    testWidgets('GPS denied — shows the enable-location banner',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(_wrap(const NavegarScreen(), dio,
          location: _gpsDeniedService));
      await tester.pumpAndSettle();

      expect(
          find.text('Enable location to see people nearby'), findsOneWidget);
    });

    testWidgets('tapping the Filtros chip opens the filter sheet',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(
          _wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filtros'));
      await tester.pumpAndSettle();

      // The existing filter sheet exposes the distance slider.
      expect(find.byType(Slider), findsWidgets);
    });

    // ──────────────────────────────────────────────────────────────────
    // T5.9: NUEVO badge + dist(units) + 3 server-side filters
    // ──────────────────────────────────────────────────────────────────

    testWidgets('navevar_sends_favorites_only_true_when_chip_active',
        (tester) async {
      final requests = <Map<String, dynamic>>[];
      final dio = Dio()..httpClientAdapter = _RecordingCascadeAdapter(requests);

      await tester.pumpWidget(_wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      // Initial query must NOT include favorites_only (chip is off by default).
      expect(requests.first.containsKey('favorites_only'), isFalse,
          reason: 'initial query must not filter by favorites');

      // Tap the Favoritos chip.
      await tester.tap(find.text('Favoritos'));
      await tester.pumpAndSettle();

      // After toggle, the API must have been re-queried with
      // favorites_only=true.
      expect(requests.last['favorites_only'], anyOf(true, 'true'),
          reason: 'tapping Favoritos must re-query with favorites_only=true');
    });

    testWidgets('navevar_sends_right_now_true_when_chip_active',
        (tester) async {
      final requests = <Map<String, dynamic>>[];
      final dio = Dio()..httpClientAdapter = _RecordingCascadeAdapter(requests);

      await tester.pumpWidget(_wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      // Initial query must NOT include right_now (chip is off by default).
      expect(requests.first.containsKey('right_now'), isFalse,
          reason: 'initial query must not filter by right_now');

      // Tap the Ahora chip (the chip — not the FAB).
      await tester.tap(find.text('Ahora'));
      await tester.pumpAndSettle();

      // After toggle, the API must have been re-queried with right_now=true.
      expect(requests.last['right_now'], anyOf(true, 'true'),
          reason: 'tapping Ahora chip must re-query with right_now=true');
    });

    testWidgets('navevar_distance_label_uses_units_provider', (tester) async {
      // Adapter that returns one user at 500 m (sub-1km, exercises units branch).
      // We assert on `distanceLabel(int units)` directly because the cascade
      // tile overlay does not display the distance label (only the name
      // overlay is shown in the grid). This is still a meaningful exercise
      // of T5.6's formatDistance unit-handling through the model.
      // (T5.10 dropped the legacy no-arg `distanceText` getter — pass
      // `units` explicitly: 0 for metric.)
      const u500 = NearbyUser(
        id: 'u-500',
        email: 'closer@test.com',
        displayName: 'Closer',
        distanceM: 500,
      );
      // Metric (0) → "500 m".
      expect(u500.distanceLabel(0), '500 m');
      // Imperial (1) → "1640 ft" (500 m × 3.28084 ≈ 1640 ft).
      expect(u500.distanceLabel(1), '1640 ft');
      // Sub-1km in imperial still uses feet, not miles.
      const u900 = NearbyUser(id: 'x', email: 'x', distanceM: 900);
      expect(u900.distanceLabel(1), '2953 ft');
      // ≥1mi in imperial switches to miles.
      const u2000 = NearbyUser(id: 'x', email: 'x', distanceM: 2000);
      expect(u2000.distanceLabel(1), '1.2 mi');
    });

    testWidgets('navevar_nuevo_badge_appears_for_recent_user', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _MockNuevoAdapter(daysOld: 1);
      await tester.pumpWidget(_wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      // Bob was created 1 day ago → NUEVO badge is shown on the tile.
      expect(find.text('NUEVO'), findsOneWidget);
      // The user name is still present (badge doesn't replace it).
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('navevar_nuevo_badge_hidden_for_old_user', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _MockNuevoAdapter(daysOld: 30);
      await tester.pumpWidget(_wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      // Bob was created 30 days ago → no NUEVO badge.
      expect(find.text('NUEVO'), findsNothing);
      // The user name is still present.
      expect(find.text('Bob'), findsOneWidget);
    });

    // ──────────────────────────────────────────────────────────────────
    // G1: photos_only, not_chatted, position filter chips
    // ──────────────────────────────────────────────────────────────────

    testWidgets('navegar_sends_photos_only_true_when_chip_active',
        (tester) async {
      final requests = <Map<String, dynamic>>[];
      final dio = Dio()..httpClientAdapter = _RecordingCascadeAdapter(requests);

      await tester.pumpWidget(_wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      // Initial query must NOT include photos_only.
      expect(requests.first.containsKey('photos_only'), isFalse,
          reason: 'initial query must not filter by photos_only');

      // Tap the "Con foto" chip.
      await tester.tap(find.text('Con foto'));
      await tester.pumpAndSettle();

      // After toggle, API must re-query with photos_only=true.
      expect(requests.last['photos_only'], anyOf(true, 'true'),
          reason: 'tapping Con foto must re-query with photos_only=true');
    });

    testWidgets('navegar_sends_not_chatted_true_when_chip_active',
        (tester) async {
      final requests = <Map<String, dynamic>>[];
      final dio = Dio()..httpClientAdapter = _RecordingCascadeAdapter(requests);

      await tester.pumpWidget(_wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      // Initial query must NOT include not_chatted.
      expect(requests.first.containsKey('not_chatted'), isFalse,
          reason: 'initial query must not filter by not_chatted');

      // The chips row is a horizontal ListView; scroll to reveal "Sin chatear"
      // (6th chip — may be off-screen in the narrow test viewport).
      await tester.drag(
        find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();

      // Tap the "Sin chatear" chip.
      await tester.tap(find.text('Sin chatear'));
      await tester.pumpAndSettle();

      // After toggle, API must re-query with not_chatted=true.
      expect(requests.last['not_chatted'], anyOf(true, 'true'),
          reason: 'tapping Sin chatear must re-query with not_chatted=true');
    });

    testWidgets('navegar_posicion_chip_visible_and_no_initial_param',
        (tester) async {
      final requests = <Map<String, dynamic>>[];
      final dio = Dio()..httpClientAdapter = _RecordingCascadeAdapter(requests);

      await tester.pumpWidget(_wrap(const NavegarScreen(), dio));
      await tester.pumpAndSettle();

      // The Posición chip is rendered in the filter row widget tree.
      // skipOffstage: false because it may be scrolled off in the narrow test
      // viewport (horizontal ListView).
      expect(find.text('Posición', skipOffstage: false), findsOneWidget,
          reason: 'Posición chip must exist in the filter row widget tree');

      // Initial query must NOT include position.
      expect(requests.first.containsKey('position'), isFalse,
          reason: 'initial query must not include position when chip is inactive');
    });
  });
}

// ────────────────────────────────────────────────────────────────────────────
// T5.9: NUEVO badge mock adapter — returns a single user with created_at
// `daysOld` days before now. The badge is shown when daysOld < 7.
// ────────────────────────────────────────────────────────────────────────────

class _MockNuevoAdapter implements HttpClientAdapter {
  final int daysOld;
  _MockNuevoAdapter({required this.daysOld});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final created = DateTime.now().subtract(Duration(days: daysOld));
    final body = jsonEncode({
      'users': [
        {
          'id': 'user-1',
          'email': 'bob@test.com',
          'display_name': 'Bob',
          'bio': 'Hey there',
          'profile_photo_id': null,
          'distance_m': 500,
          'created_at': created.toIso8601String(),
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
