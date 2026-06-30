import 'package:dio/dio.dart';
import 'models.dart';

class AuthService {
  final Dio _client;

  AuthService(this._client);

  Future<TokenPair> register(RegisterData data) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/auth/register',
      data: data.toJson(),
    );
    return TokenPair.fromJson(response.data!);
  }

  Future<TokenPair> login(LoginData data) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      data: data.toJson(),
    );
    return TokenPair.fromJson(response.data!);
  }

  /// OAuth login with Google or Apple ID token.
  /// Calls POST /auth/oauth/{provider} with the raw id_token from the platform SDK.
  Future<TokenPair> oauthLogin(String provider, String idToken) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/auth/oauth/$provider',
      data: {'id_token': idToken},
    );
    return TokenPair.fromJson(response.data!);
  }

  Future<void> verifyEmail(String code) async {
    await _client.post<void>(
      '/auth/verify-email',
      data: {'code': code},
    );
  }

  Future<void> logout(String refresh) async {
    await _client.post<void>(
      '/auth/logout',
      data: {'refresh': refresh},
    );
  }
}
