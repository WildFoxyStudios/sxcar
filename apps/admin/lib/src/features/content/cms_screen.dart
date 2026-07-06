import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class CmsContent {
  final String id;
  final String key;
  final String title;
  final String status;
  final String updatedAt;

  CmsContent({
    required this.id,
    required this.key,
    required this.title,
    required this.status,
    required this.updatedAt,
  });

  factory CmsContent.fromJson(Map<String, dynamic> json) {
    return CmsContent(
      id:        json['id']         as String? ?? '',
      key:       json['key']        as String? ?? '',
      title:     json['title']      as String? ?? '',
      status:    json['status']     as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

final cmsProvider = FutureProvider.autoDispose<List<CmsContent>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/cms');
  final data = response.data as Map<String, dynamic>;
  final list = (data['content'] as List<dynamic>?)
          ?.map((e) => CmsContent.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class CmsScreen extends ConsumerWidget {
  const CmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cmsProvider);

    return AdminLayout(
      selectedIndex: 11,
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
              Text('CMS Content',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Manage pages and content blocks',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Content'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref,
      AsyncValue<List<CmsContent>> async) {
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
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.article_outlined,
                    size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No CMS content found.',
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
                itemCount: items.length,
                itemBuilder: (_, i) =>
                    _CmsRow(item: items[i], ref: ref),
              ),
            ),
            _tableFooter(items.length),
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
          Expanded(flex: 2, child: _ColHeader('KEY')),
          Expanded(flex: 2, child: _ColHeader('TITLE')),
          SizedBox(width: 100, child: _ColHeader('STATUS')),
          SizedBox(width: 170, child: _ColHeader('UPDATED')),
          SizedBox(width: 120, child: _ColHeader('ACTION')),
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
      child: Text('$count item(s)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final keyController = TextEditingController();
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create CMS Content'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              style: const TextStyle(color: AdminTheme.kText),
              decoration: const InputDecoration(
                  labelText: 'Key', hintText: 'e.g. about_page'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              style: const TextStyle(color: AdminTheme.kText),
              decoration:
                  const InputDecoration(labelText: 'Title'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _create(context, ref, keyController.text,
                    titleController.text);
              },
              child: const Text('Create')),
        ],
      ),
    );
  }

  Future<void> _create(
      BuildContext context, WidgetRef ref, String key, String title) async {
    if (key.isEmpty) return;
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.post('/admin/cms', data: {
        'key': key,
        'title': title,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('CMS item "$key" created'),
            backgroundColor: AdminTheme.kGreen));
        ref.invalidate(cmsProvider);
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

class _CmsRow extends ConsumerWidget {
  final CmsContent item;
  final WidgetRef ref;

  const _CmsRow({required this.item, required this.ref});

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
            child: Text(item.key,
                style: const TextStyle(
                    color: AdminTheme.kText,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
          Expanded(
            flex: 2,
            child: Text(item.title,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13)),
          ),
          SizedBox(
            width: 100,
            child: _Chip(item.status, AdminTheme.kYellow),
          ),
          SizedBox(
            width: 170,
            child: Text(_fmtDate(item.updatedAt),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 120,
            child: Row(
              children: [
                _ActionBtn('Edit', AdminTheme.kYellow, () {}),
                const SizedBox(width: 6),
                _ActionBtn('Delete', AdminTheme.kRed, () =>
                    _delete(context, ref, item.id)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete CMS Item'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AdminTheme.kRed),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.delete('/admin/cms/$id');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('CMS item deleted'),
            backgroundColor: AdminTheme.kGreen));
        ref.invalidate(cmsProvider);
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Delete failed').toString()
            : 'Delete failed';
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
