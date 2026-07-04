import 'dart:async';
import 'dart:convert';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/chat_list_screen.dart';
import 'package:app/src/theme/widgets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  final Map<String, ResponseBody> routeHandlers;
  _StubAdapter({this.routeHandlers = const {}});
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (routeHandlers.containsKey(path)) {
      return routeHandlers[path]!;
    }
    return ResponseBody.fromString(
        '{"conversations":[],"albums":[]}', 200,
        headers: {'content-type': ['application/json']});
  }
}

class _AuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test-token',
        email: 'test@example.com',
      );
  @override
  Future<void> logout() async {}
}

Widget _wrap(Dio dio) => ProviderScope(
      overrides: [
        authStateProvider.overrideWith(_AuthNotifier.new),
        dioProvider.overrideWithValue(dio),
      ],
      child: MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: const ChatListScreen(),
      ),
    );

void main() {
  group('ChatListScreen (Buzón)', () {
    testWidgets('renders TabBar with Bandeja + Álbumes tabs', (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter();

      await tester.pumpWidget(_wrap(dio));
      await tester.pumpAndSettle();

      // AppBar title + first Tab label both render "Bandeja de entrada"
      expect(find.text('Bandeja de entrada'), findsWidgets);
      // Second tab is "Álbumes"
      expect(find.text('Álbumes'), findsOneWidget);
    });

    testWidgets('Bandeja tab shows conversations from /chat/conversations',
        (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter(routeHandlers: {
        '/chat/conversations': ResponseBody.fromString(
          jsonEncode({
            'conversations': [
              {
                'conversation_id': 'conv-1',
                'other_user_id': 'user-2',
                'other_display_name': 'Bob',
                'last_message_preview': 'Hey there!',
                'last_message_at': '2025-01-01T00:00:00Z',
                'unread_count': 2,
              },
            ],
          }),
          200,
          headers: {'content-type': ['application/json']},
        ),
      });

      await tester.pumpWidget(_wrap(dio));
      await tester.pumpAndSettle();

      // Bob appears in the conversation tile
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Hey there!'), findsOneWidget);
      // Unread badge shows "2"
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('filter chips row renders No leído + En línea',
        (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter();

      await tester.pumpWidget(_wrap(dio));
      await tester.pumpAndSettle();

      // Both filter chip labels are present
      expect(find.text('No leído'), findsOneWidget);
      expect(find.text('En línea'), findsOneWidget);
      // At least one FilterChipPill rendered
      expect(find.byType(FilterChipPill), findsNWidgets(2));
    });

    testWidgets('Álbumes tab shows empty state when no shared albums',
        (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter();

      await tester.pumpWidget(_wrap(dio));
      await tester.pumpAndSettle();

      // Switch to Álbumes tab
      await tester.tap(find.text('Álbumes'));
      await tester.pumpAndSettle();

      // Empty-state widget shown
      expect(find.byType(AlbumUpdatesEmptyState), findsOneWidget);
      expect(find.byType(AlbumCarousel), findsNothing);
    });

    testWidgets('Álbumes tab shows AlbumCarousel when shared albums exist',
        (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter(routeHandlers: {
        '/albums/shared': ResponseBody.fromString(
          jsonEncode({
            'albums': [
              {
                'id': 'a1',
                'name': 'Beach',
                'is_private': false,
                'photo_count': 3,
                'created_at': '2026-07-04T00:00:00Z',
              },
            ],
          }),
          200,
          headers: {'content-type': ['application/json']},
        ),
      });

      await tester.pumpWidget(_wrap(dio));
      await tester.pumpAndSettle();

      // Switch to Álbumes tab
      await tester.tap(find.text('Álbumes'));
      await tester.pumpAndSettle();

      // Carousel rendered (and empty state is absent)
      expect(find.byType(AlbumCarousel), findsOneWidget);
      expect(find.byType(AlbumUpdatesEmptyState), findsNothing);
      // Album name is shown inside the carousel tile
      expect(find.text('Beach'), findsOneWidget);
    });
  });
}