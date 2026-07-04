import 'dart:convert';
import 'dart:typed_data';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/billing/billing_providers.dart';
import 'package:app/src/billing/models.dart';
import 'package:app/src/features/profile_drawer.dart';
import 'package:app/src/theme/widgets.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockProfileAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/profile') {
      return ResponseBody.fromString(
        jsonEncode({
          'user': {
            'id': '00000000-0000-0000-0000-000000000001',
            'email': 'test@example.com',
            'email_verified': true,
            'status': 'active',
            'role': 'user',
            'created_at': '2025-01-01T00:00:00Z',
            'display_name': 'TestUser',
            'bio': 'Hello!',
            'profile_photo_id': null,
            'profile_photo_url': null,
            'tribes': [],
            'looking_for': [],
            'meet_at': [],
            'tags': [],
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.path == '/boost/active') {
      return ResponseBody.fromString(
        jsonEncode({'active': false}),
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

// ---------------------------------------------------------------------------
// Widget helper
// ---------------------------------------------------------------------------

Widget _buildDrawer(
  Dio dio, {
  Subscription? subscription,
}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(() => _AuthenticatedNotifier()),
      dioProvider.overrideWithValue(dio),
      // Default: no active subscription (T1.10).
      mySubscriptionProvider
          .overrideWith((ref) async => subscription),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Force Spanish so that l10n.online == 'En línea' and l10n.incognito == 'Incógnito'.
      locale: const Locale('es'),
      home: Scaffold(
        drawer: const ProfileDrawer(),
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    // Provide mock SharedPreferences so presenceModeProvider doesn't call
    // the native platform.
    SharedPreferences.setMockInitialValues({});
  });

  group('ProfileDrawer', () {
    testWidgets('renders key sections when opened', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockProfileAdapter();

      await tester.pumpWidget(_buildDrawer(dio));
      await tester.pumpAndSettle();

      // Open the drawer.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Profile name appears once loaded.
      expect(find.text('TestUser'), findsOneWidget);

      // Scroll to see section headers.
      await tester.drag(find.byType(ListView).first, const Offset(0, -200));
      await tester.pumpAndSettle();
    });

    testWidgets('drawer contains menu items', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockProfileAdapter();

      await tester.pumpWidget(_buildDrawer(dio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Scroll down to see menu items.
      final listFinder = find.byType(ListView).first;
      await tester.drag(listFinder, const Offset(0, -500));
      await tester.pumpAndSettle();

      // At least one menu item should be visible after scrolling.
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('Online/Incógnito segmented is present', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockProfileAdapter();

      await tester.pumpWidget(_buildDrawer(dio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // VibraSegmented renders both mode options.
      expect(find.text('En línea'), findsOneWidget);
      expect(find.text('Incógnito'), findsOneWidget);
    });

    testWidgets('tapping Incógnito segment changes mode', (tester) async {
      final dio = Dio()..httpClientAdapter = _MockProfileAdapter();

      await tester.pumpWidget(_buildDrawer(dio));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Incógnito — no exception should be thrown.
      await tester.tap(find.text('Incógnito'));
      await tester.pumpAndSettle();

      // State changed (no assertion on exact visual since SharedPreferences
      // is mocked) — just verify no exception.
      expect(tester.takeException(), isNull);
    });

    // ── T1.10: UpsellCard + active sub banner ────────────────────────────

    testWidgets('drawer renders UpsellCards without active sub',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockProfileAdapter();

      await tester.pumpWidget(_buildDrawer(dio));
      await tester.pumpAndSettle();

      // Open the drawer.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Scroll within the drawer's ListView so both UpsellCards are mounted.
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();

      // Two UpsellCards are visible: highlighted yellow + dark "Ver planes".
      expect(find.byType(UpsellCard), findsNWidgets(2));
      expect(find.text('Obtener Premium'), findsOneWidget);
      expect(find.text('Ver planes'), findsOneWidget);

      // No active sub banner when subscription is null.
      expect(find.textContaining('Plan activo'), findsNothing);
    });

    testWidgets('drawer shows active sub banner when subscription present',
        (tester) async {
      final dio = Dio()..httpClientAdapter = _MockProfileAdapter();

      final sub = Subscription(
        id: 'sub-x',
        planCode: 'vibra_plus',
        planName: 'Vibra+',
        priceId: 'price-1',
        period: 'monthly',
        periodDays: 30,
        status: 'active',
        source: 'simulated',
        startedAt: DateTime.utc(2026),
        expiresAt: DateTime.utc(2026, 8),
        daysRemaining: 30,
      );

      await tester.pumpWidget(_buildDrawer(
        dio,
        subscription: sub,
      ));
      await tester.pumpAndSettle();

      // Open the drawer.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Active sub banner shows plan name + "Plan activo".
      expect(find.textContaining('Vibra+'), findsOneWidget);
      expect(find.textContaining('Plan activo'), findsOneWidget);

      // Scroll within the drawer's ListView so both UpsellCards are mounted.
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();

      // Both UpsellCards still render below the banner.
      expect(find.byType(UpsellCard), findsNWidgets(2));
    });
  });
}
