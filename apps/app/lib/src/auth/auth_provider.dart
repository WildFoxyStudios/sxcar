import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'models.dart';
import 'token_storage.dart';

enum AuthStatus { loading, authenticated, unauthenticated, emailUnverified }

class AuthState {
  final AuthStatus status;
  final String? accessToken;
  final String? email;

  const AuthState({
    this.status = AuthStatus.loading,
    this.accessToken,
    this.email,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? accessToken,
    String? email,
  }) {
    return AuthState(
      status: status ?? this.status,
      accessToken: accessToken ?? this.accessToken,
      email: email ?? this.email,
    );
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage();
});

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  return createAuthClient(storage);
});

final authServiceProvider = Provider<AuthService>((ref) {
  final dio = ref.watch(dioProvider);
  return AuthService(dio);
});

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  String? _currentRefreshToken;

  @override
  AuthState build() {
    return const AuthState();
  }

  Future<void> checkAuth() async {
    final tokenStorage = ref.read(tokenStorageProvider);
    final accessToken = await tokenStorage.getAccessToken();
    if (accessToken != null) {
      _currentRefreshToken = await tokenStorage.getRefreshToken();
      state = AuthState(
        status: AuthStatus.authenticated,
        accessToken: accessToken,
      );
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<TokenPair> login(String email, String password) async {
    final authService = ref.read(authServiceProvider);
    final tokenStorage = ref.read(tokenStorageProvider);

    final pair = await authService.login(
      LoginData(email: email, password: password),
    );
    await tokenStorage.saveTokens(access: pair.access, refresh: pair.refresh);
    _currentRefreshToken = pair.refresh;
    state = AuthState(
      status: AuthStatus.authenticated,
      accessToken: pair.access,
      email: email,
    );
    return pair;
  }

  Future<TokenPair> register({
    required String email,
    required String password,
    required String dob,
    required List<String> consents,
  }) async {
    final authService = ref.read(authServiceProvider);
    final tokenStorage = ref.read(tokenStorageProvider);

    final pair = await authService.register(
      RegisterData(
        email: email,
        password: password,
        dob: dob,
        consents: consents,
      ),
    );
    await tokenStorage.saveTokens(access: pair.access, refresh: pair.refresh);
    _currentRefreshToken = pair.refresh;
    state = AuthState(
      status: AuthStatus.emailUnverified,
      accessToken: pair.access,
      email: email,
    );
    return pair;
  }

  Future<void> verifyEmail(String code) async {
    final authService = ref.read(authServiceProvider);
    await authService.verifyEmail(code);
    state = state.copyWith(status: AuthStatus.authenticated);
  }

  Future<void> logout() async {
    try {
      final authService = ref.read(authServiceProvider);
      if (_currentRefreshToken != null) {
        await authService.logout(_currentRefreshToken!);
      }
    } catch (_) {
      // Ignore logout errors - we clear local state anyway
    }
    final tokenStorage = ref.read(tokenStorageProvider);
    await tokenStorage.clearTokens();
    _currentRefreshToken = null;
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Sign in with Google. Gets the ID token from the Google Sign-In SDK,
  /// sends it to the backend for verification, and stores the resulting
  /// JWT pair. Falls back with [AuthException] on failure.
  Future<TokenPair> signInWithGoogle(String idToken, {String? email}) async {
    final authService = ref.read(authServiceProvider);
    final tokenStorage = ref.read(tokenStorageProvider);

    final pair = await authService.oauthLogin('google', idToken);
    await tokenStorage.saveTokens(access: pair.access, refresh: pair.refresh);
    _currentRefreshToken = pair.refresh;
    state = AuthState(
      status: AuthStatus.authenticated,
      accessToken: pair.access,
      email: email,
    );
    return pair;
  }
}
