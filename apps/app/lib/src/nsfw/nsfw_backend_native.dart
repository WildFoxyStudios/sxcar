import 'package:flutter/foundation.dart';
// Hide the package's own NsfwResult so ours (nsfw_result.dart) is unambiguous;
// detectNSFWFromBytes's return type is still inferred, so .score/.isNsfw work.
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart' hide NsfwResult;

import 'nsfw_result.dart';

/// Native (Android/iOS/desktop) NSFW backend backed by the bundled Yahoo
/// OpenNSFW TFLite model in `nsfw_detector_flutter`. Runs on-device — no image
/// leaves the device. This file is only compiled on non-web platforms (it pulls
/// in `dart:ffi` via tflite_flutter); web uses `nsfw_backend_web.dart`.
class NsfwBackend {
  NsfwDetector? _detector;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      _detector = await NsfwDetector.load();
    } catch (e) {
      debugPrint('[NsfwBackend] init failed (fail-open): $e');
    }
    _initialized = true; // don't retry a failed load every call
  }

  /// Runs on-device inference. Returns `null` when the model is unavailable so
  /// the caller can apply its own fail-open/closed policy.
  Future<NsfwResult?> detect(Uint8List bytes) async {
    await _ensureInitialized();
    final detector = _detector;
    if (detector == null) return null;
    final result = await detector.detectNSFWFromBytes(bytes);
    return NsfwResult(
      score: result?.score ?? 0.0,
      isNsfw: result?.isNsfw ?? false,
    );
  }
}
