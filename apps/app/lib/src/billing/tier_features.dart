/// Maps the user's current active subscription to a set of feature flags.
/// Used by the UI to gate premium features (incognito, see-who-viewed,
/// unlimited chats, etc.).
library;

import 'models.dart';

class TierFeatures {
  final bool unlimitedChats;
  final bool noAds;
  final bool seeWhoViewed;
  final bool incognitoMode;
  final bool boostDiscount;

  const TierFeatures({
    this.unlimitedChats = false,
    this.noAds = false,
    this.seeWhoViewed = false,
    this.incognitoMode = false,
    this.boostDiscount = false,
  });

  static const free = TierFeatures();

  static const vibraPlus = TierFeatures(
    unlimitedChats: true,
    noAds: true,
    seeWhoViewed: true,
  );

  static const unlimited = TierFeatures(
    unlimitedChats: true,
    noAds: true,
    seeWhoViewed: true,
    incognitoMode: true,
    boostDiscount: true,
  );

  /// Resolve the feature set from an active subscription. Returns free-tier
  /// features when subscription is null or the plan_code is unknown.
  static TierFeatures fromSubscription(Subscription? sub) {
    if (sub == null) return free;
    switch (sub.planCode) {
      case 'vibra_plus':
        return vibraPlus;
      case 'unlimited':
        return unlimited;
      default:
        return free;
    }
  }

  /// Resolve the feature set from a Plan (used in Tienda upsell previews).
  static TierFeatures fromPlan(Plan plan) {
    if (plan.code == 'unlimited') return unlimited;
    if (plan.code == 'vibra_plus') return vibraPlus;
    return free;
  }
}