import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/src/auth/admin_auth_service.dart';
import 'package:admin/src/widgets/admin_http_client.dart';

/// Mock interceptor that returns canned responses.
class MockInterceptor extends Interceptor {
  final Map<String, MockResponse> _responses = {};
  int requestCount = 0;

  void on(String method, String path, MockResponse response) {
    _responses['$method $path'] = response;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requestCount++;
    final key = '${options.method} ${options.path}';
    final mock = _responses[key];
    if (mock != null) {
      final data = mock.body.isNotEmpty ? jsonDecode(mock.body) : null;
      handler.resolve(
        Response(
          requestOptions: options,
          data: data,
          statusCode: mock.statusCode,
          headers: Headers.fromMap({
            'content-type': ['application/json'],
          }),
        ),
      );
    } else {
      handler.reject(
        DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            data: {'error': 'not found'},
            statusCode: 404,
          ),
        ),
      );
    }
  }
}

class MockResponse {
  final String body;
  final int statusCode;
  MockResponse(this.body, this.statusCode);
}

void main() {
  late AdminHttpClient client;
  late AdminAuthService authService;
  late MockInterceptor mockInterceptor;

  setUp(() {
    client = AdminHttpClient();
    // Remove the auth interceptor (that uses flutter_secure_storage) for tests
    client.dio.interceptors.clear();
    mockInterceptor = MockInterceptor();
    client.dio.interceptors.add(mockInterceptor);
    authService = AdminAuthService(client);
  });

  group('AdminAuthService', () {
    test('login returns mfa_token on success', () async {
      mockInterceptor.on('POST', '/admin/auth/login', MockResponse(
        '{"mfa_token": "test-mfa-token-123"}',
        200,
      ));

      final mfaToken = await authService.login('admin@test.com', 'password123');

      expect(mfaToken, equals('test-mfa-token-123'));
      expect(mockInterceptor.requestCount, equals(1));
    });

    test('verify2FA returns access_token and session_id', () async {
      mockInterceptor.on('POST', '/admin/auth/2fa', MockResponse(
        '{"access_token": "jwt-token-xyz", "session_id": "session-abc-123"}',
        200,
      ));

      final result = await authService.verify2FA('mfa-token', '123456');

      expect(result['access_token'], equals('jwt-token-xyz'));
      expect(result['session_id'], equals('session-abc-123'));
    });

    test('logout succeeds', () async {
      mockInterceptor.on('POST', '/admin/auth/logout', MockResponse(
        '{"ok": true}',
        200,
      ));

      await authService.logout('session-abc-123');

      expect(mockInterceptor.requestCount, equals(1));
    });
  });
}
