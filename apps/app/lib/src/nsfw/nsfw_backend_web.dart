import 'package:flutter/foundation.dart';

import 'nsfw_result.dart';

/// Web NSFW backend. The on-device TFLite model requires `dart:ffi`, which is
/// unavailable on web, so there is no client-side detection here — web relies
/// on server-side moderation (the backend gates photos by `moderation_status`).
///
/// [detect] always returns `null` so [NsfwService] applies its web fail-open
/// policy (never block all web uploads for lack of a local model).
class NsfwBackend {
  Future<NsfwResult?> detect(Uint8List bytes) async => null;
}
