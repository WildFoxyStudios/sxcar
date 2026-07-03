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

    test('authenticated + unknown path → /navegar', () {
      final result = appRedirect(
        incomingPath: '/some/unregistered/path',
        matchedLocation: '/some/unregistered/path',
        status: AuthStatus.authenticated,
      );
      expect(result, equals('/navegar'));
    });

    test('loading + unknown path → /navegar (avoid splash deadlock)', () {
      final result = appRedirect(
        incomingPath: '/some/unregistered/path',
        matchedLocation: '/some/unregistered/path',
        status: AuthStatus.loading,
      );
      expect(result, equals('/navegar'));
    });

    test(
        'emailUnverified + unknown path → /navegar (TBD; the auth-guard will reroute to /verify-email)',
        () {
      final result = appRedirect(
        incomingPath: '/some/unregistered/path',
        matchedLocation: '/some/unregistered/path',
        status: AuthStatus.emailUnverified,
      );
      // The unmatched-path check is the only one that runs for unknown
      // paths. Auth-state checks fire only after the path is known, so
      // a /verify-email bounce won't happen on the very first frame.
      // We land on /navegar as a stable default.
      expect(result, equals('/navegar'));
    });

    test('known path: unauthenticated + /login stays put', () {
      final result = appRedirect(
        incomingPath: '/login',
        matchedLocation: '/login',
        status: AuthStatus.unauthenticated,
      );
      expect(result, isNull);
    });

    test('known path: authenticated + /login → /navegar', () {
      final result = appRedirect(
        incomingPath: '/login',
        matchedLocation: '/login',
        status: AuthStatus.authenticated,
      );
      expect(result, equals('/navegar'));
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

    // Legacy redirect paths are still known, so the unmatched guard
    // doesn't fire — the auth-state check handles them instead.
    test('known legacy path /cascade: authenticated stays put (then router redirects to /navegar)',
        () {
      final result = appRedirect(
        incomingPath: '/cascade',
        matchedLocation: '/cascade',
        status: AuthStatus.authenticated,
      );
      // appRedirect doesn't know about the router-level /cascade→/navegar
      // redirect; it just passes through and GoRouter's own redirect handles it.
      expect(result, isNull);
    });

    test('known path /navegar: authenticated stays put', () {
      final result = appRedirect(
        incomingPath: '/navegar',
        matchedLocation: '/navegar',
        status: AuthStatus.authenticated,
      );
      expect(result, isNull);
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
  Widget noopBuilder(BuildContext _, GoRouterState _) =>
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
      // New shell tabs (T2)
      GoRoute(path: '/navegar', builder: noopBuilder),
      GoRoute(path: '/right-now', builder: noopBuilder),
      GoRoute(path: '/interest', builder: noopBuilder),
      GoRoute(path: '/inbox', builder: noopBuilder),
      GoRoute(path: '/tienda', builder: noopBuilder),
      // Top-level routes
      GoRoute(path: '/edit-profile', builder: noopBuilder),
      GoRoute(path: '/settings', builder: noopBuilder),
      GoRoute(path: '/albums', builder: noopBuilder),
      // Legacy redirect routes (kept as known paths)
      GoRoute(path: '/cascade', redirect: (_, _) => '/navegar'),
      GoRoute(path: '/you', redirect: (_, _) => '/navegar'),
      GoRoute(path: '/explore', redirect: (_, _) => '/right-now'),
      GoRoute(
        path: '/profile/:userId',
        builder: (_, state) => Scaffold(
          body:
              Center(child: Text('profile:${state.pathParameters['userId']}')),
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
