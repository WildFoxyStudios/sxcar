import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class Webhook {
  final String id;
  final String name;
  final String url;
  final List<String> events;
  final String status;
  final String? lastFired;

  Webhook({
    required this.id,
    required this.name,
    required this.url,
    required this.events,
    required this.status,
    this.lastFired,
  });

  factory Webhook.fromJson(Map<String, dynamic> json) {
    final evts = (json['events'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return Webhook(
      id:        json['id']         as String? ?? '',
      name:      json['name']       as String? ?? '',
      url:       json['url']        as String? ?? '',
      events:    evts,
      status:    json['status']     as String? ?? '',
      lastFired: json['last_fired'] as String?,
    );
  }
}

final webhooksProvider = FutureProvider.autoDispose<List<Webhook>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/webhooks');
  final data = response.data as Map<String, dynamic>;
  final list = (data['webhooks'] as List<dynamic>?)
          ?.map((e) => Webhook.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class WebhooksScreen extends ConsumerWidget {
  const WebhooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(webhooksProvider);

    return AdminLayout(
      selectedIndex: 17,
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
              Text('Webhooks',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('External service integrations',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<List<Webhook>> async) {
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
      data: (webhooks) {
        if (webhooks.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.webhook, size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No webhooks configured.',
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
                itemCount: webhooks.length,
                itemBuilder: (_, i) =>
                    _WebhookRow(webhook: webhooks[i]),
              ),
            ),
            _tableFooter(webhooks.length),
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
          Expanded(flex: 3, child: _ColHeader('URL')),
          SizedBox(width: 100, child: _ColHeader('STATUS')),
          SizedBox(width: 170, child: _ColHeader('LAST FIRED')),
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
      child: Text('$count webhook(s)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }
}

class _WebhookRow extends StatelessWidget {
  final Webhook webhook;
  const _WebhookRow({required this.webhook});

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(webhook.name,
                    style: const TextStyle(
                        color: AdminTheme.kText, fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(webhook.events.join(', '),
                    style: const TextStyle(
                        color: AdminTheme.kMuted, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(webhook.url,
                style: const TextStyle(
                    color: AdminTheme.kMuted,
                    fontSize: 12,
                    fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 100,
            child: _Chip(webhook.status,
                webhook.status == 'active'
                    ? AdminTheme.kGreen
                    : AdminTheme.kMuted),
          ),
          SizedBox(
            width: 170,
            child: Text(_fmtDate(webhook.lastFired),
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

String _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso.length > 16 ? iso.substring(0, 16) : iso;
  }
}
