import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// On-device chat translation (free, offline after the language model is
/// downloaded once). Source language is auto-detected; the target is the
/// user's device locale.
///
/// Uses ML Kit — no API keys, no server round-trip, no per-message cost.
class TranslationService {
  /// Translate [text] into [targetBcp] (e.g. `en`, `es`), auto-detecting the
  /// source language on-device. Returns the original text unchanged when the
  /// source can't be determined or already matches the target. Downloads the
  /// required models on first use (~30 MB per language). Throws on failure.
  Future<String> translate(String text, {required String targetBcp}) async {
    if (text.trim().isEmpty) return text;

    // 1. Detect the source language on-device.
    final identifier = LanguageIdentifier(confidenceThreshold: 0.4);
    String sourceBcp;
    try {
      sourceBcp = await identifier.identifyLanguage(text);
    } finally {
      await identifier.close();
    }
    if (sourceBcp == 'und') return text; // undetermined

    final source = _toLang(sourceBcp);
    final target = _toLang(targetBcp);
    if (source == null || target == null || source == target) return text;

    // 2. Ensure both translation models are present (downloads if needed).
    final manager = OnDeviceTranslatorModelManager();
    for (final lang in {source, target}) {
      final downloaded = await manager.isModelDownloaded(lang.bcpCode);
      if (!downloaded) {
        await manager.downloadModel(lang.bcpCode);
      }
    }

    // 3. Translate.
    final translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
    try {
      return await translator.translateText(text);
    } finally {
      await translator.close();
    }
  }

  /// Map a BCP-47 code (possibly region-tagged, e.g. `en-US`) to the closest
  /// supported [TranslateLanguage], or null if unsupported.
  TranslateLanguage? _toLang(String bcp) {
    final base = bcp.split('-').first.toLowerCase();
    for (final lang in TranslateLanguage.values) {
      if (lang.bcpCode == base) return lang;
    }
    return null;
  }
}

final translationServiceProvider =
    Provider<TranslationService>((ref) => TranslationService());
