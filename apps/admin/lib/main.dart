import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'src/auth/admin_auth_provider.dart';
import 'src/features/config/flags_screen.dart';
import 'src/features/config/plans_screen.dart';
import 'src/features/dashboard/dashboard_screen.dart';
import 'src/features/login/login_screen.dart';
import 'src/features/login/totp_screen.dart';
import 'src/features/moderation/reports_screen.dart';
import 'src/features/users/user_detail_screen.dart';
import 'src/features/users/user_list_screen.dart';
import 'src/theme/admin_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: AdminApp(),
    ),
  );
}

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = _createRouter(ref);

    return MaterialApp.router(
      title: 'Vibra Admin',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.build(),
      routerConfig: router,
    );
  }

  GoRouter _createRouter(WidgetRef ref) {
    return GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final authState = ref.read(authProvider);
        final isLoginRoute = state.matchedLocation == '/login' ||
            state.matchedLocation.startsWith('/totp');
        final isAuthenticated = authState.status == AuthStatus.authenticated;

        if (!isAuthenticated && !isLoginRoute) {
          return '/login';
        }
        if (isAuthenticated && isLoginRoute) {
          return '/dashboard';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/totp',
          builder: (context, state) => TotpScreen(
            mfaToken: state.extra as String,
          ),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/users',
          builder: (context, state) => const UserListScreen(),
          routes: [
            GoRoute(
              path: ':userId',
              builder: (context, state) => UserDetailScreen(
                userId: state.pathParameters['userId']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const ReportsScreen(),
        ),
        GoRoute(
          path: '/flags',
          builder: (context, state) => const FlagsScreen(),
        ),
        GoRoute(
          path: '/plans',
          builder: (context, state) => const PlansScreen(),
        ),
      ],
    );
  }
}
