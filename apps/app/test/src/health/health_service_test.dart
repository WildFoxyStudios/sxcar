import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/health/health_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockHealthAdapter implements HttpClientAdapter {
  final Map<String, dynamic>? getResponse;
  Map<String, dynamic>? putBody;
  String? lastPutPath;

  _MockHealthAdapter({this.getResponse});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'GET' && options.path == '/profile/health') {
      if (getResponse == null) {
        return ResponseBody.fromString(
          '{"error":"not found"}',
          404,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode(getResponse),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'PUT' && options.path == '/profile/health') {
      lastPutPath = options.path;
      // Capture the request body for inspection.
      if (options.data is Map) {
        putBody = options.data as Map<String, dynamic>;
      } else if (options.data is String) {
        try {
          putBody = jsonDecode(options.data as String) as Map<String, dynamic>;
        } catch (_) {
          putBody = null;
        }
      }
      return ResponseBody.fromString(
        jsonEncode(getResponse ?? {'hiv_status': null, 'last_tested_on': null, 'prep': null}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
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
  group('HealthInfo', () {
    test('fromJson parses all fields', () {
      final info = HealthInfo.fromJson({
        'hiv_status': 'negative',
        'last_tested_on': '2026-01-15',
        'prep': true,
      });

      expect(info.hivStatus, equals('negative'));
      expect(info.lastTestedOn, equals('2026-01-15'));
      expect(info.prep, isTrue);
    });

    test('fromJson handles all nulls', () {
      final info = HealthInfo.fromJson({
        'hiv_status': null,
        'last_tested_on': null,
        'prep': null,
      });

      expect(info.hivStatus, isNull);
      expect(info.lastTestedOn, isNull);
      expect(info.prep, isNull);
    });

    test('toJson omits null fields', () {
      final info = const HealthInfo();
      final json = info.toJson();
      expect(json.containsKey('hiv_status'), isFalse);
      expect(json.containsKey('last_tested_on'), isFalse);
      expect(json.containsKey('prep'), isFalse);
    });

    test('toJson includes non-null fields', () {
      final info = const HealthInfo(
        hivStatus: 'negative',
        lastTestedOn: '2026-01-15',
        prep: true,
      );
      final json = info.toJson();
      expect(json['hiv_status'], equals('negative'));
      expect(json['last_tested_on'], equals('2026-01-15'));
      expect(json['prep'], isTrue);
    });
  });

  group('HealthService', () {
    test('fetchHealth GETs /profile/health and parses response', () async {
      final adapter = _MockHealthAdapter(getResponse: {
        'hiv_status': 'negative',
        'last_tested_on': '2026-01-15',
        'prep': true,
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final service = HealthService(dio);

      final info = await service.fetchHealth();

      expect(info.hivStatus, equals('negative'));
      expect(info.lastTestedOn, equals('2026-01-15'));
      expect(info.prep, isTrue);
    });

    test('fetchHealth returns empty HealthInfo on 404', () async {
      final adapter = _MockHealthAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = HealthService(dio);

      final info = await service.fetchHealth();

      expect(info.hivStatus, isNull);
      expect(info.lastTestedOn, isNull);
      expect(info.prep, isNull);
    });

    test('updateHealth PUTs to /profile/health with non-null fields only',
        () async {
      final adapter = _MockHealthAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = HealthService(dio);

      await service.updateHealth(const HealthInfo(
        hivStatus: 'negative',
        prep: true,
      ));

      expect(adapter.lastPutPath, equals('/profile/health'));
      expect(adapter.putBody, isNotNull);
      expect(adapter.putBody!['hiv_status'], equals('negative'));
      expect(adapter.putBody!['prep'], isTrue);
      // last_tested_on should NOT be present
      expect(adapter.putBody!.containsKey('last_tested_on'), isFalse);
    });

    test('updateHealth sends null hiv_status when field is null', () async {
      final adapter = _MockHealthAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = HealthService(dio);

      await service.updateHealth(const HealthInfo(
        hivStatus: 'unknown',
      ));

      expect(adapter.putBody!['hiv_status'], equals('unknown'));
      expect(adapter.putBody!.containsKey('prep'), isFalse);
    });
  });
}