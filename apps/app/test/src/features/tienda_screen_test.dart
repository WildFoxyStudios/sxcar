import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/tienda_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/l10n/gen/app_localizations.dart';

/// Fake Dio adapter that returns canned billing responses.
class _BillingAdapter implements HttpClientAdapter {
  _BillingAdapter();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    if (path == '/billing/plans') {
      return _ok({
        'plans': [
          {
            'code': 'vibra_plus',
            'name': 'Vibra+',
            'tier': 1,
            'description': 'Premium tier',
            'active': true,
            'features': ['unlimited_chats', 'no_ads'],
            'prices': [
              {
                'id': 'price-monthly',
                'country_code': 'XX',
                'currency': 'EUR',
                'period': 'monthly',
                'amount_minor': 899,
              },
              {
                'id': 'price-yearly',
                'country_code': 'XX',
                'currency': 'EUR',
                'period': 'yearly',
                'amount_minor': 4999,
              },
            ],
          },
          {
            'code': 'unlimited',
            'name': 'Unlimited',
            'tier': 2,
            'description': 'Top tier',
            'active': true,
            'features': ['unlimited_chats', 'no_ads', 'incognito_mode'],
            'prices': [
              {
                'id': 'price-u-monthly',
                'country_code': 'XX',
                'currency': 'EUR',
                'period': 'monthly',
                'amount_minor': 1999,
              },
            ],
          },
        ],
      });
    }
    if (path == '/billing/me') {
      return _ok({'subscription': null});
    }
    return _ok({}, status: 404);
  }

  ResponseBody _ok(Object body, {int status = 200}) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
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
        accessToken: 'test',
        email: 'u@test.com',
      );

  @override
  Future<void> logout() async {}
}

Widget _wrap(Widget child, {required Dio dio}) {
  return ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      authStateProvider.overrideWith(_AuthenticatedNotifier.new),
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
      home: child,
    ),
  );
}

void main() {
  testWidgets('renders plans after load', (tester) async {
    final dio = Dio()..httpClientAdapter = _BillingAdapter();
    await tester.pumpWidget(_wrap(const TiendaScreen(), dio: dio));
    await tester.pumpAndSettle();
    expect(find.text('Elija la actualización'), findsOneWidget);
    expect(find.text('Vibra+'), findsWidgets);
    expect(find.text('Unlimited'), findsWidgets);
  });

  testWidgets('shows duration cards', (tester) async {
    final dio = Dio()..httpClientAdapter = _BillingAdapter();
    await tester.pumpWidget(_wrap(const TiendaScreen(), dio: dio));
    await tester.pumpAndSettle();
    expect(find.text('€8.99'), findsOneWidget);
    expect(find.text('€49.99'), findsOneWidget);
  });

  testWidgets('Continue button visible', (tester) async {
    final dio = Dio()..httpClientAdapter = _BillingAdapter();
    await tester.pumpWidget(_wrap(const TiendaScreen(), dio: dio));
    await tester.pumpAndSettle();
    expect(find.text('Continuar'), findsOneWidget);
  });
}