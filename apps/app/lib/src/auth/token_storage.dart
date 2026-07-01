import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class TokenStorage {
  Future<void> saveTokens({required String access, required String refresh});
  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
  Future<void> clearTokens();
}

class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;

  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';

  SecureTokenStorage({FlutterSecureStorage? secure})
      : _secure = secure ?? const FlutterSecureStorage();

  Future<SharedPreferences> get _sharedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    try {
      await Future.wait([
        _secure.write(key: _accessKey, value: access),
        _secure.write(key: _refreshKey, value: refresh),
      ]);
    } catch (_) {
      // Fallback to SharedPreferences if secure storage fails
      final prefs = await _sharedPrefs;
      await prefs.setString(_accessKey, access);
      await prefs.setString(_refreshKey, refresh);
    }
  }

  @override
  Future<String?> getAccessToken() async {
    try {
      final token = await _secure.read(key: _accessKey);
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}
    // Fallback
    final prefs = await _sharedPrefs;
    return prefs.getString(_accessKey);
  }

  @override
  Future<String?> getRefreshToken() async {
    try {
      final token = await _secure.read(key: _refreshKey);
      if (token != null && token.isNotEmpty) return token;
    } catch (_) {}
    final prefs = await _sharedPrefs;
    return prefs.getString(_refreshKey);
  }

  @override
  Future<void> clearTokens() async {
    try {
      await Future.wait([
        _secure.delete(key: _accessKey),
        _secure.delete(key: _refreshKey),
      ]);
    } catch (_) {}
    final prefs = await _sharedPrefs;
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }
}
