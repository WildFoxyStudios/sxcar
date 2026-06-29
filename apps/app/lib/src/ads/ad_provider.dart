import 'package:flutter/widgets.dart';

/// Abstract ad provider. Swappable implementation (AdMob, mediation, etc.).
abstract class AdProvider {
  Future<void> initialize();
  Widget createNativeAd({double? width, double? height});
  bool get isSupported;
}

/// Stub provider — shows nothing. Used when ads are disabled or not supported.
class StubAdProvider implements AdProvider {
  @override
  Future<void> initialize() async {}

  @override
  Widget createNativeAd({double? width, double? height}) =>
      SizedBox(width: width, height: height);

  @override
  bool get isSupported => false;
}

// TODO(F1.7-real): implement AdMobAdProvider using google_mobile_ads package.
// - Requires AdMob App ID from Firebase/AdMob console
// - Native ads only, entitlement-gated (no ads for subscribers)
// - Only shown on mobile (Android/iOS), not web
