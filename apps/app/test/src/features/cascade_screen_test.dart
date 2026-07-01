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

      expect(find.text('No one nearby yet'), findsOneWidget);
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

    testWidgets('has filter icon in AppBar', (tester) async {
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

      // Filter icon is present; search icon was replaced by the filter sheet
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
}

/// Adapter that records each /grid/nearby request and returns canned data.
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
