import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class ApiKey {
  final String id;
  final String name;
  final String keyPreview;
  final String status;
  final String createdAt;

  ApiKey({
    required this.id,
    required this.name,
    required this.keyPreview,
    required this.status,
    required this.createdAt,
  });

  factory ApiKey.fromJson(Map<String, dynamic> json) {
    return ApiKey(
      id:         json['id']          as String? ?? '',
      name:       json['name']        as String? ?? '',
      keyPreview: json['key_preview'] as String? ?? '',
      status:     json['status']      as String? ?? '',
      createdAt:  json['created_at']  as String? ?? '',
    );
  }
}

final apiKeysProvider = FutureProvider.autoDispose<List<ApiKey>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/api-keys');
  final data = response.data as Map<String, dynamic>;
  final list = (data['keys'] as List<dynamic>?)
          ?.map((e) => ApiKey.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class ApiKeysScreen extends ConsumerWidget {
  const ApiKeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(apiKeysProvider);

    return AdminLayout(
      selectedIndex: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, ref),
          const Divider(height: 1),
          Expanded(child: _body(context, ref, async)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('API Keys',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Manage API access keys',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Key'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref,
      AsyncValue<List<ApiKey>> async) {
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
      data: (keys) {
        if (keys.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.vpn_key_off, size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No API keys found.',
                    style:
                        TextStyle(color: AdminTheme.kMuted, fontSize: 14)),
              ],
            ),
          );
        }
        return Column(
          children: [
            _tableHeader(),
            Expanded(
              child: ListView.builder(
                itemCount: keys.length,
                itemBuilder: (_, i) => _ApiKeyRow(apiKey: keys[i], ref: ref),
              ),
            ),
            _tableFooter(keys.length),
          ],
        );
      },
    );
  }

  Widget _tableHeader() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: AdminTheme.kSurface,
        border: Border(bottom: BorderSide(color: AdminTheme.kBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Row(
        children: [
          Expanded(flex: 2, child: _ColHeader('NAME')),
          Expanded(flex: 2, child: _ColHeader('KEY')),
          SizedBox(width: 100, child: _ColHeader('STATUS')),
          SizedBox(width: 170, child: _ColHeader('CREATED')),
          SizedBox(width: 80, child: _ColHeader('ACTION')),
        ],
      ),
    );
  }

  Widget _tableFooter(int count) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: AdminTheme.kSurface,
        border: Border(top: BorderSide(color: AdminTheme.kBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text('$count key(s)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create API Key'),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: AdminTheme.kText),
          decoration: const InputDecoration(
              labelText: 'Key Name', hintText: 'e.g. Production CI'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _create(context, ref, nameController.text);
              },
              child: const Text('Create')),
        ],
      ),
    );
  }

  Future<void> _create(
      BuildContext context, WidgetRef ref, String name) async {
    if (name.isEmpty) return;
    try {
      final client = ref.read(adminHttpClientProvider);
      final response = await client.dio
          .post('/admin/api-keys', data: {'name': name});
      if (context.mounted) {
        final fullKey = response.data is Map
            ? (response.data as Map)['key']?.toString() ?? ''
            : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                fullKey.isNotEmpty
                    ? 'Key created: $fullKey (copy now)'
                    : 'Key created',
                style: const TextStyle(fontSize: 13)),
            backgroundColor: AdminTheme.kGreen,
            duration: const Duration(seconds: 8)));
        ref.invalidate(apiKeysProvider);
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Create failed').toString()
            : 'Create failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg), backgroundColor: AdminTheme.kRed));
      }
    }
  }
}

class _ApiKeyRow extends ConsumerWidget {
  final ApiKey apiKey;
  final WidgetRef ref;

  const _ApiKeyRow({required this.apiKey, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 50,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminTheme.kBorder, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(apiKey.name,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text(apiKey.keyPreview,
                style: const TextStyle(
                    color: AdminTheme.kMuted,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
          SizedBox(
            width: 100,
            child: _Chip(apiKey.status,
                apiKey.status == 'active'
                    ? AdminTheme.kGreen
                    : AdminTheme.kMuted),
          ),
          SizedBox(
            width: 170,
            child: Text(_fmtDate(apiKey.createdAt),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 80,
            child: apiKey.status == 'active'
                ? _ActionBtn('Revoke', AdminTheme.kRed,
                    () => _revoke(context, ref, apiKey.id))
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Key'),
        content: const Text(
            'This will immediately invalidate this API key. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AdminTheme.kRed),
              child: const Text('Revoke')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.post('/admin/api-keys/$id/revoke');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Key revoked'),
            backgroundColor: AdminTheme.kGreen));
        ref.invalidate(apiKeysProvider);
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Revoke failed').toString()
            : 'Revoke failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg), backgroundColor: AdminTheme.kRed));
      }
    }
  }
}

class _ColHeader extends StatelessWidget {
  final String label;
  const _ColHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(label, style: AdminTheme.tableHeader),
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

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _ActionBtn(this.label, this.color, this.onPressed);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

String _fmtDate(String iso) {
  if (iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}
