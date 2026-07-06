import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/auth/api_client.dart';
import 'package:app/src/onboarding/models.dart';
import 'package:app/src/onboarding/onboarding_provider.dart';
import 'package:app/src/onboarding/onboarding_wizard_screen.dart';
import 'package:app/l10n/gen/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class _MockApi extends ApiClient {
  _MockApi() : super(baseUrl: 'http://test');
  Map<String, dynamic>? getResponse;

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    return getResponse ?? {};
  }

  @override
  Future<Map<String, dynamic>> postJson(
      String path, Map<String, dynamic> body) async {
    return {};
  }
}

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    );

void main() {
  testWidgets('wizard renders first card and shows the close button',
      (tester) async {
    final api = _MockApi()
      ..getResponse = {
        'onboarding_completed': false,
        'onboarding_completed_at': null,
        'cards': [
          {
            'id': 'profile_photo',
            'label': 'Profile photo',
            'kind': 'required',
            'completed': false,
            'skipped_at': null,
            'cta_label': 'Add a photo',
          },
        ],
      };
    final provider = OnboardingProvider(api);
    await provider.load();
    await tester.pumpWidget(_wrap(OnboardingWizardScreen(provider: provider)));
    await tester.pumpAndSettle();
    expect(find.text('Profile photo'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
