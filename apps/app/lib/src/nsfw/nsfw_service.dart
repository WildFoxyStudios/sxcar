import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../rust/nsfw.dart';

/// Function type used to inject a fake classifier in tests.
typedef NsfwClassifyFn = Future<NsfwResult> Function(List<int> bytes);

/// Riverpod provider — returns the real service in production.
/// Override in tests with [NsfwService.withClassifier].
final nsfwServiceProvider = Provider<NsfwService>(
  (ref) => NsfwService(),
);

/// On-device NSFW detection service backed by the Rust/tract-onnx bridge.
///
/// The ONNX model (bundled at `assets/models/nsfw.onnx`) is extracted to the
/// device's temp directory on first use and compiled by tract once per process.
///
/// On web ([kIsWeb]), all checks return safe instantly (score=0, isNsfw=false)
/// because the WASM target is excluded from the Rust inference path.
///
/// On failure the service **fails open** — it logs and returns safe so that
/// an inference hiccup never prevents a legitimate upload.
class NsfwService {
  final NsfwClassifyFn? _classifyOverride;

  bool _initialized = false;

  /// Production constructor — uses the real Rust bridge.
  NsfwService() : _classifyOverride = null;

  /// Test constructor — injects a fake classifier instead of calling Rust.
  ///
  /// ```dart
  /// final svc = NsfwService.withClassifier(
  ///   (_) async => const NsfwResult(score: 0.9, isNsfw: true),
  /// );
  /// ```
  NsfwService.withClassifier(NsfwClassifyFn classify)
      : _classifyOverride = classify;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Check [imageBytes] for NSFW content.
  ///
  /// Always returns a [NsfwResult]; never throws.
  Future<NsfwResult> check(List<int> imageBytes) async {
    if (kIsWeb) {
      return const NsfwResult(score: 0.0, isNsfw: false);
    }
    await _ensureInitialized();

    final classify = _classifyOverride ??
        (bytes) => nsfwClassify(imageBytes: bytes);

    try {
      return await classify(imageBytes);
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
    if (_initialized || _classifyOverride != null) {
      _initialized = true;
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final modelFile = File('${tempDir.path}/nsfw.onnx');
      if (!modelFile.existsSync()) {
        final byteData = await rootBundle.load('assets/models/nsfw.onnx');
        await modelFile.writeAsBytes(byteData.buffer.asUint8List());
      }
      // Ignore "already set" — safe to call multiple times.
      try {
        await loadNsfwModel(path: modelFile.path);
      } catch (_) {}
      _initialized = true;
    } catch (e) {
      // Fail open on init errors too (e.g. disk full, bad permissions).
      debugPrint('[NsfwService] initialization failed (fail-open): $e');
      _initialized = true;
    }
  }
}
