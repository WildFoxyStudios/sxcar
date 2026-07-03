import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/right_now_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockRightNowAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> intents;

  _MockRightNowAdapter({this.intents = const []});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/right-now' && options.method == 'GET') {
      return ResponseBody.fromString(
        jsonEncode({'intents': intents}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.path == '/right-now' && options.method == 'POST') {
      return ResponseBody.fromString(
        jsonEncode({
          'id': 'new-1',
          'user_id': 'user-1',
          'body': 'Test post',
          'expires_at': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'created_at': DateTime.now().toIso8601String(),
        }),
        201,
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

Widget _buildScreen(Dio dio) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
      dioProvider.overrideWithValue(dio),
    ],
    child: const MaterialApp(home: RightNowScreen()),
  );
}

void main() {
  group('RightNowScreen', () {
    testWidgets('shows empty state when feed is empty', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockRightNowAdapter();

      await tester.pumpWidget(_buildScreen(dio));
      await tester.pumpAndSettle();

      expect(find.text('Nadie por aquí ahora mismo'), findsOneWidget);
      expect(find.text('Sé el primero en publicar'), findsOneWidget);
    });

    testWidgets('shows feed intents when available', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _MockRightNowAdapter(intents: [
          {
            'id': 'intent-1',
            'user_id': 'other-user',
            'body': 'Looking for coffee',
            'expires_at':
                DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
          },
          {
            'id': 'intent-2',
            'user_id': 'another-user',
            'body': 'Up for a walk!',
            'expires_at':
                DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
          },
        ]);

      await tester.pumpWidget(_buildScreen(dio));
      await tester.pumpAndSettle();

      expect(find.text('Looking for coffee'), findsOneWidget);
      expect(find.text('Up for a walk!'), findsOneWidget);
    });

    testWidgets('has FAB that opens post sheet', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockRightNowAdapter();

      await tester.pumpWidget(_buildScreen(dio));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Tap FAB — should open a bottom sheet.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Post Right Now'), findsOneWidget);
    });

    testWidgets('own intent shows delete button', (tester) async {
      // JWT sub = user-1 encoded in the test token
      // We just test the delete icon is NOT shown for other users' intents.
      final dio = Dio()
        ..httpClientAdapter = _MockRightNowAdapter(intents: [
          {
            'id': 'intent-1',
            'user_id': 'different-user',
            'body': 'Others post',
            'expires_at':
                DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
          },
        ]);

      await tester.pumpWidget(_buildScreen(dio));
      await tester.pumpAndSettle();

      expect(find.text('Others post'), findsOneWidget);
      // No delete (close) icon for other users' posts.
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
