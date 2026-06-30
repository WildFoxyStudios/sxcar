import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RegisterScreen', () {
    testWidgets('renders form fields, consent checkbox, and register button',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _UnauthenticatedNotifier(),
            ),
          ],
          child: const MaterialApp(home: RegisterScreen()),
        ),
      );

      expect(find.text('Register'), findsWidgets);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password (min 8 characters)'), findsOneWidget);
      expect(find.text('Date of Birth'), findsOneWidget);
      expect(
        find.text('I accept the terms and privacy policy (I am 18+)'),
        findsOneWidget,
      );
      expect(
        find.text('Already have an account? Login'),
        findsOneWidget,
      );
    });
  });
}

class _UnauthenticatedNotifier extends AuthNotifier {
  _UnauthenticatedNotifier() : super();

  @override
  AuthState build() =>
      const AuthState(status: AuthStatus.unauthenticated);
}
