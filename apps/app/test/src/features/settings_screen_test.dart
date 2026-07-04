import 'dart:convert';
import 'dart:typed_data';

import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/settings_screen.dart';
import 'package:app/src/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mock HTTP adapter — returns canned notif preferences so the screen loads.
// ─────────────────────────────────────────────────────────────────────────────

class _MockAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    final method = options.method.toUpperCase();

    if (method == 'GET' && path == '/notifications/preferences') {
      return ResponseBody.fromString(
        jsonEncode({
          'new_messages': false,
          'new_taps': false,
          'promotions': false,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // PUT /notifications/preferences — accept everything
    if (method == 'PUT' && path == '/notifications/preferences') {
      return ResponseBody.fromString(
        jsonEncode({'ok': true}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // Default: 200 OK
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth notifier stub — keeps the auth state out of the picture.
// ─────────────────────────────────────────────────────────────────────────────

class _AuthNotifierStub extends AuthNotifier {
  _AuthNotifierStub();

  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test-token',
        email: 'test@example.com',
      );

  @override
  Future<void> logout() async {}
}

// ─────────────────────────────────────────────────────────────────────────────
// Test harness — wraps SettingsScreen in a GoRouter with real Navigator
// so context.push() actually navigates. Provider overrides are applied at
// the ProviderScope layer so the auth/dio providers are stable.
// ─────────────────────────────────────────────────────────────────────────────

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, state) => SettingsScreen(
          initialTab: state.uri.queryParameters['tab'],
        ),
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (_, _) => const Scaffold(body: Text('EditProfile')),
      ),
      GoRoute(
        path: '/albums',
        builder: (_, _) => const Scaffold(body: Text('Albums')),
      ),
      GoRoute(
        path: '/settings/phrases',
        builder: (_, _) => const Scaffold(body: Text('Phrases')),
      ),
      GoRoute(
        path: '/settings/sessions',
        builder: (_, _) => const Scaffold(body: Text('Sessions')),
      ),
      GoRoute(
        path: '/settings/discreet-icon',
        builder: (_, _) => const Scaffold(body: Text('DiscreetIcon')),
      ),
      GoRoute(
        path: '/settings/pin',
        builder: (_, _) => const Scaffold(body: Text('Pin')),
      ),
      GoRoute(
        path: '/settings/blocks',
        builder: (_, _) => const Scaffold(body: Text('Blocks')),
      ),
    ],
  );
}

Widget _wrap(GoRouter router, Dio dio) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(_AuthNotifierStub.new),
      dioProvider.overrideWithValue(dio),
    ],
    child: MaterialApp.router(
      theme: VibraTheme.dark(),
      routerConfig: router,
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsScreen (redesigned ListView)', () {
    late Dio dio;
    late GoRouter router;

    setUp(() {
      dio = Dio()..httpClientAdapter = _MockAdapter();
      router = _buildRouter();
    });

    tearDown(() {
      router.dispose();
    });

    /// The redesigned settings screen has a long ListView. Increase the test
    /// surface so off-screen widgets (e.g. SISTEMA DE UNIDADES, NOTIFICACIONES)
    /// are still in the rendered tree.
    Future<void> _setBigSurface(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
    }

    // ── Test 1: all 7 section headers render ─────────────────────────────
    testWidgets('renders all 7 section headers', (tester) async {
      await _setBigSurface(tester);
      await tester.pumpWidget(_wrap(router, dio));
      await tester.pumpAndSettle();

      // Each section header is rendered as uppercased text via _sectionHeader().
      expect(find.text('CUENTA'), findsOneWidget);
      expect(find.text('MULTIMEDIA'), findsOneWidget);
      expect(find.text('PREFERENCIAS DE PANTALLA'), findsOneWidget);
      expect(find.text('CENTRO DE SEGURIDAD'), findsOneWidget);
      expect(find.text('SISTEMA DE UNIDADES'), findsOneWidget);
      expect(find.text('ESTADO DE VISITANTE'), findsOneWidget);
      expect(find.text('NOTIFICACIONES Y SESIONES'), findsOneWidget);
    });

    // ── Test 2: units Segmented3 toggles unitsProvider ───────────────────
    testWidgets('units Segmented3 toggles unitsProvider', (tester) async {
      await _setBigSurface(tester);
      await tester.pumpWidget(_wrap(router, dio));
      await tester.pumpAndSettle();

      // Both options rendered.
      expect(find.text('Métrico'), findsOneWidget);
      expect(find.text('Imperial'), findsOneWidget);

      // Tap Imperial → unitsProvider becomes 1.
      await tester.tap(find.text('Imperial'));
      await tester.pumpAndSettle();

      // Verify the value persisted via SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('settings_units'), 1);
    });

    // ── Test 3: visitor status Segmented3 toggles visitorStatusProvider ──
    testWidgets('visitor status Segmented3 toggles visitorStatusProvider',
        (tester) async {
      await _setBigSurface(tester);
      await tester.pumpWidget(_wrap(router, dio));
      await tester.pumpAndSettle();

      // Three options rendered (note "Desactivada" appears elsewhere as a
      // subtitle, so we just check Activado + Automático are present).
      expect(find.text('Activado'), findsWidgets);
      expect(find.text('Automático'), findsOneWidget);

      // Tap "Activado" (index 1). Use last() to prefer the Segmented3 option
      // over any other matches.
      await tester.tap(find.text('Activado').last);
      await tester.pumpAndSettle();

      final prefs1 = await SharedPreferences.getInstance();
      expect(prefs1.getInt('settings_visitor_status'), 1);

      // Tap "Automático" (index 2).
      await tester.tap(find.text('Automático'));
      await tester.pumpAndSettle();

      final prefs2 = await SharedPreferences.getInstance();
      expect(prefs2.getInt('settings_visitor_status'), 2);
    });

    // ── Test 4: tap "Desbloquear usuarios" navigates to /settings/blocks ─
    testWidgets('Desbloquear usuarios row navigates to /settings/blocks',
        (tester) async {
      await _setBigSurface(tester);
      await tester.pumpWidget(_wrap(router, dio));
      await tester.pumpAndSettle();

      // Find the InkWell ancestor of the row title and tap it directly.
      final inkWell = find.ancestor(
        of: find.text('Desbloquear usuarios'),
        matching: find.byType(InkWell),
      );
      expect(inkWell, findsOneWidget);
      await tester.tap(inkWell, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Destination screen rendered (proves the navigation occurred).
      expect(find.text('Blocks'), findsOneWidget);
    });

    // ── Test 5: tap "Icono de aplicación discreto" navigates ─────────────
    testWidgets('Icono de aplicación discreto navigates to /settings/discreet-icon',
        (tester) async {
      await _setBigSurface(tester);
      await tester.pumpWidget(_wrap(router, dio));
      await tester.pumpAndSettle();

      final inkWell = find.ancestor(
        of: find.text('Icono de aplicación discreto'),
        matching: find.byType(InkWell),
      );
      await tester.tap(inkWell, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('DiscreetIcon'), findsOneWidget);
    });

    // ── Test 6: tap "Frases guardadas" navigates ────────────────────────
    testWidgets('Frases guardadas row navigates to /settings/phrases',
        (tester) async {
      await _setBigSurface(tester);
      await tester.pumpWidget(_wrap(router, dio));
      await tester.pumpAndSettle();

      final inkWell = find.ancestor(
        of: find.text('Frases guardadas'),
        matching: find.byType(InkWell),
      );
      await tester.tap(inkWell, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Phrases'), findsOneWidget);
    });
  });
}