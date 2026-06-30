import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      tier: json['tier'] as int? ?? 0,
      active: json['active'] as bool? ?? false,
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
      planCode: json['plan_code'] as String? ?? '',
      feature: json['feature'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
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

final planFeaturesProvider = FutureProvider.autoDispose.family<List<PlanFeature>, String>((ref, planCode) async {
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plans',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: plansAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Failed to load plans: $error'),
                    ],
                  ),
                ),
                data: (plans) => plans.isEmpty
                    ? const Center(child: Text('No plans configured.'))
                    : ListView.builder(
                        itemCount: plans.length,
                        itemBuilder: (context, index) {
                          final plan = plans[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ExpansionTile(
                              leading: Icon(
                                plan.active ? Icons.check_circle : Icons.cancel,
                                color: plan.active ? Colors.green : Colors.grey,
                              ),
                              title: Text('${plan.name} (${plan.code})'),
                              subtitle: Text(
                                'Tier ${plan.tier}${plan.description != null ? " - ${plan.description}" : ""}',
                              ),
                              children: [
                                _PlanFeaturesList(planCode: plan.code),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: _AddFeatureButton(planCode: plan.code),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      error: (error, stack) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load features: $error'),
      ),
      data: (features) {
        if (features.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No features configured for this plan.'),
          );
        }
        return Column(
          children: features
              .map((f) => ListTile(
                    dense: true,
                    leading: Icon(
                      f.enabled ? Icons.check : Icons.close,
                      color: f.enabled ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    title: Text(f.feature),
                    subtitle: f.limitValue != null
                        ? Text('Limit: ${f.limitValue}')
                        : null,
                  ))
              .toList(),
        );
      },
    );
  }
}

class _AddFeatureButton extends ConsumerWidget {
  final String planCode;

  const _AddFeatureButton({required this.planCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () => _showAddFeatureDialog(context, ref, planCode),
      icon: const Icon(Icons.add),
      label: const Text('Add Feature'),
    );
  }

  void _showAddFeatureDialog(BuildContext context, WidgetRef ref, String planCode) {
    final featureController = TextEditingController();
    final limitController = TextEditingController();
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
                  decoration: const InputDecoration(
                    labelText: 'Feature',
                    hintText: 'e.g. unlimited_likes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: limitController,
                  decoration: const InputDecoration(
                    labelText: 'Limit Value (optional)',
                    hintText: 'e.g. 100',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Enabled'),
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
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
                  context, ref, planCode, featureController.text,
                  enabled, limitController.text,
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
      BuildContext context, WidgetRef ref,
      String planCode, String feature, bool enabled, String limitStr) async {
    if (feature.isEmpty) return;

    try {
      final client = ref.read(adminHttpClientProvider);
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
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(planFeaturesProvider(planCode));
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Failed to add feature').toString()
            : 'Failed to add feature';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }
}
