import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/taps/taps_count_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  final int? errorStatus;
  final int? count;
  final Map<String, int>? types;

  _StubAdapter({this.errorStatus, this.count, this.types});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (errorStatus != null) {
      return ResponseBody.fromString(
        '{"error":"server"}',
        errorStatus!,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'count': count ?? 0, 'types': types ?? const {}}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('TapsCount', () {
    test('fromJson parses total and types', () {
      final taps = TapsCount.fromJson({
        'count': 7,
        'types': {'fire': 3, 'wave': 2, 'smile': 1, 'hello': 1},
      });

      expect(taps.total, equals(7));
      expect(taps.byType['fire'], equals(3));
      expect(taps.byType['wave'], equals(2));
      expect(taps.byType['smile'], equals(1));
      expect(taps.byType['hello'], equals(1));
      expect(taps.byType.length, equals(4));
    });

    test('fromJson handles missing types map', () {
      final taps = TapsCount.fromJson({'count': 0});

      expect(taps.total, equals(0));
      expect(taps.byType, isEmpty);
    });
  });

  group('TapsCountService', () {
    test('fetchCount returns parsed count', () async {
      final dio = Dio()
        ..options.baseUrl = 'http://test'
        ..httpClientAdapter = _StubAdapter(
          count: 5,
          types: {'fire': 5},
        );

      final service = TapsCountService(dio);
      final result = await service.fetchCount();

      expect(result.total, equals(5));
      expect(result.byType['fire'], equals(5));
    });

    test('fetchCount returns zero count on empty types', () async {
      final dio = Dio()
        ..options.baseUrl = 'http://test'
        ..httpClientAdapter = _StubAdapter();

      final service = TapsCountService(dio);
      final result = await service.fetchCount();

      expect(result.total, equals(0));
      expect(result.byType, isEmpty);
    });

    test('fetchCount rethrows on error', () async {
      final dio = Dio()
        ..options.baseUrl = 'http://test'
        ..httpClientAdapter = _StubAdapter(errorStatus: 500);

      final service = TapsCountService(dio);

      expect(
        () => service.fetchCount(),
        throwsA(isA<DioException>()),
      );
    });
  });
}