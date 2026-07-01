import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/albums_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake response adapter that returns a canned albums list.
class _MockAdapter implements HttpClientAdapter {
  Completer<void>? _completer;

  /// If set, the adapter will wait for this completer before responding.
  void hold() => _completer = Completer<void>();
  void release() => _completer?.complete();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_completer != null) {
      await _completer!.future;
    }

    final body = jsonEncode({
      'albums': [
        {
          'id': '00000000-0000-0000-0000-000000000001',
          'name': 'Vacation',
          'description': 'Summer trip photos',
          'is_private': false,
          'photo_count': 5,
          'cover_photo_url': null,
          'created_at': '2025-06-01T00:00:00Z',
        },
        {
          'id': '00000000-0000-0000-0000-000000000002',
          'name': 'Private',
          'description': null,
          'is_private': true,
          'photo_count': 0,
          'cover_photo_url': null,
          'created_at': '2025-06-02T00:00:00Z',
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

void main() {
  group('AlbumsScreen', () {
    late Dio dio;

    setUp(() {
      dio = Dio()..httpClientAdapter = _MockAdapter();
    });

    testWidgets('loads and displays albums list', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(dio),
          ],
          child: const MaterialApp(home: AlbumsScreen()),
        ),
      );

      // Initially shows loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for the albums to load
      await tester.pumpAndSettle();

      // Verify albums are displayed
      expect(find.text('Vacation'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.text('Summer trip photos'), findsOneWidget);

      // Verify photo counts
      expect(find.text('5 photos'), findsOneWidget);
      expect(find.text('0 photos  (private)'), findsOneWidget);

      // Verify FAB is present
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows empty state when no albums', (tester) async {
      // Override adapter to return empty list
      final emptyDio = Dio()
        ..httpClientAdapter = _EmptyMockAdapter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(emptyDio),
          ],
          child: const MaterialApp(home: AlbumsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No albums yet'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      final errorDio = Dio()
        ..httpClientAdapter = _ErrorMockAdapter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
            dioProvider.overrideWithValue(errorDio),
          ],
          child: const MaterialApp(home: AlbumsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Should show error message and retry button
      expect(find.textContaining('Failed to load albums'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

class _EmptyMockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = jsonEncode({'albums': []});
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

class _ErrorMockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('{"error":"server error"}', 500, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _AuthenticatedNotifier extends AuthNotifier {
  _AuthenticatedNotifier() : super();

  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'token',
        email: 'test@example.com',
      );

  @override
  Future<void> logout() async {}
}
