import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../auth/auth_provider.dart';
import 'tier_features.dart';

/// RevenueCat billing wrapper.
///
/// Handles SDK configuration, fetching offerings, making purchases, and
/// mapping RC entitlements to our internal [TierFeatures] model.
///
/// **Testability:** this class depends on the static [Purchases] SDK, which
/// talks to platform channels. For unit tests, override
/// [revenueCatServiceProvider] with a mock of this class and test the
/// Tienda/provider integration at the seam.
class RevenueCatService {
  final Ref _ref;

  // Set to true once [configure] has succeeded so it's idempotent.
  bool _configured = false;

  RevenueCatService(this._ref);

  /// RevenueCat test SDK key (public — safe to hardcode in the binary).
  static const _rcApiKey = 'test_UBghduyLgpGRfYQJFKMwTOdJLaU';

  /// Configure the RC SDK with the authenticated user's UUID.
  ///
  /// [appUserID] is set to our backend user UUID so that webhook events
  /// from RC are attributed to the correct user on our side.
  ///
  /// Idempotent — safe to call multiple times. No-op when the user is
  /// not yet authenticated.
  Future<void> configure() async {
    if (_configured) return;
    final userId = _ref.read(authStateProvider).userId;
    if (userId == null) return;

    final config = PurchasesConfiguration(_rcApiKey)
      ..appUserID = userId;
    await Purchases.configure(config);
    _configured = true;
  }

  /// Whether the SDK has been successfully configured.
  bool get isConfigured => _configured;

  /// Fetch the current RC offerings.
  ///
  /// Ensures [configure] has been called first. Returns null on any error
  /// (e.g. no network, SDK not configured).
  Future<Offerings?> getOfferings() async {
    await configure();
    try {
      return await Purchases.getOfferings();
    } catch (_) {
      return null;
    }
  }

  /// Find an RC [Package] matching [planCode] and subscription [period].
  ///
  /// Package identifiers in the RC dashboard should follow the convention
  /// `{plan_code}_{period}`, for example `vibra_plus_monthly` or
  /// `unlimited_yearly`.
  Future<Package?> packageFor(String planCode, String period) async {
    final offerings = await getOfferings();
    final current = offerings?.current;
    if (current == null) return null;

    final targetId = '${planCode}_$period';
    for (final pkg in current.availablePackages) {
      if (pkg.identifier == targetId) return pkg;
    }
    return null;
  }

  /// Purchase [package] through RevenueCat.
  ///
  /// Ensures [configure] has been called first. On success the backend
  /// webhook will update the subscriptions table within seconds; meanwhile
  /// the returned [CustomerInfo] can be checked for immediate entitlement.
  ///
  /// Throws [PlatformException] if the purchase is cancelled or fails.
  Future<CustomerInfo> purchasePackage(Package package) async {
    await configure();
    final result = await Purchases.purchase(
      PurchaseParams.package(package),
    );
    return result.customerInfo;
  }

  // ------------------------------------------------------------------
  // Static helpers (no SDK state required — safe for tests)
  // ------------------------------------------------------------------

  /// Resolve [TierFeatures] from RC [CustomerInfo] entitlements.
  ///
  /// Maps RC entitlement identifiers (`vibra_plus`, `unlimited`) to our
  /// feature-model constants. Returns `null` when no active entitlement
  /// is found, which callers should treat as free-tier.
  static TierFeatures? featuresFromCustomerInfo(CustomerInfo? info) {
    if (info == null) return null;
    final entitlements = info.entitlements.all;

    // Check unlimited first (it also grants vibra_plus).
    final unlimited = entitlements['unlimited'];
    if (unlimited != null && unlimited.isActive) {
      return TierFeatures.unlimited;
    }

    final vibraPlus = entitlements['vibra_plus'];
    if (vibraPlus != null && vibraPlus.isActive) {
      return TierFeatures.vibraPlus;
    }

    return null;
  }
}
