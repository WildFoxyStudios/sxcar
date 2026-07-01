import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/rightnow/rightnow_service.dart';

void main() {
  test('create posts body + expires_in_minutes and parses the intent',
      () async {
    final adapter = _CapturingAdapter(
      body: '{"id":"i1","user_id":"u1","body":"Coffee now",'
          '"expires_at":"2026-07-02T10:00:00Z","created_at":"2026-07-02T09:00:00Z"}',
      statusCode: 200,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final service = RightNowService(dio);

    final intent = await service.create('Coffee now', 60);

    expect(adapter.lastPath, '/right-now');
    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastBody, contains('Coffee now'));
    expect(adapter.lastBody, contains('60'));
    expect(intent.id, 'i1');
    expect(intent.body, 'Coffee now');
  });

  test('list parses the intents array', () async {
    final adapter = _CapturingAdapter(
      body: '{"intents":['
          '{"id":"i1","user_id":"u1","body":"A","expires_at":"x","created_at":"y"},'
          '{"id":"i2","user_id":"u2","body":"B","expires_at":"x","created_at":"y"}'
          ']}',
      statusCode: 200,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final service = RightNowService(dio);

    final intents = await service.list();

    expect(intents.length, 2);
    expect(intents[0].body, 'A');
    expect(intents[1].userId, 'u2');
  });

  test('delete issues DELETE to /right-now/:id', () async {
    final adapter = _CapturingAdapter(body: '', statusCode: 204);
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    final service = RightNowService(dio);

    await service.delete('i9');

    expect(adapter.lastPath, '/right-now/i9');
    expect(adapter.lastMethod, 'DELETE');
  });
}

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter({required this.body, required this.statusCode});
  final String body;
  final int statusCode;
  String? lastPath;
  String? lastMethod;
  String? lastBody;

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
    lastBody = options.data?.toString();
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }
}
