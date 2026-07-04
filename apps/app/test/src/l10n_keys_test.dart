import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 1 l10n keys (T1.6 fix + T1.11 cleanup)', () {
    final required = ['precioContinuar', 'precioTotal', 'compraSimulada', 'planActivo'];

    for (final arb in ['lib/l10n/app_es.arb', 'lib/l10n/app_en.arb']) {
      test('$arb contains all required keys', () {
        final content = File(arb).readAsStringSync();
        for (final key in required) {
          expect(content, contains('"$key":'),
              reason: '$arb is missing key $key');
        }
      });
    }

    test('generated localizations_es.dart exposes getters', () {
      final content = File('lib/l10n/gen/app_localizations_es.dart').readAsStringSync();
      for (final key in required) {
        // price-taking keys are methods (String nombre(...)); simple keys are getters.
        final hasGetter = content.contains('String get $key');
        final hasMethod = RegExp(r'String ' + key + r'\(').hasMatch(content);
        expect(hasGetter || hasMethod, isTrue,
            reason: 'app_localizations_es.dart missing getter/method for $key');
      }
    });

    test('generated localizations_en.dart exposes getters', () {
      final content = File('lib/l10n/gen/app_localizations_en.dart').readAsStringSync();
      for (final key in required) {
        final hasGetter = content.contains('String get $key');
        final hasMethod = RegExp(r'String ' + key + r'\(').hasMatch(content);
        expect(hasGetter || hasMethod, isTrue,
            reason: 'app_localizations_en.dart missing getter/method for $key');
      }
    });
  });
}