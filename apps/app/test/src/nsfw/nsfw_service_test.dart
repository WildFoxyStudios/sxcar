import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/nsfw/nsfw_service.dart';

void main() {
  group('NsfwService (injected classifier)', () {
    test('returns isNsfw=false and safe score for a safe image', () async {
      final svc = NsfwService.withClassifier(
        (_) async => const NsfwResult(score: 0.1, isNsfw: false),
      );

      final result = await svc.check(Uint8List.fromList([0, 1, 2]));

      expect(result.isNsfw, isFalse);
      expect(result.score, closeTo(0.1, 0.001));
    });

    test('returns isNsfw=true for an NSFW image', () async {
      final svc = NsfwService.withClassifier(
        (_) async => const NsfwResult(score: 0.95, isNsfw: true),
      );

      final result = await svc.check(Uint8List.fromList([0, 1, 2]));

      expect(result.isNsfw, isTrue);
      expect(result.score, greaterThan(0.7));
    });

    test('fails open when classifier throws', () async {
      final svc = NsfwService.withClassifier(
        (_) async => throw Exception('TFLite unavailable'),
      );

      final result = await svc.check(Uint8List.fromList([0, 1, 2]));

      expect(result.isNsfw, isFalse);
      expect(result.score, equals(0.0));
    });

    test('returns safe result on missing detector (fail-open)', () async {
      final svc = NsfwService.withClassifier(
        (_) async => const NsfwResult(score: 0.0, isNsfw: false),
      );
      final bytes = Uint8List.fromList(List.filled(100, 0));
      final result = await svc.check(bytes);
      expect(result.isNsfw, isFalse);
    });

    test('classifier receives the exact bytes passed to check()', () async {
      final received = <Uint8List>[];
      final svc = NsfwService.withClassifier((bytes) async {
        received.add(bytes);
        return const NsfwResult(score: 0.0, isNsfw: false);
      });

      final payload = Uint8List.fromList([10, 20, 30]);
      await svc.check(payload);

      expect(received, hasLength(1));
      expect(received.first, equals(payload));
    });
  });
}
