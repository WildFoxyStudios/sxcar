import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'revenuecat_service.dart';
import 'tier_features.dart';

/// Singleton [RevenueCatService] instance.
final revenueCatServiceProvider = Provider<RevenueCatService>((ref) {
  return RevenueCatService(ref);
});

/// RC [CustomerInfo] — refreshed on purchase or app foreground.
///
/// Returns `null` when the SDK is not yet configured or an error occurs
/// (no network, not authenticated, etc.).
final customerInfoProvider = FutureProvider<CustomerInfo?>((ref) async {
  final svc = ref.read(revenueCatServiceProvider);
  await svc.configure();
  try {
    return await Purchases.getCustomerInfo();
  } catch (_) {
    return null;
  }
});

/// Feature flags derived from the active RC entitlement.
///
/// Falls back to free-tier features when no active entitlement is found
/// or when the customer info fetch fails.
final tierFeaturesFromRCProvider = Provider<TierFeatures>((ref) {
  // Riverpod 3.x: AsyncValue.value returns ValueT? (nullable).
  final info = ref.watch(customerInfoProvider).value;
  return RevenueCatService.featuresFromCustomerInfo(info) ?? TierFeatures.free;
});
