import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class FeatureFlag {
  final String key;
  final dynamic value;
  final String? description;
  final bool enabled;
  final String createdAt;
  final String updatedAt;
  final String? updatedBy;

  FeatureFlag({
    required this.key,
    this.value,
    this.description,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.updatedBy,
  });

  factory FeatureFlag.fromJson(Map<String, dynamic> json) {
    return FeatureFlag(
      key: json['key'] as String? ?? '',
      value: json['value'],
      description: json['description'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
      updatedBy: json['updated_by'] as String?,
    );
  }
}

final flagsProvider = FutureProvider.autoDispose<List<FeatureFlag>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/flags');
  final data = response.data as Map<String, dynamic>;
  final flagsList = (data['flags'] as List<dynamic>?)
          ?.map((e) => FeatureFlag.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return flagsList;
});

class FlagsScreen extends ConsumerWidget {
  const FlagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagsAsync = ref.watch(flagsProvider);

    return AdminLayout(
      selectedIndex: 3,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Feature Flags',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                FilledButton.icon(
                  onPressed: () => _showCreateDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('New Flag'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: flagsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Failed to load flags: $error'),
                    ],
                  ),
                ),
                data: (flags) => flags.isEmpty
                    ? const Center(child: Text('No feature flags configured.'))
                    : ListView.builder(
                        itemCount: flags.length,
                        itemBuilder: (context, index) {
                          final flag = flags[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(flag.key),
                              subtitle: Text(flag.description ?? 'Value: ${flag.value}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: flag.enabled,
                                    onChanged: (enabled) =>
                                        _toggleFlag(context, ref, flag, enabled),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    onPressed: () =>
                                        _deleteFlag(context, ref, flag.key),
                                  ),
                                ],
                              ),
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

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final keyController = TextEditingController();
    final valueController = TextEditingController(text: 'true');
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Feature Flag'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'Key',
                  hintText: 'e.g. new_onboarding_flow',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                decoration: const InputDecoration(
                  labelText: 'Value',
                  hintText: 'true, false, or JSON value',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
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
              _createFlag(
                context, ref, keyController.text,
                valueController.text, descriptionController.text,
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createFlag(
      BuildContext context, WidgetRef ref,
      String key, String value, String description) async {
    if (key.isEmpty) return;

    try {
      final client = ref.read(adminHttpClientProvider);
      // Parse value as JSON if possible
      dynamic parsedValue;
      try {
        parsedValue = value.toLowerCase() == 'true'
            ? true
            : value.toLowerCase() == 'false'
                ? false
                : value; // Keep as string for simplicity
      } catch (_) {
        parsedValue = value;
      }

      await client.dio.post('/admin/flags', data: {
        'key': key,
        'value': parsedValue,
        'description': description.isEmpty ? null : description,
        'enabled': true,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Flag "$key" created'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(flagsProvider);
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Failed to create flag').toString()
            : 'Failed to create flag';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleFlag(
      BuildContext context, WidgetRef ref, FeatureFlag flag, bool enabled) async {
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.post('/admin/flags', data: {
        'key': flag.key,
        'value': flag.value ?? true,
        'description': flag.description,
        'enabled': enabled,
      });
      ref.invalidate(flagsProvider);
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Failed to update flag').toString()
            : 'Failed to update flag';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteFlag(BuildContext context, WidgetRef ref, String key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Flag'),
        content: Text('Are you sure you want to delete "$key"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.delete('/admin/flags/$key');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Flag "$key" deleted'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(flagsProvider);
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Failed to delete flag').toString()
            : 'Failed to delete flag';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }
}
