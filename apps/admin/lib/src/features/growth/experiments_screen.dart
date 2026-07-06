import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class Experiment {
  final String id;
  final String name;
  final String status;
  final List<String> variants;
  final String? startDate;
  final String? endDate;

  Experiment({
    required this.id,
    required this.name,
    required this.status,
    required this.variants,
    this.startDate,
    this.endDate,
  });

  factory Experiment.fromJson(Map<String, dynamic> json) {
    final vars = (json['variants'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return Experiment(
      id:       json['id']        as String? ?? '',
      name:     json['name']      as String? ?? '',
      status:   json['status']    as String? ?? 'draft',
      variants: vars,
      startDate: json['start_date'] as String?,
      endDate:   json['end_date']   as String?,
    );
  }
}

final experimentsProvider =
    FutureProvider.autoDispose<List<Experiment>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/experiments');
  final data = response.data as Map<String, dynamic>;
  final list = (data['experiments'] as List<dynamic>?)
          ?.map((e) => Experiment.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class ExperimentsScreen extends ConsumerWidget {
  const ExperimentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(experimentsProvider);

    return AdminLayout(
      selectedIndex: 9,
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
              Text('A/B Experiments',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Active and past experiments',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(AsyncValue<List<Experiment>> async) {
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
      data: (experiments) {
        if (experiments.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.science_outlined,
                    size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No experiments found.',
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
                itemCount: experiments.length,
                itemBuilder: (_, i) =>
                    _ExperimentRow(experiment: experiments[i]),
              ),
            ),
            _tableFooter(experiments.length),
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
          SizedBox(width: 100, child: _ColHeader('STATUS')),
          Expanded(flex: 2, child: _ColHeader('VARIANTS')),
          SizedBox(width: 130, child: _ColHeader('START')),
          SizedBox(width: 130, child: _ColHeader('END')),
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
      child: Text('$count experiment(s)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }
}

class _ExperimentRow extends StatelessWidget {
  final Experiment experiment;
  const _ExperimentRow({required this.experiment});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (experiment.status) {
      'running' => AdminTheme.kGreen,
      'paused' => AdminTheme.kOrange,
      'stopped' => AdminTheme.kRed,
      _ => AdminTheme.kMuted,
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
            child: Text(experiment.name,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13)),
          ),
          SizedBox(
            width: 100,
            child: _Chip(experiment.status, statusColor),
          ),
          Expanded(
            flex: 2,
            child: Text(experiment.variants.join(', '),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 130,
            child: Text(_fmtDate(experiment.startDate),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 130,
            child: Text(_fmtDate(experiment.endDate),
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
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso.length > 10 ? iso.substring(0, 10) : iso;
  }
}
