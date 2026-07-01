import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Online presence + last-seen info for a single user.
class UserStatus {
  final bool isOnline;
  final String? lastSeenAt;

  const UserStatus({required this.isOnline, this.lastSeenAt});

  factory UserStatus.fromJson(Map<String, dynamic> json) {
    return UserStatus(
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] as String?,
    );
  }
}

/// REST service for presence (heartbeat + per-user status).
class PresenceService {
  final Dio _dio;

  PresenceService(this._dio);

  /// POST /heartbeat — tells the backend we are active.
  Future<void> sendHeartbeat() async {
    await _dio.post('/heartbeat');
  }

  /// GET /users/:id/status — returns the given user's online + last_seen.
  /// On any error, returns an offline status (best-effort, used for UI hints).
  Future<UserStatus> getStatus(String userId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/users/$userId/status',
      );
      return UserStatus.fromJson(response.data!);
    } catch (_) {
      return const UserStatus(isOnline: false, lastSeenAt: null);
    }
  }
}

/// Riverpod provider for the PresenceService.
final presenceServiceProvider = Provider<PresenceService>((ref) {
  final dio = ref.watch(dioProvider);
  return PresenceService(dio);
});

/// Heartbeat provider — POSTs on construction and on each app foreground.
/// The actual scheduling is done by `WidgetsBindingObserver` in main.dart.
final heartbeatProvider = Provider<void>((ref) {
  final service = ref.watch(presenceServiceProvider);
  // Fire-and-forget; ignore failures.
  service.sendHeartbeat().catchError((_) {});
});

/// FutureProvider family keyed by user ID that fetches a user's status.
final userStatusProvider =
    FutureProvider.family<UserStatus, String>((ref, userId) async {
  final service = ref.watch(presenceServiceProvider);
  return service.getStatus(userId);
});

/// Returns a human-readable label for a [UserStatus]:
/// "Online", "Active 5m ago", "Active 2h ago", "Active 3d ago".
String formatLastSeen(UserStatus status) {
  if (status.isOnline) return 'Online';

  final ts = status.lastSeenAt;
  if (ts == null) return '';

  DateTime? lastSeen;
  try {
    lastSeen = DateTime.parse(ts);
  } catch (_) {
    return '';
  }

  final diff = DateTime.now().difference(lastSeen);
  if (diff.inSeconds < 0) return '';
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
  if (diff.inDays < 7) return 'Active ${diff.inDays}d ago';
  if (diff.inDays < 30) return 'Active ${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays < 365) return 'Active ${(diff.inDays / 30).floor()}mo ago';
  return 'Active ${(diff.inDays / 365).floor()}y ago';
}