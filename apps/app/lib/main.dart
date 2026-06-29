import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'src/rust/frb_generated.dart';
import 'src/auth/auth_provider.dart';
import 'src/features/home_screen.dart';
import 'src/features/login_screen.dart';
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
      path: '/profile/:userId',
      builder: (context, state) => _PlaceholderScreen(
        title: 'Profile',
        message: 'User ID: ${state.pathParameters['userId']}',
      ),
    ),
    GoRoute(
      path: '/chat/:conversationId',
      builder: (context, state) => _PlaceholderScreen(
        title: 'Chat',
        message: 'Conversation ID: ${state.pathParameters['conversationId']}',
      ),
    ),
  ],
);

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(message, style: Theme.of(context).textTheme.headlineSmall),
      ),
    );
  }
}

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
