import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/chat/chat_service.dart';

// ---------------------------------------------------------------------------
// HTTP stub adapter — records the last request and returns a canned response.
// ---------------------------------------------------------------------------
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({required this.body, required this.statusCode});
  final String body;
  final int statusCode;

  RequestOptions? lastRequest;
  dynamic capturedData;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    lastRequest = options;
    capturedData = options.data;
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }
}

void main() {
  group('ChatService.setReaction', () {
    test('PUT /chat/messages/:id/reaction with emoji body', () async {
      final stub = _StubAdapter(body: '{}', statusCode: 200);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      await service.setReaction('msg-1', '❤️');

      expect(stub.lastRequest!.method, 'PUT');
      expect(stub.lastRequest!.path, '/chat/messages/msg-1/reaction');
      final body = stub.capturedData as Map<String, dynamic>;
      expect(body['emoji'], '❤️');
    });

    test('different message id encodes correctly', () async {
      final stub = _StubAdapter(body: '{}', statusCode: 200);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      await service.setReaction('msg-42', '🔥');

      expect(stub.lastRequest!.path, '/chat/messages/msg-42/reaction');
      final body = stub.capturedData as Map<String, dynamic>;
      expect(body['emoji'], '🔥');
    });
  });

  group('ChatService.removeReaction', () {
    test('DELETE /chat/messages/:id/reaction', () async {
      final stub = _StubAdapter(body: '{}', statusCode: 200);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      await service.removeReaction('msg-1');

      expect(stub.lastRequest!.method, 'DELETE');
      expect(stub.lastRequest!.path, '/chat/messages/msg-1/reaction');
    });

    test('different message id encodes correctly', () async {
      final stub = _StubAdapter(body: '{}', statusCode: 200);
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      await service.removeReaction('msg-99');

      expect(stub.lastRequest!.path, '/chat/messages/msg-99/reaction');
    });
  });
}
