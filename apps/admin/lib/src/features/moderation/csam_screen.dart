import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';
import '../../widgets/page_controls.dart';

const _pageSize = 50;

final _csamOffsetProvider = StateProvider.autoDispose<int>((ref) => 0);

final csamProvider = FutureProvider.autoDispose<List<CsamItem>>((ref) async {
  final offset = ref.watch(_csamOffsetProvider);
  final client = ref.read(adminHttpClientProvider);
  final response =
      await client.dio.get('/admin/csam', queryParameters: {'limit': '$_pageSize', 'offset': '$offset'});
  final data = response.data as Map<String, dynamic>;
  final list = (data['hits'] as List<dynamic>?)
          ?.map((e) => CsamItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});
  final String id;
  final String contentHash;
  final String matchedBy;
  final String severity;
  final String createdAt;
  final String status;

  CsamItem({
    required this.id,
    required this.contentHash,
    required this.matchedBy,
    required this.severity,
    required this.createdAt,
    required this.status,
  });

  factory CsamItem.fromJson(Map<String, dynamic> json) {
    return CsamItem(
      id:          json['id']           as String? ?? '',
      contentHash: json['content_hash'] as String? ?? '',
      matchedBy:   json['matched_by']   as String? ?? '',
      severity:    json['severity']     as String? ?? '',
      createdAt:   json['created_at']   as String? ?? '',
      status:      json['status']       as String? ?? 'open',
    );
  }
}

class CsamsScreen extends ConsumerWidget {
  const CsamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(csamProvider);

    return AdminLayout(
      selectedIndex: 6,
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
              Text('CSAM Hash Queue',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Content hash matches awaiting review',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(
      BuildContext context, WidgetRef ref, AsyncValue<List<CsamItem>> async) {
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
                Icon(Icons.verified_outlined,
                    size: 40, color: AdminTheme.kGreen),
                SizedBox(height: 12),
                Text('No CSAM hits.',
                    style:
                        TextStyle(color: AdminTheme.kMuted, fontSize: 14)),
              ],
            ),
          );
        }
        final currentPage = ref.watch(_csamOffsetProvider) ~/ _pageSize;
        final totalPages = items.length < _pageSize
            ? currentPage + 1
            : currentPage + 2;
        return Column(
          children: [
            _tableHeader(),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (_, i) => _CsamRow(
                    item: items[i],
                    onReviewed: () => _act(context, ref, items[i].id, 'reviewed'),
                    onEscalate: () => _act(context, ref, items[i].id, 'escalated')),
              ),
            ),
            PageControls(
              currentPage: currentPage,
              totalPages: totalPages,
              onPageChanged: (page) =>
                  ref.read(_csamOffsetProvider.notifier).state =
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
          Expanded(flex: 3, child: _ColHeader('CONTENT HASH')),
          SizedBox(width: 120, child: _ColHeader('MATCHED BY')),
          SizedBox(width: 80, child: _ColHeader('SEVERITY')),
          SizedBox(width: 100, child: _ColHeader('STATUS')),
          SizedBox(width: 170, child: _ColHeader('CREATED')),
          SizedBox(width: 140, child: _ColHeader('ACTION')),
        ],
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, String id, String action) async {
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.post('/admin/csam/$id/$action');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Hit ${action}ed'),
            backgroundColor: AdminTheme.kGreen));
        ref.invalidate(csamProvider);
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Action failed').toString()
            : 'Action failed';
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

class _CsamRow extends StatelessWidget {
  final CsamItem item;
  final VoidCallback onReviewed;
  final VoidCallback onEscalate;

  const _CsamRow({
    required this.item,
    required this.onReviewed,
    required this.onEscalate,
  });

  @override
  Widget build(BuildContext context) {
    final severityColor = switch (item.severity) {
      'high' => AdminTheme.kRed,
      'medium' => AdminTheme.kOrange,
      _ => AdminTheme.kYellow,
    };

    return Container(
      height: 50,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminTheme.kBorder, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
                item.contentHash.length > 16
                    ? '${item.contentHash.substring(0, 16)}…'
                    : item.contentHash,
                style: const TextStyle(
                    color: AdminTheme.kText,
                    fontSize: 13,
                    fontFamily: 'monospace')),
          ),
          SizedBox(
            width: 120,
            child: Text(item.matchedBy,
                style: const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 80,
            child: _Chip(item.severity, severityColor),
          ),
          SizedBox(
            width: 100,
            child: _Chip(item.status, AdminTheme.kMuted),
          ),
          SizedBox(
            width: 170,
            child: Text(_fmtDate(item.createdAt),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 140,
            child: Row(
              children: [
                _ActionBtn('Reviewed', AdminTheme.kGreen, onReviewed),
                const SizedBox(width: 6),
                _ActionBtn('Escalate', AdminTheme.kOrange, onEscalate),
              ],
            ),
          ),
        ],
      ),
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
