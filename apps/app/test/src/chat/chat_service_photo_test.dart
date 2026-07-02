import 'dart:convert';
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
  // ── sendPhotoMessage ────────────────────────────────────────────────────────

  group('ChatService.sendPhotoMessage', () {
    test('sends media_key + media_type, omits ephemeral=false', () async {
      final stub = _StubAdapter(
        body: '{"id":"msg-photo-1","kind":"photo"}',
        statusCode: 201,
      );
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      final id = await service.sendPhotoMessage(
        'conv-abc',
        mediaKey: 'album/key1.jpg',
      );

      expect(id, 'msg-photo-1');

      final body = stub.capturedData as Map<String, dynamic>;
      expect(body['media_key'], 'album/key1.jpg');
      expect(body['media_type'], 'photo');
      expect(body.containsKey('ephemeral'), isFalse,
          reason: 'ephemeral must be omitted when false');
      expect(stub.lastRequest!.path,
          '/chat/conversations/conv-abc/messages');
    });

    test('includes ephemeral=true when requested', () async {
      final stub = _StubAdapter(
        body: '{"id":"msg-eph-1","kind":"ephemeral_photo"}',
        statusCode: 201,
      );
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      final id = await service.sendPhotoMessage(
        'conv-abc',
        mediaKey: 'album/key2.jpg',
        ephemeral: true,
      );

      expect(id, 'msg-eph-1');

      final body = stub.capturedData as Map<String, dynamic>;
      expect(body['ephemeral'], isTrue);
      expect(body['media_key'], 'album/key2.jpg');
      expect(body['media_type'], 'photo');
    });

    test('posts to the correct conversation path', () async {
      final stub = _StubAdapter(
        body: '{"id":"x","kind":"photo"}',
        statusCode: 201,
      );
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      await service.sendPhotoMessage('my-conv-id', mediaKey: 'k.jpg');

      expect(stub.lastRequest!.path,
          '/chat/conversations/my-conv-id/messages');
    });
  });

  // ── getMediaUrl ─────────────────────────────────────────────────────────────

  group('ChatService.getMediaUrl', () {
    test('calls GET /media/get-url?key=…&kind=album', () async {
      final stub = _StubAdapter(
        body: jsonEncode({
          'get_url': 'https://r2.example.com/presigned/key.jpg?sig=abc',
        }),
        statusCode: 200,
      );
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      final url = await service.getMediaUrl('album/key.jpg');

      expect(url, 'https://r2.example.com/presigned/key.jpg?sig=abc');
      expect(stub.lastRequest!.path, '/media/get-url');
      expect(stub.lastRequest!.queryParameters['key'], 'album/key.jpg');
      expect(stub.lastRequest!.queryParameters['kind'], 'album');
    });
  });

  // ── markEphemeralViewed ─────────────────────────────────────────────────────

  group('ChatService.markEphemeralViewed', () {
    test('returns true on first view', () async {
      final stub = _StubAdapter(
        body: '{"viewed":true}',
        statusCode: 200,
      );
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      final result =
          await service.markEphemeralViewed('conv-abc', 'msg-eph-1');

      expect(result, isTrue);
      expect(stub.lastRequest!.path,
          '/chat/conversations/conv-abc/messages/msg-eph-1/viewed');
    });

    test('returns false on second view (already expired)', () async {
      final stub = _StubAdapter(
        body: '{"viewed":false}',
        statusCode: 200,
      );
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      final result =
          await service.markEphemeralViewed('conv-abc', 'msg-eph-1');

      expect(result, isFalse);
    });

    test('posts to the correct path', () async {
      final stub = _StubAdapter(
        body: '{"viewed":true}',
        statusCode: 200,
      );
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final service = ChatService(dio, 'token');
      await service.markEphemeralViewed('conv-xyz', 'msg-999');

      expect(
        stub.lastRequest!.path,
        '/chat/conversations/conv-xyz/messages/msg-999/viewed',
      );
      expect(stub.lastRequest!.method, 'POST');
    });
  });
}
