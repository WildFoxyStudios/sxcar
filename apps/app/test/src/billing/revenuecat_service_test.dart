import 'package:app/src/billing/revenuecat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Helper to build [CustomerInfo] instances with specific entitlement states.
///
/// The [CustomerInfo.fromJson] factory is pure Dart (no platform channel),
/// so we can construct objects for unit tests even though live SDK calls
/// require a device/emulator.
CustomerInfo _customerInfoWith({
  required String identifier,
  required bool active,
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final entitlement = {
    'identifier': identifier,
    'isActive': active,
    'willRenew': true,
    'latestPurchaseDate': now,
    'originalPurchaseDate': now,
    'productIdentifier': '${identifier}_monthly',
    'isSandbox': true,
  };

  return CustomerInfo.fromJson({
    'entitlements': {
      'all': {identifier: entitlement},
      'active': active ? {identifier: entitlement} : <String, dynamic>{},
    },
    'allPurchaseDates': <String, String>{},
    'activeSubscriptions': <String>[],
    'allPurchasedProductIdentifiers': <String>[],
    'nonSubscriptionTransactions': <dynamic>[],
    'firstSeen': now,
    'originalAppUserId': 'test-user',
    'allExpirationDates': <String, String>{},
    'requestDate': now,
  });
}

/// Build a [CustomerInfo] with both vibra_plus and unlimited entitlements.
CustomerInfo _customerInfoWithBoth({bool unlimitedActive = false}) {
  final now = DateTime.now().toUtc().toIso8601String();

  final vp = {
    'identifier': 'vibra_plus',
    'isActive': !unlimitedActive, // inactive when unlimited takes over
    'willRenew': !unlimitedActive,
    'latestPurchaseDate': now,
    'originalPurchaseDate': now,
    'productIdentifier': 'vibra_plus_monthly',
    'isSandbox': true,
  };
  final ul = {
    'identifier': 'unlimited',
    'isActive': unlimitedActive,
    'willRenew': true,
    'latestPurchaseDate': now,
    'originalPurchaseDate': now,
    'productIdentifier': 'unlimited_monthly',
    'isSandbox': true,
  };
  final all = <String, dynamic>{'vibra_plus': vp, 'unlimited': ul};

  return CustomerInfo.fromJson({
    'entitlements': {
      'all': all,
      'active': unlimitedActive
          ? <String, dynamic>{'unlimited': ul}
          : <String, dynamic>{'vibra_plus': vp},
    },
    'allPurchaseDates': <String, String>{},
    'activeSubscriptions': <String>[],
    'allPurchasedProductIdentifiers': <String>[],
    'nonSubscriptionTransactions': <dynamic>[],
    'firstSeen': now,
    'originalAppUserId': 'test-user',
    'allExpirationDates': <String, String>{},
    'requestDate': now,
  });
}

CustomerInfo _emptyCustomerInfo() {
  final now = DateTime.now().toUtc().toIso8601String();
  return CustomerInfo.fromJson({
    'entitlements': {
      'all': <String, dynamic>{},
      'active': <String, dynamic>{},
    },
    'allPurchaseDates': <String, String>{},
    'activeSubscriptions': <String>[],
    'allPurchasedProductIdentifiers': <String>[],
    'nonSubscriptionTransactions': <dynamic>[],
    'firstSeen': now,
    'originalAppUserId': 'test-user',
    'allExpirationDates': <String, String>{},
    'requestDate': now,
  });
}

void main() {
  group('RevenueCatService.featuresFromCustomerInfo', () {
    test('returns null for null input', () {
      expect(RevenueCatService.featuresFromCustomerInfo(null), isNull);
    });

    test('returns null when no entitlements are present', () {
      expect(
        RevenueCatService.featuresFromCustomerInfo(_emptyCustomerInfo()),
        isNull,
      );
    });

    test('returns null when entitlements are inactive', () {
      final info = _customerInfoWith(identifier: 'vibra_plus', active: false);
      expect(RevenueCatService.featuresFromCustomerInfo(info), isNull);
    });

    test('maps active vibra_plus to TierFeatures.vibraPlus', () {
      final info = _customerInfoWith(identifier: 'vibra_plus', active: true);
      final features = RevenueCatService.featuresFromCustomerInfo(info);
      expect(features, isNotNull);
      expect(features!.unlimitedChats, true);
      expect(features.noAds, true);
      expect(features.seeWhoViewed, true);
      expect(features.incognitoMode, false);
      expect(features.boostDiscount, false);
    });

    test('maps active unlimited to TierFeatures.unlimited', () {
      final info = _customerInfoWith(identifier: 'unlimited', active: true);
      final features = RevenueCatService.featuresFromCustomerInfo(info);
      expect(features, isNotNull);
      expect(features!.unlimitedChats, true);
      expect(features.noAds, true);
      expect(features.seeWhoViewed, true);
      expect(features.incognitoMode, true);
      expect(features.boostDiscount, true);
    });

    test('unlimited takes priority over vibra_plus when both present', () {
      // Simulate a user who upgraded from vibra_plus to unlimited.
      final info = _customerInfoWithBoth(unlimitedActive: true);
      final features = RevenueCatService.featuresFromCustomerInfo(info);
      expect(features, isNotNull);
      // Must be unlimited (the higher tier).
      expect(features!.incognitoMode, true);
      expect(features.boostDiscount, true);
    });
  });

  // RevenueCatService.configure() depends on platform channels (native SDK)
  // and cannot be exercised on the Dart VM. The idempotency of configure()
  // is enforced by the _configured guard flag. Full integration tests that
  // verify the RC SDK configuration require a physical device or emulator.
}
