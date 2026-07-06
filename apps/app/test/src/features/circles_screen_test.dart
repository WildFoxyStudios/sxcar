import 'dart:async';
import 'dart:convert';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/circles_screen.dart';
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
    return ResponseBody.fromString('{}', 200,
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
        home: const CirclesScreen(),
      ),
    );

Future<AppLocalizations> _pumpAndL10n(WidgetTester tester, Dio dio) async {
  await tester.pumpWidget(_wrapWithLocale(dio));
  await tester.pumpAndSettle();
  return AppLocalizations.of(
    tester.element(find.byType(CirclesScreen)),
  )!;
}

void main() {
  group('CirclesScreen', () {
    testWidgets('shows empty state when no groups', (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter(routeHandlers: {
        '/chat/groups': ResponseBody.fromString(
          jsonEncode({'groups': []}),
          200,
          headers: {'content-type': ['application/json']},
        ),
      });

      final l10n = await _pumpAndL10n(tester, dio);

      expect(find.text(l10n.noGroupsYet), findsOneWidget);
      expect(find.text(l10n.createGroup), findsOneWidget);
    });

    testWidgets('shows group list when groups exist', (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter(routeHandlers: {
        '/chat/groups': ResponseBody.fromString(
          jsonEncode({
            'groups': [
              {
                'group_id': 'group-1',
                'name': 'Amigos',
                'member_count': 5,
                'last_message_preview': 'Hello!',
                'last_message_at': '2026-07-06T10:00:00Z',
              },
              {
                'group_id': 'group-2',
                'name': 'Work',
                'member_count': 3,
                'last_message_preview': null,
                'last_message_at': null,
              },
            ],
          }),
          200,
          headers: {'content-type': ['application/json']},
        ),
      });

      await _pumpAndL10n(tester, dio);

      expect(find.text('Amigos'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('5 members'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
    });

    testWidgets('shows error state on 500 response', (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter(routeHandlers: {
        '/chat/groups': ResponseBody.fromString(
          'Server error',
          500,
          headers: {'content-type': ['text/plain']},
        ),
      });

      await tester.pumpWidget(_wrapWithLocale(dio));
      await tester.pumpAndSettle();

      expect(find.textContaining('Error'), findsOneWidget);
    });

    testWidgets('create group button exists in empty state', (tester) async {
      final dio = Dio();
      dio.options.baseUrl = 'http://test';
      dio.httpClientAdapter = _StubAdapter(routeHandlers: {
        '/chat/groups': ResponseBody.fromString(
          jsonEncode({'groups': []}),
          200,
          headers: {'content-type': ['application/json']},
        ),
      });

      final l10n = await _pumpAndL10n(tester, dio);

      expect(find.text(l10n.createGroup), findsWidgets);
      // ElevatedButton with create group text should exist
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });
}
