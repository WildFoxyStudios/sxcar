import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/verify_email_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VerifyEmailScreen', () {
    testWidgets('renders code field, verify button, and resend button',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _EmailUnverifiedNotifier(),
            ),
          ],
          child: const MaterialApp(home: VerifyEmailScreen()),
        ),
      );

      expect(find.text('Verify Email'), findsOneWidget);
      expect(find.text('Verification Code'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.text('Resend Code'), findsOneWidget);
    });
  });
}

class _EmailUnverifiedNotifier extends AuthNotifier {
  _EmailUnverifiedNotifier() : super();

  @override
  AuthState build() => const AuthState(
        status: AuthStatus.emailUnverified,
        accessToken: 'token',
        email: 'test@example.com',
      );
}
