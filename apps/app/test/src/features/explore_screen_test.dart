import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/explore_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockExploreAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> places;
  final Map<String, dynamic>? roamLocation;
  final List<String> paths = [];

  _MockExploreAdapter({this.places = const [], this.roamLocation});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add('${options.method} ${options.path}');

    if (options.path == '/grid/nearby') {
      final body = jsonEncode({
        'users': [
          {
            'id': 'user-1',
            'email': 'global1@test.com',
            'display_name': 'GlobalUser1',
            'bio': 'Far away',
            'profile_photo_id': null,
            'distance_m': 250000,
          },
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
  group('ExploreScreen', () {
    testWidgets('loads and displays global grid', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockExploreAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: ExploreScreen()),
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
          child: const MaterialApp(home: ExploreScreen()),
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
          child: const MaterialApp(home: ExploreScreen()),
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
          child: const MaterialApp(home: ExploreScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Title should show the persisted location name.
      expect(find.textContaining('NYC'), findsOneWidget);
    });
  });
}
