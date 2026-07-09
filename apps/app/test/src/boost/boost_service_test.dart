import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/boost/boost_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mocks the REAL backend contract:
///  - `POST /boost` → top-level `{ id, user_id, duration_secs, started_at,
///    expires_at, source }` (no `boost` wrapper, no `minutes_remaining`).
///  - `GET /boost/active` → `{ is_boosted, remaining_secs }`.
class _MockBoostAdapter implements HttpClientAdapter {
  /// When non-null, `/boost/active` returns an active boost with these seconds.
  final int? activeRemainingSecs;
  final List<String> paths = [];

  _MockBoostAdapter({this.activeRemainingSecs});

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
          'id': 'boost-1',
          'user_id': 'user-1',
          'duration_secs': 1800,
          'started_at': '2026-07-01T12:00:00Z',
          'expires_at': '2026-07-01T12:30:00Z',
          'source': 'manual',
        }),
        201,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    }

    if (options.method == 'GET' && options.path == '/boost/active') {
      final body = activeRemainingSecs == null
          ? jsonEncode({'is_boosted': false, 'remaining_secs': 0})
          : jsonEncode({'is_boosted': true, 'remaining_secs': activeRemainingSecs});
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
  group('BoostService', () {
    test('activate POSTs /boost and derives minutes from duration_secs', () async {
      final dio = Dio()..httpClientAdapter = _MockBoostAdapter();
      final service = BoostService(dio);

      final boost = await service.activate();

      // 1800s / 60 = 30 min
      expect(boost.minutesRemaining, equals(30));
      expect(boost.expiresAt, equals('2026-07-01T12:30:00Z'));
    });

    test('getActive returns null when not boosted', () async {
      final dio = Dio()..httpClientAdapter = _MockBoostAdapter();
      final service = BoostService(dio);

      final boost = await service.getActive();
      expect(boost, isNull);
    });

    test('getActive returns parsed Boost (ceil minutes) when active', () async {
      // 1300s / 60 = 21.67 → ceil → 22
      final dio = Dio()
        ..httpClientAdapter = _MockBoostAdapter(activeRemainingSecs: 1300);
      final service = BoostService(dio);

      final boost = await service.getActive();
      expect(boost, isNotNull);
      expect(boost!.minutesRemaining, equals(22));
      // active endpoint carries no expires_at
      expect(boost.expiresAt, isNull);
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
