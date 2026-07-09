import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/gen/app_localizations.dart';
import '../settings/settings_providers.dart';
import '../theme/app_theme.dart';

/// Lets the user pick which app icon to display.
///
/// This is a UI-only screen — the actual iOS / Android asset swap is out of
/// scope. Picking "Default" or "Discreet" toggles the [discreetIconProvider]
/// which is read by T2.7's settings screen.
class DiscreetIconPickerScreen extends ConsumerStatefulWidget {
  const DiscreetIconPickerScreen({super.key});

  @override
  ConsumerState<DiscreetIconPickerScreen> createState() =>
      _DiscreetIconPickerScreenState();
}

class _DiscreetIconPickerScreenState
    extends ConsumerState<DiscreetIconPickerScreen> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId =
        ref.read(discreetIconProvider) ? 'discreet' : 'default';
  }

  Future<void> _select(String id) async {
    setState(() => _selectedId = id);
    await ref
        .read(discreetIconProvider.notifier)
        .setDiscreetIcon(id == 'discreet');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final options = [
      _IconOption(
        id: 'default',
        label: 'Vibra',
        icon: const Icon(Icons.favorite, color: VibraTheme.kBrandPrimary, size: 36),
      ),
      _IconOption(
        id: 'discreet',
        label: l10n.iconoAplicacionDiscreto,
        icon: const Icon(Icons.water_drop, color: VibraTheme.kTierTop, size: 36),
      ),
    ];

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        title: Text(l10n.iconoAplicacionDiscreto),
        backgroundColor: VibraTheme.kBg,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: options.length,
        itemBuilder: (_, i) {
          final opt = options[i];
          final selected = opt.id == _selectedId;
          return InkWell(
            onTap: () => _select(opt.id),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: VibraTheme.kSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? VibraTheme.kBrandPrimary : VibraTheme.kDivider,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  opt.icon,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      opt.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle,
                        color: VibraTheme.kBrandPrimary, size: 22),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IconOption {
  final String id;
  final String label;
  final Icon icon;
  const _IconOption({required this.id, required this.label, required this.icon});
}