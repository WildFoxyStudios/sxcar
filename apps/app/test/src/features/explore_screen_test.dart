import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/explore_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockExploreAdapter implements HttpClientAdapter {
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
  });
}
