import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/places/places_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPlacesAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> places;
  final List<String> deletedIds = [];
  final List<Map<String, dynamic>> posts = [];

  _MockPlacesAdapter({this.places = const []});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.path == '/places') {
      return ResponseBody.fromString(
        jsonEncode({'places': places}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.method == 'POST' && options.path == '/places') {
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : options.data as Map<String, dynamic>;
      posts.add(body);
      return ResponseBody.fromString(
        jsonEncode({
          'place': {
            'id': 'new-id',
            'name': body['name'] as String,
            'lat': body['lat'] as num,
            'lon': body['lon'] as num,
          }
        }),
        201,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.method == 'DELETE' && options.path.startsWith('/places/')) {
      final id = options.path.split('/').last;
      deletedIds.add(id);
      return ResponseBody.fromString(
        '',
        204,
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
  group('Place', () {
    test('fromJson parses all fields', () {
      final p = Place.fromJson({
        'id': '00000000-0000-0000-0000-000000000001',
        'name': 'Home',
        'lat': 19.4326,
        'lon': -99.1332,
      });

      expect(p.id, equals('00000000-0000-0000-0000-000000000001'));
      expect(p.name, equals('Home'));
      expect(p.lat, closeTo(19.4326, 0.0001));
      expect(p.lon, closeTo(-99.1332, 0.0001));
    });
  });

  group('PlacesService', () {
    test('list returns parsed places', () async {
      final dio = Dio()..httpClientAdapter = _MockPlacesAdapter(places: [
        {'id': 'id-1', 'name': 'Home', 'lat': 19.4, 'lon': -99.1},
        {'id': 'id-2', 'name': 'Work', 'lat': 19.5, 'lon': -99.2},
      ]);

      final service = PlacesService(dio);
      final places = await service.list();

      expect(places.length, equals(2));
      expect(places[0].name, equals('Home'));
      expect(places[1].name, equals('Work'));
    });

    test('add posts and returns the new place', () async {
      final adapter = _MockPlacesAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = PlacesService(dio);

      final p = await service.add('Coffee Shop', 19.43, -99.13);

      expect(p.name, equals('Coffee Shop'));
      expect(adapter.posts, hasLength(1));
      expect(adapter.posts.first['name'], equals('Coffee Shop'));
      expect(adapter.posts.first['lat'], equals(19.43));
      expect(adapter.posts.first['lon'], equals(-99.13));
    });

    test('delete calls DELETE with the right path', () async {
      final adapter = _MockPlacesAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = PlacesService(dio);

      await service.delete('id-1');

      expect(adapter.deletedIds, contains('id-1'));
    });

    test('rethrows on error', () async {
      final dio = Dio()
        ..httpClientAdapter = _BadPlacesAdapter();
      final service = PlacesService(dio);

      expect(
        () => service.list(),
        throwsA(isA<DioException>()),
      );
    });
  });
}

class _BadPlacesAdapter implements HttpClientAdapter {
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
