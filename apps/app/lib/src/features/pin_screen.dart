import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../main.dart' show appRouter, clearPinRequirement;
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

// ---------------------------------------------------------------------------
// PinChallengeScreen
//
// Full-screen PIN lock shown at app launch (cold start) and whenever the app
// is resumed from the background, but only when the user has configured a PIN
// (pinEnabledProvider == true && pinCodeProvider is a non-empty 4-digit code).
// The router redirect in main.dart sends the user here; on a correct entry we
// call clearPinRequirement() (which flips the global _requirePin flag to false
// and refreshes the router) and then explicitly navigate to /navegar.
//
// This is intentionally separate from [PinScreen] (the management screen) so
// the two flows — "set/change my PIN" vs "prove it's me" — stay independent.
// The user cannot back out of this screen into the app without entering the
// right code.
// ---------------------------------------------------------------------------

class PinChallengeScreen extends ConsumerStatefulWidget {
  const PinChallengeScreen({super.key});

  @override
  ConsumerState<PinChallengeScreen> createState() =>
      _PinChallengeScreenState();
}

class _PinChallengeScreenState extends ConsumerState<PinChallengeScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _wrong = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final entered = _controller.text.trim();
    final expected = ref.read(pinCodeProvider);
    if (entered.length != 4 || int.tryParse(entered) == null) {
      setState(() => _wrong = true);
      return;
    }
    if (entered == expected) {
      clearPinRequirement(); // flips _requirePin=false + refreshes router
      if (!mounted) return;
      // Belt-and-suspenders: ensure we land on the home grid even if a stale
      // router evaluation races the refresh above.
      appRouter.go('/navegar');
    } else {
      setState(() => _wrong = true);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      // Block the system back gesture — there's nowhere to go back to.
      canPop: false,
      child: Scaffold(
        backgroundColor: VibraTheme.kBg,
        appBar: AppBar(
          title: Text(l10n.pin),
          backgroundColor: VibraTheme.kBg,
          automaticallyImplyLeading: false,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter your PIN to unlock',
                    style: const TextStyle(
                      color: VibraTheme.kText,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your 4-digit PIN to continue.',
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
                    autofocus: true,
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
                    onChanged: (_) {
                      if (_wrong) setState(() => _wrong = false);
                    },
                    onSubmitted: (_) => _verify(),
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
                      errorText: _wrong ? 'Incorrect PIN' : null,
                      counterText: '',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: VibraTheme.kTextSecondary,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VibraTheme.kBrandPrimary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _verify,
                      child: const Text('Unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
