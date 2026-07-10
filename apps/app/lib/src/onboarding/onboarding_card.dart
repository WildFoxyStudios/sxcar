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
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step pill (+ "done" check). Required = brand teal; Optional =
            // muted. Required must NOT read as an error.
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isRequired
                        ? VibraTheme.kBrandPrimary.withValues(alpha: 0.16)
                        : VibraTheme.kChip,
                    borderRadius: BorderRadius.circular(24),
                    border: isRequired
                        ? Border.all(
                            color: VibraTheme.kBrandPrimary.withValues(alpha: 0.4))
                        : null,
                  ),
                  child: Text(
                    isRequired
                        ? l10n.onboarding_required
                        : l10n.onboarding_optional,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isRequired
                          ? VibraTheme.kBrandPrimary
                          : VibraTheme.kTextSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                if (card.completed)
                  const Icon(Icons.check_circle,
                      color: VibraTheme.kSuccess, size: 20),
              ],
            ),
            const SizedBox(height: 28),
            // Brand accent bar — a small teal flourish above the question.
            Container(
              width: 34,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: VibraTheme.kBrandPrimary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              card.label,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -0.3,
                color: VibraTheme.kText,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              card.ctaLabel,
              style: const TextStyle(
                fontSize: 16,
                height: 1.4,
                color: VibraTheme.kTextSecondary,
              ),
            ),
            const SizedBox(height: 32),
            Expanded(child: SingleChildScrollView(child: child)),
            const SizedBox(height: 20),
            // Full-width primary CTA (modern onboarding pattern) — big, teal,
            // unmistakable. Skip moves to a subtle centered link below it so the
            // primary stays the obvious next step.
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: VibraTheme.kBrandPrimary,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      VibraTheme.kBrandPrimary.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                ),
                onPressed: primaryEnabled ? onPrimary : null,
                child: Text(primaryLabel),
              ),
            ),
            if (onSkip != null) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: VibraTheme.kTextTertiary,
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  child: Text(l10n.onboarding_skip),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
