import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/sessions/sessions_service.dart';

void main() {
  test('list parses the sessions array', () async {
    final adapter = _CapturingAdapter(
      body: '{"sessions":['
          '{"id":"s1","device_id":"phone","issued_at":"a","expires_at":"b","revoked_at":null},'
          '{"id":"s2","device_id":null,"issued_at":"c","expires_at":"d","revoked_at":null}'
          ']}',
      statusCode: 200,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final service = SessionsService(dio);

    final sessions = await service.list();

    expect(adapter.lastPath, '/me/sessions');
    expect(sessions.length, 2);
    expect(sessions[0].deviceId, 'phone');
    expect(sessions[1].deviceId, isNull);
  });

  test('revoke issues DELETE to /me/sessions/:id', () async {
    final adapter = _CapturingAdapter(body: '', statusCode: 204);
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final service = SessionsService(dio);

    await service.revoke('s9');

    expect(adapter.lastPath, '/me/sessions/s9');
    expect(adapter.lastMethod, 'DELETE');
  });
}

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter({required this.body, required this.statusCode});
  final String body;
  final int statusCode;
  String? lastPath;
  String? lastMethod;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    lastPath = options.path;
    lastMethod = options.method;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }
}
