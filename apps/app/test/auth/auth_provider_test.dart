import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/auth/auth_provider.dart';

void main() {
  group('AuthState.needsOnboarding', () {
    test('is false when user is unauthenticated (no user)', () {
      const state = AuthState(
        status: AuthStatus.unauthenticated,
        onboardingCompleted: false,
      );
      expect(state.needsOnboarding, false);
    });

    test('is true when user is authenticated and onboarding not completed', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test',
        onboardingCompleted: false,
      );
      expect(state.needsOnboarding, true);
    });

    test('is false when user is authenticated and onboarding completed', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test',
        onboardingCompleted: true,
      );
      expect(state.needsOnboarding, false);
    });

    test('defaults onboardingCompleted to true for backward compat', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'test',
      );
      expect(state.onboardingCompleted, true);
      expect(state.needsOnboarding, false);
    });

    test('copyWith preserves onboardingCompleted when not overridden', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        onboardingCompleted: false,
      );
      final copy = state.copyWith(accessToken: 'new-token');
      expect(copy.onboardingCompleted, false);
      expect(copy.needsOnboarding, true);
    });

    test('copyWith overrides onboardingCompleted when specified', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        onboardingCompleted: false,
      );
      final copy = state.copyWith(
        status: AuthStatus.authenticated,
        onboardingCompleted: true,
      );
      expect(copy.onboardingCompleted, true);
      expect(copy.needsOnboarding, false);
    });
  });
}
