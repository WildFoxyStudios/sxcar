import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';

class AdminHttpClient {
  late final Dio dio;
  final FlutterSecureStorage _storage;
  void Function()? onUnauthorized;

  AdminHttpClient({void Function()? onUnauthorized})
      : _storage = const FlutterSecureStorage() {
    this.onUnauthorized = onUnauthorized;
    dio = Dio(BaseOptions(
      baseUrl: AdminConfig.apiUrl,
      connectTimeout: AdminConfig.httpTimeout,
      receiveTimeout: AdminConfig.httpTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'admin_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await _storage.delete(key: 'admin_token');
          onUnauthorized?.call();
        }
        handler.next(error);
      },
    ));
  }

  Future<void> setToken(String token) async {
    await _storage.write(key: 'admin_token', value: token);
  }

  Future<String?> getToken() async {
    return _storage.read(key: 'admin_token');
  }

  Future<void> clearToken() async {
    await _storage.delete(key: 'admin_token');
  }
}

final adminHttpClientProvider = Provider<AdminHttpClient>((ref) {
  return AdminHttpClient();
});
