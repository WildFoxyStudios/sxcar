// Distance formatter for /grid/nearby `distance_m` field.
//
// units: 0 = Metric (km/m), 1 = Imperial (mi/ft)
// - <1 km returns "350 m" (metric) or "1150 ft" (imperial)
// - ≥1 km returns "1.2 km" (metric) or "0.7 mi" (imperial)
// - null returns "—" (em-dash) — no distance known (e.g., user opted out of location)
// - negative values are clamped to 0 (defensive — bad data shouldn't crash UI)

import 'package:flutter/foundation.dart';

const double kMetersPerKilometer = 1000.0;
const double kMetersPerMile = 1609.344;
const double kFeetPerMeter = 3.28084;

@visibleForTesting
const String kDashPlaceholder = '—';

/// Formats a distance in meters for display.
///
/// [units] must be `0` (metric) or `1` (imperial). Any other value is treated
/// as metric (`0`) — same fail-safe as `unitsProvider` uses in production.
///
/// Returns "—" when [meters] is null (no location data).
String formatDistance(int? meters, int units) {
  final u = (units == 0 || units == 1) ? units : 0;
  if (meters == null) return kDashPlaceholder;
  final m = meters < 0 ? 0 : meters;

  if (u == 0) {
    // Metric
    if (m < kMetersPerKilometer) {
      return '$m m';
    }
    final km = m / kMetersPerKilometer;
    return '${_trimTrailingZero(km)} km';
  } else {
    // Imperial
    if (m < kMetersPerMile) {
      final ft = (m * kFeetPerMeter).round();
      return '$ft ft';
    }
    final mi = m / kMetersPerMile;
    return '${_trimTrailingZero(mi)} mi';
  }
}

/// Strips trailing ".0" so "1.0 km" → "1 km". Keeps "1.2 km" as is.
String _trimTrailingZero(double value) {
  // toStringAsFixed(1) gives e.g. "1.2" or "2.0"; we strip trailing ".0".
  final s = value.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}