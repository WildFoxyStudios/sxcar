import 'package:app/src/location/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

// A reusable fake Position for tests.
Position _fakePosition() => Position(
      latitude: 37.42,
      longitude: -122.08,
      timestamp: DateTime(2024, 1, 1),
      accuracy: 10.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

void main() {
  group('LocationService', () {
    // ------------------------------------------------------------------ //
    // ensurePermission
    // ------------------------------------------------------------------ //
    group('ensurePermission', () {
      test(
          'returns whileInUse when already granted — requestPermission not called',
          () async {
        var requestCalled = false;
        final service = LocationService(
          checkPermission: () async => LocationPermission.whileInUse,
          requestPermission: () async {
            requestCalled = true;
            return LocationPermission.whileInUse;
          },
        );

        final result = await service.ensurePermission();

        expect(result, equals(LocationPermission.whileInUse));
        expect(requestCalled, isFalse);
      });

      test(
          'requests permission when denied and returns result of requestPermission',
          () async {
        var requestCalled = false;
        final service = LocationService(
          checkPermission: () async => LocationPermission.denied,
          requestPermission: () async {
            requestCalled = true;
            return LocationPermission.whileInUse;
          },
        );

        final result = await service.ensurePermission();

        expect(result, equals(LocationPermission.whileInUse));
        expect(requestCalled, isTrue);
      });
    });

    // ------------------------------------------------------------------ //
    // getCurrentPosition
    // ------------------------------------------------------------------ //
    group('getCurrentPosition', () {
      test('returns null when permission is deniedForever', () async {
        final service = LocationService(
          checkPermission: () async => LocationPermission.deniedForever,
          requestPermission: () async => LocationPermission.deniedForever,
          isLocationServiceEnabled: () async => true,
          doGetCurrentPosition: () async => _fakePosition(),
        );

        final result = await service.getCurrentPosition();

        expect(result, isNull);
      });

      test(
          'returns null when permission is denied (after request still denied)',
          () async {
        final service = LocationService(
          checkPermission: () async => LocationPermission.denied,
          requestPermission: () async => LocationPermission.denied,
          isLocationServiceEnabled: () async => true,
          doGetCurrentPosition: () async => _fakePosition(),
        );

        final result = await service.getCurrentPosition();

        expect(result, isNull);
      });

      test('returns a Position when permission is granted', () async {
        final expected = _fakePosition();
        final service = LocationService(
          checkPermission: () async => LocationPermission.whileInUse,
          requestPermission: () async => LocationPermission.whileInUse,
          isLocationServiceEnabled: () async => true,
          doGetCurrentPosition: () async => expected,
        );

        final result = await service.getCurrentPosition();

        expect(result, isNotNull);
        expect(result!.latitude, closeTo(37.42, 0.001));
        expect(result.longitude, closeTo(-122.08, 0.001));
      });

      test('returns null on exception (e.g. timeout)', () async {
        final service = LocationService(
          checkPermission: () async => LocationPermission.whileInUse,
          requestPermission: () async => LocationPermission.whileInUse,
          isLocationServiceEnabled: () async => true,
          doGetCurrentPosition: () async =>
              throw Exception('Location timed out'),
        );

        final result = await service.getCurrentPosition();

        expect(result, isNull);
      });

      test('returns null when location services are disabled', () async {
        final service = LocationService(
          checkPermission: () async => LocationPermission.whileInUse,
          requestPermission: () async => LocationPermission.whileInUse,
          isLocationServiceEnabled: () async => false,
          doGetCurrentPosition: () async => _fakePosition(),
        );

        final result = await service.getCurrentPosition();

        expect(result, isNull);
      });
    });

    // ------------------------------------------------------------------ //
    // getLastKnownPosition
    // ------------------------------------------------------------------ //
    group('getLastKnownPosition', () {
      test('returns null on exception', () async {
        final service = LocationService(
          doGetLastKnownPosition: () async =>
              throw Exception('No last known position'),
        );

        final result = await service.getLastKnownPosition();

        expect(result, isNull);
      });

      test('returns position when available', () async {
        final expected = _fakePosition();
        final service = LocationService(
          doGetLastKnownPosition: () async => expected,
        );

        final result = await service.getLastKnownPosition();

        expect(result, isNotNull);
        expect(result!.latitude, closeTo(37.42, 0.001));
      });
    });
  });
}
