import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/admin_http_client.dart';
import 'admin_auth_service.dart';

enum AuthStatus { unauthenticated, authenticated, loading }

class AuthState {
  final AuthStatus status;
  final String? accessToken;
  final String? sessionId;
  final String? error;
  /// Email captured at login step; shown in the top bar.
  final String? adminEmail;

  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.accessToken,
    this.sessionId,
    this.error,
    this.adminEmail,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? accessToken,
    String? sessionId,
    String? error,
    String? adminEmail,
  }) {
    return AuthState(
      status:      status      ?? this.status,
      accessToken: accessToken ?? this.accessToken,
      sessionId:   sessionId   ?? this.sessionId,
      // error intentionally always overrides (null clears it)
      error:       error,
      // adminEmail persists across copyWith unless a new value is passed
      adminEmail:  adminEmail  ?? this.adminEmail,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Wire 401 interceptor callback to auto-logout on unauthorized
    final client = ref.watch(adminHttpClientProvider);
    client.onUnauthorized = () => _unauthorizedLogout();
    return const AuthState();
  }

  AdminAuthService get _authService => ref.read(adminAuthServiceProvider);
  AdminHttpClient  get _httpClient  => ref.read(adminHttpClientProvider);

  void _unauthorizedLogout() {
    state = const AuthState();
  }

  /// Step 1: Login with email + password. Returns mfa_token.
  Future<String?> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      final mfaToken = await _authService.login(email, password);
      state = state.copyWith(
        status:     AuthStatus.unauthenticated,
        adminEmail: email, // keep email so the top bar can show it after 2FA
      );
      return mfaToken;
    } on DioException catch (e) {
      final msg = _extractErrorMessage(e);
      state = state.copyWith(status: AuthStatus.unauthenticated, error: msg);
      return null;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Connection error. Please try again.',
      );
      return null;
    }
  }

  /// Step 2: Verify TOTP code. Stores JWT on success.
  Future<bool> verify2FA(String mfaToken, String totpCode) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);
    try {
      final result = await _authService.verify2FA(mfaToken, totpCode);
      await _httpClient.setToken(result['access_token']!);
      state = state.copyWith(
        status:      AuthStatus.authenticated,
        accessToken: result['access_token'],
        sessionId:   result['session_id'],
        error:       null,
      );
      return true;
    } on DioException catch (e) {
      final msg = _extractErrorMessage(e);
      state = state.copyWith(status: AuthStatus.unauthenticated, error: msg);
      return false;
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Connection error. Please try again.',
      );
      return false;
    }
  }

  /// Logout.
  Future<void> logout() async {
    try {
      if (state.sessionId != null) {
        await _authService.logout(state.sessionId!);
      }
    } catch (_) {
      // Ignore errors during logout
    }
    await _httpClient.clearToken();
    state = const AuthState();
  }

  /// Clear error.
  void clearError() {
    state = state.copyWith(error: null);
  }

  String _extractErrorMessage(DioException e) {
    if (e.response?.data is Map) {
      final msg = (e.response!.data as Map)['error'];
      if (msg != null) return msg.toString();
    }
    if (e.response?.statusCode == 401) return 'Invalid credentials.';
    if (e.response?.statusCode == 423) return 'Account locked. Try again later.';
    return 'Request failed. Please try again.';
  }
}

final adminAuthServiceProvider = Provider<AdminAuthService>((ref) {
  return AdminAuthService(ref.read(adminHttpClientProvider));
});

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
