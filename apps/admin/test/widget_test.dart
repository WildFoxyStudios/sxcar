import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: AdminApp(),
      ),
    );

    // Allow async operations to settle
    await tester.pumpAndSettle();

    // Verify login screen is shown
    expect(find.text('Admin Login'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
