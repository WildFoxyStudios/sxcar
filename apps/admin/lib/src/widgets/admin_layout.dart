import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/admin_auth_provider.dart';

class AdminLayout extends ConsumerWidget {
  final Widget child;
  final int selectedIndex;

  const AdminLayout({
    super.key,
    required this.child,
    this.selectedIndex = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) =>
                  _onNavSelected(context, ref, index),
              labelType: NavigationRailLabelType.all,
              minExtendedWidth: 160,
              extended: MediaQuery.of(context).size.width >= 900,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  Icons.admin_panel_settings,
                  color: Theme.of(context).colorScheme.primary,
                  size: 32,
                ),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.dashboard),
                  label: Text('Dashboard'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.people),
                  label: Text('Users'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.flag),
                  label: Text('Reports'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.toggle_on),
                  label: Text('Flags'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.card_membership),
                  label: Text('Plans'),
                ),
              ],
              trailing: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: () => _onLogout(context, ref),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  void _onNavSelected(BuildContext context, WidgetRef ref, int index) {
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/users');
        break;
      case 2:
        context.go('/reports');
        break;
      case 3:
        context.go('/flags');
        break;
      case 4:
        context.go('/plans');
        break;
    }
  }

  Future<void> _onLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Logout'),
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
