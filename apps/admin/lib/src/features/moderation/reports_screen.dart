import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      id: json['id'] as String? ?? '',
      reporterId: json['reporter_id'] as String?,
      targetUserId: json['target_user_id'] as String?,
      targetKind: json['target_kind'] as String?,
      targetId: json['target_id'] as String?,
      reason: json['reason'] as String? ?? '',
      status: json['status'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      resolvedAt: json['resolved_at'] as String?,
    );
  }
}

final reportsProvider = FutureProvider.autoDispose<List<ReportItem>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/reports', queryParameters: {
    'status': 'open',
    'limit': '50',
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reports',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: reportsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Failed to load reports: $error'),
                    ],
                  ),
                ),
                data: (reports) => reports.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 64, color: Colors.green),
                            SizedBox(height: 16),
                            Text('No open reports.'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: reports.length,
                        itemBuilder: (context, index) {
                          final report = reports[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.flag),
                              ),
                              title: Text(report.reason),
                              subtitle: Text(
                                'Target: ${report.targetUserId?.substring(0, 8) ?? "N/A"}... | ${report.createdAt}',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showReportDialog(context, ref, report),
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

  void _showReportDialog(BuildContext context, WidgetRef ref, ReportItem report) {
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
                Text('Report ID: ${report.id.substring(0, 8)}...'),
                Text('Reason: ${report.reason}'),
                Text('Target: ${report.targetUserId}'),
                Text('Status: ${report.status}'),
                const Divider(),
                DropdownButtonFormField<String>(
                  initialValue: selectedAction,
                  decoration: const InputDecoration(
                    labelText: 'Action',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'warn', child: Text('Warn')),
                    DropdownMenuItem(value: 'suspend', child: Text('Suspend')),
                    DropdownMenuItem(value: 'ban', child: Text('Ban')),
                    DropdownMenuItem(value: 'clear', child: Text('Clear')),
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
              onPressed: () => _resolveReport(context, ref, report.id, 'dismissed', 'clear', noteController.text),
              child: const Text('Dismiss'),
            ),
            FilledButton(
              onPressed: () => _resolveReport(context, ref, report.id, 'actioned', selectedAction, noteController.text),
              child: const Text('Resolve'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resolveReport(
      BuildContext context, WidgetRef ref, String reportId,
      String resolution, String action, String note) async {
    Navigator.of(context).pop();
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.post('/admin/reports/$reportId/resolve', data: {
        'resolution': resolution,
        'action': action,
        'note': note.isEmpty ? null : note,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report ${resolution}ed successfully'),
            backgroundColor: Colors.green,
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
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }
}
