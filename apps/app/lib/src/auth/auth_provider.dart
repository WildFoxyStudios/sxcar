import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'jwt_utils.dart';
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

  /// The current user's id, decoded from the access token's `sub` claim.
  /// Null when unauthenticated or the token is malformed.
  String? get userId => jwtSubject(accessToken);

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

/// Resolves when the auth notifier has finished hydrating from storage
/// (status is no longer `loading`). Any screen that fires authenticated
/// requests in initState should `await` this — without it, requests race
/// the storage read and 401 because the Authorization header is missing.
final authReadyProvider = FutureProvider<void>((ref) async {
  while (ref.read(authStateProvider).status == AuthStatus.loading) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
});

class AuthNotifier extends Notifier<AuthState> {
  String? _currentRefreshToken;

  @override
  AuthState build() {
    // Hydrate from storage on the next microtask so the first frame is
    // drawn with status=loading and any initial route that depends on
    // authState (like the splash) can use authReadyProvider to wait.
    // _hydrate publishes the real status (authenticated/unauthenticated)
    // a few milliseconds later, and authReadyProvider signals the transition.
    Future.microtask(_hydrate);
    return const AuthState();
  }

  Future<void> _hydrate() async {
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

  /// Backward-compat alias — some widgets trigger this explicitly.
  Future<void> checkAuth() => _hydrate();

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
