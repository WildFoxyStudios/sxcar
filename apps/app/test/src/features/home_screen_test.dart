import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsScreen', () {
    testWidgets('shows user email and logout option', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _AuthenticatedNotifier(email: 'test@example.com'),
            ),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
    });

    testWidgets('shows User placeholder when email is null', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _AuthenticatedNotifier(),
            ),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );

      expect(find.text('User'), findsOneWidget);
    });
  });
}

class _AuthenticatedNotifier extends AuthNotifier {
  final String? email;

  _AuthenticatedNotifier({this.email}) : super();

  @override
  AuthState build() => AuthState(
        status: AuthStatus.authenticated,
        accessToken: 'token',
        email: email,
      );

  @override
  Future<void> logout() async {}
}
