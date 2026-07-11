import 'package:app/src/presence/presence_mode_provider.dart';
import 'package:app/src/presence/presence_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No-op presence service so `setIncognito` doesn't fire a real HTTP call
/// during these unit tests (the backend sync is best-effort and covered
/// separately). Only the local state + SharedPreferences behaviour is tested.
class _NoopPresenceService extends PresenceService {
  _NoopPresenceService() : super(Dio());
  @override
  Future<void> setIncognito(bool value) async {}
}

ProviderContainer _makeContainer() => ProviderContainer(
      overrides: [
        presenceServiceProvider.overrideWithValue(_NoopPresenceService()),
      ],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('presenceModeProvider', () {
    test('default state is false (online)', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      expect(container.read(presenceModeProvider), isFalse);
    });

    test('setIncognito(true) changes state to true', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      expect(container.read(presenceModeProvider), isFalse);

      await container
          .read(presenceModeProvider.notifier)
          .setIncognito(true);

      expect(container.read(presenceModeProvider), isTrue);
    });

    test('setIncognito(false) after true reverts to false', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container
          .read(presenceModeProvider.notifier)
          .setIncognito(true);
      expect(container.read(presenceModeProvider), isTrue);

      await container
          .read(presenceModeProvider.notifier)
          .setIncognito(false);
      expect(container.read(presenceModeProvider), isFalse);
    });

    test('persists incognito=true to SharedPreferences', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      await container
          .read(presenceModeProvider.notifier)
          .setIncognito(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('presence_incognito'), isTrue);
    });

    test('hydrates from SharedPreferences on next build', () async {
      // Prime SharedPreferences with true before creating a new container.
      SharedPreferences.setMockInitialValues({
        'presence_incognito': true,
      });

      final container = _makeContainer();
      addTearDown(container.dispose);

      // Initial state is false (default before hydration).
      expect(container.read(presenceModeProvider), isFalse);

      // Allow microtasks to run so _hydrate() can complete.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Now the hydrated value should be true.
      expect(container.read(presenceModeProvider), isTrue);
    });
  });
}
