import 'package:app/src/features/discreet_icon_picker_screen.dart';
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

  testWidgets('DiscreetIconPickerScreen shows two options', (tester) async {
    await tester.pumpWidget(
      _wrap(child: const DiscreetIconPickerScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Vibra'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(2));
  });

  testWidgets('tapping Discreet toggles provider', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      _wrap(child: const DiscreetIconPickerScreen(), container: container),
    );
    await tester.pumpAndSettle();
    expect(container.read(discreetIconProvider), false);
    await tester.tap(find.byType(InkWell).at(1));
    await tester.pumpAndSettle();
    expect(container.read(discreetIconProvider), true);
  });
}