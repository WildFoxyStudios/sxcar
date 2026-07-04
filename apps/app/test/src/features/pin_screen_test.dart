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

  testWidgets('PinScreen shows PIN toggle', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _wrap(child: const PinScreen(), container: container),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
    expect(container.read(pinEnabledProvider), false);
  });

  testWidgets('toggling switch flips pinEnabledProvider', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _wrap(child: const PinScreen(), container: container),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(container.read(pinEnabledProvider), true);
  });
}