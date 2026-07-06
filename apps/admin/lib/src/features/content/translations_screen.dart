import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class TranslationItem {
  final String key;
  final String locale;
  final String value;

  TranslationItem({
    required this.key,
    required this.locale,
    required this.value,
  });

  factory TranslationItem.fromJson(Map<String, dynamic> json) {
    return TranslationItem(
      key:    json['key']    as String? ?? '',
      locale: json['locale'] as String? ?? '',
      value:  json['value']  as String? ?? '',
    );
  }
}

final translationsProvider =
    FutureProvider.autoDispose<List<TranslationItem>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/i18n');
  final data = response.data as Map<String, dynamic>;
  final list = (data['translations'] as List<dynamic>?)
          ?.map((e) => TranslationItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class TranslationsScreen extends ConsumerWidget {
  const TranslationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(translationsProvider);

    return AdminLayout(
      selectedIndex: 10,
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
              Text('Translations',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('i18n key-value editor',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref,
      AsyncValue<List<TranslationItem>> async) {
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
                Icon(Icons.translate, size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No translations found.',
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
                    _TranslationRow(item: items[i], ref: ref),
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
          SizedBox(width: 80, child: _ColHeader('LOCALE')),
          Expanded(flex: 3, child: _ColHeader('VALUE')),
          SizedBox(width: 100, child: _ColHeader('ACTION')),
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
      child: Text('$count translation(s)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }
}

class _TranslationRow extends ConsumerWidget {
  final TranslationItem item;
  final WidgetRef ref;

  const _TranslationRow({required this.item, required this.ref});

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
          SizedBox(
            width: 80,
            child: Text(item.locale,
                style: const TextStyle(
                    color: AdminTheme.kAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 3,
            child: Text(item.value,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 100,
            child: _ActionBtn('Edit', AdminTheme.kYellow,
                () => _showEditDialog(context, ref, item)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, WidgetRef ref, TranslationItem item) {
    final valueController = TextEditingController(text: item.value);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Translation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Key: ${item.key}',
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 13)),
            Text('Locale: ${item.locale}',
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: valueController,
              style: const TextStyle(color: AdminTheme.kText),
              decoration: const InputDecoration(labelText: 'Value'),
              maxLines: 3,
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
                _save(context, ref, item.key, item.locale,
                    valueController.text);
              },
              child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _save(
      BuildContext context, WidgetRef ref, String key, String locale, String value) async {
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.put('/admin/i18n/$locale/$key', data: {'value': value});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Translation updated'),
            backgroundColor: AdminTheme.kGreen));
        ref.invalidate(translationsProvider);
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
