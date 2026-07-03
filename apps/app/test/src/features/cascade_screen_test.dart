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

Widget _wrap(Widget child, Dio dio, {LocationService? location}) {
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
  });
}
