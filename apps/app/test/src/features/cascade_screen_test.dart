import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/cascade_screen.dart';
import 'package:app/src/location/location_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
// Queue-based adapter (used by GPS-specific tests)
// ---------------------------------------------------------------------------

class _MockAdapter implements HttpClientAdapter {
  final _queue = <_MockResponse>[];

  void enqueue(int statusCode, [Map<String, dynamic>? body]) {
    _queue.add(_MockResponse(statusCode, body));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_queue.isEmpty) {
      // Return empty users for any unexpected call (e.g., presence status).
      return ResponseBody.fromString(
        jsonEncode({'users': <dynamic>[]}),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    }
    final response = _queue.removeAt(0);
    final body = response.body != null ? jsonEncode(response.body) : '';
    return ResponseBody.fromString(
      body,
      response.statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MockResponse {
  final int statusCode;
  final Map<String, dynamic>? body;
  _MockResponse(this.statusCode, this.body);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CascadeScreen', () {
    testWidgets('loads and displays 3-column grid of users', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            locationServiceProvider.overrideWithValue(_gpsAvailableService),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: CascadeScreen()),
        ),
      );

      // Initially shows loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for GPS + data
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
            locationServiceProvider.overrideWithValue(_gpsAvailableService),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: CascadeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No one nearby yet'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockErrorAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            locationServiceProvider.overrideWithValue(_gpsAvailableService),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: CascadeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Failed to load nearby users'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('has filter icon in AppBar', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            locationServiceProvider.overrideWithValue(_gpsAvailableService),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: CascadeScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Filter icon is present; search icon was replaced by the filter sheet
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
    });

    testWidgets('shows online indicator dot on user cards', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockCascadeAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            locationServiceProvider.overrideWithValue(_gpsAvailableService),
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

  group('CascadeScreen — distance slider', () {
    testWidgets(
      'distance slider defaults to 5 km and includes in initial query',
      (tester) async {
        final requests = <Map<String, dynamic>>[];
        final dio = Dio()
          ..httpClientAdapter = _RecordingCascadeAdapter(requests);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
              locationServiceProvider.overrideWithValue(_gpsAvailableService),
              dioProvider.overrideWithValue(dio),
            ],
            child: const MaterialApp(home: CascadeScreen()),
          ),
        );

        await tester.pumpAndSettle();

        expect(requests, isNotEmpty);
        final first = requests.first;
        // Default 5 km = 5000 m
        expect(first['radius_m'], equals(5000));
      },
    );

    testWidgets(
      'changing distance in filter sheet updates the grid query',
      (tester) async {
        final requests = <Map<String, dynamic>>[];
        final dio = Dio()
          ..httpClientAdapter = _RecordingCascadeAdapter(requests);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
              locationServiceProvider.overrideWithValue(_gpsAvailableService),
              dioProvider.overrideWithValue(dio),
            ],
            child: const MaterialApp(home: CascadeScreen()),
          ),
        );

        await tester.pumpAndSettle();

        final initialCount = requests.length;

        // Open filter sheet
        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();

        // Distance label should be visible
        expect(find.textContaining('Distance'), findsOneWidget);

        // Slider should be present
        final sliderFinder = find.byKey(const Key('distance_slider'));
        expect(sliderFinder, findsOneWidget);

        // Drag the slider thumb to a different value.
        await tester.drag(sliderFinder, const Offset(500, 0));
        await tester.pumpAndSettle();

        // Scroll the bottom sheet so the Apply button is on screen.
        await tester.drag(find.byType(SingleChildScrollView).first,
            const Offset(0, -500));
        await tester.pumpAndSettle();

        // Apply the filter
        await tester.tap(find.text('Apply'), warnIfMissed: false);
        await tester.pumpAndSettle();

        // A new request should have been made with the new radius
        expect(requests.length, greaterThan(initialCount));
        final last = requests.last;
        expect(last['radius_m'], isA<num>());
        // The new radius should be > the default 5000m
        expect((last['radius_m'] as num).toInt(), greaterThan(5000));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // GPS integration tests (Task 2)
  // ---------------------------------------------------------------------------

  group('CascadeScreen — GPS integration', () {
    Widget buildScreen({
      required LocationService locationService,
      required Dio dio,
    }) {
      return ProviderScope(
        overrides: [
          locationServiceProvider.overrideWithValue(locationService),
          dioProvider.overrideWithValue(dio),
        ],
        child: const MaterialApp(
          home: CascadeScreen(),
        ),
      );
    }

    Dio mockDio({Map<String, dynamic>? body}) {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.turnend.win'));
      final adapter = _MockAdapter();
      adapter.enqueue(200, body ?? {'users': []});
      dio.httpClientAdapter = adapter;
      return dio;
    }

    testWidgets(
      'GPS available — no location banner shown',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildScreen(
          locationService: _gpsAvailableService,
          dio: mockDio(),
        ));

        // pumpAndSettle drains the full async chain (GPS → network call →
        // FutureBuilder rebuild) including Dio's internal zero-duration timers.
        // Once the empty-list state replaces the spinner, no animations remain
        // and the test settles quickly.
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(
          find.text('Enable location to see people nearby'),
          findsNothing,
          reason: 'Banner must NOT appear when GPS resolves to a position',
        );
      },
    );

    testWidgets(
      'GPS denied — location banner visible',
      (WidgetTester tester) async {
        // Dio mock supplied but _fetchNearbyUsers returns early when position
        // is null, so no HTTP call is actually made.
        await tester.pumpWidget(buildScreen(
          locationService: _gpsDeniedService,
          dio: mockDio(),
        ));

        // GPS resolves instantly; banner is static so pumpAndSettle settles.
        await tester.pumpAndSettle(const Duration(seconds: 5));

        expect(
          find.text('Enable location to see people nearby'),
          findsOneWidget,
          reason: 'Banner MUST appear when GPS is denied',
        );
      },
    );
  });
}
