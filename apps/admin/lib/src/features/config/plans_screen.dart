import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class Plan {
  final String code;
  final String name;
  final int tier;
  final bool active;
  final String? description;

  Plan({
    required this.code,
    required this.name,
    required this.tier,
    required this.active,
    this.description,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      code:        json['code']        as String? ?? '',
      name:        json['name']        as String? ?? '',
      tier:        json['tier']        as int?    ?? 0,
      active:      json['active']      as bool?   ?? false,
      description: json['description'] as String?,
    );
  }
}

class PlanFeature {
  final String planCode;
  final String feature;
  final bool enabled;
  final int? limitValue;

  PlanFeature({
    required this.planCode,
    required this.feature,
    required this.enabled,
    this.limitValue,
  });

  factory PlanFeature.fromJson(Map<String, dynamic> json) {
    return PlanFeature(
      planCode:   json['plan_code']   as String? ?? '',
      feature:    json['feature']     as String? ?? '',
      enabled:    json['enabled']     as bool?   ?? false,
      limitValue: json['limit_value'] as int?,
    );
  }
}

final plansProvider = FutureProvider.autoDispose<List<Plan>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/plans');
  final data = response.data as Map<String, dynamic>;
  final plansList = (data['plans'] as List<dynamic>?)
          ?.map((e) => Plan.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return plansList;
});

final planFeaturesProvider =
    FutureProvider.autoDispose.family<List<PlanFeature>, String>(
        (ref, planCode) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/plans/$planCode/features');
  final data = response.data as Map<String, dynamic>;
  final featuresList = (data['features'] as List<dynamic>?)
          ?.map((e) => PlanFeature.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return featuresList;
});

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(plansProvider);

    return AdminLayout(
      selectedIndex: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plans',
                  style: TextStyle(
                    color: AdminTheme.kText,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Subscription tiers and feature entitlements',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── List ──────────────────────────────────────────────────────────
          Expanded(
            child: plansAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 40, color: AdminTheme.kRed),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load plans: $error',
                      style:
                          const TextStyle(color: AdminTheme.kMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              data: (plans) => plans.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.credit_card,
                              size: 40, color: AdminTheme.kMuted),
                          SizedBox(height: 12),
                          Text(
                            'No plans configured.',
                            style: TextStyle(
                                color: AdminTheme.kMuted, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: plans.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 10),
                      itemBuilder: (ctx, i) =>
                          _PlanCard(plan: plans[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final Plan plan;
  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.kBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.zero,
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: plan.active
                  ? AdminTheme.kAccentBg
                  : AdminTheme.kBorder.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              plan.active ? Icons.check : Icons.close,
              size: 16,
              color: plan.active ? AdminTheme.kAccent : AdminTheme.kMuted,
            ),
          ),
          title: Row(
            children: [
              Text(
                plan.name,
                style: const TextStyle(
                  color: AdminTheme.kText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AdminTheme.kBorder,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  plan.code,
                  style: const TextStyle(
                    color: AdminTheme.kMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          subtitle: Text(
            'Tier ${plan.tier}'
            '${plan.description != null ? " · ${plan.description}" : ""}',
            style:
                const TextStyle(color: AdminTheme.kMuted, fontSize: 12),
          ),
          children: [
            const Divider(height: 1),
            _PlanFeaturesList(planCode: plan.code),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _AddFeatureButton(planCode: plan.code),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Features list ─────────────────────────────────────────────────────────────

class _PlanFeaturesList extends ConsumerWidget {
  final String planCode;
  const _PlanFeaturesList({required this.planCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featuresAsync = ref.watch(planFeaturesProvider(planCode));

    return featuresAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Failed to load features: $error',
          style: const TextStyle(color: AdminTheme.kMuted, fontSize: 13),
        ),
      ),
      data: (features) {
        if (features.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No features configured for this plan.',
              style: TextStyle(color: AdminTheme.kMuted, fontSize: 13),
            ),
          );
        }
        return Column(
          children: features
              .map(
                (f) => Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: AdminTheme.kBorder, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        f.enabled ? Icons.check : Icons.close,
                        size: 14,
                        color:
                            f.enabled ? AdminTheme.kGreen : AdminTheme.kRed,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f.feature,
                          style: const TextStyle(
                            color: AdminTheme.kText,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (f.limitValue != null)
                        Text(
                          'limit: ${f.limitValue}',
                          style: const TextStyle(
                            color: AdminTheme.kMuted,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

// ── Add feature button ────────────────────────────────────────────────────────

class _AddFeatureButton extends ConsumerWidget {
  final String planCode;
  const _AddFeatureButton({required this.planCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.add, size: 14),
      label: const Text('Add Feature'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminTheme.kAccent,
        side: const BorderSide(color: AdminTheme.kBorder),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      onPressed: () => _showAddFeatureDialog(context, ref, planCode),
    );
  }

  void _showAddFeatureDialog(
      BuildContext context, WidgetRef ref, String planCode) {
    final featureController = TextEditingController();
    final limitController   = TextEditingController();
    bool enabled = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Add Feature to $planCode'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: featureController,
                  style: const TextStyle(color: AdminTheme.kText),
                  decoration: const InputDecoration(
                    labelText: 'Feature',
                    hintText: 'e.g. unlimited_likes',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: limitController,
                  style: const TextStyle(color: AdminTheme.kText),
                  decoration: const InputDecoration(
                    labelText: 'Limit Value (optional)',
                    hintText: 'e.g. 100',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text(
                    'Enabled',
                    style: TextStyle(color: AdminTheme.kText, fontSize: 14),
                  ),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _addFeature(
                  context,
                  ref,
                  planCode,
                  featureController.text,
                  enabled,
                  limitController.text,
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFeature(
    BuildContext context,
    WidgetRef ref,
    String planCode,
    String feature,
    bool enabled,
    String limitStr,
  ) async {
    if (feature.isEmpty) return;

    try {
      final client     = ref.read(adminHttpClientProvider);
      final int? limit = int.tryParse(limitStr);

      await client.dio.post('/admin/plans/$planCode/features', data: {
        'feature': feature,
        'enabled': enabled,
        if (limit != null) 'limit_value': limit,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Feature "$feature" added to $planCode'),
            backgroundColor: AdminTheme.kGreen,
          ),
        );
        ref.invalidate(planFeaturesProvider(planCode));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Failed to add feature')
                .toString()
            : 'Failed to add feature';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AdminTheme.kRed),
        );
      }
    }
  }
}
