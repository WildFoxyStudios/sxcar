import 'dart:async';
import 'dart:convert';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/blocks_list_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/l10n/gen/app_localizations.dart';

class _StubAdapter implements HttpClientAdapter {
  final List<ResponseBody Function(RequestOptions)> handlers;
  _StubAdapter({this.handlers = const []});
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (handlers.isNotEmpty) return handlers.removeAt(0)(options);
    return ResponseBody.fromString('{"blocks":[]}', 200,
        headers: {'content-type': ['application/json']});
  }
}

class _AuthNotifier extends AuthNotifier {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test',
        email: 'u@test.com',
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
        home: const BlocksListScreen(),
      ),
    );

void main() {
  testWidgets('BlocksListScreen shows empty state when no blocks', (tester) async {
    final dio = Dio();
    dio.options.baseUrl = 'http://test';
    dio.httpClientAdapter = _StubAdapter();
    await tester.pumpWidget(_wrap(dio));
    await tester.pumpAndSettle();
    expect(find.text('No hay usuarios bloqueados'), findsOneWidget);
  });

  testWidgets('BlocksListScreen renders populated list', (tester) async {
    final dio = Dio();
    dio.options.baseUrl = 'http://test';
    dio.httpClientAdapter = _StubAdapter(handlers: [
      (_) => ResponseBody.fromString(
          jsonEncode({
            'blocks': [
              {'user_id': 'u1', 'display_name': 'Alex'},
              {'user_id': 'u2', 'display_name': 'Sam'},
            ],
          }),
          200,
          headers: {'content-type': ['application/json']}),
    ]);
    await tester.pumpWidget(_wrap(dio));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
  });
}