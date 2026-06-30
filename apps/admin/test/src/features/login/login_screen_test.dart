import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin/main.dart';

void main() {
  testWidgets('LoginScreen shows email and password fields', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: AdminApp(),
      ),
    );

    // Wait for the login screen to render
    await tester.pump();

    // Check all key elements are present
    expect(find.text('Admin Login'), findsOneWidget);
    expect(find.byIcon(Icons.email_outlined), findsOneWidget);
    expect(find.byIcon(Icons.lock_outlined), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
