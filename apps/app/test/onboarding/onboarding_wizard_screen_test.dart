import 'package:app/src/auth/auth_provider.dart';
import 'package:app/src/nsfw/nsfw_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/auth/api_client.dart';
import 'package:app/src/onboarding/onboarding_provider.dart';
import 'package:app/src/onboarding/onboarding_wizard_screen.dart';
import 'package:app/l10n/gen/app_localizations.dart';

class _MockApi extends ApiClient {
  _MockApi() : super(baseUrl: 'http://test');
  Map<String, dynamic>? getResponse;

  /// When set, a POST to this path swaps [getResponse] to [onPostResponse]
  /// before the follow-up load() — used to simulate a skip shrinking the list.
  String? shrinkOnPostPath;
  Map<String, dynamic>? onPostResponse;

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    return getResponse ?? {};
  }

  @override
  Future<Map<String, dynamic>> postJson(
      String path, Map<String, dynamic> body) async {
    if (shrinkOnPostPath != null && path == shrinkOnPostPath) {
      getResponse = onPostResponse;
    }
    return {};
  }
}

Map<String, dynamic> _card(String id, String label, {String kind = 'optional'}) => {
      'id': id,
      'label': label,
      'kind': kind,
      'completed': false,
      'skipped_at': null,
      'cta_label': '$label helper copy',
    };

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(Dio()),
        nsfwServiceProvider.overrideWithValue(
          NsfwService.withClassifier(
            (_) async => const NsfwResult(score: 0, isNsfw: false),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: child,
      ),
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

  testWidgets(
      'skipping the last card clamps the index instead of stranding a blank page',
      (tester) async {
    // Two optional cards. Complete the first to advance to the last card,
    // then skip that last card — which shrinks the list to one. Before the
    // clamp fix, _index stayed at 1 (out of bounds) and the user saw a blank
    // page. Now it must clamp back to the remaining card.
    final api = _MockApi()
      ..getResponse = {
        'onboarding_completed': false,
        'onboarding_completed_at': null,
        'cards': [_card('about_me', 'About me'), _card('height', 'Height')],
      }
      // When the skip POST fires, the refreshed list drops 'height'.
      ..shrinkOnPostPath = '/me/onboarding/skip'
      ..onPostResponse = {
        'onboarding_completed': false,
        'onboarding_completed_at': null,
        'cards': [_card('about_me', 'About me')],
      };
    final provider = OnboardingProvider(api);
    await provider.load();
    await tester.pumpWidget(_wrap(OnboardingWizardScreen(provider: provider)));
    await tester.pumpAndSettle();

    // On the first card (About me), index shows "1 / 2".
    expect(find.text('1 / 2'), findsOneWidget);

    // Complete it to advance to the last card (Height).
    await tester.enterText(find.byType(TextField).first, 'hello there');
    await tester.pump();
    await tester.tap(find.text('Next').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Height'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);

    // Skip the last card — list shrinks to one; index must clamp to 0.
    await tester.tap(find.text('Skip').hitTestable());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Height'), findsNothing);
    expect(find.text('About me'), findsWidgets);
    expect(find.text('1 / 1'), findsOneWidget);
  });
}
