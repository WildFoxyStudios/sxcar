import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class Campaign {
  final String id;
  final String name;
  final String type;
  final String status;
  final String? sentAt;
  final Map<String, dynamic>? stats;

  Campaign({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    this.sentAt,
    this.stats,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) {
    return Campaign(
      id:     json['id']     as String? ?? '',
      name:   json['name']   as String? ?? '',
      type:   json['type']   as String? ?? '',
      status: json['status'] as String? ?? '',
      sentAt: json['sent_at'] as String?,
      stats:  json['stats']  as Map<String, dynamic>?,
    );
  }
}

final campaignsProvider =
    FutureProvider.autoDispose<List<Campaign>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/campaigns');
  final data = response.data as Map<String, dynamic>;
  final list = (data['campaigns'] as List<dynamic>?)
          ?.map((e) => Campaign.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(campaignsProvider);

    return AdminLayout(
      selectedIndex: 13,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(child: _body(async)),
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
              Text('Campaigns',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Push and email campaigns',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<List<Campaign>> async) {
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
      data: (campaigns) {
        if (campaigns.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.campaign_outlined,
                    size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No campaigns found.',
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
                itemCount: campaigns.length,
                itemBuilder: (_, i) =>
                    _CampaignRow(campaign: campaigns[i]),
              ),
            ),
            _tableFooter(campaigns.length),
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
          SizedBox(width: 100, child: _ColHeader('STATUS')),
          SizedBox(width: 170, child: _ColHeader('SENT')),
          Expanded(child: _ColHeader('STATS')),
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
      child: Text('$count campaign(s)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }
}

class _CampaignRow extends StatelessWidget {
  final Campaign campaign;
  const _CampaignRow({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (campaign.status) {
      'sent' => AdminTheme.kGreen,
      'scheduled' => AdminTheme.kBlue,
      'draft' => AdminTheme.kMuted,
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
            flex: 2,
            child: Text(campaign.name,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13)),
          ),
          SizedBox(
            width: 90,
            child: Text(campaign.type,
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 100,
            child: _Chip(campaign.status, statusColor),
          ),
          SizedBox(
            width: 170,
            child: Text(_fmtDate(campaign.sentAt),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          Expanded(
            child: campaign.stats != null
                ? Text(
                    campaign.stats!.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join(', '),
                    style: const TextStyle(
                        color: AdminTheme.kMuted, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  )
                : const Text('—',
                    style:
                        TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
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

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}
