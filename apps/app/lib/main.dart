import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'src/rust/frb_generated.dart';
import 'src/auth/auth_provider.dart';
import 'src/features/albums_screen.dart';
import 'src/features/album_detail_screen.dart';
import 'src/features/home_screen.dart';
import 'src/features/login_screen.dart';
import 'src/features/chat_list_screen.dart';
import 'src/features/chat_screen.dart';
import 'src/features/nearby_screen.dart';
import 'src/features/profile_screen.dart';
import 'src/features/register_screen.dart';
import 'src/features/verify_email_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const ProviderScope(child: ProyectoXApp()));
}

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final authState = ProviderScope.containerOf(context).read(authStateProvider);

    final isAuthRoute = state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';

    if (authState.status == AuthStatus.loading) {
      return null;
    }

    if (authState.status == AuthStatus.unauthenticated && !isAuthRoute) {
      return '/login';
    }

    if (authState.status == AuthStatus.authenticated && isAuthRoute) {
      return '/';
    }

    if (authState.status == AuthStatus.emailUnverified &&
        state.matchedLocation != '/verify-email') {
      return '/verify-email';
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/verify-email',
      builder: (context, state) => const VerifyEmailScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/grid',
      builder: (context, state) => const NearbyScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/profile/:userId',
      builder: (context, state) => ProfileScreen(
        userId: state.pathParameters['userId'],
      ),
    ),
    GoRoute(
      path: '/albums',
      builder: (context, state) => const AlbumsScreen(),
      routes: [
        GoRoute(
          path: ':albumId',
          builder: (context, state) => AlbumDetailScreen(
            albumId: state.pathParameters['albumId']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) => const ChatListScreen(),
      routes: [
        GoRoute(
          path: ':conversationId',
          builder: (context, state) => ChatScreen(
            conversationId: state.pathParameters['conversationId']!,
          ),
        ),
      ],
    ),
  ],
);

class ProyectoXApp extends ConsumerStatefulWidget {
  const ProyectoXApp({super.key});

  @override
  ConsumerState<ProyectoXApp> createState() => _ProyectoXAppState();
}

class _ProyectoXAppState extends ConsumerState<ProyectoXApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(authStateProvider.notifier).checkAuth();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state changes and refresh router
    ref.listen<AuthState>(authStateProvider, (prev, next) {
      if (prev?.status != next.status) {
        _router.refresh();
      }
    });

    return MaterialApp.router(
      title: 'proyecto-X',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.dark,
        ),
      ),
      routerConfig: _router,
    );
  }
}
