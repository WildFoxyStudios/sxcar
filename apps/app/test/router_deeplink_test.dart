import 'package:app/main.dart';
import 'package:app/src/auth/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('appRedirect: deep-link / unmatched-route fallback', () {
    test('unauthenticated + unknown path → /login', () {
      final result = appRedirect(
        incomingPath: '/some/unregistered/path',
        matchedLocation: '/some/unregistered/path',
        status: AuthStatus.unauthenticated,
      );
      expect(result, equals('/login'));
    });

    test('authenticated + unknown path → /cascade', () {
      final result = appRedirect(
        incomingPath: '/some/unregistered/path',
        matchedLocation: '/some/unregistered/path',
        status: AuthStatus.authenticated,
      );
      expect(result, equals('/cascade'));
    });

    test('loading + unknown path → /cascade (avoid splash deadlock)', () {
      final result = appRedirect(
        incomingPath: '/some/unregistered/path',
        matchedLocation: '/some/unregistered/path',
        status: AuthStatus.loading,
      );
      expect(result, equals('/cascade'));
    });

    test('emailUnverified + unknown path → /cascade (TBD; the auth-guard will reroute to /verify-email)', () {
      final result = appRedirect(
        incomingPath: '/some/unregistered/path',
        matchedLocation: '/some/unregistered/path',
        status: AuthStatus.emailUnverified,
      );
      // The unmatched-path check is the only one that runs for unknown
      // paths. Auth-state checks fire only after the path is known, so
      // a /verify-email bounce won't happen on the very first frame.
      // We land on /cascade as a stable default.
      expect(result, equals('/cascade'));
    });

    test('known path: unauthenticated + /login stays put', () {
      final result = appRedirect(
        incomingPath: '/login',
        matchedLocation: '/login',
        status: AuthStatus.unauthenticated,
      );
      expect(result, isNull);
    });

    test('known path: authenticated + /login → /cascade', () {
      final result = appRedirect(
        incomingPath: '/login',
        matchedLocation: '/login',
        status: AuthStatus.authenticated,
      );
      expect(result, equals('/cascade'));
    });

    test('known path: authenticated + /profile/abc123 stays put', () {
      final result = appRedirect(
        incomingPath: '/profile/abc123',
        matchedLocation: '/profile/abc123',
        status: AuthStatus.authenticated,
      );
      expect(result, isNull);
    });

    test('known path: unauthenticated + /profile/abc123 → /login', () {
      final result = appRedirect(
        incomingPath: '/profile/abc123',
        matchedLocation: '/profile/abc123',
        status: AuthStatus.unauthenticated,
      );
      expect(result, equals('/login'));
    });

    test('known path: loading + /profile/abc123 → /splash', () {
      final result = appRedirect(
        incomingPath: '/profile/abc123',
        matchedLocation: '/profile/abc123',
        status: AuthStatus.loading,
      );
      expect(result, equals('/splash'));
    });

    test('known path: emailUnverified + non-verify path → /verify-email', () {
      final result = appRedirect(
        incomingPath: '/cascade',
        matchedLocation: '/cascade',
        status: AuthStatus.emailUnverified,
      );
      expect(result, equals('/verify-email'));
    });
  });

  group('GoRouter: pump with various URLs does not throw', () {
    // Regression: previously a deep link to an unregistered path made
    // GoRouter throw "goroute /<path> doesn't exist" on first pump.
    //
    // We use a stripped-down GoRouter with placeholder builders so the
    // test doesn't need to initialize Firebase or render the real screens
    // (which would require native bindings and asset bundles). The point
    // of this test is the redirect logic — which is what the bug was
    // about — not the screen implementations.
    testWidgets('pump with various deep-link URLs does not throw',
        (tester) async {
      final urls = [
        '/',
        '/profile/123',
        '/chat/abc',
        '/vibra-typo', // completely unknown
        '/this/route/does/not/exist',
      ];
      for (final url in urls) {
        final router = _buildTestRouter(initialLocation: url);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith(() => _UnauthenticatedNotifier()),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'No exception expected for URL $url');
        router.dispose();
      }
    });
  });
}

/// Builds a tiny GoRouter that uses [appRedirect] for its redirect logic
/// but maps every path to a no-op screen. This lets the widget test pump
/// the redirect logic without pulling in Firebase or the full route
/// table (which references screens that need native bindings).
GoRouter _buildTestRouter({required String initialLocation}) {
  final noopBuilder = (BuildContext _, GoRouterState __) =>
      const Scaffold(body: SizedBox.shrink());
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) => appRedirect(
      incomingPath: state.uri.path,
      matchedLocation: state.matchedLocation,
      status: const AuthState(status: AuthStatus.unauthenticated).status,
    ),
    routes: [
      GoRoute(path: '/', builder: noopBuilder),
      GoRoute(path: '/login', builder: noopBuilder),
      GoRoute(path: '/register', builder: noopBuilder),
      GoRoute(path: '/verify-email', builder: noopBuilder),
      GoRoute(path: '/splash', builder: noopBuilder),
      GoRoute(path: '/cascade', builder: noopBuilder),
      GoRoute(path: '/interest', builder: noopBuilder),
      GoRoute(path: '/inbox', builder: noopBuilder),
      GoRoute(path: '/explore', builder: noopBuilder),
      GoRoute(path: '/you', builder: noopBuilder),
      GoRoute(path: '/edit-profile', builder: noopBuilder),
      GoRoute(path: '/settings', builder: noopBuilder),
      GoRoute(path: '/settings/phrases', builder: noopBuilder),
      GoRoute(path: '/albums', builder: noopBuilder),
      GoRoute(
        path: '/profile/:userId',
        builder: (_, state) => Scaffold(
          body: Center(child: Text('profile:${state.pathParameters['userId']}')),
        ),
      ),
    ],
  );
}

class _UnauthenticatedNotifier extends AuthNotifier {
  _UnauthenticatedNotifier() : super();
  @override
  AuthState build() => const AuthState(status: AuthStatus.unauthenticated);
  @override
  Future<void> logout() async {}
}
