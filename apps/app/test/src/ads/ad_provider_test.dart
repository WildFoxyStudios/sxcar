import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/src/ads/ad_provider.dart';

void main() {
  group('StubAdProvider', () {
    late StubAdProvider provider;

    setUp(() {
      provider = StubAdProvider();
    });

    test('initialize completes without error', () async {
      await provider.initialize();
      // no exception expected
    });

    test('isSupported returns false', () {
      expect(provider.isSupported, isFalse);
    });

    test('createNativeAd returns SizedBox with no size by default', () {
      final widget = provider.createNativeAd();
      expect(widget, isA<SizedBox>());
      final sizedBox = widget as SizedBox;
      expect(sizedBox.width, isNull);
      expect(sizedBox.height, isNull);
    });

    test('createNativeAd respects width and height', () {
      final widget = provider.createNativeAd(width: 300, height: 250);
      expect(widget, isA<SizedBox>());
      final sizedBox = widget as SizedBox;
      expect(sizedBox.width, 300);
      expect(sizedBox.height, 250);
    });

    test('createNativeAd respects only width', () {
      final widget = provider.createNativeAd(width: 320);
      expect(widget, isA<SizedBox>());
      final sizedBox = widget as SizedBox;
      expect(sizedBox.width, 320);
      expect(sizedBox.height, isNull);
    });

    test('createNativeAd respects only height', () {
      final widget = provider.createNativeAd(height: 480);
      expect(widget, isA<SizedBox>());
      final sizedBox = widget as SizedBox;
      expect(sizedBox.width, isNull);
      expect(sizedBox.height, 480);
    });
  });
}
