import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/chat/chat_service.dart';

// ---------------------------------------------------------------------------
// HTTP stub adapter — returns canned responses for upload-url and
// send-message.
// ---------------------------------------------------------------------------
class _VoiceStubAdapter implements HttpClientAdapter {
  int _callCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    _callCount++;
    // First call: POST /media/upload-url
    if (_callCount == 1) {
      return ResponseBody.fromString(
        jsonEncode({
          'key': 'album/user-uuid/voice-uuid.m4a',
          'bucket': 'proyectox-private',
          'put_url': 'https://r2.example.com/put/voice-uuid.m4a',
          'get_url': 'https://r2.example.com/get/voice-uuid.m4a',
          'expires_in': 300,
        }),
        200,
        headers: const {
          'content-type': ['application/json'],
        },
      );
    }
    // Second call: POST /chat/conversations/:id/messages
    return ResponseBody.fromString(
      '{"id":"msg-voice-1","kind":"audio"}',
      201,
      headers: const {
        'content-type': ['application/json'],
      },
    );
  }
}

/// Stub adapter for the R2 upload client. Accepts any PUT and returns 200.
class _R2StubAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    return ResponseBody.fromString('', 200);
  }
}

void main() {
  group('ChatService.sendVoiceMessage', () {
    test('sends audio file path: upload-to-R2 then send-message POST', () async {
      final stub = _VoiceStubAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..httpClientAdapter = stub;

      final r2Dio = Dio()..httpClientAdapter = _R2StubAdapter();

      final service = ChatService(dio, 'token');

      // Create a temporary audio file for the test
      final tmpFile = File('${Directory.systemTemp.path}/test_voice.m4a');
      await tmpFile.writeAsBytes(List.filled(1024, 0));

      try {
        final id = await service.sendVoiceMessage(
          'conv-abc',
          tmpFile.path,
          mimeType: 'audio/mp4',
          r2Client: r2Dio,
        );

        expect(id, 'msg-voice-1');
      } finally {
        await tmpFile.delete();
      }
    });
  });
}
