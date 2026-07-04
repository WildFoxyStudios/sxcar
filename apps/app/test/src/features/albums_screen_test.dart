import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/albums_screen.dart';
import 'package:app/src/theme/widgets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake response adapter that returns a canned albums list plus stubs for
/// the new endpoints (shared / share / delete).
class _MockAdapter implements HttpClientAdapter {
  Completer<void>? _completer;

  /// If set, the adapter will wait for this completer before responding.
  void hold() => _completer = Completer<void>();
  void release() => _completer?.complete();

  /// If set, the next GET /albums returns this list instead of the default.
  List<Map<String, dynamic>>? albumsOverride;

  /// If set, GET /albums/shared returns this list (default returns one album).
  List<Map<String, dynamic>>? sharedOverride;

  /// Inject failures.
  bool shareFails = false;
  bool deleteFails = false;

  /// Captured arguments.
  String? shareCalledWithAlbumId;
  String? shareCalledWithUserId;
  String? deleteCalledWithAlbumId;
  bool listSharedCalled = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_completer != null) {
      await _completer!.future;
    }

    final method = options.method;
    final path = options.path;

    if (method == 'GET' && path == '/albums') {
      final body = jsonEncode({
        'albums': albumsOverride ??
            [
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
      return ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }

    if (method == 'GET' && path == '/albums/shared') {
      listSharedCalled = true;
      final body = jsonEncode({
        'albums': sharedOverride ??
            [
              {
                'id': 'shared-a',
                'name': 'Shared Album',
                'description': null,
                'is_private': false,
                'photo_count': 3,
                'cover_photo_url': null,
                'created_at': '2025-06-03T00:00:00Z',
              },
            ],
      });
      return ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }

    if (method == 'POST' && path.contains('/share')) {
      if (shareFails) {
        return ResponseBody.fromString('{"error":"share failed"}', 500,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
      }
      final body = options.data is Map<String, dynamic>
          ? options.data as Map<String, dynamic>
          : const <String, dynamic>{};
      shareCalledWithUserId = body['user_id'] as String?;
      // /albums/<id>/share → parts = ['', 'albums', '<id>', 'share']
      final parts = path.split('/');
      shareCalledWithAlbumId = parts.length >= 3 ? parts[2] : null;
      return ResponseBody.fromString(
          '{"shared_with_user_id":"${body['user_id']}"}', 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }

    if (method == 'DELETE' && path.startsWith('/albums/') && !path.endsWith('/share')) {
      if (deleteFails) {
        return ResponseBody.fromString('{"error":"delete failed"}', 500,
            headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
      }
      // /albums/<id>
      deleteCalledWithAlbumId = path.split('/')[2];
      return ResponseBody.fromString('', 204, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }

    return ResponseBody.fromString('{"error":"not stubbed"}', 404, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Adapter that returns empty list for GET /albums (used by the empty-state
/// test). For GET /albums/shared it ALSO returns an empty list so the
/// "Mis compartidos" carousel does not pre-empt the shared test wiring.
class _EmptyMockAdapter implements HttpClientAdapter {
  /// Override shared-list behavior; default empty.
  List<Map<String, dynamic>>? sharedOverride;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final method = options.method;
    final path = options.path;
    if (method == 'GET' && path == '/albums') {
      return ResponseBody.fromString(jsonEncode({'albums': []}), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    if (method == 'GET' && path == '/albums/shared') {
      final list = sharedOverride ??
          <Map<String, dynamic>>[]; // default empty
      return ResponseBody.fromString(jsonEncode({'albums': list}), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString('{"error":"not stubbed"}', 404, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Adapter that returns 500 on GET /albums (used by the error-state test).
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

/// Adapter that returns full albums but EMPTY shared list. Used so we can
/// keep the rest of the screen rendered while only the shared list is empty.
class _EmptySharedMockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final method = options.method;
    final path = options.path;
    if (method == 'GET' && path == '/albums') {
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
        ],
      });
      return ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    if (method == 'GET' && path == '/albums/shared') {
      return ResponseBody.fromString(jsonEncode({'albums': []}), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString('{"error":"not stubbed"}', 404, headers: {
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

Future<void> _pumpScreen(WidgetTester tester, Dio dio) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
        dioProvider.overrideWithValue(dio),
      ],
      child: MaterialApp(
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AlbumsScreen(),
      ),
    ),
  );
  // Initial frame
  await tester.pump();
  // Let the album GET request resolve
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

void main() {
  group('AlbumsScreen', () {
    testWidgets('loads and displays albums list (grid layout)', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockAdapter();
      await _pumpScreen(tester, dio);

      // Verify albums are displayed
      expect(find.text('Vacation'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);

      // Photo-count overlay now shows just the number, not "5 photos".
      expect(find.text('5'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      // Verify FAB is still present.
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows empty state when no albums', (tester) async {
      final emptyDio = Dio()..httpClientAdapter = _EmptyMockAdapter();
      await _pumpScreen(tester, emptyDio);

      expect(find.text('No tienes álbumes aún'), findsOneWidget);
    });

    testWidgets('shows error state on failure', (tester) async {
      final errorDio = Dio()..httpClientAdapter = _ErrorMockAdapter();
      await _pumpScreen(tester, errorDio);

      // Should show error message and retry button.
      expect(find.textContaining('Failed to load albums'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    // ── 6 new tests below ──────────────────────────────────────────────────

    testWidgets('renders 3-column grid of albums', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockAdapter();
      await _pumpScreen(tester, dio);

      // Both albums visible in the grid.
      expect(find.text('Vacation'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);

      // Private album shows the lock badge.
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // The grid is rendered via SliverGrid — verify by finding SliverGrid.
      expect(find.byType(SliverGrid), findsOneWidget);
    });

    testWidgets('shows Mis compartidos carousel when shared albums exist',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockAdapter();
      await _pumpScreen(tester, dio);

      expect(find.byType(AlbumCarousel), findsOneWidget);
    });

    testWidgets('shows empty state for Mis compartidos when no shared albums',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _EmptySharedMockAdapter();
      await _pumpScreen(tester, dio);

      // Fallback text comes from the existing `noHayActualizaciones` key.
      expect(find.textContaining('actualizaciones'), findsOneWidget);
    });

    testWidgets('long-press opens action sheet with Compartir + Eliminar',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockAdapter();
      await _pumpScreen(tester, dio);

      expect(find.text('Vacation'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // Get the centre of the album tile for the Private album by looking
      // up the gesture detector wrapping the lock icon's parent Stack.
      final privateTile = find
          .ancestor(
            of: find.byIcon(Icons.lock),
            matching: find.byType(GestureDetector),
          )
          .first;

      await tester.longPress(privateTile, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('Compartir álbum'), findsOneWidget);
      expect(find.text('Eliminar álbum'), findsOneWidget);
    });

    testWidgets('Compartir sheet calls POST /albums/:id/share with user_id',
        (tester) async {
      final adapter = _MockAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      await _pumpScreen(tester, dio);

      await tester.longPress(find.byIcon(Icons.lock));
      await tester.pumpAndSettle();
      // Tap the menu entry "Compartir álbum" (list tile, not the sheet title).
      await tester.tap(find.text('Compartir álbum').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextField), '11111111-1111-1111-1111-111111111111');
      // Tap the bottom-sheet "Compartir álbum" pill button (also last in tree).
      await tester.tap(find.text('Compartir álbum').last);
      await tester.pumpAndSettle();

      expect(adapter.shareCalledWithAlbumId,
          '00000000-0000-0000-0000-000000000002');
      expect(adapter.shareCalledWithUserId,
          '11111111-1111-1111-1111-111111111111');
    });

    testWidgets('Eliminar action calls DELETE /albums/:id', (tester) async {
      final adapter = _MockAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      await _pumpScreen(tester, dio);

      await tester.longPress(find.byIcon(Icons.lock));
      await tester.pumpAndSettle();
      // Tap the menu entry "Eliminar álbum".
      await tester.tap(find.text('Eliminar álbum'));
      await tester.pumpAndSettle();
      // Confirm dialog → tap the delete action (last "Eliminar álbum").
      await tester.tap(find.text('Eliminar álbum').last);
      await tester.pumpAndSettle();

      expect(adapter.deleteCalledWithAlbumId,
          '00000000-0000-0000-0000-000000000002');
    });
  });
}
