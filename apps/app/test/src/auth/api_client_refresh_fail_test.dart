import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/auth/api_client.dart';
import 'package:app/src/auth/token_storage.dart';

/// Test that when `/auth/refresh` fails (e.g. 400 because the refresh
/// token has expired or is invalid), the original request's error is the
/// one the caller sees — NOT a swallowed "Session expired" message.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('refresh failure (400) preserves original request error', () async {
    final storage = _InMemoryTokenStorage()
      ..access = 'old_access'
      ..refresh = 'invalid_refresh';

    final dio = createAuthClient(storage);
    final adapter = _FixedAdapter(then: {
      '/favorites': _Resp(401, '{}'),
      '/auth/refresh': _Resp(400, '{"message":"invalid refresh token"}'),
    });
    dio.httpClientAdapter = adapter;
    dio.options.baseUrl = 'http://127.0.0.1:0';

    try {
      await dio.get('/favorites');
      fail('expected an exception');
    } on DioException catch (e) {
      // Original request's status (401) wins. Refresh failure (400) is
      // captured only in the clear-tokens side-effect, not in the
      // surface error.
      expect(e.response?.statusCode, 401,
          reason: 'refresh failure should not surface the refresh 400');
    }
    expect(storage.access, isNull);
    expect(storage.refresh, isNull);
  });
}

class _InMemoryTokenStorage extends TokenStorage {
  String? access;
  String? refresh;
  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<String?> getAccessToken() async => access;

  @override
  Future<String?> getRefreshToken() async => refresh;

  @override
  Future<void> clearTokens() async {
    access = null;
    refresh = null;
  }
}

class _Resp {
  _Resp(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter({required this.then});
  final Map<String, _Resp> then;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final entry = then[options.path] ?? then['/']!;
    return ResponseBody.fromString(
      entry.body,
      entry.statusCode,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }
}
