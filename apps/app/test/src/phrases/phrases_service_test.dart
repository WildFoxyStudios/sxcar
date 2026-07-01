import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/phrases/phrases_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPhrasesAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> phrases;
  final Map<String, List<dynamic>> requests = {};

  _MockPhrasesAdapter({this.phrases = const []});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests[options.method] = [
      options.path,
      options.queryParameters,
      options.data,
    ];

    if (options.method == 'GET' && options.path == '/phrases') {
      return ResponseBody.fromString(
        jsonEncode({'phrases': phrases}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.method == 'POST' && options.path == '/phrases') {
      final body = options.data is String
          ? jsonDecode(options.data as String) as Map<String, dynamic>
          : options.data as Map<String, dynamic>;
      final newPhrase = {
        'id': 'new-id-${phrases.length + 1}',
        'phrase': body['phrase'] as String,
        'position': phrases.length,
      };
      return ResponseBody.fromString(
        jsonEncode({'phrase': newPhrase}),
        201,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.method == 'DELETE' && options.path.startsWith('/phrases/')) {
      return ResponseBody.fromString(
        '',
        204,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    if (options.method == 'PUT' && options.path == '/phrases/order') {
      return ResponseBody.fromString(
        jsonEncode({'ok': true}),
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
  group('Phrase', () {
    test('fromJson parses all fields', () {
      final p = Phrase.fromJson({
        'id': '00000000-0000-0000-0000-000000000001',
        'phrase': 'Hey there',
        'position': 2,
      });

      expect(p.id, equals('00000000-0000-0000-0000-000000000001'));
      expect(p.text, equals('Hey there'));
      expect(p.position, equals(2));
    });

    test('fromJson handles missing position', () {
      final p = Phrase.fromJson({
        'id': 'id-1',
        'phrase': 'Hello',
      });

      expect(p.position, equals(0));
    });
  });

  group('PhrasesService', () {
    test('list returns parsed phrases', () async {
      final dio = Dio()..httpClientAdapter = _MockPhrasesAdapter(phrases: [
        {
          'id': 'id-1',
          'phrase': 'First',
          'position': 0,
        },
        {
          'id': 'id-2',
          'phrase': 'Second',
          'position': 1,
        },
      ]);

      final service = PhrasesService(dio);
      final phrases = await service.list();

      expect(phrases.length, equals(2));
      expect(phrases[0].text, equals('First'));
      expect(phrases[1].text, equals('Second'));
    });

    test('add posts and returns the new phrase', () async {
      final adapter = _MockPhrasesAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = PhrasesService(dio);

      final p = await service.add('Yo');

      expect(p.text, equals('Yo'));
      expect(p.id, startsWith('new-id-'));
      expect(adapter.requests['POST'], isNotNull);
      expect(adapter.requests['POST']![0], equals('/phrases'));
    });

    test('delete calls DELETE with the right path', () async {
      final adapter = _MockPhrasesAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = PhrasesService(dio);

      await service.delete('id-1');

      expect(adapter.requests['DELETE'], isNotNull);
      expect(adapter.requests['DELETE']![0], equals('/phrases/id-1'));
    });

    test('reorder sends ids in the new order', () async {
      final adapter = _MockPhrasesAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = PhrasesService(dio);

      await service.reorder(['id-2', 'id-1']);

      expect(adapter.requests['PUT'], isNotNull);
      expect(adapter.requests['PUT']![0], equals('/phrases/order'));
      final body = adapter.requests['PUT']![2] as Map<String, dynamic>;
      expect(body['ids'], equals(['id-2', 'id-1']));
    });

    test('rethrows on error', () async {
      final dio = Dio()
        ..httpClientAdapter = _BadAdapter();
      final service = PhrasesService(dio);

      expect(
        () => service.list(),
        throwsA(isA<DioException>()),
      );
    });
  });
}

class _BadAdapter implements HttpClientAdapter {
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
