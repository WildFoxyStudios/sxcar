import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// Current Roam / location preference for the user.
class RoamLocation {
  final double lat;
  final double lon;
  final String? name;
  final bool isRoam;

  const RoamLocation({
    required this.lat,
    required this.lon,
    this.name,
    this.isRoam = false,
  });

  factory RoamLocation.fromJson(Map<String, dynamic> json) {
    return RoamLocation(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      name: json['name'] as String?,
      isRoam: json['is_roam'] as bool? ?? false,
    );
  }
}

/// REST client for `/me/location` (the Roam preference).
class RoamService {
  final Dio _dio;

  RoamService(this._dio);

  /// GET /me/location — returns the current Roam location, or null if none.
  Future<RoamLocation?> getCurrent() async {
    final response = await _dio.get<Map<String, dynamic>>('/me/location');
    final data = response.data!;
    final loc = data['location'];
    if (loc == null) return null;
    return RoamLocation.fromJson(loc as Map<String, dynamic>);
  }

  /// PUT /me/location — set the Roam location.
  Future<void> set({
    required double lat,
    required double lon,
    String? name,
    bool isRoam = false,
  }) async {
    final body = <String, dynamic>{
      'lat': lat,
      'lon': lon,
      'is_roam': isRoam,
    };
    if (name != null) body['name'] = name;
    await _dio.put<void>('/me/location', data: body);
  }

  /// PUT /me/location — clear roam and use real device location.
  Future<void> setRealLocation({
    required double lat,
    required double lon,
  }) async {
    return set(lat: lat, lon: lon, isRoam: false);
  }
}

/// Riverpod provider for the RoamService.
final roamServiceProvider = Provider<RoamService>((ref) {
  final dio = ref.watch(dioProvider);
  return RoamService(dio);
});

/// FutureProvider for the current Roam location (null if none).
final roamLocationProvider = FutureProvider<RoamLocation?>((ref) async {
  final service = ref.watch(roamServiceProvider);
  return service.getCurrent();
});
