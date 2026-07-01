import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'firebase_options.dart';
import 'src/rust/frb_generated.dart';
import 'src/auth/auth_provider.dart';
import 'src/chat/unread_count_provider.dart';
import 'src/presence/presence_service.dart';
import 'src/features/album_detail_screen.dart';
import 'src/features/albums_screen.dart';
import 'src/features/cascade_screen.dart';
import 'src/features/chat_list_screen.dart';
import 'src/features/chat_screen.dart';
import 'src/features/explore_screen.dart';
import 'src/features/interest_screen.dart';
import 'src/features/login_screen.dart';
import 'src/features/profile_detail_screen.dart';
import 'src/features/register_screen.dart';
import 'src/features/verify_email_screen.dart';
import 'src/features/you_screen.dart';
import 'src/features/edit_profile_screen.dart';
import 'src/features/settings_screen.dart';
import 'src/phrases/phrases_screen.dart';
import 'src/sessions/sessions_screen.dart';

const Color grindrYellow = Color(0xFFF4C542);

/// Top-level paths that are valid in the route table. Used by the redirect
/// callback to detect unregistered paths arriving from a deep link
/// (e.g. `vibra://profile/abc123` or `https://api.turnend.win/profile/abc123`)
/// and bounce them to a safe fallback. If we don't, GoRouter throws
/// `goroute /<unmatched> doesn't exist` before any screen can render.
const Set<String> _knownTopLevelPaths = {
  '/splash',
  '/login',
  '/register',
  '/verify-email',
  '/profile',
  '/cascade',
  '/interest',
  '/inbox',
  '/explore',
  '/you',
  '/edit-profile',
  '/settings',
  '/settings/phrases',
  '/settings/sessions',
  '/albums',
};

/// Returns the top-level path segment for a URI (e.g. `/profile/abc123` -> `/profile`).
String _topLevelPath(String fullPath) {
  final segments = fullPath.split('/');
  if (segments.length < 2) return fullPath;
  return '/${segments[1]}';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await RustLib.init();
  runApp(const ProviderScope(child: VibraApp()));
}

/// Top-level redirect logic. Extracted as a function so widget tests can
/// call it directly with arbitrary incoming paths to assert fallback
/// behaviour without spinning up a full GoRouter.
String? appRedirect({
  required String incomingPath,
  required String matchedLocation,
  required AuthStatus status,
}) {
  // Deep-link / unmatched route guard. GoRouter runs the redirect
  // BEFORE the route table is matched. If the incoming URL does not
  // correspond to any registered top-level path (e.g. an old deep
  // link, a typo, or a route we removed), fall back to a safe page
  // rather than letting GoRouter throw "goroute /... doesn't exist".
  if (!_knownTopLevelPaths.contains(_topLevelPath(incomingPath))) {
    if (status == AuthStatus.unauthenticated) {
      return '/login';
    }
    // Loading or authenticated: land on the home tab. The auth-state
    // checks below will further redirect if appropriate.
    return '/cascade';
  }

  final isAuthRoute = matchedLocation == '/login' ||
      matchedLocation == '/register';
  final isVerifyRoute = matchedLocation == '/verify-email';
  final isSplash = matchedLocation == '/splash';

  // While checking stored tokens, show splash — don't redirect to login yet
  if (status == AuthStatus.loading) {
    return isSplash ? null : '/splash';
  }

  if (status == AuthStatus.unauthenticated && !isAuthRoute) {
    return '/login';
  }

  if (status == AuthStatus.authenticated && (isAuthRoute || isSplash)) {
    return '/cascade';
  }

  if (status == AuthStatus.emailUnverified && !isVerifyRoute) {
    return '/verify-email';
  }

  return null;
}

