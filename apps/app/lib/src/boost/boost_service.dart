import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// A boost for the current user.
class Boost {
  final String id;
  final String expiresAt;
  final int minutesRemaining;

  const Boost({
    required this.id,
    required this.expiresAt,
    required this.minutesRemaining,
  });

  factory Boost.fromJson(Map<String, dynamic> json) {
    return Boost(
      id: json['id'] as String,
      expiresAt: json['expires_at'] as String,
      minutesRemaining: (json['minutes_remaining'] as num).toInt(),
    );
  }
}

/// REST client for the `/boost` and `/boost/active` endpoints.
class BoostService {
  final Dio _dio;

  BoostService(this._dio);

  /// POST /boost — activate a 30-min boost for the current user.
  Future<Boost> activate() async {
    final response = await _dio.post<Map<String, dynamic>>('/boost');
    final data = response.data!;
    return Boost.fromJson(data['boost'] as Map<String, dynamic>);
  }

  /// GET /boost/active — returns the active boost, or null if none.
  Future<Boost?> getActive() async {
    final response = await _dio.get<Map<String, dynamic>>('/boost/active');
    final data = response.data!;
    if (data['active'] != true) return null;
    return Boost.fromJson(data);
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
