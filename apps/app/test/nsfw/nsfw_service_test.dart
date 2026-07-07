import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/nsfw/nsfw_service.dart';

void main() {
  group('NsfwService fail-closed', () {
    test('error paths return isNsfw=true in release mode', () {
      final result = NsfwService.classifyErrorFallback(isRelease: true);
      expect(result.isNsfw, true);
      expect(result.score, closeTo(1.0, 0.01));
    });

    test('error paths return isNsfw=false in debug mode', () {
      final result = NsfwService.classifyErrorFallback(isRelease: false);
      expect(result.isNsfw, false);
      expect(result.score, closeTo(0.0, 0.01));
    });
  });
}
