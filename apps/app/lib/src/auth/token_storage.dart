import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStorage {
  Future<void> saveTokens({
    required String access,
    required String refresh,
  });
  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
  Future<void> clearTokens();
}

class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage _storage;

  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';

  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await Future.wait([
      _storage.write(key: _accessKey, value: access),
      _storage.write(key: _refreshKey, value: refresh),
    ]);
  }

  @override
  Future<String?> getAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _accessKey),
      _storage.delete(key: _refreshKey),
    ]);
  }
}
