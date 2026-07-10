import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/gen/app_localizations.dart';
import '../settings/settings_providers.dart';
import '../theme/app_theme.dart';

/// PIN management screen — set, change, or remove a 4-digit PIN lock.
class PinScreen extends ConsumerStatefulWidget {
  const PinScreen({super.key});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _savePin() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _controller.text.trim();
    if (code.length != 4 || int.tryParse(code) == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pinEnterExactly4Digits)),
      );
      return;
    }
    await ref.read(pinCodeProvider.notifier).setPinCode(code);
    if (!mounted) return;
    await ref.read(pinEnabledProvider.notifier).setPinEnabled(true);
    _controller.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.pinActivated)),
    );
  }

  Future<void> _removePin() async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VibraTheme.kSurface,
        title: Text(l10n.pinRemoveTitle, style: const TextStyle(color: VibraTheme.kText)),
        content: Text(l10n.pinRemoveBody,
            style: const TextStyle(color: VibraTheme.kTextSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelar)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.pinRemoveConfirm, style: const TextStyle(color: VibraTheme.kError))),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(pinCodeProvider.notifier).setPinCode('');
    if (!mounted) return;
    await ref.read(pinEnabledProvider.notifier).setPinEnabled(false);
    _controller.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.pinRemoved)),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          // ── PIN entry ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VibraTheme.kSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled ? l10n.pinChangeYourPin : l10n.pinSetAPin,
                  style: const TextStyle(
                    color: VibraTheme.kText,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  enabled ? l10n.pinEnterNewPinDesc : l10n.pinEnterPinDesc,
                  style: const TextStyle(
                    color: VibraTheme.kTextSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  obscureText: _obscure,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  style: const TextStyle(
                    color: VibraTheme.kText,
                    fontSize: 24,
                    letterSpacing: 8,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '····',
                    hintStyle: const TextStyle(
                      color: VibraTheme.kTextSecondary,
                      fontSize: 24,
                      letterSpacing: 8,
                    ),
                    filled: true,
                    fillColor: VibraTheme.kBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: VibraTheme.kDivider),
                    ),
                    counterText: '',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: VibraTheme.kTextSecondary,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: VibraTheme.kBrandPrimary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _savePin,
                        child: Text(enabled ? l10n.pinUpdatePin : l10n.pinActivatePin),
                      ),
                    ),
                    if (enabled) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: VibraTheme.kError,
                            side: const BorderSide(color: VibraTheme.kError),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _removePin,
                          child: Text(l10n.pinRemovePin),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
