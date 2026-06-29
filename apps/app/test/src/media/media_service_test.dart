import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/media/media_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UploadUrl', () {
    test('fromJson parses a response correctly', () {
      final json = {
        'key': 'abc123.jpg',
        'bucket': 'media-prod',
        'put_url': 'https://r2.example.com/put/abc123',
        'get_url': 'https://r2.example.com/get/abc123',
        'expires_in': 3600,
      };

      final url = UploadUrl.fromJson(json);

      expect(url.key, equals('abc123.jpg'));
      expect(url.bucket, equals('media-prod'));
      expect(url.putUrl, equals('https://r2.example.com/put/abc123'));
      expect(url.getUrl, equals('https://r2.example.com/get/abc123'));
      expect(url.expiresIn, equals(3600));
    });

    test('toJson produces the expected map', () {
      final url = UploadUrl(
        key: 'key.jpg',
        bucket: 'b',
        putUrl: 'https://put.url',
        getUrl: 'https://get.url',
        expiresIn: 600,
      );

      final json = url.toJson();

      expect(json['key'], equals('key.jpg'));
      expect(json['expires_in'], equals(600));
    });
  });

  group('MediaService', () {
    late Dio dio;
    late MediaService mediaService;
    late _MockAdapter mockAdapter;
    late _MockAdapter r2Adapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.turnend.win'));
      mockAdapter = _MockAdapter();
      dio.httpClientAdapter = mockAdapter;
      final r2Dio = Dio();
      r2Adapter = _MockAdapter();
      r2Dio.httpClientAdapter = r2Adapter;
      mediaService = MediaService(dio, r2Client: r2Dio);
    });

    group('getUploadUrl', () {
      test('returns UploadUrl on 200', () async {
        mockAdapter.enqueue(200, {
          'key': 'abc.jpg',
          'bucket': 'media-prod',
          'put_url': 'https://r2.example.com/put/abc',
          'get_url': 'https://r2.example.com/get/abc',
          'expires_in': 1800,
        });

        final result = await mediaService.getUploadUrl(kind: 'avatar');

        expect(result.key, equals('abc.jpg'));
        expect(result.bucket, equals('media-prod'));
        expect(result.putUrl, equals('https://r2.example.com/put/abc'));
        expect(result.getUrl, equals('https://r2.example.com/get/abc'));
        expect(result.expiresIn, equals(1800));
      });

      test('sends kind and ext in the request body', () async {
        mockAdapter.enqueue(200, {
          'key': 'x.jpg',
          'bucket': 'b',
          'put_url': 'https://put',
          'get_url': 'https://get',
          'expires_in': 300,
        });

        await mediaService.getUploadUrl(kind: 'photo', ext: 'png');

        final request = mockAdapter.lastRequest;
        expect(request, isNotNull);
        expect(request!.method, equals('POST'));
        expect(request.path, equals('/media/upload-url'));

        final body = request.data as Map<String, dynamic>;
        expect(body['kind'], equals('photo'));
        expect(body['ext'], equals('png'));
      });

      test('ext is optional', () async {
        mockAdapter.enqueue(200, {
          'key': 'x.jpg',
          'bucket': 'b',
          'put_url': 'https://put',
          'get_url': 'https://get',
          'expires_in': 300,
        });

        await mediaService.getUploadUrl(kind: 'avatar');

        final request = mockAdapter.lastRequest;
        final body = request!.data as Map<String, dynamic>;
        expect(body['kind'], equals('avatar'));
        expect(body.containsKey('ext'), isFalse);
      });

      test('throws on 500', () async {
        mockAdapter.enqueue(500, {'error': 'Server error'});

        expect(
          () => mediaService.getUploadUrl(kind: 'avatar'),
          throwsA(isA<DioException>()),
        );
      });
    });

    group('uploadToR2', () {
      test('PUTs bytes to the presigned URL', () async {
        r2Adapter.enqueue(200);

        final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
        await mediaService.uploadToR2(
          'https://r2.example.com/put/test',
          bytes,
          contentType: 'image/jpeg',
        );

        final request = r2Adapter.lastRequest;
        expect(request, isNotNull);
        expect(request!.method, equals('PUT'));
        expect(request.path, equals('https://r2.example.com/put/test'));
        expect(request.headers['content-type'], equals('image/jpeg'));

        // Verify body bytes were sent (Dio stores Uint8List data as-is)
        final sentData = request.data;
        if (sentData is Uint8List) {
          expect(sentData, orderedEquals([0xFF, 0xD8, 0xFF]));
        } else if (sentData is String) {
          // Some Dio versions convert to String
          expect(sentData.codeUnits, orderedEquals([0xFF, 0xD8, 0xFF]));
        }
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Mock HttpClientAdapter that queues responses and records the last request.
// ---------------------------------------------------------------------------
class _MockAdapter implements HttpClientAdapter {
  final _queue = <_MockResponse>[];
  RequestOptions? lastRequest;

  void enqueue(int statusCode, [Map<String, dynamic>? body]) {
    _queue.add(_MockResponse(statusCode, body));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;

    if (_queue.isEmpty) {
      throw DioException(
        requestOptions: options,
        error: 'No mock response enqueued',
        type: DioExceptionType.unknown,
      );
    }

    final response = _queue.removeAt(0);
    final body = response.body != null ? jsonEncode(response.body) : '';
    return ResponseBody.fromString(
      body,
      response.statusCode,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MockResponse {
  final int statusCode;
  final Map<String, dynamic>? body;
  _MockResponse(this.statusCode, this.body);
}
