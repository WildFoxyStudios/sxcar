import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// REST client for the Tier 3 per-user settings (`/me/idle-reminder`).
class Tier3SettingsService {
  final Dio _dio;

  Tier3SettingsService(this._dio);

  /// GET /me/idle-reminder — returns the configured friendly-reminder delay in
  /// hours, or null when disabled.
  Future<int?> getIdleReminderHours() async {
    final response = await _dio.get<Map<String, dynamic>>('/me/idle-reminder');
    final hours = response.data!['hours'];
    return hours == null ? null : (hours as num).toInt();
  }

  /// PUT /me/idle-reminder — set the delay in hours, or null to disable.
  Future<void> setIdleReminderHours(int? hours) async {
    await _dio.put<void>('/me/idle-reminder', data: {'hours': hours});
  }
}

/// Riverpod provider for the Tier3SettingsService.
final tier3SettingsServiceProvider = Provider<Tier3SettingsService>((ref) {
  final dio = ref.watch(dioProvider);
  return Tier3SettingsService(dio);
});

/// FutureProvider for the current friendly-reminder setting (null = off).
final idleReminderHoursProvider = FutureProvider<int?>((ref) async {
  final service = ref.watch(tier3SettingsServiceProvider);
  return service.getIdleReminderHours();
});
