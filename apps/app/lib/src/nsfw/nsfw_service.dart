import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nsfw_result.dart';
// Platform-split backend: native (TFLite/ffi) on mobile/desktop, no-op on web.
import 'nsfw_backend_native.dart'
    if (dart.library.html) 'nsfw_backend_web.dart';

// Re-export so existing consumers keep importing `NsfwResult` from here.
export 'nsfw_result.dart';

/// Function type used to inject a fake classifier in tests.
typedef NsfwClassifyFn = Future<NsfwResult> Function(Uint8List bytes);

/// Riverpod provider — returns the real service in production.
/// Override in tests with [NsfwService.withClassifier].
final nsfwServiceProvider = Provider<NsfwService>(
  (ref) => NsfwService(),
);

/// On-device NSFW detection service.
///
/// On native platforms it uses the Yahoo OpenNSFW TFLite model bundled in
/// `nsfw_detector_flutter` (zero setup, all inference on-device). On web there
/// is no on-device model (TFLite needs `dart:ffi`), so detection is skipped and
/// the app relies on server-side moderation.
///
/// On failure the service **fails open** — it logs and returns safe so an
/// inference hiccup never blocks a legitimate upload.
class NsfwService {
  final NsfwClassifyFn? _classifyOverride;
  final NsfwBackend _backend = NsfwBackend();

  /// Production constructor.
  NsfwService() : _classifyOverride = null;

  /// Test constructor — injects a fake classifier.
  NsfwService.withClassifier(NsfwClassifyFn classify)
      : _classifyOverride = classify;

  /// Returns the [NsfwResult] to use when classification fails.
  /// In release mode, fails CLOSED — blocks uploads.
  /// In debug mode, fails open — allows uploads for development without the model.
  static NsfwResult classifyErrorFallback({required bool isRelease}) {
    if (isRelease) {
      // Fail-closed: block the upload when NSFW detection is unavailable.
      return const NsfwResult(score: 1.0, isNsfw: true);
    }
    // Debug/dev: allow the upload so developers can test without the model.
    return const NsfwResult(score: 0.0, isNsfw: false);
  }

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
        return classifyErrorFallback(isRelease: kReleaseMode);
      }
    }

    try {
      final result = await _backend.detect(imageBytes);
      if (result != null) return result;
      // Model unavailable. On web there is intentionally no local model, so
      // fail OPEN (server-side moderation handles it) rather than blocking
      // every web upload. On native, apply the normal fail-open/closed policy.
      if (kIsWeb) return const NsfwResult(score: 0.0, isNsfw: false);
      debugPrint('[NsfwService] detector not initialised (fail-open)');
      return classifyErrorFallback(isRelease: kReleaseMode);
    } catch (e) {
      // Fail open — an inference error must not block a legitimate upload.
      debugPrint('[NsfwService] classify error (fail-open): $e');
      return classifyErrorFallback(isRelease: kReleaseMode);
    }
  }
}
