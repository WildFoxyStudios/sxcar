import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Lightweight service that fetches the total unread message count by
/// summing `unread_count` over GET /chat/conversations. On any error it
/// returns 0 — the badge stays hidden rather than showing a red bubble.
class UnreadCountService {
  final Dio _dio;

  UnreadCountService(this._dio);

  Future<int> fetchUnread() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/chat/conversations',
      );
      final data = response.data!;
      final list = data['conversations'] as List<dynamic>? ?? const [];
      var total = 0;
      for (final c in list) {
        final map = c as Map<String, dynamic>;
        final unread = map['unread_count'];
        if (unread is num) total += unread.toInt();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}

final unreadCountServiceProvider = Provider<UnreadCountService>((ref) {
  final dio = ref.watch(dioProvider);
  return UnreadCountService(dio);
});

/// Total unread count across all conversations. Use this from the bottom
/// nav to render the badge.
final unreadCountProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(unreadCountServiceProvider);
  return service.fetchUnread();
});