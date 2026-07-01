import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/places/roam_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockRoamAdapter implements HttpClientAdapter {
  final Map<String, dynamic>? getResponse;
  final List<Map<String, dynamic>> putBodies = [];

  _MockRoamAdapter({this.getResponse});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.path == '/me/location') {
      if (getResponse == null) {
        return ResponseBody.fromString(
          jsonEncode({'location': null}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode({'location': getResponse}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.method == 'PUT' && options.path == '/me/location') {
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : options.data as Map<String, dynamic>;
      putBodies.add(body);
      return ResponseBody.fromString(
        jsonEncode({
          'location': {
            'lat': body['lat'] as num,
            'lon': body['lon'] as num,
            'name': body['name'] as String?,
            'is_roam': body['is_roam'] as bool? ?? false,
          }
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      '{}',
      404,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('RoamLocation', () {
    test('fromJson parses all fields', () {
      final r = RoamLocation.fromJson({
        'lat': 19.4326,
        'lon': -99.1332,
        'name': 'Mexico City',
        'is_roam': true,
      });

      expect(r.lat, closeTo(19.4326, 0.0001));
      expect(r.lon, closeTo(-99.1332, 0.0001));
      expect(r.name, equals('Mexico City'));
      expect(r.isRoam, isTrue);
    });

    test('fromJson handles missing name and is_roam', () {
      final r = RoamLocation.fromJson({
        'lat': 0.0,
        'lon': 0.0,
      });

      expect(r.name, isNull);
      expect(r.isRoam, isFalse);
    });
  });

  group('RoamService', () {
    test('getCurrent returns null when no location set', () async {
      final dio = Dio()..httpClientAdapter = _MockRoamAdapter();
      final service = RoamService(dio);

      final loc = await service.getCurrent();
      expect(loc, isNull);
    });

    test('getCurrent returns parsed location when set', () async {
      final dio = Dio()
        ..httpClientAdapter = _MockRoamAdapter(getResponse: {
          'lat': 19.4326,
          'lon': -99.1332,
          'name': 'CDMX',
          'is_roam': true,
        });
      final service = RoamService(dio);

      final loc = await service.getCurrent();
      expect(loc, isNotNull);
      expect(loc!.name, equals('CDMX'));
      expect(loc.isRoam, isTrue);
    });

    test('set sends all fields in the body', () async {
      final adapter = _MockRoamAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = RoamService(dio);

      await service.set(lat: 19.4, lon: -99.1, name: 'Test', isRoam: true);

      expect(adapter.putBodies, hasLength(1));
      expect(adapter.putBodies.first['lat'], equals(19.4));
      expect(adapter.putBodies.first['lon'], equals(-99.1));
      expect(adapter.putBodies.first['name'], equals('Test'));
      expect(adapter.putBodies.first['is_roam'], isTrue);
    });

    test('setRealLocation sends is_roam=false with no name', () async {
      final adapter = _MockRoamAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = RoamService(dio);

      await service.setRealLocation(lat: 19.4, lon: -99.1);

      expect(adapter.putBodies, hasLength(1));
      expect(adapter.putBodies.first['is_roam'], isFalse);
    });

    test('rethrows on error', () async {
      final dio = Dio()..httpClientAdapter = _BadRoamAdapter();
      final service = RoamService(dio);

      expect(
        () => service.getCurrent(),
        throwsA(isA<DioException>()),
      );
    });
  });
}

class _BadRoamAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error":"server"}',
      500,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
