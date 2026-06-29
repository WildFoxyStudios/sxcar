import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/features/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HomeScreen', () {
    testWidgets('shows welcome message and email', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _AuthenticatedNotifier(email: 'test@example.com'),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.text('Welcome to proyecto-X'), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
    });

    testWidgets('shows User when email is null', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(
              () => _AuthenticatedNotifier(),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.text('Welcome to proyecto-X'), findsOneWidget);
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
