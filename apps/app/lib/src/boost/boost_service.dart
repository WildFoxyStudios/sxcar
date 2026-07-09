import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// A boost for the current user.
///
/// Matches the real backend contract:
///  - `POST /boost` returns a top-level boost object with `duration_secs` and
///    `expires_at` (no `minutes_remaining`, no `boost` wrapper).
///  - `GET /boost/active` returns `{ is_boosted, remaining_secs }` only.
///
/// [minutesRemaining] is derived (ceil) from whichever seconds field the
/// endpoint provided. [expiresAt] is only present on activate().
class Boost {
  final int minutesRemaining;
  final String? expiresAt;

  const Boost({required this.minutesRemaining, this.expiresAt});
}

/// REST client for the `/boost` and `/boost/active` endpoints.
class BoostService {
  final Dio _dio;

  BoostService(this._dio);

  /// POST /boost — activate a 30-min boost for the current user.
  /// Response is top-level: `{ id, user_id, duration_secs, started_at,
  /// expires_at, source }`. Minutes are derived from `duration_secs`.
  Future<Boost> activate() async {
    final response = await _dio.post<Map<String, dynamic>>('/boost');
    final data = response.data!;
    final durationSecs = (data['duration_secs'] as num? ?? 0);
    return Boost(
      minutesRemaining: (durationSecs / 60).ceil(),
      expiresAt: data['expires_at'] as String?,
    );
  }

  /// GET /boost/active — returns the active boost, or null if none.
  /// Response is `{ is_boosted: bool, remaining_secs: int }`.
  Future<Boost?> getActive() async {
    final response = await _dio.get<Map<String, dynamic>>('/boost/active');
    final data = response.data!;
    if (data['is_boosted'] != true) return null;
    final remainingSecs = (data['remaining_secs'] as num? ?? 0);
    return Boost(minutesRemaining: (remainingSecs / 60).ceil());
  }
}

/// Riverpod provider for the BoostService.
final boostServiceProvider = Provider<BoostService>((ref) {
  final dio = ref.watch(dioProvider);
  return BoostService(dio);
});

/// FutureProvider for the currently active boost (null if not boosted).
final activeBoostProvider = FutureProvider<Boost?>((ref) async {
  final service = ref.watch(boostServiceProvider);
  return service.getActive();
});
