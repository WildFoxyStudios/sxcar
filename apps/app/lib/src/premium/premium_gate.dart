/// Reusable widget that gates premium features behind a tier check.
///
/// Shows the child widget when the user's tier allows the feature; otherwise
/// shows a configurable upgrade prompt banner/sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/gen/app_localizations.dart';
import '../theme/app_theme.dart';
import 'premium_service.dart';

/// Wraps a widget and shows it only if the user's tier grants [feature].
///
/// When the feature is locked, [lockedBuilder] (default: a yellow upgrade
/// banner) is shown instead. Tapping the banner navigates to the shop.
///
/// Usage:
/// ```dart
/// PremiumGate(
///   feature: PremiumFeature.travelPass,
///   child: MyTravelPassWidget(),
/// )
/// ```
class PremiumGate extends ConsumerWidget {
  /// The feature key to check (see [PremiumFeature] constants).
  final String feature;

  /// Widget shown when the feature is available.
  final Widget child;

  /// Optional custom builder for the locked state. If null, a default
  /// upgrade banner is shown.
  final Widget Function(
    BuildContext context,
    String featureDisplayName,
  )? lockedBuilder;

  const PremiumGate({
    super.key,
    required this.feature,
    required this.child,
    this.lockedBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premiumAsync = ref.watch(premiumStatusProvider);
    final status = premiumAsync is AsyncData<PremiumStatus>
        ? premiumAsync.value
        : null;

    final canAccess = status != null &&
        _checkFeature(status.features, feature);

    if (canAccess) return child;

    // Build locked state.
    final displayName = _featureDisplayName(context, feature);
    if (lockedBuilder != null) {
      return lockedBuilder!(context, displayName);
    }
    return _DefaultUpgradeBanner(featureDisplayName: displayName);
  }

  /// Check a single booleand feature flag.
  static bool _checkFeature(PremiumFeatures features, String feature) {
    return switch (feature) {
      PremiumFeature.unlimitedGrid => features.unlimitedGrid,
      PremiumFeature.noAds => features.noAds,
      PremiumFeature.incognitoMode => features.incognitoMode,
      PremiumFeature.readReceipts => features.readReceipts,
      PremiumFeature.travelPass => features.travelPass,
      PremiumFeature.prioritySupport => features.prioritySupport,
      PremiumFeature.advancedFilters => features.advancedFilters,
      _ => false,
    };
  }

  static String _featureDisplayName(BuildContext context, String feature) {
    final l10n = AppLocalizations.of(context)!;
    return switch (feature) {
      PremiumFeature.travelPass => l10n.travelPass,
      PremiumFeature.incognitoMode => l10n.incognito,
      PremiumFeature.readReceipts => l10n.chatReadReceipts,
      _ => feature,
    };
  }
}

/// Shows the current tier info for the user — used in the drawer or settings.
class PremiumStatusBadge extends ConsumerWidget {
  const PremiumStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premiumAsync = ref.watch(premiumStatusProvider);
    final status = premiumAsync is AsyncData<PremiumStatus>
        ? premiumAsync.value
        : const PremiumStatus();

    final l10n = AppLocalizations.of(context)!;

    final (String label, Color color) = switch (status.tier) {
      'xtra' => (l10n.premiumTierXtra, VibraTheme.kYellow),
      'unlimited' => (l10n.premiumTierUnlimited, VibraTheme.kTierTop),
      _ => (l10n.premiumTierFree, VibraTheme.kTextSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Default upgrade banner shown below a locked feature.
class _DefaultUpgradeBanner extends StatelessWidget {
  final String featureDisplayName;

  const _DefaultUpgradeBanner({required this.featureDisplayName});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () => _showUpgradeSheet(context),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: VibraTheme.kYellow.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: VibraTheme.kYellow.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline,
                  color: VibraTheme.kYellow, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.premiumUpgradePrompt(featureDisplayName),
                  style: const TextStyle(
                    color: VibraTheme.kYellow,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  color: VibraTheme.kYellow, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navigate to the shop tab.
void _showUpgradeSheet(BuildContext context) {
  // Navigate to the Shop tab — the bottom nav's /tienda route.
  // We use the context's closest GoRouter (or Navigator) to push /tienda.
  Navigator.of(context).pushNamed('/tienda');
}

/// Show a modal bottom sheet with a simple tier comparison.
void showPremiumComparisonSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;

  showModalBottomSheet(
    context: context,
    backgroundColor: VibraTheme.kSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PremiumComparisonSheet(l10n: l10n),
  );
}

class _PremiumComparisonSheet extends StatelessWidget {
  final AppLocalizations l10n;

  const _PremiumComparisonSheet({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.premiumComparisonTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          _TierRow(
            tierName: l10n.premiumTierFree,
            tierColor: VibraTheme.kTextSecondary,
            features: [
              _FeatureRow(l10n.premiumFeatureBasicGrid, true),
              _FeatureRow(l10n.premiumFeatureBasicFilters, true),
              _FeatureRow(l10n.premiumFeatureOneTribe, true),
              _FeatureRow(l10n.premiumFeatureNoAds, false),
              _FeatureRow(l10n.premiumFeatureTravelPass, false),
              _FeatureRow(l10n.premiumFeatureIncognito, false),
            ],
          ),
          const SizedBox(height: 12),
          _TierRow(
            tierName: l10n.premiumTierXtra,
            tierColor: VibraTheme.kYellow,
            features: [
              _FeatureRow(l10n.premiumFeatureUnlimitedGrid, true),
              _FeatureRow(l10n.premiumFeatureAdvancedFilters, true),
              _FeatureRow(l10n.premiumFeatureTribes3, true),
              _FeatureRow(l10n.premiumFeatureNoAds, true),
              _FeatureRow(l10n.premiumFeatureTravelPass, true),
              _FeatureRow(l10n.premiumFeatureReadReceipts, true),
            ],
          ),
          const SizedBox(height: 12),
          _TierRow(
            tierName: l10n.premiumTierUnlimited,
            tierColor: VibraTheme.kTierTop,
            features: [
              _FeatureRow(l10n.premiumFeatureUnlimitedGrid, true),
              _FeatureRow(l10n.premiumFeatureUnlimitedTribes, true),
              _FeatureRow(l10n.premiumFeatureIncognito, true),
              _FeatureRow(l10n.premiumFeatureNoAds, true),
              _FeatureRow(l10n.premiumFeatureTravelPass, true),
              _FeatureRow(l10n.premiumFeaturePrioritySupport, true),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/tienda');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: VibraTheme.kYellow,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Text(
                l10n.obtenerPremium,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  final String tierName;
  final Color tierColor;
  final List<_FeatureRow> features;

  const _TierRow({
    required this.tierName,
    required this.tierColor,
    required this.features,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VibraTheme.kChip,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tierColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tierName,
            style: TextStyle(
              color: tierColor,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      f.available ? Icons.check : Icons.close,
                      size: 16,
                      color:
                          f.available ? Colors.green[400] : Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      f.label,
                      style: TextStyle(
                        color: f.available ? Colors.white : Colors.grey[500],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _FeatureRow {
  final String label;
  final bool available;
  const _FeatureRow(this.label, this.available);
}
