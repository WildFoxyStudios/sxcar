import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;

/// Function type for injecting a custom geocoding implementation (testable).
typedef GeocodingSearchFn = Future<List<geo.Location>> Function(String query);

/// Default implementation: delegates to the native `geocoding` package.
final geo.Geocoding _defaultGeocoding = geo.Geocoding();
Future<List<geo.Location>> _defaultSearch(String query) =>
    _defaultGeocoding.locationFromAddress(query);

/// Service that wraps the native geocoder with an injectable seam for testing.
///
/// Usage in production:
/// ```dart
/// final results = await ref.read(geocodingServiceProvider).search('Barcelona');
/// ```
class GeocodingService {
  final GeocodingSearchFn _search;

  GeocodingService({GeocodingSearchFn? search})
      : _search = search ?? _defaultSearch;

  /// Searches for locations matching [query] using the native geocoder.
  /// Returns a list of [geo.Location] results (upstream typically returns 1-5).
  Future<List<geo.Location>> search(String query) => _search(query);
}

/// Provider for [GeocodingService].
final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  return GeocodingService();
});
