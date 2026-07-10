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

Widget _wrapWithLocale(Dio dio) => ProviderScope(
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

/// Pumps the wrapped widget and captures the `AppLocalizations` for the
/// locale used (`es`). Tests can use `l10n.X` lookups instead of the
/// previously-hardcoded Spanish literals.
Future<AppLocalizations> _pumpAndL10n(
    WidgetTester tester, Dio dio) async {
  await tester.pumpWidget(_wrapWithLocale(dio));
  await tester.pumpAndSettle();
  // Localizations aren't initialized on MaterialApp's own element; pull them
  // from a descendant of the screen (the ChatListScreen widget) where the
  // Localizations ancestor is wired up.
  return AppLocalizations.of(
    tester.element(find.byType(ChatListScreen)),
  )!;
}

void main() {
  group('ChatListScreen (Buzón)', () {
    testWidgets('renders TabBar with Bandeja + Álbumes tabs', (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter();

      final l10n = await _pumpAndL10n(tester, dio);

      // AppBar title + first Tab label both render the Bandeja string
      expect(find.text(l10n.bandejaDeEntrada), findsWidgets);
      // Second tab is the albumes label
      expect(find.text(l10n.albumes), findsOneWidget);
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

      await _pumpAndL10n(tester, dio);

      // Bob appears in the conversation tile
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Hey there!'), findsOneWidget);
      // Unread badge shows "2"
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('filter chips row renders the No leído chip',
        (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter();

      final l10n = await _pumpAndL10n(tester, dio);

      // Only the "No leído" (unread) filter chip is rendered. The "En línea"
      // chip was removed: the Conversation model exposes no presence/online
      // flag, so an online filter would have been purely visual (filtered
      // nothing). One working filter chip > two fake ones.
      expect(find.text(l10n.noLeido), findsOneWidget);
      expect(find.text(l10n.enLineaFiltro), findsNothing);
      expect(find.byType(FilterChipPill), findsOneWidget);
    });

    testWidgets('Álbumes tab shows empty state when no shared albums',
        (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter();

      final l10n = await _pumpAndL10n(tester, dio);

      // Switch to Álbumes tab
      await tester.tap(find.text(l10n.albumes));
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

      final l10n = await _pumpAndL10n(tester, dio);

      // Switch to Álbumes tab
      await tester.tap(find.text(l10n.albumes));
      await tester.pumpAndSettle();

      // Carousel rendered (and empty state is absent)
      expect(find.byType(AlbumCarousel), findsOneWidget);
      expect(find.byType(AlbumUpdatesEmptyState), findsNothing);
      // Album name is shown inside the carousel tile
      expect(find.text('Beach'), findsOneWidget);
    });
  });
}