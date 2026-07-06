import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class LegalDoc {
  final String id;
  final String title;
  final String version;
  final String effectiveDate;
  final String status;

  LegalDoc({
    required this.id,
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.status,
  });

  factory LegalDoc.fromJson(Map<String, dynamic> json) {
    return LegalDoc(
      id:            json['id']             as String? ?? '',
      title:         json['title']          as String? ?? '',
      version:       json['version']        as String? ?? '',
      effectiveDate: json['effective_date'] as String? ?? '',
      status:        json['status']         as String? ?? '',
    );
  }
}

final legalDocsProvider =
    FutureProvider.autoDispose<List<LegalDoc>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/legal-docs');
  final data = response.data as Map<String, dynamic>;
  final list = (data['documents'] as List<dynamic>?)
          ?.map((e) => LegalDoc.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class LegalDocsScreen extends ConsumerWidget {
  const LegalDocsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(legalDocsProvider);

    return AdminLayout(
      selectedIndex: 12,
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
              Text('Legal Documents',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Terms, privacy policy, and other legal docs',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _showCreateDialog(context, ref),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Version'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref,
      AsyncValue<List<LegalDoc>> async) {
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
      data: (docs) {
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.gavel, size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No legal documents found.',
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
                itemCount: docs.length,
                itemBuilder: (_, i) => _DocRow(doc: docs[i]),
              ),
            ),
            _tableFooter(docs.length),
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
          Expanded(flex: 2, child: _ColHeader('TITLE')),
          SizedBox(width: 80, child: _ColHeader('VERSION')),
          SizedBox(width: 130, child: _ColHeader('EFFECTIVE')),
          SizedBox(width: 100, child: _ColHeader('STATUS')),
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
      child: Text('$count document(s)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final versionController = TextEditingController();
    final effectiveController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Legal Document Version'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: AdminTheme.kText),
              decoration:
                  const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: versionController,
              style: const TextStyle(color: AdminTheme.kText),
              decoration:
                  const InputDecoration(labelText: 'Version'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: effectiveController,
              style: const TextStyle(color: AdminTheme.kText),
              decoration: const InputDecoration(
                  labelText: 'Effective Date', hintText: 'YYYY-MM-DD'),
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
                _create(context, ref, titleController.text,
                    versionController.text, effectiveController.text);
              },
              child: const Text('Create')),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref, String title,
      String version, String effectiveDate) async {
    if (title.isEmpty) return;
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.post('/admin/legal-docs', data: {
        'title': title,
        'version': version,
        'effective_date': effectiveDate,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Document "$title" created'),
            backgroundColor: AdminTheme.kGreen));
        ref.invalidate(legalDocsProvider);
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

class _DocRow extends StatelessWidget {
  final LegalDoc doc;
  const _DocRow({required this.doc});

  @override
  Widget build(BuildContext context) {
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
            child: Text(doc.title,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13)),
          ),
          SizedBox(
            width: 80,
            child: Text(doc.version,
                style: const TextStyle(
                    color: AdminTheme.kMuted,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
          SizedBox(
            width: 130,
            child: Text(_fmtDate(doc.effectiveDate),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 100,
            child: _Chip(doc.status,
                doc.status == 'active'
                    ? AdminTheme.kGreen
                    : AdminTheme.kYellow),
          ),
        ],
      ),
    );
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

String _fmtDate(String iso) {
  if (iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}
