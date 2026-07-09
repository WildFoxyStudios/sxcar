import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// A single alert from GET /screenshots, representing that [userId] took
/// a screenshot in [conversationId] at [reportedAt].
class ScreenshotAlert {
  final String id;
  final String userId;
  final String conversationId;
  final String reportedAt;

  const ScreenshotAlert({
    required this.id,
    required this.userId,
    required this.conversationId,
    required this.reportedAt,
  });

  factory ScreenshotAlert.fromJson(Map<String, dynamic> json) {
    return ScreenshotAlert(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      conversationId: json['conversation_id'] as String,
      reportedAt: json['reported_at'] as String,
    );
  }
}

/// Service wrapping the /screenshots endpoints.
///
/// ## Platform limitations
/// Screenshot detection is inherently best-effort:
/// - **Android**: [screenshot_callback] uses `onWindowFocusChanged` or a
///   FileObserver on the Screenshots folder. Reliability varies by OEM and
///   Android version; no reliable *pre*-capture hook exists on older versions.
/// - **iOS**: The system calls the app back *after* the screenshot is taken
///   (via `UIApplication.userDidTakeScreenshotNotification`) — the user has
///   already captured the image by the time we are notified.
/// Therefore, this feature is best-effort and should NOT be relied on for
/// DRM purposes — it is an informational notification only.
class ScreenshotsService {
  final Dio _client;

  const ScreenshotsService(this._client);

  /// POST /screenshots — report that the current user took a screenshot in
  /// [conversationId].
  Future<void> report(String conversationId) async {
    await _client.post<void>(
      '/screenshots',
      data: {'conversation_id': conversationId},
    );
  }

  /// GET /screenshots — returns alerts for conversations the caller is a
  /// member of that were taken by someone else.
  ///
  /// Handles both a bare JSON array and an object with a list field
  /// (`{ "alerts": [...] }`) defensively.
  Future<List<ScreenshotAlert>> list() async {
    final res = await _client.get<dynamic>('/screenshots');
    final data = res.data;

    List<dynamic> items;
    if (data is List) {
      items = data;
    } else if (data is Map<String, dynamic>) {
      // Try common wrapper keys
      final value = data['alerts'] ?? data['data'] ?? data['items'] ?? [];
      items = value is List ? value : [];
    } else {
      items = [];
    }

    return items
        .whereType<Map<String, dynamic>>()
        .map(ScreenshotAlert.fromJson)
        .toList();
  }
}

/// Provider for [ScreenshotsService]. Uses the shared authenticated [Dio].
final screenshotsServiceProvider = Provider<ScreenshotsService>((ref) {
  return ScreenshotsService(ref.watch(dioProvider));
});
