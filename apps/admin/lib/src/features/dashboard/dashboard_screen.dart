import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
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
      totalUsers:     json['total_users']     as int? ?? 0,
      activeToday:    json['active_today']    as int? ?? 0,
      bannedUsers:    json['banned_users']    as int? ?? 0,
      suspendedUsers: json['suspended_users'] as int? ?? 0,
      premiumUsers:   json['premium_users']   as int? ?? 0,
      newUsersToday:  json['new_users_today'] as int? ?? 0,
    );
  }
}

final dashboardProvider =
    FutureProvider.autoDispose<AnalyticsOverview>((ref) async {
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page header
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overview',
                        style: TextStyle(
                          color: AdminTheme.kText,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Platform metrics at a glance',
                        style: TextStyle(color: AdminTheme.kMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                // Refresh button
                analyticsAsync.when(
                  loading: () => const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (_) => IconButton(
                    icon: const Icon(Icons.refresh, size: 18, color: AdminTheme.kMuted),
                    tooltip: 'Refresh',
                    onPressed: () => ref.invalidate(dashboardProvider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            analyticsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(64),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => _ErrorBanner(error: error.toString()),
              data: (analytics) => _MetricGrid(analytics: analytics),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error banner ─────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String error;
  const _ErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.kRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.kRed.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AdminTheme.kRed, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Failed to load analytics: $error',
              style: const TextStyle(color: AdminTheme.kRed, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Metric grid ──────────────────────────────────────────────────────────────

class _MetricGrid extends StatelessWidget {
  final AnalyticsOverview analytics;
  const _MetricGrid({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricDef(
        label: 'TOTAL USERS',
        value: analytics.totalUsers,
        icon: Icons.people,
        accent: AdminTheme.kAccent,
      ),
      _MetricDef(
        label: 'ACTIVE TODAY',
        value: analytics.activeToday,
        icon: Icons.trending_up,
        accent: AdminTheme.kGreen,
      ),
      _MetricDef(
        label: 'PREMIUM',
        value: analytics.premiumUsers,
        icon: Icons.workspace_premium,
        accent: AdminTheme.kAccent,
      ),
      _MetricDef(
        label: 'NEW TODAY',
        value: analytics.newUsersToday,
        icon: Icons.person_add_outlined,
        accent: AdminTheme.kBlue,
      ),
      _MetricDef(
        label: 'SUSPENDED',
        value: analytics.suspendedUsers,
        icon: Icons.pause_circle_outlined,
        accent: AdminTheme.kOrange,
      ),
      _MetricDef(
        label: 'BANNED',
        value: analytics.bannedUsers,
        icon: Icons.block_outlined,
        accent: AdminTheme.kRed,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= 700
                ? 2
                : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 2.6,
          ),
          itemCount: metrics.length,
          itemBuilder: (ctx, i) => _MetricCard(metric: metrics[i]),
        );
      },
    );
  }
}

class _MetricDef {
  final String label;
  final int value;
  final IconData icon;
  final Color accent;
  const _MetricDef({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });
}

class _MetricCard extends StatelessWidget {
  final _MetricDef metric;
  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: AdminTheme.kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Icon + label row
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: metric.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(metric.icon, color: metric.accent, size: 16),
              ),
              const Spacer(),
            ],
          ),
          // Value + label
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatNumber(metric.value),
                style: const TextStyle(
                  color: AdminTheme.kText,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                metric.label,
                style: const TextStyle(
                  color: AdminTheme.kMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
