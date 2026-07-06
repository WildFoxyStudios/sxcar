import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/grid_search_screen.dart';
import 'package:app/src/location/geocoding_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mock geocoding search function: returns canned results or empty.
class _MockGeocodingSearch {
  final List<Location> results;
  _MockGeocodingSearch(this.results);

  Future<List<Location>> call(String query) async => results;
}

class _MockExploreAdapter implements HttpClientAdapter {
  final List<String> paths = [];

  _MockExploreAdapter();

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
            'bio': 'In Barcelona',
            'profile_photo_id': null,
            'distance_m': 5000,
          },
        ],
      });
      return ResponseBody.fromString(
        body,
        200,
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
  group('GridSearchScreen geocoding', () {
    testWidgets('search_bar_debounces_input', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final mockSearch = _MockGeocodingSearch([]);
      int callCount = 0;
      final countingSearch = GeocodingService(search: (query) async {
        callCount++;
        return mockSearch.call(query);
      });

      final dio = Dio()..httpClientAdapter = _MockExploreAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
            geocodingServiceProvider.overrideWithValue(countingSearch),
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

      // Find the city search TextField (the one with the location_city icon)
      final cityField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText?.contains('ciudad') == true,
      );
      expect(cityField, findsOneWidget);
      await tester.tap(cityField);
      await tester.pump();

      // Type fast — 3 characters without waiting
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText?.contains('ciudad') == true,
        ),
        'Bar',
      );

      // Advance past the 500ms debounce timer but not fully settle
      // (the 500ms timer should be pending)
      await tester.pump(const Duration(milliseconds: 200));
      // Should not have been called yet (debounce is 500ms)
      expect(callCount, 0,
          reason: 'geocoder should NOT be called before 500ms debounce');

      // Now advance past the debounce
      await tester.pump(const Duration(milliseconds: 400));
      // Should have been called once
      expect(callCount, 1,
          reason: 'geocoder should be called once after debounce');

      // Type more characters quickly
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText?.contains('ciudad') == true,
        ),
        'Barcelona',
      );
      await tester.pump(const Duration(milliseconds: 600));
      // Should still be called only 2 times total (1 for "Bar" + 1 for "Barcelona")
      expect(callCount, 2,
          reason: 'geocoder should be called once per debounced input');
    });

    testWidgets('select_city_centers_grid', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final barcelonaLoc = Location(
        latitude: 41.3874,
        longitude: 2.1686,
        timestamp: DateTime.now(),
      );

      final dio = Dio()..httpClientAdapter = _MockExploreAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
            geocodingServiceProvider.overrideWithValue(
              GeocodingService(
                search: _MockGeocodingSearch([barcelonaLoc]).call,
              ),
            ),
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

      // Find city search field
      final cityField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText?.contains('ciudad') == true,
      );
      await tester.tap(cityField);
      await tester.pump();

      // Type a city
      await tester.enterText(cityField, 'Barcelona');
      await tester.pump(const Duration(milliseconds: 600));

      // Should see the suggestion label (just the query text, inside a ListTile)
      final suggestionFinder = find.ancestor(
        of: find.text('Barcelona'),
        matching: find.byType(ListTile),
      );
      expect(suggestionFinder, findsOneWidget,
          reason: 'suggestion should show label from geocoder result');

      // Tap the suggestion
      await tester.tap(suggestionFinder);
      await tester.pumpAndSettle();

      // The "Back to my location" button should be visible
      expect(
        find.text('Volver a mi ubicación'),
        findsOneWidget,
        reason: 'back to my location button should appear when city is selected',
      );

      // The grid should show users (fetched with the search coordinates)
      expect(find.text('GlobalUser1'), findsOneWidget);
    });

    testWidgets('back_to_my_location_clears_search', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final barcelonaLoc = Location(
        latitude: 41.3874,
        longitude: 2.1686,
        timestamp: DateTime.now(),
      );

      final dio = Dio()..httpClientAdapter = _MockExploreAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
            geocodingServiceProvider.overrideWithValue(
              GeocodingService(
                search: _MockGeocodingSearch([barcelonaLoc]).call,
              ),
            ),
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

      // First select a city
      final cityField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText?.contains('ciudad') == true,
      );
      await tester.tap(cityField);
      await tester.pump();
      await tester.enterText(cityField, 'Barcelona');
      await tester.pump(const Duration(milliseconds: 600));

      // Verify suggestion is visible and tap it
      final suggestionFinder = find.ancestor(
        of: find.text('Barcelona'),
        matching: find.byType(ListTile),
      );
      expect(suggestionFinder, findsOneWidget);
      await tester.tap(suggestionFinder);
      await tester.pumpAndSettle();

      // Now the back button should be visible
      final backButton = find.text('Volver a mi ubicación');
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Location indicator and back button should be gone
      expect(
        find.text('Volver a mi ubicación'),
        findsNothing,
        reason: 'back button should disappear after returning to GPS',
      );

      // The grid should still show users
      expect(find.text('GlobalUser1'), findsOneWidget,
          reason: 'grid should still show users after clearing city search');
    });

    testWidgets('empty_results_shows_message', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final dio = Dio()..httpClientAdapter = _MockExploreAdapter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
            geocodingServiceProvider.overrideWithValue(
              GeocodingService(
                search: _MockGeocodingSearch([]).call,
              ),
            ),
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

      // Find city search field
      final cityField = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText?.contains('ciudad') == true,
      );
      await tester.tap(cityField);
      await tester.pump();
      await tester.enterText(cityField, 'Atlantis');
      await tester.pump(const Duration(milliseconds: 600));

      // Should show "Sin resultados" message
      expect(
        find.text('Sin resultados'),
        findsOneWidget,
        reason: 'should show "no results" message when geocoding returns empty',
      );
    });
  });
}
