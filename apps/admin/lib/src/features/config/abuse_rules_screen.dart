import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class AbuseRule {
  final String id;
  final String name;
  final String pattern;
  final String severity;
  final bool enabled;

  AbuseRule({
    required this.id,
    required this.name,
    required this.pattern,
    required this.severity,
    required this.enabled,
  });

  factory AbuseRule.fromJson(Map<String, dynamic> json) {
    return AbuseRule(
      id:       json['id']       as String? ?? '',
      name:     json['name']     as String? ?? '',
      pattern:  json['pattern']  as String? ?? '',
      severity: json['severity'] as String? ?? 'low',
      enabled:  json['enabled']  as bool?   ?? false,
    );
  }
}

final abuseRulesProvider =
    FutureProvider.autoDispose<List<AbuseRule>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/abuse/rules');
  final data = response.data as Map<String, dynamic>;
  final list = (data['rules'] as List<dynamic>?)
          ?.map((e) => AbuseRule.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class AbuseRulesScreen extends ConsumerWidget {
  const AbuseRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(abuseRulesProvider);

    return AdminLayout(
      selectedIndex: 15,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(child: _body(context, ref, async)),
        ],
      ),
    );
  }

  Widget _header() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Abuse Detection Rules',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Rules that flag abusive content',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref,
      AsyncValue<List<AbuseRule>> async) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AdminTheme.kRed),
            const SizedBox(height: 12),
            Text('Failed to load: $error',
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 14)),
          ],
        ),
      ),
      data: (rules) {
        if (rules.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.rule, size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No abuse rules configured.',
                    style:
                        TextStyle(color: AdminTheme.kMuted, fontSize: 14)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: rules.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) =>
              _RuleCard(rule: rules[i], onToggle: (enabled) {
            _toggleRule(context, ref, rules[i].id, enabled);
          }),
        );
      },
    );
  }
}

class _RuleCard extends StatelessWidget {
  final AbuseRule rule;
  final ValueChanged<bool> onToggle;
  const _RuleCard({required this.rule, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (rule.severity) {
      'high' => AdminTheme.kRed,
      'medium' => AdminTheme.kOrange,
      _ => AdminTheme.kYellow,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminTheme.kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              color: rule.enabled ? AdminTheme.kGreen : AdminTheme.kBorder,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rule.name,
                    style: const TextStyle(
                        color: AdminTheme.kText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(rule.pattern,
                    style: const TextStyle(
                        color: AdminTheme.kMuted,
                        fontSize: 12,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          _Chip(rule.severity, severityColor),
          const SizedBox(width: 12),
          Switch(value: rule.enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}

Future<void> _toggleRule(
    BuildContext context, WidgetRef ref, String id, bool enabled) async {
  try {
    final client = ref.read(adminHttpClientProvider);
    await client.dio.put('/admin/abuse/rules/$id', data: {'enabled': enabled});
    ref.invalidate(abuseRulesProvider);
  } on DioException catch (e) {
    if (context.mounted) {
      final msg = e.response?.data is Map
          ? ((e.response!.data as Map)['error'] ?? 'Update failed').toString()
          : 'Update failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: AdminTheme.kRed));
    }
  }
}
