import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/admin_theme.dart';
import '../../widgets/admin_http_client.dart';
import '../../widgets/admin_layout.dart';

class CountryConfig {
  final String code;
  final String name;
  final List<String> features;
  final bool safetyOverride;

  CountryConfig({
    required this.code,
    required this.name,
    required this.features,
    required this.safetyOverride,
  });

  factory CountryConfig.fromJson(Map<String, dynamic> json) {
    final feats = (json['features'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return CountryConfig(
      code:           json['code']            as String? ?? '',
      name:           json['name']            as String? ?? '',
      features:       feats,
      safetyOverride: json['safety_override'] as bool? ?? false,
    );
  }
}

final countriesProvider =
    FutureProvider.autoDispose<List<CountryConfig>>((ref) async {
  final client = ref.read(adminHttpClientProvider);
  final response = await client.dio.get('/admin/countries');
  final data = response.data as Map<String, dynamic>;
  final list = (data['countries'] as List<dynamic>?)
          ?.map((e) => CountryConfig.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [];
  return list;
});

class CountriesScreen extends ConsumerWidget {
  const CountriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(countriesProvider);

    return AdminLayout(
      selectedIndex: 8,
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
              Text('Countries',
                  style: TextStyle(
                      color: AdminTheme.kText,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Per-country feature configuration',
                  style: TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref,
      AsyncValue<List<CountryConfig>> async) {
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
      data: (countries) {
        if (countries.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.public_off, size: 40, color: AdminTheme.kMuted),
                SizedBox(height: 12),
                Text('No countries configured.',
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
                itemCount: countries.length,
                itemBuilder: (_, i) =>
                    _CountryRow(country: countries[i], ref: ref),
              ),
            ),
            _tableFooter(countries.length),
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
          SizedBox(width: 50, child: _ColHeader('CODE')),
          Expanded(flex: 2, child: _ColHeader('NAME')),
          Expanded(flex: 3, child: _ColHeader('FEATURES')),
          SizedBox(width: 120, child: _ColHeader('SAFETY')),
          SizedBox(width: 80, child: _ColHeader('ACTION')),
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
      child: Text('$count country(ies)',
          style:
              const TextStyle(color: AdminTheme.kMuted, fontSize: 11)),
    );
  }
}

class _CountryRow extends ConsumerWidget {
  final CountryConfig country;
  final WidgetRef ref;

  const _CountryRow({required this.country, required this.ref});

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
          const SizedBox(width: 50),
          SizedBox(
            width: 50,
            child: Text(country.code.toUpperCase(),
                style: const TextStyle(
                    color: AdminTheme.kAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace')),
          ),
          Expanded(
            flex: 2,
            child: Text(country.name,
                style:
                    const TextStyle(color: AdminTheme.kText, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Text(country.features.join(', '),
                style:
                    const TextStyle(color: AdminTheme.kMuted, fontSize: 12)),
          ),
          SizedBox(
            width: 120,
            child: _Chip(
                country.safetyOverride ? 'Override' : 'Normal',
                country.safetyOverride
                    ? AdminTheme.kOrange
                    : AdminTheme.kGreen),
          ),
          SizedBox(
            width: 80,
            child: _ActionBtn('Edit', AdminTheme.kYellow, () =>
                _showEditDialog(context, ref, country)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
      BuildContext context, WidgetRef ref, CountryConfig country) {
    bool safetyOverride = country.safetyOverride;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Edit ${country.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Code: ${country.code}',
                  style: const TextStyle(color: AdminTheme.kMuted, fontSize: 13)),
              const SizedBox(height: 12),
              Text('Features: ${country.features.join(", ")}',
                  style: const TextStyle(color: AdminTheme.kMuted, fontSize: 13)),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Safety Override',
                    style: TextStyle(color: AdminTheme.kText, fontSize: 14)),
                value: safetyOverride,
                onChanged: (v) => setState(() => safetyOverride = v),
                contentPadding: EdgeInsets.zero,
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
                  _save(context, ref, country.code, safetyOverride);
                },
                child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  Future<void> _save(
      BuildContext context, WidgetRef ref, String code, bool safety) async {
    try {
      final client = ref.read(adminHttpClientProvider);
      await client.dio.put('/admin/countries/$code',
          data: {'safety_override': safety});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$code updated'),
            backgroundColor: AdminTheme.kGreen));
        ref.invalidate(countriesProvider);
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
