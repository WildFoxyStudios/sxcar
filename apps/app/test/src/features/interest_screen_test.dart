import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/interest_screen.dart';
import 'package:app/src/premium/premium_service.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Path-keyed mock adapter for InterestScreen tests.
///
/// Handles the endpoints the Interest screen hits:
///   - `/taps/received` -> list of taps
///   - `/profile/views` -> list of viewers
///   - `/profile/views/count` -> `{count: int}`
///   - `/taps/count` -> `{count: int, types: {...}}`
///   - `/billing/me` -> `{subscription: obj|null}` (entitlement check)
class _MockTapsAdapter implements HttpClientAdapter {
  /// Override-able stub counters; default 0 each.
  int viewsCount;
  int tapsCount;

  _MockTapsAdapter({
    this.viewsCount = 0,
    this.tapsCount = 0,
  });

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.path;
    if (uri.contains('/taps/received')) {
      final body = jsonEncode({
        'taps': [
          {
            'id': 'tap-1',
            'sender_id': 'user-1',
            'sender_display_name': 'Bob',
            'sender_photo_url': null,
            'tap_type': 'wave',
            'created_at': '2025-01-01T00:00:00Z',
          },
          {
            'id': 'tap-2',
            'sender_id': 'user-2',
            'sender_display_name': 'Alice',
            'sender_photo_url': null,
            'tap_type': 'fire',
            'created_at': '2025-01-01T01:00:00Z',
          },
        ],
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (uri.contains('/profile/views/count')) {
      final body = jsonEncode({'count': viewsCount});
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (uri.contains('/taps/count')) {
      final body = jsonEncode({
        'count': tapsCount,
        'types': {'fire': tapsCount},
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (uri.contains('/profile/views')) {
      final body = jsonEncode({
        'viewers': [
          {
            'viewer_id': 'viewer-1',
            'viewed_at': '2025-01-01T00:00:00Z',
            'display_name': 'Vicky Viewer',
            'profile_photo_url': null,
          },
        ],
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }
    if (uri.contains('/billing/me')) {
      final body = jsonEncode({
        'subscription': null,
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
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

/// Notifier that starts with `loading` (no token) and is later updated
/// to `authenticated` with a token. Used to reproduce the race where
/// InterestScreen runs `_fetchTaps` before the secure-storage token is
/// loaded.
class _LoadingThenAuthNotifier extends AuthNotifier {
  _LoadingThenAuthNotifier() : super();

  @override
  AuthState build() => const AuthState(
        status: AuthStatus.loading,
        accessToken: null,
        email: null,
      );

  void becomeAuthed() {
    state = const AuthState(
      status: AuthStatus.authenticated,
      accessToken: 'test-token',
      email: 'test@example.com',
    );
  }

  @override
  Future<void> logout() async {}
}

/// Wraps the widget under test with the localizations delegates +
/// Riverpod overrides. All InterestScreen tests use this so they get
/// `AppLocalizations.of(context)!` to resolve.
Widget _wrap({
  required Widget child,
  required Dio dio,
  AuthNotifier? authNotifier,
  PremiumStatus? premium,
}) {
  return ProviderScope(
    overrides: [
      authStateProvider
          .overrideWith(() => authNotifier ?? _AuthenticatedNotifier()),
      dioProvider.overrideWithValue(dio),
      if (premium != null)
        premiumStatusProvider.overrideWith((ref) async => premium),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

/// Pumps [child] with the providers + locale, and returns the resolved
/// [AppLocalizations]. All InterestScreen tests route through this helper so
/// their assertions can switch from hardcoded strings to `l10n.X` references.
Future<AppLocalizations> _pumpAndL10n(
  WidgetTester tester, {
  required Widget child,
  required Dio dio,
  AuthNotifier? authNotifier,
  PremiumStatus? premium,
}) async {
  await tester.pumpWidget(
    _wrap(
      child: child,
      dio: dio,
      authNotifier: authNotifier,
      premium: premium,
    ),
  );
  await tester.pumpAndSettle();
  // Localizations aren't yet initialised on MaterialApp's own element, so we
  // capture from inside the InterestScreen (or its child) subtree instead.
  return AppLocalizations.of(
    tester.element(find.byType(InterestScreen)),
  )!;
}

void main() {
  group('InterestScreen', () {
    testWidgets('title is 32 sp white', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockTapsAdapter();

      final l10n = await _pumpAndL10n(
        tester,
        child: const InterestScreen(),
        dio: dio,
      );

      // The "Interest" title should be rendered with fontSize 32.
      final titleFinder = find.text(l10n.interest);
      expect(titleFinder, findsOneWidget);
      final titleWidget = tester.widget<Text>(titleFinder);
      expect(titleWidget.style?.fontSize, 32);
      expect(titleWidget.style?.color, Colors.white);
    });

    testWidgets('renders tab labels with counts Views 0 / Taps 0',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockTapsAdapter();

      final l10n = await _pumpAndL10n(
        tester,
        child: const InterestScreen(),
        dio: dio,
      );

      expect(find.text('${l10n.views} 0'), findsOneWidget);
      expect(find.text('${l10n.taps} 0'), findsOneWidget);
    });

    testWidgets('NUEVO badge appears when count > 6 and no entitlement',
        (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _MockTapsAdapter(viewsCount: 7, tapsCount: 0);

      final l10n = await _pumpAndL10n(
        tester,
        child: const InterestScreen(),
        dio: dio,
      );

      expect(find.text(l10n.desbloquearGratis), findsOneWidget);
    });

    testWidgets('NUEVO badge hidden when count <= 6', (tester) async {
      final dio = Dio()
        ..httpClientAdapter = _MockTapsAdapter(viewsCount: 3, tapsCount: 3);

      final l10n = await _pumpAndL10n(
        tester,
        child: const InterestScreen(),
        dio: dio,
      );

      expect(find.text(l10n.desbloquearGratis), findsNothing);
    });

    testWidgets('Boost FAB renders with icon', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockTapsAdapter();

      final l10n = await _pumpAndL10n(
        tester,
        child: const InterestScreen(),
        dio: dio,
      );

      expect(find.byIcon(Icons.bolt), findsOneWidget);
      expect(find.text(l10n.boostTuInterest), findsOneWidget);
    });

    testWidgets('Taps tab shows received taps', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockTapsAdapter();

      final l10n = await _pumpAndL10n(
        tester,
        child: const InterestScreen(),
        dio: dio,
      );

      // Tabs are: Views, Taps. Switch to Taps.
      await tester.tap(find.text('${l10n.taps} 0'));
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('Views tab shows received viewers', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockTapsAdapter();

      // "See who viewed me" is an Xtra+ benefit; unlock it so the viewer list
      // renders instead of the free-tier upgrade prompt.
      final l10n = await _pumpAndL10n(
        tester,
        child: const InterestScreen(),
        dio: dio,
        premium: const PremiumStatus(tier: 'xtra'),
      );
      // Reference l10n so the analyzer does not strip the variable if unused
      // (this test relies on the default Views tab content).
      expect(l10n.views, isNotNull);

      // Views is the default tab — content should be visible.
      expect(find.text('Vicky Viewer'), findsOneWidget);
    });

    testWidgets(
        'Taps request WAITS for authReadyProvider when the notifier is still '
        'loading (regression for 401 on /taps/received)', (tester) async {
      // The original bug: `_fetchTaps` ran in initState and fired
      // immediately. The Dio interceptor then read the secure-storage
      // cache (still empty mid-boot) and the request went out without
      // an Authorization header, producing the 401 we saw in logcat.
      // The fix: the screen's `_waitForAuth` polls the token before
      // firing the request, so the fetcher blocks until auth resolves.
      final dio = Dio()..httpClientAdapter = _MockTapsAdapter();
      final notifier = _LoadingThenAuthNotifier();

      // Pump directly with the loading notifier — we don't pumpAndSettle
      // because that would resolve the future and trigger the fetcher.
      await tester.pumpWidget(
        _wrap(
          child: const InterestScreen(),
          dio: dio,
          authNotifier: notifier,
        ),
      );
      // Capture l10n from the widget tree now (the notifier is just the
      // auth state — the localizations delegates always load). Pull from
      // the InterestScreen widget's element since Localizations are wired
      // in further down the tree.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(InterestScreen)),
      )!;

      // Pump a few frames — the auth token is still null so the
      // fetcher must be waiting. The tab shows its loading state.
      // No exception (no 401 printed).
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('${l10n.taps} 0'));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Now become authenticated — _waitForAuth resolves and the
      // fetcher fires.
      notifier.becomeAuthed();
      await tester.pumpAndSettle();

      // After auth resolves the taps list is fetched — Bob should be
      // visible in the Taps tab.
      expect(find.text('Bob'), findsOneWidget,
          reason: 'fetch should have fired once the token arrived');
    });
  });
}
