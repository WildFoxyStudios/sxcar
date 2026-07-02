import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
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
      key:         json['key']        as String? ?? '',
      value:       json['value'],
      description: json['description'] as String?,
      enabled:     json['enabled']    as bool?   ?? false,
      createdAt:   json['created_at'] as String? ?? '',
      updatedAt:   json['updated_at'] as String? ?? '',
      updatedBy:   json['updated_by'] as String?,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Feature Flags',
                      style: TextStyle(
                        color: AdminTheme.kText,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Toggle platform features without a deploy',
                      style: TextStyle(color: AdminTheme.kMuted, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showCreateDialog(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New Flag'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── List ──────────────────────────────────────────────────────────
          Expanded(
            child: flagsAsync.when(
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
                      'Failed to load flags: $error',
                      style:
                          const TextStyle(color: AdminTheme.kMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              data: (flags) => flags.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.toggle_off,
                              size: 40, color: AdminTheme.kMuted),
                          SizedBox(height: 12),
                          Text(
                            'No feature flags configured.',
                            style: TextStyle(
                                color: AdminTheme.kMuted, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: flags.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 8),
                      itemBuilder: (ctx, i) => _FlagCard(
                        flag: flags[i],
                        onToggle: (enabled) =>
                            _toggleFlag(context, ref, flags[i], enabled),
                        onDelete: () =>
                            _deleteFlag(context, ref, flags[i].key),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final keyController         = TextEditingController();
    final valueController       = TextEditingController(text: 'true');
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
                style: const TextStyle(color: AdminTheme.kText),
                decoration: const InputDecoration(
                  labelText: 'Key',
                  hintText: 'e.g. new_onboarding_flow',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                style: const TextStyle(color: AdminTheme.kText),
                decoration: const InputDecoration(
                  labelText: 'Value',
                  hintText: 'true, false, or JSON value',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                style: const TextStyle(color: AdminTheme.kText),
                decoration:
                    const InputDecoration(labelText: 'Description'),
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
                context,
                ref,
                keyController.text,
                valueController.text,
                descriptionController.text,
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createFlag(
    BuildContext context,
    WidgetRef ref,
    String key,
    String value,
    String description,
  ) async {
    if (key.isEmpty) return;

    try {
      final client = ref.read(adminHttpClientProvider);
      dynamic parsedValue = value.toLowerCase() == 'true'
          ? true
          : value.toLowerCase() == 'false'
              ? false
              : value;

      await client.dio.post('/admin/flags', data: {
        'key':         key,
        'value':       parsedValue,
        'description': description.isEmpty ? null : description,
        'enabled':     true,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Flag "$key" created'),
            backgroundColor: AdminTheme.kGreen,
          ),
        );
        ref.invalidate(flagsProvider);
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Failed to create flag')
                .toString()
            : 'Failed to create flag';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AdminTheme.kRed),
        );
      }
    }
  }

  Future<void> _toggleFlag(
    BuildContext context,
    WidgetRef ref,
    FeatureFlag flag,
    bool enabled,
  ) async {
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.post('/admin/flags', data: {
        'key':         flag.key,
        'value':       flag.value ?? true,
        'description': flag.description,
        'enabled':     enabled,
      });
      ref.invalidate(flagsProvider);
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Failed to update flag')
                .toString()
            : 'Failed to update flag';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AdminTheme.kRed),
        );
      }
    }
  }

  Future<void> _deleteFlag(
    BuildContext context,
    WidgetRef ref,
    String key,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Flag'),
        content: Text('Delete flag "$key"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AdminTheme.kRed,
              foregroundColor: Colors.white,
            ),
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
            backgroundColor: AdminTheme.kGreen,
          ),
        );
        ref.invalidate(flagsProvider);
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Failed to delete flag')
                .toString()
            : 'Failed to delete flag';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AdminTheme.kRed),
        );
      }
    }
  }
}

// ── Flag card ─────────────────────────────────────────────────────────────────

class _FlagCard extends StatelessWidget {
  final FeatureFlag flag;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _FlagCard({
    required this.flag,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AdminTheme.kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.kBorder),
      ),
      child: Row(
        children: [
          // Enabled indicator dot
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              color: flag.enabled ? AdminTheme.kGreen : AdminTheme.kBorder,
              shape: BoxShape.circle,
            ),
          ),
          // Key + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  flag.key,
                  style: const TextStyle(
                    color: AdminTheme.kText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                if (flag.description != null &&
                    flag.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    flag.description!,
                    style: const TextStyle(
                        color: AdminTheme.kMuted, fontSize: 12),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Text(
                    'Value: ${flag.value}',
                    style: const TextStyle(
                        color: AdminTheme.kMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          // Toggle
          Switch(
            value: flag.enabled,
            onChanged: onToggle,
          ),
          // Delete
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 18,
              color: AdminTheme.kMuted,
            ),
            tooltip: 'Delete flag',
            onPressed: onDelete,
            style: IconButton.styleFrom(
              hoverColor: AdminTheme.kRed.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
