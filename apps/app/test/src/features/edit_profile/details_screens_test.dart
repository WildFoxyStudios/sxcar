import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/features/edit_profile/add_trip_screen.dart';
import 'package:app/src/features/edit_profile/vaccines_screen.dart';
import 'package:app/src/features/edit_profile/practices_screen.dart';

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: screen,
  ));
}

void main() {
  group('AddTripScreen', () {
    testWidgets('renders empty state when no trips', (tester) async {
      await _pumpScreen(
        tester,
        AddTripScreen(current: const [], onChanged: (_) {}),
      );
      expect(find.textContaining('Añade tus viajes'), findsOneWidget);
    });

    testWidgets('renders existing trips + add FAB', (tester) async {
      await _pumpScreen(
        tester,
        AddTripScreen(
          current: const [
            TripEntry(date: 'Mar 2024', location: 'Madrid'),
          ],
          onChanged: (_) {},
        ),
      );
      expect(find.text('Madrid'), findsOneWidget);
      expect(find.textContaining('Mar 2024'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('delete icon removes entry and calls onChanged',
        (tester) async {
      List<TripEntry>? captured;
      await _pumpScreen(
        tester,
        AddTripScreen(
          current: const [TripEntry(date: 'Mar 2024', location: 'Madrid')],
          onChanged: (next) => captured = next,
        ),
      );
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.length, 0);
    });
  });

  group('VaccinesScreen', () {
    testWidgets('tapping a vaccine adds it via onChanged', (tester) async {
      Set<String>? captured;
      await _pumpScreen(
        tester,
        VaccinesScreen(current: const <String>{}, onChanged: (s) => captured = s),
      );
      await tester.tap(find.text('covid'));
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      expect(captured!.contains('covid'), isTrue);
    });
  });

  group('PracticesScreen', () {
    testWidgets('renders all practice chips', (tester) async {
      await _pumpScreen(
        tester,
        PracticesScreen(current: const <String>{}, onChanged: (_) {}),
      );
      // Sanity-check first three options are present.
      expect(find.text('Oral'), findsOneWidget);
      expect(find.text('Anal'), findsOneWidget);
      expect(find.text('Versátil'), findsOneWidget);
    });
  });
}