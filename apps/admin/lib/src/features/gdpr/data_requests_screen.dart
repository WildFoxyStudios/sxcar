import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class DataRequest {
  final String id;
  final String userId;
  final String type;
  final String status;
  final String createdAt;

  DataRequest({
    required this.id,
    required this.userId,
    required this.type,
    required this.status,
    required this.createdAt,
  });

  factory DataRequest.fromJson(Map<String, dynamic> json) {
    return DataRequest(
      id:        json['id']         as String? ?? '',
      userId:    json['user_id']    as String? ?? '',
      type:      json['type']       as String? ?? '',
      status:    json['status']     as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

final dataRequestsProvider =
    FutureProvider.autoDispose<List<DataRequest>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/gdpr/data-requests',
      queryParameters: {'status': 'pending', 'limit': '50', 'offset': '0'});
  final data = response.data as Map<String, dynamic>;
  final list = (data['requests'] as List<dynamic>?)
          ?.map((e) => DataRequest.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class DataRequestsScreen extends ConsumerWidget {
  const DataRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dataRequestsProvider);

    return AdminLayout(
      selectedIndex: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const Divider(height: 1),
          Expanded(child: _body(context, ref, async)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GDPR Data Requests',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Manage data export and deletion requests',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(
      BuildContext context, WidgetRef ref, AsyncValue<List<DataRequest>> async) {
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
      data: (requests) {
        if (requests.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 40, color: AdminTheme.kGreen),
                SizedBox(height: 12),
                Text('No pending data requests.',
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
                itemCount: requests.length,
                itemBuilder: (_, i) =>
                    _RequestRow(request: requests[i], ref: ref),
              ),
            ),
            _tableFooter(requests.length),
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
          Expanded(flex: 2, child: _ColHeader('USER ID')),
          SizedBox(width: 100, child: _ColHeader('TYPE')),
          SizedBox(width: 100, child: _ColHeader('STATUS')),
          SizedBox(width: 170, child: _ColHeader('CREATED')),
          SizedBox(width: 140, child: _ColHeader('ACTION')),
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
      child: Text('$count request(s)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }
}

class _RequestRow extends ConsumerWidget {
  final DataRequest request;
  final WidgetRef ref;

  const _RequestRow({required this.request, required this.ref});

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
            child: Text(request.userId.length > 12
                ? '${request.userId.substring(0, 12)}…'
                : request.userId,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13)),
          ),
          SizedBox(
            width: 100,
            child: _Chip(request.type == 'export' ? 'Export' : 'Delete',
                request.type == 'export'
                    ? AdminTheme.kBlue
                    : AdminTheme.kOrange),
          ),
          SizedBox(
            width: 100,
            child: _Chip(request.status, AdminTheme.kYellow),
          ),
          SizedBox(
            width: 170,
            child: Text(_fmtDate(request.createdAt),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 140,
            child: Row(
              children: [
                _ActionBtn(
                    label: 'Approve',
                    color: AdminTheme.kGreen,
                    onPressed: () => _resolve(context, request.id, 'approved')),
                const SizedBox(width: 6),
                _ActionBtn(
                    label: 'Reject',
                    color: AdminTheme.kRed,
                    onPressed: () => _resolve(context, request.id, 'rejected')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context, String id, String status) async {
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.post('/admin/gdpr/data-requests/$id/resolve',
          data: {'status': status});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Request $status'),
            backgroundColor: AdminTheme.kGreen));
        ref.invalidate(dataRequestsProvider);
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
      child: Text(label,
          style: AdminTheme.tableHeader),
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
  const _ActionBtn(
      {required this.label, required this.color, required this.onPressed});

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
