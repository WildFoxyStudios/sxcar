/// Result of an on-device NSFW classification.
///
/// Kept in its own file (no platform imports) so both the native and web
/// NSFW backends and the shared service can depend on it without pulling in
/// `dart:ffi` (which is unavailable on web).
class NsfwResult {
  final double score;
  final bool isNsfw;

  const NsfwResult({required this.score, required this.isNsfw});
}
