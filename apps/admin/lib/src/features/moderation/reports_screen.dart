import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class ReportItem {
  final String id;
  final String? reporterId;
  final String? targetUserId;
  final String? targetKind;
  final String? targetId;
  final String reason;
  final String status;
  final String createdAt;
  final String? resolvedAt;

  ReportItem({
    required this.id,
    this.reporterId,
    this.targetUserId,
    this.targetKind,
    this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  factory ReportItem.fromJson(Map<String, dynamic> json) {
    return ReportItem(
      id:           json['id']             as String? ?? '',
      reporterId:   json['reporter_id']    as String?,
      targetUserId: json['target_user_id'] as String?,
      targetKind:   json['target_kind']    as String?,
      targetId:     json['target_id']      as String?,
      reason:       json['reason']         as String? ?? '',
      status:       json['status']         as String? ?? '',
      createdAt:    json['created_at']     as String? ?? '',
      resolvedAt:   json['resolved_at']    as String?,
    );
  }
}

final reportsProvider = FutureProvider.autoDispose<List<ReportItem>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/reports', queryParameters: {
    'status': 'open',
    'limit':  '50',
    'offset': '0',
  });
  final data = response.data as Map<String, dynamic>;
  final reportsList = (data['reports'] as List<dynamic>?)
          ?.map((e) => ReportItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return reportsList;
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(reportsProvider);

    return AdminLayout(
      selectedIndex: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Moderation Queue',
                      style: TextStyle(
                        color: AdminTheme.kText,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Open reports awaiting review',
                      style: TextStyle(color: AdminTheme.kMuted, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                reportsAsync.maybeWhen(
                  data: (reports) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AdminTheme.kRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AdminTheme.kRed.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '${reports.length} open',
                      style: const TextStyle(
                        color: AdminTheme.kRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Queue ────────────────────────────────────────────────────────
          Expanded(
            child: reportsAsync.when(
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
                      'Failed to load reports: $error',
                      style: const TextStyle(
                          color: AdminTheme.kMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              data: (reports) => reports.isEmpty
                  ? const _EmptyQueue()
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: reports.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _ReportCard(
                        report: reports[i],
                        onResolve: (resolution, action, note) =>
                            _resolveReport(
                          context,
                          ref,
                          reports[i].id,
                          resolution,
                          action,
                          note,
                        ),
                        onShowDetail: () =>
                            _showReportDialog(context, ref, reports[i]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDialog(
      BuildContext context, WidgetRef ref, ReportItem report) {
    final noteController = TextEditingController();
    String selectedAction = 'warn';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Review Report'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogInfo('Report ID', '${report.id.substring(0, 8)}…'),
                const SizedBox(height: 4),
                _dialogInfo('Reason', report.reason),
                const SizedBox(height: 4),
                _dialogInfo('Target',
                    report.targetUserId ?? 'N/A'),
                const SizedBox(height: 4),
                _dialogInfo('Status', report.status),
                const Divider(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedAction,
                  decoration: const InputDecoration(
                    labelText: 'Action',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'warn',    child: Text('Warn')),
                    DropdownMenuItem(value: 'suspend', child: Text('Suspend')),
                    DropdownMenuItem(value: 'ban',     child: Text('Ban')),
                    DropdownMenuItem(value: 'clear',   child: Text('Clear')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() => selectedAction = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
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
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _resolveReport(context, ref, report.id, 'dismissed', 'clear',
                    noteController.text);
              },
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _resolveReport(context, ref, report.id, 'actioned',
                    selectedAction, noteController.text);
              },
              child: const Text('Resolve'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogInfo(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
                color: AdminTheme.kMuted, fontSize: 13),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
                color: AdminTheme.kText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveReport(
    BuildContext context,
    WidgetRef ref,
    String reportId,
    String resolution,
    String action,
    String note,
  ) async {
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.post('/admin/reports/$reportId/resolve', data: {
        'resolution': resolution,
        'action':     action,
        'note':       note.isEmpty ? null : note,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report ${resolution}ed'),
            backgroundColor: AdminTheme.kGreen,
          ),
        );
        ref.invalidate(reportsProvider);
      }
    } on DioException catch (e) {
      if (context.mounted) {
        final msg = e.response?.data is Map
            ? ((e.response!.data as Map)['error'] ?? 'Action failed').toString()
            : 'Action failed. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AdminTheme.kRed,
          ),
        );
      }
    }
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: AdminTheme.kGreen),
          SizedBox(height: 16),
          Text(
            'Queue is clear',
            style: TextStyle(
              color: AdminTheme.kText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'No open reports at this time.',
            style: TextStyle(color: AdminTheme.kMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Report card ───────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final ReportItem report;
  final void Function(String resolution, String action, String note) onResolve;
  final VoidCallback onShowDetail;

  const _ReportCard({
    required this.report,
    required this.onResolve,
    required this.onShowDetail,
  });

  @override
  Widget build(BuildContext context) {
    final targetShort = report.targetUserId != null &&
            report.targetUserId!.length >= 8
        ? '${report.targetUserId!.substring(0, 8)}…'
        : (report.targetUserId ?? 'N/A');

    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AdminTheme.kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: reason + status chip ───────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2, right: 10),
                  child: Icon(
                    Icons.flag,
                    size: 16,
                    color: AdminTheme.kOrange,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.reason,
                        style: const TextStyle(
                          color: AdminTheme.kText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline,
                            size: 12,
                            color: AdminTheme.kMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Target: $targetShort',
                            style: const TextStyle(
                              color: AdminTheme.kMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Icon(
                            Icons.schedule,
                            size: 12,
                            color: AdminTheme.kMuted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _fmtDate(report.createdAt),
                              style: const TextStyle(
                                color: AdminTheme.kMuted,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _StatusChip(status: report.status),
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),

          // ── Action row ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              children: [
                // Dismiss
                _ActionBtn(
                  label: 'Dismiss',
                  icon: Icons.close,
                  fgColor: AdminTheme.kMuted,
                  borderColor: AdminTheme.kBorder,
                  onPressed: () => onResolve('dismissed', 'clear', ''),
                ),
                const SizedBox(width: 8),
                // Warn
                _ActionBtn(
                  label: 'Warn',
                  icon: Icons.warning_amber_outlined,
                  fgColor: AdminTheme.kOrange,
                  borderColor: AdminTheme.kOrange.withValues(alpha: 0.4),
                  onPressed: () => onResolve('actioned', 'warn', ''),
                ),
                const SizedBox(width: 8),
                // Ban (opens detail dialog for reason)
                _ActionBtn(
                  label: 'Ban',
                  icon: Icons.block,
                  fgColor: AdminTheme.kRed,
                  borderColor: AdminTheme.kRed.withValues(alpha: 0.4),
                  onPressed: onShowDetail,
                ),
                const Spacer(),
                // Detail button
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AdminTheme.kMuted,
                    textStyle:
                        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: onShowDetail,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Details'),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}';
    } catch (_) {
      return iso.length > 16 ? iso.substring(0, 16) : iso;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color fg, String label) = switch (status) {
      'open'       => (AdminTheme.kOrange, 'Open'),
      'actioned'   => (AdminTheme.kGreen,  'Actioned'),
      'dismissed'  => (AdminTheme.kMuted,  'Dismissed'),
      _            => (AdminTheme.kMuted,  status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color fgColor;
  final Color borderColor;
  final VoidCallback onPressed;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.fgColor,
    required this.borderColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 13),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: fgColor,
        side: BorderSide(color: borderColor),
        textStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onPressed,
    );
  }
}
