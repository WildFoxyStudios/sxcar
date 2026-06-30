import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Abstract ad provider. Swappable implementation (AdMob, mediation, etc.).
abstract class AdProvider {
  Future<void> initialize();
  Widget createNativeAd({double? width, double? height});
  bool get isSupported;
}

/// Real AdMob implementation using Google Mobile Ads SDK.
///
/// Uses Google's official **test** AdMob unit IDs so ads always serve test
/// creatives during development. Replace with production IDs before release.
///
/// See: https://developers.google.com/admob/flutter/test-ads
class AdMobAdProvider implements AdProvider {
  static const _testNativeAdUnitId =
      'ca-app-pub-3940256099942544/2247696110'; // Official test native ad

  // App IDs are set in platform config (AndroidManifest / Info.plist).
  // These env overrides let you swap production IDs without recompiling.
  static const _nativeAdUnitId = String.fromEnvironment('ADMOB_NATIVE_UNIT_ID',
      defaultValue: _testNativeAdUnitId);

  bool _initialized = false;

  @override
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<void> initialize() async {
    if (_initialized || !isSupported) return;
    final config = RequestConfiguration(
      testDeviceIds: const <String>[],
      tagForChildDirectedTreatment: TagForChildDirectedTreatment.no,
      tagForUnderAgeOfConsent: TagForUnderAgeOfConsent.no,
    );
    await MobileAds.instance.updateRequestConfiguration(config);
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  @override
  Widget createNativeAd({double? width, double? height}) {
    if (!isSupported) return const SizedBox.shrink();

    return SizedBox(
      width: width ?? double.infinity,
      height: height ?? 120,
      child: AdWidget(
        ad: NativeAd(
          adUnitId: _nativeAdUnitId,
          factoryId: 'listTile',
          request: const AdRequest(),
          listener: NativeAdListener(),
        )..load(),
      ),
    );
  }
}

/// Stub provider — shows nothing. Used when ads are disabled, on web,
/// or for entitled (paying) users.
class StubAdProvider implements AdProvider {
  @override
  Future<void> initialize() async {}

  @override
  Widget createNativeAd({double? width, double? height}) =>
      SizedBox(width: width, height: height);

  @override
  bool get isSupported => false;
}

/// Returns the real AdMob provider on mobile, stub on web.
AdProvider createAdProvider() {
  if (kIsWeb) return StubAdProvider();
  return AdMobAdProvider();
}
