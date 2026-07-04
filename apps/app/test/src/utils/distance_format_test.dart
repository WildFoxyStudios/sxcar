import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/utils/distance_format.dart';

void main() {
  group('formatDistance — metric (units=0)', () {
    test('null meters returns em-dash placeholder', () {
      expect(formatDistance(null, 0), '—');
    });
    test('sub-kilometer uses meters', () {
      expect(formatDistance(0, 0), '0 m');
      expect(formatDistance(350, 0), '350 m');
      expect(formatDistance(999, 0), '999 m');
    });
    test('exactly 1 km returns "1 km"', () {
      expect(formatDistance(1000, 0), '1 km');
    });
    test('multi-km returns decimal km without trailing .0', () {
      expect(formatDistance(1200, 0), '1.2 km');
      expect(formatDistance(2750, 0), '2.8 km'); // rounds 2.75 → 2.8
      expect(formatDistance(12345, 0), '12.3 km');
    });
    test('negative meters clamps to 0', () {
      expect(formatDistance(-100, 0), '0 m');
    });
  });

  group('formatDistance — imperial (units=1)', () {
    test('null meters returns em-dash placeholder', () {
      expect(formatDistance(null, 1), '—');
    });
    test('sub-mile uses feet (rounded)', () {
      expect(formatDistance(0, 1), '0 ft');
      // 100 m × 3.28084 ≈ 328.084 ft → rounds to 328 ft
      expect(formatDistance(100, 1), '328 ft');
      // 500 m × 3.28084 ≈ 1640.42 ft → rounds to 1640 ft
      expect(formatDistance(500, 1), '1640 ft');
    });
    test('multi-mile returns decimal mi without trailing .0', () {
      // 1609 m × 3.28084 ≈ 5278.87 ft → rounds to 5279 ft (still feet,
      // because 1609 < 1609.344 so we have not crossed the mile threshold)
      expect(formatDistance(1609, 1), '5279 ft');
      // 1700 m / 1609.344 ≈ 1.056 mi → "1.1 mi" (crosses the 1-mi threshold)
      expect(formatDistance(1700, 1), '1.1 mi');
      // 5000 m / 1609.344 ≈ 3.107 mi → "3.1 mi"
      expect(formatDistance(5000, 1), '3.1 mi');
      // 16093 m / 1609.344 ≈ 10.00 mi → "10 mi"
      expect(formatDistance(16093, 1), '10 mi');
    });
    test('negative meters clamps to 0', () {
      expect(formatDistance(-100, 1), '0 ft');
    });
  });

  group('formatDistance — defensive', () {
    test('unknown units value clamps to metric', () {
      // Pass a bogus units value; function should not crash, should behave as metric.
      expect(formatDistance(350, 99), '350 m');
      expect(formatDistance(2500, 99), '2.5 km');
    });
  });
}