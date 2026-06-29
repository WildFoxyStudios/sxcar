import 'dart:convert';
import 'dart:typed_data';
import 'package:app/src/auth/auth_service.dart';
import 'package:app/src/auth/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthService', () {
    late Dio dio;
    late AuthService authService;
    late _MockAdapter mockAdapter;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'https://api.turnend.win'));
      mockAdapter = _MockAdapter();
      dio.httpClientAdapter = mockAdapter;
      authService = AuthService(dio);
    });

    group('register', () {
      test('returns TokenPair on 201', () async {
        mockAdapter.enqueue(201, {
          'access': 'jwt_access',
          'refresh': 'opaque_refresh',
        });

        final result = await authService.register(RegisterData(
          email: 'test@example.com',
          password: 'securePass1!',
          dob: '2000-01-01',
          consents: ['tos', 'privacy', 'age'],
        ));

        expect(result.access, equals('jwt_access'));
        expect(result.refresh, equals('opaque_refresh'));
      });

      test('throws DioException on 409', () async {
        mockAdapter.enqueue(409, {'error': 'Email already taken'});

        expect(
          () => authService.register(RegisterData(
            email: 'existing@example.com',
            password: 'securePass1!',
            dob: '2000-01-01',
            consents: ['tos', 'privacy', 'age'],
          )),
          throwsA(isA<DioException>()),
        );
      });
    });

    group('login', () {
      test('returns TokenPair on 200', () async {
        mockAdapter.enqueue(200, {
          'access': 'jwt_login',
          'refresh': 'opaque_login',
        });

        final result = await authService.login(LoginData(
          email: 'test@example.com',
          password: 'securePass1!',
        ));

        expect(result.access, equals('jwt_login'));
        expect(result.refresh, equals('opaque_login'));
      });

      test('throws DioException on 401', () async {
        mockAdapter.enqueue(401, {'error': 'Bad credentials'});

        expect(
          () => authService.login(LoginData(
            email: 'wrong@example.com',
            password: 'badpass',
          )),
          throwsA(isA<DioException>()),
        );
      });
    });

    group('verifyEmail', () {
      test('succeeds on 204', () async {
        mockAdapter.enqueue(204);

        await authService.verifyEmail('123456');
      });

      test('throws DioException on 401', () async {
        mockAdapter.enqueue(401, {'error': 'Bad token'});

        expect(
          () => authService.verifyEmail('wrong'),
          throwsA(isA<DioException>()),
        );
      });
    });

    group('logout', () {
      test('succeeds on 204', () async {
        mockAdapter.enqueue(204);

        await authService.logout('refresh_token');
      });
    });
  });
}

class _MockAdapter implements HttpClientAdapter {
  final _queue = <_MockResponse>[];

  void enqueue(int statusCode, [Map<String, dynamic>? body]) {
    _queue.add(_MockResponse(statusCode, body));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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
