import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Function type for injecting a custom position getter (testable).
typedef PositionGetter = Future<Position?> Function();

/// Top-level default: calls Geolocator.getCurrentPosition with high accuracy
/// and a 15-second timeout.
Future<Position?> _defaultGetCurrentPosition() =>
    Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );

/// Service that wraps geolocator calls with permission handling and null-safe
/// error returns. All geolocator calls are injectable so unit tests can run
/// without a real device.
class LocationService {
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<bool> Function() _isLocationServiceEnabled;
  final Future<Position?> Function() _doGetCurrentPosition;
  final Future<Position?> Function() _doGetLastKnownPosition;

  LocationService({
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<bool> Function()? isLocationServiceEnabled,
    Future<Position?> Function()? doGetCurrentPosition,
    Future<Position?> Function()? doGetLastKnownPosition,
  })  : _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission,
        _isLocationServiceEnabled =
            isLocationServiceEnabled ?? Geolocator.isLocationServiceEnabled,
        _doGetCurrentPosition =
            doGetCurrentPosition ?? _defaultGetCurrentPosition,
        _doGetLastKnownPosition =
            doGetLastKnownPosition ?? Geolocator.getLastKnownPosition;

  /// Checks permission; if denied, requests it and returns the new result.
  /// Returns the existing permission for all other states (whileInUse,
  /// always, deniedForever, unableToDetermine).
  Future<LocationPermission> ensurePermission() async {
    final permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      return _requestPermission();
    }
    return permission;
  }

  /// Returns the current GPS position, or null if:
  /// - permission is denied or deniedForever
  /// - location services are disabled on the device
  /// - any exception is thrown (timeout, platform error, etc.)
  ///
  /// Never throws.
  Future<Position?> getCurrentPosition() async {
    try {
      final permission = await ensurePermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final enabled = await _isLocationServiceEnabled();
      if (!enabled) return null;

      return await _doGetCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  /// Returns the last known GPS position cached by the platform, or null on
  /// any error. Never throws.
  Future<Position?> getLastKnownPosition() async {
    try {
      return await _doGetLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}

/// Provider for the [LocationService].
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// FutureProvider that tries [LocationService.getCurrentPosition] first, then
/// falls back to [LocationService.getLastKnownPosition]. Returns null if both
/// fail (caller should show a banner or fallback UI).
final currentPositionProvider = FutureProvider<Position?>((ref) async {
  final service = ref.watch(locationServiceProvider);
  return await service.getCurrentPosition() ??
      await service.getLastKnownPosition();
});
