import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'firebase_options.dart';
import 'src/rust/frb_generated.dart';
import 'src/auth/auth_provider.dart';
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

const Color grindrYellow = Color(0xFFF4C542);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await RustLib.init();
  runApp(const ProviderScope(child: VibraApp()));
}

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final authState =
        ProviderScope.containerOf(context).read(authStateProvider);

    final isAuthRoute = state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';
    final isVerifyRoute = state.matchedLocation == '/verify-email';

    if (authState.status == AuthStatus.loading) return null;

    if (authState.status == AuthStatus.unauthenticated && !isAuthRoute) {
      return '/login';
    }

    if (authState.status == AuthStatus.authenticated && isAuthRoute) {
      return '/cascade';
    }

    if (authState.status == AuthStatus.emailUnverified && !isVerifyRoute) {
      return '/verify-email';
    }

    return null;
  },
  routes: [
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
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        backgroundColor: const Color(0xFF0D0D0D),
        selectedItemColor: grindrYellow,
        unselectedItemColor: const Color(0xFF777777),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Cascade',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            label: 'Interest',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'You',
          ),
        ],
      ),
    );
  }
}

class VibraApp extends ConsumerStatefulWidget {
  const VibraApp({super.key});

  @override
  ConsumerState<VibraApp> createState() => _VibraAppState();
}

class _VibraAppState extends ConsumerState<VibraApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(authStateProvider.notifier).checkAuth();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (prev?.status != next.status) {
        _router.refresh();
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
      routerConfig: _router,
    );
  }
}
