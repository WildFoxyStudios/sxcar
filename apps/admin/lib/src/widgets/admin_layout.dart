import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/admin_auth_provider.dart';
import '../theme/admin_theme.dart';

class AdminLayout extends ConsumerWidget {
  final Widget child;
  final int selectedIndex;

  const AdminLayout({
    super.key,
    required this.child,
    this.selectedIndex = 0,
  });

  static const _navItems = [
    (icon: Icons.dashboard_outlined,     activeIcon: Icons.dashboard,     label: 'Dashboard'),
    (icon: Icons.people_outlined,        activeIcon: Icons.people,        label: 'Users'),
    (icon: Icons.flag_outlined,          activeIcon: Icons.flag,          label: 'Reports'),
    (icon: Icons.toggle_on_outlined,     activeIcon: Icons.toggle_on,     label: 'Flags'),
    (icon: Icons.credit_card_outlined,   activeIcon: Icons.credit_card,   label: 'Plans'),
  ];

  static const _routes = ['/dashboard', '/users', '/reports', '/flags', '/plans'];

  String get _sectionTitle => selectedIndex < _navItems.length
      ? _navItems[selectedIndex].label
      : 'Admin';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final extended = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AdminTheme.kBg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: _sectionTitle,
              adminEmail: authState.adminEmail,
              onLogout: () => _onLogout(context, ref),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                children: [
                  _NavRail(
                    selectedIndex: selectedIndex,
                    extended: extended,
                    onDestinationSelected: (i) =>
                        _onNavSelected(context, ref, i),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AdminTheme.kBorder,
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onNavSelected(BuildContext context, WidgetRef ref, int index) {
    if (index >= 0 && index < _routes.length) {
      context.go(_routes[index]);
    }
  }

  Future<void> _onLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) {
        context.go('/login');
      }
    }
  }
}

// ── Top bar ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final String? adminEmail;
  final VoidCallback onLogout;

  const _TopBar({
    required this.title,
    required this.adminEmail,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: AdminTheme.kSurface,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AdminTheme.kText,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (adminEmail != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AdminTheme.kCard,
                borderRadius: BorderRadius.circular(20),
                border: const Border.fromBorderSide(
                  BorderSide(color: AdminTheme.kBorder),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    size: 14,
                    color: AdminTheme.kMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    adminEmail!,
                    style: const TextStyle(
                      color: AdminTheme.kMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.logout, size: 18),
            color: AdminTheme.kMuted,
            tooltip: 'Sign out',
            onPressed: onLogout,
            style: IconButton.styleFrom(
              hoverColor: AdminTheme.kBorder,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Navigation rail ──────────────────────────────────────────────────────────

class _NavRail extends StatelessWidget {
  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onDestinationSelected;

  const _NavRail({
    required this.selectedIndex,
    required this.extended,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      extended: extended,
      minExtendedWidth: 200,
      backgroundColor: AdminTheme.kSurface,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
        child: extended
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 16),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AdminTheme.kAccentBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings,
                      color: AdminTheme.kAccent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VIBRA',
                        style: TextStyle(
                          color: AdminTheme.kAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Admin Console',
                        style: TextStyle(
                          color: AdminTheme.kMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AdminTheme.kAccentBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.admin_panel_settings,
                  color: AdminTheme.kAccent,
                  size: 18,
                ),
              ),
      ),
      destinations: AdminLayout._navItems
          .map(
            (item) => NavigationRailDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.activeIcon),
              label: Text(item.label),
            ),
          )
          .toList(),
    );
  }
}
