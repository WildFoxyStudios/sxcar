import 'package:app/src/settings/settings_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('settings providers', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    test('units default = 0 (metric)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(unitsProvider), 0);
    });

    test('units set persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(unitsProvider.notifier).setUnits(1);
      expect(container.read(unitsProvider), 1);
      // Re-read from SharedPreferences (simulate restart).
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('settings_units'), 1);
    });

    test('discreetIcon default = false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(discreetIconProvider), false);
    });

    test('discreetIcon set persists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(discreetIconProvider.notifier).setDiscreetIcon(true);
      expect(container.read(discreetIconProvider), true);
    });

    test('pinEnabled default = false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(pinEnabledProvider), false);
    });

    test('visitorStatus default = 0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(visitorStatusProvider), 0);
    });

    test('visitorStatus accepts 0/1/2', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      for (final v in [0, 1, 2]) {
        await container.read(visitorStatusProvider.notifier).setVisitorStatus(v);
        expect(container.read(visitorStatusProvider), v);
      }
    });

    test('visitorStatus rejects invalid values (3)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        () => container.read(visitorStatusProvider.notifier).setVisitorStatus(3),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
