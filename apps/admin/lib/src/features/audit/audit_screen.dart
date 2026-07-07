import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';
import '../../widgets/page_controls.dart';

const _pageSize = 50;

final _auditOffsetProvider = StateProvider.autoDispose<int>((ref) => 0);

class AuditEntry {
  final String id;
  final String actor;
  final String action;
  final String target;
  final String? justification;
  final String timestamp;

  AuditEntry({
    required this.id,
    required this.actor,
    required this.action,
    required this.target,
    this.justification,
    required this.timestamp,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      id:            json['id']            as String? ?? '',
      actor:         json['actor']         as String? ?? '',
      action:        json['action']        as String? ?? '',
      target:        json['target']        as String? ?? '',
      justification: json['justification'] as String?,
      timestamp:     json['timestamp']     as String? ?? '',
    );
  }
}

final auditProvider = FutureProvider.autoDispose<List<AuditEntry>>((ref) async {
  final offset = ref.watch(_auditOffsetProvider);
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/audit',
      queryParameters: {'limit': '$_pageSize', 'offset': '$offset'});
  final data = response.data as Map<String, dynamic>;
  final list = (data['entries'] as List<dynamic>?)
          ?.map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(auditProvider);

    return AdminLayout(
      selectedIndex: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(child: _body(async, ref)),
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
              Text('Audit Log',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Read-only trail of admin actions',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<List<AuditEntry>> async, WidgetRef ref) {
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
      data: (entries) {
        if (entries.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No audit entries found.',
                    style:
                        TextStyle(color: AdminTheme.kMuted, fontSize: 14)),
              ],
            ),
          );
        }
        final currentPage = ref.watch(_auditOffsetProvider) ~/ _pageSize;
        final totalPages = entries.length < _pageSize
            ? currentPage + 1
            : currentPage + 2;
        return Column(
          children: [
            _tableHeader(),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (_, i) => _AuditRow(entry: entries[i]),
              ),
            ),
            PageControls(
              currentPage: currentPage,
              totalPages: totalPages,
              onPageChanged: (page) =>
                  ref.read(_auditOffsetProvider.notifier).state =
                      page * _pageSize,
            ),
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
          Expanded(flex: 2, child: _ColHeader('ACTOR')),
          SizedBox(width: 100, child: _ColHeader('ACTION')),
          Expanded(flex: 3, child: _ColHeader('TARGET')),
          SizedBox(width: 170, child: _ColHeader('TIMESTAMP')),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final AuditEntry entry;
  const _AuditRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminTheme.kBorder, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(entry.actor,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13)),
          ),
          SizedBox(
            width: 100,
            child: _Chip(entry.action, AdminTheme.kYellow),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.target,
                    style: const TextStyle(
                        color: AdminTheme.kText, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
                if (entry.justification != null &&
                    entry.justification!.isNotEmpty)
                  Text(entry.justification!,
                      style: const TextStyle(
                          color: AdminTheme.kMuted, fontSize: 11)),
              ],
            ),
          ),
          SizedBox(
            width: 170,
            child: Text(_fmtTs(entry.timestamp),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
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

String _fmtTs(String iso) {
  if (iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso.length > 16 ? iso.substring(0, 16) : iso;
  }
}
