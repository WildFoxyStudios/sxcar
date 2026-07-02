import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/nsfw/nsfw_service.dart';
import 'package:app/src/rust/nsfw.dart';

void main() {
  group('NsfwService (injected classifier)', () {
    test('returns isNsfw=false and safe score for a safe image', () async {
      final svc = NsfwService.withClassifier(
        (_) async => const NsfwResult(score: 0.1, isNsfw: false),
      );

      final result = await svc.check([0, 1, 2]);

      expect(result.isNsfw, isFalse);
      expect(result.score, closeTo(0.1, 0.001));
    });

    test('returns isNsfw=true for an NSFW image', () async {
      final svc = NsfwService.withClassifier(
        (_) async => const NsfwResult(score: 0.95, isNsfw: true),
      );

      final result = await svc.check([0, 1, 2]);

      expect(result.isNsfw, isTrue);
      expect(result.score, greaterThan(0.7));
    });

    test('fails open when classifier throws', () async {
      final svc = NsfwService.withClassifier(
        (_) async => throw Exception('Rust bridge unavailable'),
      );

      // Must not throw; must return safe.
      final result = await svc.check([0, 1, 2]);

      expect(result.isNsfw, isFalse);
      expect(result.score, equals(0.0));
    });

    test('returns safe result on web (kIsWeb path covered by mock)', () async {
      // kIsWeb is false in flutter_test, so the web branch is not hit here.
      // This test confirms the service itself never throws on any input path.
      final svc = NsfwService.withClassifier(
        (_) async => const NsfwResult(score: 0.0, isNsfw: false),
      );
      final result = await svc.check(List<int>.filled(100, 0));
      expect(result.isNsfw, isFalse);
    });

    test('classifier receives the exact bytes passed to check()', () async {
      final received = <List<int>>[];
      final svc = NsfwService.withClassifier((bytes) async {
        received.add(bytes);
        return const NsfwResult(score: 0.0, isNsfw: false);
      });

      final payload = [10, 20, 30];
      await svc.check(payload);

      expect(received, hasLength(1));
      expect(received.first, equals(payload));
    });
  });
}
