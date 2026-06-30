import '../widgets/admin_http_client.dart';

class AdminAuthService {
  final AdminHttpClient _client;

  AdminAuthService(this._client);

  /// Step 1: Login with email + password. Returns mfa_token.
  Future<String> login(String email, String password) async {
    final response = await _client.dio.post(
      '/admin/auth/login',
      data: {'email': email, 'password': password},
    );
    return response.data['mfa_token'] as String;
  }

  /// Step 2: Verify TOTP code. Returns access_token.
  Future<Map<String, String>> verify2FA(String mfaToken, String totpCode) async {
    final response = await _client.dio.post(
      '/admin/auth/2fa',
      data: {'mfa_token': mfaToken, 'totp_code': totpCode},
    );
    final accessToken = response.data['access_token'] as String;
    final sessionId = response.data['session_id'] as String;
    return {'access_token': accessToken, 'session_id': sessionId};
  }

  /// Logout: revoke the session.
  Future<void> logout(String sessionId) async {
    await _client.dio.post(
      '/admin/auth/logout',
      data: {'session_id': sessionId},
    );
  }
}
