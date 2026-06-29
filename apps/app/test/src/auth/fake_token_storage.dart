import 'package:app/src/auth/token_storage.dart';

class FakeTokenStorage implements TokenStorage {
  String? _access;
  String? _refresh;

  @override
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    _access = access;
    _refresh = refresh;
  }

  @override
  Future<String?> getAccessToken() async => _access;

  @override
  Future<String?> getRefreshToken() async => _refresh;

  @override
  Future<void> clearTokens() async {
    _access = null;
    _refresh = null;
  }
}
