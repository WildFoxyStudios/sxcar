import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'firebase_options.dart';
import 'src/rust/frb_generated.dart';
import 'src/auth/auth_provider.dart';
import 'src/features/albums_screen.dart';
import 'src/features/album_detail_screen.dart';
import 'src/features/chat_list_screen.dart';
import 'src/features/chat_screen.dart';
import 'src/features/login_screen.dart';
import 'src/features/nearby_screen.dart';
import 'src/features/profile_screen.dart';
import 'src/features/register_screen.dart';
import 'src/features/settings_screen.dart';
import 'src/features/verify_email_screen.dart';

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
      return '/';
    }

    if (authState.status == AuthStatus.emailUnverified && !isVerifyRoute) {
      return '/verify-email';
    }

    return null;
  },
  routes: [
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
    GoRoute(
      path: '/profile/:userId',
      builder: (_, state) => ProfileScreen(
        userId: state.pathParameters['userId'],
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) =>
          _VibraShell(navigationShell: navigationShell),
      branches: [
        // Tab 0: Grid — main screen
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const NearbyScreen(),
            ),
          ],
        ),
        // Tab 1: Chat
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chat',
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
        // Tab 2: Albums
        StatefulShellBranch(
          routes: [
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
        // Tab 3: Profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (_, _) => const ProfileScreen(),
            ),
          ],
        ),
        // Tab 4: Settings
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Shell widget that provides the bottom navigation bar around the
/// active tab content.
class _VibraShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _VibraShell({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        backgroundColor: const Color(0xFF121212),
        selectedItemColor: const Color(0xFFFF6B00),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view),
            label: 'Grid',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library),
            label: 'Albums',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune),
            label: 'Settings',
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
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B00),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
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
