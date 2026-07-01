import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// An active login session (refresh token) for the current user.
class UserSession {
  final String id;
  final String? deviceId;
  final String issuedAt;
  final String expiresAt;
  final String? revokedAt;

  const UserSession({
    required this.id,
    required this.deviceId,
    required this.issuedAt,
    required this.expiresAt,
    required this.revokedAt,
  });

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      id: json['id'] as String,
      deviceId: json['device_id'] as String?,
      issuedAt: json['issued_at'] as String,
      expiresAt: json['expires_at'] as String,
      revokedAt: json['revoked_at'] as String?,
    );
  }
}

/// REST client for the `/me/sessions` endpoints.
class SessionsService {
  final Dio _dio;

  SessionsService(this._dio);

  /// GET /me/sessions — list active sessions for the current user.
  Future<List<UserSession>> list() async {
    final response = await _dio.get<Map<String, dynamic>>('/me/sessions');
    final sessions = response.data!['sessions'] as List<dynamic>;
    return sessions
        .map((s) => UserSession.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  /// DELETE /me/sessions/:id — revoke a session (logout that device).
  Future<void> revoke(String id) async {
    await _dio.delete<void>('/me/sessions/$id');
  }
}

/// Riverpod provider for the SessionsService.
final sessionsServiceProvider = Provider<SessionsService>((ref) {
  final dio = ref.watch(dioProvider);
  return SessionsService(dio);
});

/// FutureProvider for the current user's active sessions.
final sessionsProvider = FutureProvider<List<UserSession>>((ref) async {
  final service = ref.watch(sessionsServiceProvider);
  return service.list();
});
