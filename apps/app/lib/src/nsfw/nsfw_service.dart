import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';

/// Result of an on-device NSFW classification.
class NsfwResult {
  final double score;
  final bool isNsfw;

  const NsfwResult({required this.score, required this.isNsfw});
}

/// Function type used to inject a fake classifier in tests.
typedef NsfwClassifyFn = Future<NsfwResult> Function(Uint8List bytes);

/// Riverpod provider — returns the real service in production.
/// Override in tests with [NsfwService.withClassifier].
final nsfwServiceProvider = Provider<NsfwService>(
  (ref) => NsfwService(),
);

/// On-device NSFW detection service backed by [nsfw_detector_flutter].
///
/// Uses the Yahoo OpenNSFW TFLite model bundled inside the package (zero
/// setup, no downloads). All inference runs on-device — no images leave
/// the device.
///
/// On failure the service **fails open** — it logs and returns safe so
/// an inference hiccup never blocks a legitimate upload.
class NsfwService {
  final NsfwClassifyFn? _classifyOverride;

  bool _initialized = false;
  NsfwDetector? _detector;

  /// Production constructor — uses [NsfwDetector].
  NsfwService() : _classifyOverride = null;

  /// Test constructor — injects a fake classifier.
  NsfwService.withClassifier(NsfwClassifyFn classify)
      : _classifyOverride = classify;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Check [imageBytes] for NSFW content.
  ///
  /// Always returns a [NsfwResult]; never throws.
  Future<NsfwResult> check(Uint8List imageBytes) async {
    // Inject override (tests).
    final override = _classifyOverride;
    if (override != null) {
      try {
        return await override(imageBytes);
      } catch (e) {
        debugPrint('[NsfwService] override error (fail-open): $e');
        return const NsfwResult(score: 0.0, isNsfw: false);
      }
    }

    await _ensureInitialized();

    final detector = _detector;
    if (detector == null) {
      debugPrint('[NsfwService] detector not initialised (fail-open)');
      return const NsfwResult(score: 0.0, isNsfw: false);
    }

    try {
      final result = await detector.detectNSFWFromBytes(imageBytes);
      return NsfwResult(
        score: result?.score ?? 0.0,
        isNsfw: result?.isNsfw ?? false,
      );
    } catch (e) {
      // Fail open — an inference error must not block a legitimate upload.
      debugPrint('[NsfwService] classify error (fail-open): $e');
      return const NsfwResult(score: 0.0, isNsfw: false);
    }
  }

  // ---------------------------------------------------------------------------
  // Initialisation (idempotent)
  // ---------------------------------------------------------------------------

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      _detector = await NsfwDetector.load();
      _initialized = true;
    } catch (e) {
      // Fail open on init errors.
      debugPrint('[NsfwService] initialization failed (fail-open): $e');
      _initialized = true; // don't retry
    }
  }
}
