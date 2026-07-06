import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'firebase_options.dart';
import 'src/rust/frb_generated.dart';
import 'src/auth/auth_provider.dart';
import 'src/billing/revenuecat_providers.dart';
import 'src/notifications/push_service.dart';
import 'src/chat/models.dart';
import 'src/chat/unread_count_provider.dart';
import 'src/presence/presence_service.dart';
import 'src/features/album_detail_screen.dart';
import 'src/features/albums_screen.dart';
import 'src/features/blocks_list_screen.dart';
import 'src/features/cascade_screen.dart';
import 'src/features/chat_list_screen.dart';
import 'src/features/grid_search_screen.dart';
import 'src/features/chat_screen.dart';
import 'src/features/circles_screen.dart';
import 'src/features/create_group_screen.dart';
import 'src/features/create_story_screen.dart';
import 'src/features/group_info_screen.dart';
import 'src/features/discreet_icon_picker_screen.dart';
import 'src/features/interest_screen.dart';
import 'src/features/login_screen.dart';
import 'src/features/pin_screen.dart';
import 'src/features/profile_detail_screen.dart';
import 'src/features/profile_drawer.dart';
import 'src/features/register_screen.dart';
import 'src/features/right_now_screen.dart';
import 'src/features/verify_email_screen.dart';
import 'src/features/edit_profile_screen.dart';
import 'src/features/security_screen.dart';
import 'src/features/settings_screen.dart';
import 'src/phrases/phrases_screen.dart';
import 'src/sessions/sessions_screen.dart';
import 'src/theme/app_theme.dart';
import 'l10n/gen/app_localizations.dart';

// ---------------------------------------------------------------------------
// Global key used by CascadeScreen's temporary drawer button (T2) and by
// the Navegar header avatar (T3) to open the ProfileDrawer without needing
// to walk up the widget tree past CascadeScreen's own Scaffold.
// ---------------------------------------------------------------------------

/// Key for the outer [MainShell] Scaffold that owns the [ProfileDrawer].
final GlobalKey<ScaffoldState> mainScaffoldKey = GlobalKey<ScaffoldState>();

