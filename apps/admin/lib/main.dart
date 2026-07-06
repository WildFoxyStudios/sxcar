import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'src/auth/admin_auth_provider.dart';
import 'src/features/audit/audit_screen.dart';
import 'src/features/config/abuse_rules_screen.dart';
import 'src/features/config/countries_screen.dart';
import 'src/features/config/flags_screen.dart';
import 'src/features/config/plans_screen.dart';
import 'src/features/content/cms_screen.dart';
import 'src/features/content/legal_docs_screen.dart';
import 'src/features/content/templates_screen.dart';
import 'src/features/content/translations_screen.dart';
import 'src/features/dashboard/dashboard_screen.dart';
import 'src/features/gdpr/data_requests_screen.dart';
import 'src/features/growth/campaigns_screen.dart';
import 'src/features/growth/experiments_screen.dart';
import 'src/features/login/login_screen.dart';
import 'src/features/login/totp_screen.dart';
import 'src/features/moderation/csam_screen.dart';
import 'src/features/moderation/reports_screen.dart';
import 'src/features/settings/api_keys_screen.dart';
import 'src/features/settings/webhooks_screen.dart';
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
        GoRoute(
          path: '/admin/gdpr',
          builder: (context, state) => const DataRequestsScreen(),
        ),
        GoRoute(
          path: '/admin/csam',
          builder: (context, state) => const CsamsScreen(),
        ),
        GoRoute(
          path: '/admin/audit',
          builder: (context, state) => const AuditScreen(),
        ),
        GoRoute(
          path: '/admin/countries',
          builder: (context, state) => const CountriesScreen(),
        ),
        GoRoute(
          path: '/admin/experiments',
          builder: (context, state) => const ExperimentsScreen(),
        ),
        GoRoute(
          path: '/admin/translations',
          builder: (context, state) => const TranslationsScreen(),
        ),
        GoRoute(
          path: '/admin/cms',
          builder: (context, state) => const CmsScreen(),
        ),
        GoRoute(
          path: '/admin/legal-docs',
          builder: (context, state) => const LegalDocsScreen(),
        ),
        GoRoute(
          path: '/admin/campaigns',
          builder: (context, state) => const CampaignsScreen(),
        ),
        GoRoute(
          path: '/admin/templates',
          builder: (context, state) => const TemplatesScreen(),
        ),
        GoRoute(
          path: '/admin/abuse',
          builder: (context, state) => const AbuseRulesScreen(),
        ),
        GoRoute(
          path: '/admin/api-keys',
          builder: (context, state) => const ApiKeysScreen(),
        ),
        GoRoute(
          path: '/admin/webhooks',
          builder: (context, state) => const WebhooksScreen(),
        ),
      ],
    );
  }
}
