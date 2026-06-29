import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/auth/auth_service.dart';
import 'package:app/src/auth/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fake_token_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('AuthNotifier', () {
    late AuthNotifier notifier;
    late FakeTokenStorage storage;

    setUp(() {
      storage = FakeTokenStorage();
      final container = ProviderContainer(
        overrides: [
          tokenStorageProvider.overrideWithValue(storage),
        ],
      );
      notifier = container.read(authStateProvider.notifier);
    });

    group('checkAuth', () {
      test('sets authenticated when access token exists', () async {
        await storage.saveTokens(access: 'existing_token', refresh: 'refresh');

        await notifier.checkAuth();

        expect(notifier.state.status, equals(AuthStatus.authenticated));
        expect(notifier.state.accessToken, equals('existing_token'));
      });

      test('sets unauthenticated when no access token', () async {
        await notifier.checkAuth();

        expect(notifier.state.status, equals(AuthStatus.unauthenticated));
        expect(notifier.state.accessToken, isNull);
      });
    });

    group('login', () {
      test('sets authenticated on success', () async {
        final container = ProviderContainer(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            authServiceProvider.overrideWithValue(_MockAuthService(
              loginResultOverride: TokenPair(
                access: 'jwt_login',
                refresh: 'opaque_login',
              ),
            )),
          ],
        );
        notifier = container.read(authStateProvider.notifier);

        final pair = await notifier.login('test@example.com', 'pass123!');

        expect(pair.access, equals('jwt_login'));
        expect(pair.refresh, equals('opaque_login'));
        expect(notifier.state.status, equals(AuthStatus.authenticated));
        expect(notifier.state.accessToken, equals('jwt_login'));
        expect(notifier.state.email, equals('test@example.com'));
        expect(await storage.getAccessToken(), equals('jwt_login'));
        expect(await storage.getRefreshToken(), equals('opaque_login'));
      });

      test('re-throws on failure', () async {
        final container = ProviderContainer(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            authServiceProvider.overrideWithValue(_MockAuthService(
              loginErrorOverride: AuthException('Bad credentials'),
            )),
          ],
        );
        notifier = container.read(authStateProvider.notifier);

        expect(
          () => notifier.login('test@example.com', 'wrong'),
          throwsA(isA<AuthException>()),
        );
      });
    });

    group('register', () {
      test('sets emailUnverified on success', () async {
        final container = ProviderContainer(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            authServiceProvider.overrideWithValue(_MockAuthService(
              registerResultOverride: TokenPair(
                access: 'jwt_reg',
                refresh: 'opaque_reg',
              ),
            )),
          ],
        );
        notifier = container.read(authStateProvider.notifier);

        final pair = await notifier.register(
          email: 'new@example.com',
          password: 'pass123!',
          dob: '2000-01-01',
          consents: ['tos', 'privacy', 'age'],
        );

        expect(pair.access, equals('jwt_reg'));
        expect(notifier.state.status, equals(AuthStatus.emailUnverified));
        expect(notifier.state.email, equals('new@example.com'));
        expect(await storage.getAccessToken(), equals('jwt_reg'));
      });
    });

    group('verifyEmail', () {
      test('sets authenticated on success', () async {
        final container = ProviderContainer(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            authServiceProvider.overrideWithValue(_MockAuthService(
              registerResultOverride: TokenPair(
                access: 'jwt_reg',
                refresh: 'opaque_reg',
              ),
            )),
          ],
        );
        notifier = container.read(authStateProvider.notifier);
        await notifier.register(
          email: 'test@example.com',
          password: 'pass123!',
          dob: '2000-01-01',
          consents: ['tos', 'privacy', 'age'],
        );
        expect(notifier.state.status, equals(AuthStatus.emailUnverified));

        await notifier.verifyEmail('123456');

        expect(notifier.state.status, equals(AuthStatus.authenticated));
      });

      test('re-throws on failure', () async {
        final container = ProviderContainer(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            authServiceProvider.overrideWithValue(_MockAuthService(
              verifyEmailErrorOverride: AuthException('Bad code'),
            )),
          ],
        );
        notifier = container.read(authStateProvider.notifier);

        expect(
          () => notifier.verifyEmail('wrong'),
          throwsA(isA<AuthException>()),
        );
      });
    });

    group('logout', () {
      test('clears state and tokens', () async {
        final container = ProviderContainer(
          overrides: [
            tokenStorageProvider.overrideWithValue(storage),
            authServiceProvider.overrideWithValue(_MockAuthService(
              loginResultOverride: TokenPair(
                access: 'jwt_login',
                refresh: 'opaque_login',
              ),
            )),
          ],
        );
        notifier = container.read(authStateProvider.notifier);
        await notifier.login('test@example.com', 'pass123!');
        expect(notifier.state.status, equals(AuthStatus.authenticated));

        await notifier.logout();

        expect(notifier.state.status, equals(AuthStatus.unauthenticated));
        expect(notifier.state.accessToken, isNull);
        expect(await storage.getAccessToken(), isNull);
      });

      test('works even when not authenticated', () async {
        await notifier.logout();
        expect(notifier.state.status, equals(AuthStatus.unauthenticated));
      });
    });
  });
}

class _MockAuthService extends AuthService {
  final TokenPair? loginResultOverride;
  final TokenPair? registerResultOverride;
  final Exception? loginErrorOverride;
  final Exception? verifyEmailErrorOverride;

  _MockAuthService({
    this.loginResultOverride,
    this.registerResultOverride,
    this.loginErrorOverride,
    this.verifyEmailErrorOverride,
  }) : super(Dio());

  @override
  Future<TokenPair> login(LoginData data) async {
    if (loginErrorOverride != null) throw loginErrorOverride!;
    return loginResultOverride!;
  }

  @override
  Future<TokenPair> register(RegisterData data) async {
    return registerResultOverride!;
  }

  @override
  Future<void> verifyEmail(String code) async {
    if (verifyEmailErrorOverride != null) throw verifyEmailErrorOverride!;
  }

  @override
  Future<void> logout(String refresh) async {}
}
