import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// The current active Travel Pass state.
class TravelPass {
  final double lat;
  final double lon;
  final String? cityName;
  final String expiresAt;
  final double expiresInHours;

  const TravelPass({
    required this.lat,
    required this.lon,
    this.cityName,
    required this.expiresAt,
    required this.expiresInHours,
  });

  factory TravelPass.fromJson(Map<String, dynamic> json) {
    return TravelPass(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      cityName: json['city_name'] as String?,
      expiresAt: json['expires_at'] as String,
      expiresInHours: (json['expires_in_hours'] as num).toDouble(),
    );
  }
}

/// REST client for `/me/travel` endpoints.
class TravelPassService {
  final Dio _dio;

  TravelPassService(this._dio);

  /// POST /me/travel — set a virtual location.
  Future<TravelPass> set({
    required double lat,
    required double lon,
    String? cityName,
    double expiresInHours = 24,
  }) async {
    final body = <String, dynamic>{
      'lat': lat,
      'lon': lon,
      'expires_in_hours': expiresInHours,
    };
    if (cityName != null) body['city_name'] = cityName;
    final response = await _dio.post<Map<String, dynamic>>(
      '/me/travel',
      data: body,
    );
    return TravelPass.fromJson(response.data!);
  }

  /// GET /me/travel — returns the active travel pass, or null if none/expired.
  Future<TravelPass?> getCurrent() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/me/travel');
      return TravelPass.fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// DELETE /me/travel — cancel the active travel pass.
  Future<void> delete() async {
    await _dio.delete<void>('/me/travel');
  }
}

/// Riverpod provider for the TravelPassService.
final travelPassServiceProvider = Provider<TravelPassService>((ref) {
  final dio = ref.watch(dioProvider);
  return TravelPassService(dio);
});

/// FutureProvider for the current active travel pass (null if none/expired).
final travelPassProvider = FutureProvider<TravelPass?>((ref) async {
  final service = ref.watch(travelPassServiceProvider);
  return service.getCurrent();
});
