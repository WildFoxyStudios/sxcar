import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/gen/app_localizations.dart';
import '../settings/settings_providers.dart';
import '../theme/app_theme.dart';

/// PIN management screen.
///
/// - When PIN is OFF: shows a single card with "Activar PIN"
/// - When PIN is ON: shows a card with "Cambiar PIN" + "Desactivar PIN"
///
/// Real PIN entry UI (a modal number pad) is out of scope — this screen just
/// toggles [pinEnabledProvider]. The actual lock screen on app launch will be
/// added in a future task.
class PinScreen extends ConsumerWidget {
  const PinScreen({super.key});

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool current) async {
    await ref.read(pinEnabledProvider.notifier).setPinEnabled(!current);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !current
              ? 'PIN activado (placeholder)'
              : 'PIN desactivado (placeholder)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = ref.watch(pinEnabledProvider);

    return Scaffold(
      backgroundColor: VibraTheme.kBg,
      appBar: AppBar(
        title: Text(l10n.pin),
        backgroundColor: VibraTheme.kBg,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VibraTheme.kSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        enabled ? 'PIN activo' : 'PIN inactivo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        enabled
                            ? 'Tu PIN bloquea la app al abrirla'
                            : 'Activa un PIN para bloquear la app al abrirla',
                        style: const TextStyle(
                          color: VibraTheme.kTextSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  activeThumbColor: VibraTheme.kYellow,
                  onChanged: (_) => _toggle(context, ref, enabled),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}