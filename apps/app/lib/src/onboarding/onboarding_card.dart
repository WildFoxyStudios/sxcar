import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import '../theme/app_theme.dart';
import 'models.dart';

/// Generic layout wrapper for an onboarding card — Halo styled.
///
/// Each per-card widget embeds its input inside this wrapper. The wrapper
/// renders: a Required/Optional pill, a "done" check, the card title +
/// helper copy, the input area, and the footer (Skip + primary CTA).
class OnboardingCardScaffold extends StatelessWidget {
  const OnboardingCardScaffold({
    super.key,
    required this.card,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.onSkip,
    this.primaryEnabled = true,
  });

  final OnboardingCard card;
  final Widget child;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onSkip;
  final bool primaryEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRequired = card.kind == OnboardingCardKind.required;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Required = brand teal; Optional = muted. Required must NOT
                // read as an error (the old errorContainer style did).
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isRequired
                        ? VibraTheme.kBrandPrimary.withValues(alpha: 0.15)
                        : VibraTheme.kChip,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isRequired
                        ? l10n.onboarding_required
                        : l10n.onboarding_optional,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: isRequired
                          ? VibraTheme.kBrandPrimary
                          : VibraTheme.kTextSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                if (card.completed)
                  const Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: VibraTheme.kSuccess, size: 16),
                      SizedBox(width: 4),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              card.label,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: VibraTheme.kText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              card.ctaLabel,
              style: const TextStyle(
                fontSize: 15,
                height: 1.35,
                color: VibraTheme.kTextSecondary,
              ),
            ),
            const SizedBox(height: 28),
            Expanded(child: SingleChildScrollView(child: child)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (onSkip != null)
                  TextButton(
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: VibraTheme.kTextSecondary,
                    ),
                    child: Text(l10n.onboarding_skip),
                  ),
                const Spacer(),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: VibraTheme.kBrandPrimary,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor:
                          VibraTheme.kBrandPrimary.withValues(alpha: 0.35),
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    onPressed: primaryEnabled ? onPrimary : null,
                    child: Text(primaryLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
