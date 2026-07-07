import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class TemplateItem {
  final String id;
  final String name;
  final String type;
  final String subject;
  final String body;
  final String updatedAt;

  TemplateItem({
    required this.id,
    required this.name,
    required this.type,
    required this.subject,
    required this.body,
    required this.updatedAt,
  });

  factory TemplateItem.fromJson(Map<String, dynamic> json) {
    return TemplateItem(
      id:        json['id']         as String? ?? '',
      name:      json['name']       as String? ?? '',
      type:      json['type']       as String? ?? '',
      subject:   json['subject']    as String? ?? '',
      body:      json['body']       as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

final templatesProvider =
    FutureProvider.autoDispose<List<TemplateItem>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/templates');
  final data = response.data as Map<String, dynamic>;
  final list = (data['templates'] as List<dynamic>?)
          ?.map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(templatesProvider);

    return AdminLayout(
      selectedIndex: 14,
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
              Text('Notification Templates',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Manage push and email templates',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref,
      AsyncValue<List<TemplateItem>> async) {
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
                Icon(Icons.email_outlined,
                    size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No templates found.',
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
                    _TemplateRow(item: items[i], ref: ref),
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
          Expanded(flex: 2, child: _ColHeader('NAME')),
          SizedBox(width: 90, child: _ColHeader('TYPE')),
          Expanded(flex: 2, child: _ColHeader('SUBJECT')),
          SizedBox(width: 170, child: _ColHeader('UPDATED')),
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
      child: Text('$count template(s)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }
}

class _TemplateRow extends ConsumerWidget {
  final TemplateItem item;
  final WidgetRef ref;

  const _TemplateRow({required this.item, required this.ref});

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
            child: Text(item.name,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13)),
          ),
          SizedBox(
            width: 90,
            child: Text(item.type,
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: Text(item.subject,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 170,
            child: Text(_fmtDate(item.updatedAt),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 80,
            child: _ActionBtn('Edit', AdminTheme.kYellow,
                () => _showEditDialog(context, ref, item)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, WidgetRef ref, TemplateItem item) {
    final subjectController = TextEditingController(text: item.subject);
    final bodyController = TextEditingController(text: item.body);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Name: ${item.name}',
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 13)),
            Text('Type: ${item.type}',
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: subjectController,
              style: const TextStyle(color: AdminTheme.kText),
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyController,
              style: const TextStyle(color: AdminTheme.kText),
              decoration: const InputDecoration(
                  labelText: 'Body', alignLabelWithHint: true),
              maxLines: 6,
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
                _save(context, ref, item.id, subjectController.text,
                    bodyController.text);
              },
              child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref, String id,
      String subject, String body) async {
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.put('/admin/templates/$id',
          data: {'subject': subject, 'body': body});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Template updated'),
            backgroundColor: AdminTheme.kGreen));
        ref.invalidate(templatesProvider);
      }
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
