import 'package:app/src/features/pin_screen.dart';
import 'package:app/src/settings/settings_providers.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap({required Widget child, ProviderContainer? container}) {
  final inner = MaterialApp(
    locale: const Locale('es'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: child,
  );
  if (container == null) return ProviderScope(child: inner);
  return UncontrolledProviderScope(container: container, child: inner);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('PinScreen shows PIN entry field and activate button',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _wrap(child: const PinScreen(), container: container),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Activate PIN'), findsOneWidget);
    expect(container.read(pinEnabledProvider), false);
  });

  testWidgets('entering digits and tapping activate calls provider',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _wrap(child: const PinScreen(), container: container),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('Activate PIN'));
    // SharedPreferences in tests uses async method channels; pump to flush.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // The PIN code + enabled state are written via SharedPreferences.
    // Verify the container received the state update.
    expect(container.read(pinEnabledProvider), true);
  });

  testWidgets('remove PIN button shows when PIN is active', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Pre-seed with an active PIN.
    await container.read(pinEnabledProvider.notifier).setPinEnabled(true);
    await tester.pumpWidget(
      _wrap(child: const PinScreen(), container: container),
    );
    await tester.pumpAndSettle();
    expect(find.text('Remove PIN'), findsOneWidget);
    expect(find.text('Update PIN'), findsOneWidget);
  });
}
