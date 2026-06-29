import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('renders email, password, login button and register link',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _UnauthenticatedNotifier(),
            ),
          ],
          child: const MaterialApp(home: LoginScreen()),
        ),
      );

      expect(find.text('Login'), findsWidgets);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(
        find.text("Don't have an account? Register"),
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