// ---------------------------------------------------------------------------
// Known top-level paths
// ---------------------------------------------------------------------------

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
  // New shell tabs (T2)
  '/navegar',
  '/right-now',
  '/interest',
  '/inbox',
  '/tienda',
  // Top-level routes moved out of You branch (T2)
  '/edit-profile',
  '/settings',
  '/security',
  '/albums',
  '/grid-search',
  // Legacy paths kept as redirect routes so old deep links / tests don't break
  '/cascade',
  '/you',
  '/explore',
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
  // Register the background message handler before runApp so that it is set
  // up even when the app is launched from a terminated state by a notification.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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
    return '/navegar';
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
    return '/navegar';
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
              Text('V',
                  style: TextStyle(
                      color: VibraTheme.kYellow,
                      fontSize: 48,
                      fontWeight: FontWeight.bold)),
              SizedBox(height: 16),
              CircularProgressIndicator(color: VibraTheme.kYellow),
            ],
          ),
        ),
      ),
    ),

    // ── Auth routes ────────────────────────────────────────────────────────
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

    // ── Full-screen profile detail (no bottom nav) ─────────────────────────
    GoRoute(
      path: '/profile/:userId',
      builder: (_, state) => ProfileDetailScreen(
        userId: state.pathParameters['userId']!,
      ),
    ),

    // ── Top-level routes moved OUT of the You branch (T2) ─────────────────
    // These appear above the shell so they are full-screen (no bottom nav),
    // and a back button in their AppBar returns to the previous shell tab.
    GoRoute(
      path: '/grid-search',
      builder: (_, _) => const GridSearchScreen(),
    ),
    GoRoute(
      path: '/edit-profile',
      builder: (_, _) => const EditProfileScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, state) => SettingsScreen(
        initialTab: state.uri.queryParameters['tab'],
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
      path: '/settings/discreet-icon',
      builder: (_, _) => const DiscreetIconPickerScreen(),
    ),
    GoRoute(
      path: '/settings/pin',
      builder: (_, _) => const PinScreen(),
    ),
    GoRoute(
      path: '/settings/blocks',
      builder: (_, _) => const BlocksListScreen(),
    ),
    GoRoute(
      path: '/security',
      builder: (_, _) => const SecurityScreen(),
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

    // ── Full-screen story screens ──────────────────────────────────────────
    GoRoute(
      path: '/create-story',
      builder: (_, _) => const CreateStoryScreen(),
    ),

    // ── Legacy redirect routes (keeps old deep links / tests working) ──────
    GoRoute(
      path: '/cascade',
      redirect: (_, _) => '/navegar',
    ),
    GoRoute(
      path: '/you',
      redirect: (_, _) => '/navegar',
    ),
    GoRoute(
      path: '/explore',
      redirect: (_, _) => '/right-now',
    ),

    // ── Main shell with 5-tab bottom navigation ────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (_, _, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        // Tab 0: Navegar (nearby grid — content from CascadeScreen; T3 redesigns)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/navegar',
              builder: (_, _) => const NavegarScreen(),
            ),
          ],
        ),
        // Tab 1: Right Now (active "Right Now" intent feed)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/right-now',
              builder: (_, _) => const RightNowScreen(),
            ),
          ],
        ),
        // Tab 2: Interest (views + taps)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/interest',
              builder: (_, _) => const InterestScreen(),
            ),
          ],
        ),
        // Tab 3: Buzón (inbox + conversation).
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/inbox',
              builder: (_, _) => const ChatListScreen(),
              routes: [
                // conversationId sub-route: pageBuilder (not builder) so we
                // can pass a unique ValueKey per /inbox/<id>. Otherwise the
                // StatefulShellRoute's IndexedStack reuses the same Page for
                // /inbox and /inbox/123 and Navigator's debug assert fires
                // about duplicated page keys.
                GoRoute(
                  path: ':conversationId',
                  pageBuilder: (context, state) {
                    final Conversation? extra =
                        state.extra as Conversation?;
                    return MaterialPage<void>(
                      key: ValueKey(
                          'chat-${state.pathParameters['conversationId']}'),
                      child: ChatScreen(
                        conversationId:
                            state.pathParameters['conversationId']!,
                        isGroup: extra?.isGroup ?? false,
                        conversationName: extra?.displayTitle,
                      ),
                    );
                  },
                ),
                // Circles (group chats) sub-routes
                GoRoute(
                  path: 'circles',
                  builder: (_, _) => const CirclesScreen(),
                ),
                GoRoute(
                  path: 'create-group',
                  builder: (_, _) => const CreateGroupScreen(),
                ),
                GoRoute(
                  path: 'group-info/:groupId',
                  builder: (_, state) => GroupInfoScreen(
                    groupId: state.pathParameters['groupId']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        // Tab 4: Tienda (shop / plans)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tienda',
              builder: (context, _) => Scaffold(
                backgroundColor: VibraTheme.kBg,
                appBar: AppBar(
                  backgroundColor: VibraTheme.kBg,
                  title: Text(
                    AppLocalizations.of(context)?.tienda ?? 'Tienda',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                body: Center(
                  child: Text(
                    AppLocalizations.of(context)?.tienda ?? 'Tienda',
                    style: const TextStyle(
                        color: VibraTheme.kTextSecondary, fontSize: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Shell widget that provides the Grindr-style bottom navigation bar and
/// the left-side [ProfileDrawer].
class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final unreadAsync = ref.watch(unreadCountProvider);
    final unreadCount = unreadAsync.maybeWhen(
      data: (n) => n,
      orElse: () => 0,
    );

    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      key: mainScaffoldKey,
      backgroundColor: VibraTheme.kBg,
      drawer: const ProfileDrawer(),
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        backgroundColor: const Color(0xFF0D0D0D),
        selectedItemColor: VibraTheme.kYellow,
        unselectedItemColor: const Color(0xFF777777),
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.grid_view_rounded),
            label: l10n.navegar,
          ),
          BottomNavigationBarItem(
            icon: Icon(currentIndex == 1
                ? Icons.water_drop
                : Icons.water_drop_outlined),
            label: l10n.rightNow,
          ),
          BottomNavigationBarItem(
            icon: Icon(currentIndex == 2
                ? Icons.local_fire_department
                : Icons.local_fire_department_outlined),
            label: l10n.interest,
          ),
          BottomNavigationBarItem(
            icon: _BuzonTabIcon(
              unreadCount: unreadCount,
              isSelected: currentIndex == 3,
            ),
            label: l10n.buzon,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.storefront_outlined),
            label: l10n.tienda,
          ),
        ],
      ),
    );
  }
}

/// Buzón tab icon — wraps the standard chat icon in a [Badge] when there
/// are unread messages. Hidden when count == 0.
class _BuzonTabIcon extends StatelessWidget {
  final int unreadCount;
  final bool isSelected;

  const _BuzonTabIcon({required this.unreadCount, required this.isSelected});

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
      backgroundColor: VibraTheme.kBadgeRed,
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
    // heartbeatProvider is automatically a no-op in Incognito mode.
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
        // Register the FCM token once the user is authenticated. Doing this
        // post-auth ensures the Bearer token is in the Dio headers when the
        // request reaches /notifications/register.
        if (next.status == AuthStatus.authenticated) {
          ref.read(pushServiceProvider).initAndRegister();
          ref.read(revenueCatServiceProvider).configure();
        }
      }
    });

    return MaterialApp.router(
      title: 'Vibra',
      debugShowCheckedModeBanner: false,
      theme: VibraTheme.dark(),
      routerConfig: appRouter,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
