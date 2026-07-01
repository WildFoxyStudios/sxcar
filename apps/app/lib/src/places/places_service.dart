import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';

/// A saved named location (lat/lon).
class Place {
  final String id;
  final String name;
  final double lat;
  final double lon;

  const Place({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      id: json['id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }
}

/// REST client for the `/places` endpoint.
class PlacesService {
  final Dio _dio;

  PlacesService(this._dio);

  /// GET /places — list the current user's saved places.
  Future<List<Place>> list() async {
    final response = await _dio.get<Map<String, dynamic>>('/places');
    final data = response.data!;
    final list = data['places'] as List<dynamic>;
    return list
        .map((p) => Place.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// POST /places — add a new place. Returns the created place.
  Future<Place> add(String name, double lat, double lon) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/places',
      data: {'name': name, 'lat': lat, 'lon': lon},
    );
    return Place.fromJson(response.data!['place'] as Map<String, dynamic>);
  }

  /// DELETE /places/:id — remove a place.
  Future<void> delete(String id) async {
    await _dio.delete<void>('/places/$id');
  }
}

/// Riverpod provider for the PlacesService.
final placesServiceProvider = Provider<PlacesService>((ref) {
  final dio = ref.watch(dioProvider);
  return PlacesService(dio);
});

/// FutureProvider for the list of saved places.
final placesProvider = FutureProvider<List<Place>>((ref) async {
  final service = ref.watch(placesServiceProvider);
  return service.list();
});
