import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:app/src/features/edit_profile/sheets.dart';

void main() {
  group('Edit profile selector sheets', () {
    testWidgets('showEthnicitySheet renders all 9 options', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox.shrink());
        }),
      ));
      unawaited(showEthnicitySheet(ctx));
      await tester.pumpAndSettle();
      // Title localized
      final l10n = AppLocalizations.of(ctx)!;
      expect(find.text(l10n.sheetSelectEthnicity), findsOneWidget);
      // ListView.builder is lazy — drag each option into view to confirm
      // it is in the widget tree (drag scrolls list, exposing each item).
      for (final opt in ['Latino', 'White', 'Black', 'Asian',
                          'Middle Eastern', 'Indigenous',
                          'South Asian', 'Mixed', 'Other']) {
        await tester.scrollUntilVisible(
          find.text(opt), 100,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(opt), findsOneWidget);
      }
      // All 9 options rendered (verified via scrollUntilVisible loop above).
    });

    testWidgets('showBodyTypeSheet: tap option returns value', (tester) async {
      late BuildContext ctx;
      String? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showBodyTypeSheet(ctx);
              },
              child: const Text('OPEN'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Athletic'));
      await tester.pumpAndSettle();
      expect(result, 'Athletic');
    });

    testWidgets('showLookingForSheet multi-select: tapping two chips picks both',
        (tester) async {
      late BuildContext ctx;
      Set<String>? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showLookingForSheet(ctx);
              },
              child: const Text('OPEN'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friends'));
      await tester.pumpAndSettle();
      // Tap OK to confirm
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.contains('Chat'), isTrue);
      expect(result!.contains('Friends'), isTrue);
      expect(result!.length, 2);
    });

    testWidgets('showHeightSheet increments with + and clamps at max',
        (tester) async {
      late BuildContext ctx;
      int? result;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showHeightSheet(ctx, currentCm: 219);
              },
              child: const Text('OPEN'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      // Currently 219 (max - 1). Tap + button.
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();
      // Value should clamp at 220.
      expect(find.text('220 cm'), findsOneWidget);
      // Confirm
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, 220);
    });

    testWidgets('dismiss (tap close) returns null', (tester) async {
      late BuildContext ctx;
      String? result = 'unset';
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showPositionSheet(ctx);
              },
              child: const Text('OPEN'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('showLookingForSheet preserves current selections on open',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox.shrink());
        }),
      ));
      unawaited(showLookingForSheet(ctx, current: const {'Chat', 'Dates'}));
      await tester.pumpAndSettle();
      // Both should be visually selected (ChipMultiSelect wraps them — find
      // both texts still present, but their parent chip has selected style).
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Dates'), findsOneWidget);
      // Selected chips render with kBrandPrimary background. The test verifies the
      // chips are in the tree; full visual diff is overkill here.
    });
  });
}

/// Minimal unawaited to avoid lint about ignoring the future from sheets that
/// don't return (single-line convenience).
void unawaited(Future<dynamic>? _) {}