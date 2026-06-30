import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class AnalyticsOverview {
  final int totalUsers;
  final int activeToday;
  final int bannedUsers;
  final int suspendedUsers;
  final int premiumUsers;
  final int newUsersToday;

  AnalyticsOverview({
    required this.totalUsers,
    required this.activeToday,
    required this.bannedUsers,
    required this.suspendedUsers,
    required this.premiumUsers,
    required this.newUsersToday,
  });

  factory AnalyticsOverview.fromJson(Map<String, dynamic> json) {
    return AnalyticsOverview(
      totalUsers: json['total_users'] as int? ?? 0,
      activeToday: json['active_today'] as int? ?? 0,
      bannedUsers: json['banned_users'] as int? ?? 0,
      suspendedUsers: json['suspended_users'] as int? ?? 0,
      premiumUsers: json['premium_users'] as int? ?? 0,
      newUsersToday: json['new_users_today'] as int? ?? 0,
    );
  }
}

final dashboardProvider = FutureProvider.autoDispose<AnalyticsOverview>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/analytics/overview');
  return AnalyticsOverview.fromJson(response.data as Map<String, dynamic>);
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(dashboardProvider);

    return AdminLayout(
      selectedIndex: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dashboard',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            analyticsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Failed to load analytics: $error'),
                  ],
                ),
              ),
              data: (analytics) => Expanded(
                child: _buildGrid(context, analytics),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, AnalyticsOverview analytics) {
    return GridView.count(
      crossAxisCount: _gridColumns(context),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          title: 'Total Users',
          value: analytics.totalUsers.toString(),
          icon: Icons.people,
          color: Colors.blue,
        ),
        _StatCard(
          title: 'Active Today',
          value: analytics.activeToday.toString(),
          icon: Icons.trending_up,
          color: Colors.green,
        ),
        _StatCard(
          title: 'Premium Users',
          value: analytics.premiumUsers.toString(),
          icon: Icons.star,
          color: Colors.amber,
        ),
        _StatCard(
          title: 'New Today',
          value: analytics.newUsersToday.toString(),
          icon: Icons.person_add,
          color: Colors.teal,
        ),
        _StatCard(
          title: 'Banned',
          value: analytics.bannedUsers.toString(),
          icon: Icons.block,
          color: Colors.red,
        ),
        _StatCard(
          title: 'Suspended',
          value: analytics.suspendedUsers.toString(),
          icon: Icons.pause_circle,
          color: Colors.orange,
        ),
      ],
    );
  }

  int _gridColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 1200) return 3;
    if (width >= 800) return 2;
    return 1;
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const Spacer(),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
