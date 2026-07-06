import 'package:flutter/material.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'models.dart';

/// Generic layout wrapper for an onboarding card.
///
/// Each per-card widget (e.g. profile_photo_card) embeds the input
/// inside this wrapper. The wrapper handles: title, kind badge
/// (Required/Optional), progress text, primary CTA, and the optional
/// "Skip" button.
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
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isRequired
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isRequired
                        ? l10n.onboarding_required
                        : l10n.onboarding_optional,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                const Spacer(),
                if (card.completed)
                  Text(l10n.onboarding_done,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      )),
              ],
            ),
            const SizedBox(height: 12),
            Text(card.label,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(card.ctaLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 24),
            Expanded(child: SingleChildScrollView(child: child)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (onSkip != null)
                  TextButton(
                      onPressed: onSkip, child: Text(l10n.onboarding_skip)),
                const Spacer(),
                FilledButton(
                  onPressed: primaryEnabled ? onPrimary : null,
                  child: Text(primaryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
