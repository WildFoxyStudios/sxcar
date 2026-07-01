import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// A "Right Now" intent — a short-lived post visible to nearby users.
class RightNowIntent {
  final String id;
  final String userId;
  final String body;
  final String expiresAt;
  final String createdAt;

  const RightNowIntent({
    required this.id,
    required this.userId,
    required this.body,
    required this.expiresAt,
    required this.createdAt,
  });

  factory RightNowIntent.fromJson(Map<String, dynamic> json) {
    return RightNowIntent(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      body: json['body'] as String,
      expiresAt: json['expires_at'] as String,
      createdAt: json['created_at'] as String,
    );
  }
}

/// REST client for the `/right-now` endpoints.
class RightNowService {
  final Dio _dio;

  RightNowService(this._dio);

  /// POST /right-now — create an intent that expires after [expiresInMinutes].
  Future<RightNowIntent> create(String body, int expiresInMinutes) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/right-now',
      data: {'body': body, 'expires_in_minutes': expiresInMinutes},
    );
    return RightNowIntent.fromJson(response.data!);
  }

  /// GET /right-now — list active nearby intents.
  Future<List<RightNowIntent>> list() async {
    final response = await _dio.get<Map<String, dynamic>>('/right-now');
    final intents = response.data!['intents'] as List<dynamic>;
    return intents
        .map((i) => RightNowIntent.fromJson(i as Map<String, dynamic>))
        .toList();
  }

  /// DELETE /right-now/:id — delete one of the current user's own intents.
  Future<void> delete(String id) async {
    await _dio.delete<void>('/right-now/$id');
  }
}

/// Riverpod provider for the RightNowService.
final rightNowServiceProvider = Provider<RightNowService>((ref) {
  final dio = ref.watch(dioProvider);
  return RightNowService(dio);
});

/// FutureProvider for the active nearby intents feed.
final rightNowFeedProvider = FutureProvider<List<RightNowIntent>>((ref) async {
  final service = ref.watch(rightNowServiceProvider);
  return service.list();
});
