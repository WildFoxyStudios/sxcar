import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/boost/boost_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockBoostAdapter implements HttpClientAdapter {
  final Map<String, dynamic>? activeResponse;
  final List<String> paths = [];

  _MockBoostAdapter({this.activeResponse});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add('${options.method} ${options.path}');

    if (options.method == 'POST' && options.path == '/boost') {
      return ResponseBody.fromString(
        jsonEncode({
          'boost': {
            'id': 'boost-1',
            'expires_at': '2026-07-01T12:00:00Z',
            'minutes_remaining': 30,
          }
        }),
        201,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }

    if (options.method == 'GET' && options.path == '/boost/active') {
      final body = activeResponse == null
          ? jsonEncode({'active': false, 'minutes_remaining': 0})
          : jsonEncode({'active': true, ...activeResponse!});
      return ResponseBody.fromString(
        body,
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }

    return ResponseBody.fromString(
      '{}',
      404,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('Boost', () {
    test('fromJson parses all fields', () {
      final b = Boost.fromJson({
        'id': '00000000-0000-0000-0000-000000000001',
        'expires_at': '2026-07-01T12:30:00Z',
        'minutes_remaining': 15,
      });

      expect(b.id, equals('00000000-0000-0000-0000-000000000001'));
      expect(b.expiresAt, equals('2026-07-01T12:30:00Z'));
      expect(b.minutesRemaining, equals(15));
    });
  });

  group('BoostService', () {
    test('activate POSTs /boost and returns Boost', () async {
      final dio = Dio()..httpClientAdapter = _MockBoostAdapter();
      final service = BoostService(dio);

      final boost = await service.activate();

      expect(boost.id, equals('boost-1'));
      expect(boost.minutesRemaining, equals(30));
    });

    test('getActive returns null when not boosted', () async {
      final dio = Dio()..httpClientAdapter = _MockBoostAdapter();
      final service = BoostService(dio);

      final boost = await service.getActive();
      expect(boost, isNull);
    });

    test('getActive returns parsed Boost when active', () async {
      final dio = Dio()
        ..httpClientAdapter = _MockBoostAdapter(activeResponse: {
          'id': 'active-1',
          'expires_at': '2026-07-01T13:00:00Z',
          'minutes_remaining': 22,
        });
      final service = BoostService(dio);

      final boost = await service.getActive();
      expect(boost, isNotNull);
      expect(boost!.id, equals('active-1'));
      expect(boost.minutesRemaining, equals(22));
    });

    test('rethrows on error', () async {
      final dio = Dio()..httpClientAdapter = _BadBoostAdapter();
      final service = BoostService(dio);

      expect(
        () => service.activate(),
        throwsA(isA<DioException>()),
      );
    });
  });
}

class _BadBoostAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"error":"server"}',
      500,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}
