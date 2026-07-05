import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/notifications/push_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Mock Dio adapter — captures POST /notifications/register calls.
// ---------------------------------------------------------------------------

class _MockPushAdapter implements HttpClientAdapter {
  String? lastMethod;
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastMethod = options.method;
    lastPath = options.path;

    if (options.data is Map) {
      lastBody = Map<String, dynamic>.from(options.data as Map);
    } else if (options.data is String) {
      try {
        lastBody = jsonDecode(options.data as String) as Map<String, dynamic>;
      } catch (_) {
        lastBody = null;
      }
    }

    return ResponseBody.fromString(
      '{}',
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PushService', () {
    test(
        'initAndRegister POSTs device_token and platform=android '
        'when tokenOverride is supplied', () async {
      final adapter = _MockPushAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = PushService(dio);

      const fakeToken = 'fake-fcm-token-1234567890';
      await service.initAndRegister(tokenOverride: fakeToken);

      expect(adapter.lastMethod, equals('POST'));
      expect(adapter.lastPath, equals('/notifications/register'));
      expect(adapter.lastBody, isNotNull);
      expect(adapter.lastBody!['device_token'], equals(fakeToken));
      // Test VM is not iOS → platform must be 'android'.
      expect(adapter.lastBody!['platform'], equals('android'));
    });

    test('initAndRegister does not call the API when tokenOverride is null '
        'and FirebaseMessaging is unavailable (no-op guard)', () async {
      // On the Dart VM there is no Firebase runtime. The service must not
      // throw; instead it catches the error internally. The adapter should
      // never be reached because getToken() would throw before _registerToken.
      final adapter = _MockPushAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = PushService(dio);

      // initAndRegister with no override tries to call FirebaseMessaging SDK,
      // which will throw on the test VM. The service must swallow the error.
      await expectLater(
        () => service.initAndRegister(),
        returnsNormally,
      );
      // The adapter should NOT have been called (error was caught before POST).
      expect(adapter.lastPath, isNull);
    });

    test('payload uses the exact token string provided', () async {
      final adapter = _MockPushAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = PushService(dio);

      const token = 'aBcDeFgH:APA91bXYZ';
      await service.initAndRegister(tokenOverride: token);

      expect(adapter.lastBody!['device_token'], equals(token));
    });
  });
}
