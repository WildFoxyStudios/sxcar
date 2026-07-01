import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/chat/chat_service.dart';

/// Regression test: the send-message endpoint returns `{id, kind}` (the Tier 1
/// media-message change renamed `message_id` -> `id`). ChatService.sendMessage
/// must read `id`, or every sent message throws a null-cast and the chat
/// screen breaks.
void main() {
  test('sendMessage reads the "id" field from the {id, kind} response', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _StubAdapter(
      body: '{"id":"abc-123","kind":"text"}',
      statusCode: 201,
    );
    final service = ChatService(dio, 'token');

    final id = await service.sendMessage('conv-1', 'hello');

    expect(id, 'abc-123');
  });

  test('sendMessage throws if the response is missing the id (old message_id)',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test'));
    dio.httpClientAdapter = _StubAdapter(
      // Simulate the OLD server shape — must NOT silently succeed.
      body: '{"message_id":"abc-123"}',
      statusCode: 201,
    );
    final service = ChatService(dio, 'token');

    expect(
      () => service.sendMessage('conv-1', 'hello'),
      throwsA(anything),
    );
  });
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.body, required this.statusCode});
  final String body;
  final int statusCode;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }
}