/// The application's GoRouter. Exposed (non-private) so widget tests can
/// pump it with arbitrary initial locations and assert deep-link / route
/// fallback behaviour.
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  redirect: (context, state) {
    final authState =
        ProviderScope.containerOf(context).read(authStateProvider);
    return appRedirect(
      incomingPath: state.uri.path,
      matchedLocation: state.matchedLocation,
      status: authState.status,
    );
  },
  routes: [
    // Splash — shown while checking stored tokens
    GoRoute(
      path: '/splash',
      builder: (_, _) => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('V', style: TextStyle(color: grindrYellow, fontSize: 48, fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              CircularProgressIndicator(color: grindrYellow),
            ],
          ),
        ),
      ),
    ),
    // Auth routes
    GoRoute(
      path: '/login',
      builder: (_, _) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (_, _) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/verify-email',
      builder: (_, _) => const VerifyEmailScreen(),
    ),
    // Full-screen profile detail (no bottom nav)
    GoRoute(
      path: '/profile/:userId',
      builder: (_, state) => ProfileDetailScreen(
        userId: state.pathParameters['userId']!,
      ),
    ),
    // Main shell with 5-tab bottom navigation
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        // Tab 0: Cascade (home)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/cascade',
              builder: (_, _) => const CascadeScreen(),
            ),
          ],
        ),
        // Tab 1: Interest (taps + favorites)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/interest',
              builder: (_, _) => const InterestScreen(),
            ),
          ],
        ),
        // Tab 2: Chat (inbox + conversation)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/inbox',
              builder: (_, _) => const ChatListScreen(),
              routes: [
                GoRoute(
                  path: ':conversationId',
                  builder: (_, state) => ChatScreen(
                    conversationId:
                        state.pathParameters['conversationId']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        // Tab 3: Explore (global grid)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/explore',
              builder: (_, _) => const ExploreScreen(),
            ),
          ],
        ),
        // Tab 4: You (profile + settings)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/you',
              builder: (_, _) => const YouScreen(),
            ),
            GoRoute(
              path: '/edit-profile',
              builder: (_, _) => const EditProfileScreen(),
            ),
            GoRoute(
              path: '/settings',
              builder: (_, state) => SettingsScreen(
                initialTab:
                    state.uri.queryParameters['tab'] ?? 'notifications',
              ),
            ),
            GoRoute(
              path: '/settings/phrases',
              builder: (_, _) => const PhrasesScreen(),
            ),
            GoRoute(
              path: '/settings/sessions',
              builder: (_, _) => const SessionsScreen(),
            ),
            GoRoute(
              path: '/albums',
              builder: (_, _) => const AlbumsScreen(),
              routes: [
                GoRoute(
                  path: ':albumId',
                  builder: (_, state) => AlbumDetailScreen(
                    albumId: state.pathParameters['albumId']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Shell widget that provides the Grindr-style bottom navigation bar.
class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadAsync = ref.watch(unreadCountProvider);
    final unreadCount = unreadAsync.maybeWhen(
      data: (n) => n,
      orElse: () => 0,
    );

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        backgroundColor: const Color(0xFF0D0D0D),
        selectedItemColor: grindrYellow,
        unselectedItemColor: const Color(0xFF777777),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Cascade',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            label: 'Interest',
          ),
          BottomNavigationBarItem(
            icon: _ChatTabIcon(
              unreadCount: unreadCount,
              isSelected: navigationShell.currentIndex == 2,
            ),
            label: 'Chat',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            label: 'Explore',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'You',
          ),
        ],
      ),
    );
  }
}

/// Chat tab icon — wraps the standard chat icon in a [Badge] when there
/// are unread messages. Hidden when count == 0.
class _ChatTabIcon extends StatelessWidget {
  final int unreadCount;
  final bool isSelected;

  const _ChatTabIcon({required this.unreadCount, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      isSelected ? Icons.chat_bubble : Icons.chat_bubble_outline,
    );
    if (unreadCount <= 0) return icon;

    return Badge(
      label: Text(
        unreadCount > 99 ? '99+' : '$unreadCount',
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
      backgroundColor: Colors.red,
      child: icon,
    );
  }
}

class VibraApp extends ConsumerStatefulWidget {
  const VibraApp({super.key});

  @override
  ConsumerState<VibraApp> createState() => _VibraAppState();
}

class _VibraAppState extends ConsumerState<VibraApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(authStateProvider.notifier).checkAuth();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Send a heartbeat each time the app returns to the foreground so the
    // backend keeps our last_seen fresh. Only do this when authenticated —
    // guest sessions have no user id to attribute the heartbeat to.
    if (state == AppLifecycleState.resumed &&
        ref.read(authStateProvider).status == AuthStatus.authenticated) {
      // Read the provider so the side-effect (POST) actually runs.
      ref.read(heartbeatProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (prev?.status != next.status) {
        appRouter.refresh();
      }
    });

    return MaterialApp.router(
      title: 'Vibra',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: const ColorScheme.dark(
          primary: grindrYellow,
          secondary: grindrYellow,
          surface: Color(0xFF1A1A1A),
          onPrimary: Colors.black,
          onSecondary: Colors.black,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF0D0D0D),
          selectedItemColor: grindrYellow,
          unselectedItemColor: Color(0xFF777777),
          type: BottomNavigationBarType.fixed,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D0D0D),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A1A),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
