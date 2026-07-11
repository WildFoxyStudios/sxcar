import 'package:flutter_test/flutter_test.dart';
import 'package:app/src/auth/api_client.dart';
import 'package:app/src/onboarding/onboarding_provider.dart';

class _MockApi extends ApiClient {
  _MockApi() : super(baseUrl: 'http://test');
  Map<String, dynamic>? getResponse;
  Map<String, dynamic>? postResponse;
  String? lastPostPath;
  Map<String, dynamic>? lastPostBody;
  int getCalls = 0;
  int postCalls = 0;

  @override
  Future<Map<String, dynamic>> getJson(String path) async {
    getCalls++;
    return getResponse ?? {};
  }

  @override
  Future<Map<String, dynamic>> postJson(
      String path, Map<String, dynamic> body) async {
    postCalls++;
    lastPostPath = path;
    lastPostBody = body;
    return postResponse ?? {};
  }
}

void main() {
  group('OnboardingProvider', () {
    test('load() parses 14 cards and reports onboardingCompleted=false', () async {
      final api = _MockApi()
        ..getResponse = {
          'onboarding_completed': false,
          'onboarding_completed_at': null,
          'cards': List.generate(14, (i) => {
                'id': 'card_$i',
                'label': 'Card $i',
                'kind': i < 4 ? 'required' : 'optional',
                'completed': false,
                'skipped_at': null,
                'cta_label': 'CTA $i',
              }),
        };
      final p = OnboardingProvider(api);
      await p.load();
      expect(p.state!.onboardingCompleted, false);
      expect(p.state!.cards.length, 14);
      expect(p.needsOnboarding, true);
    });

    test('completeCard posts to the right path and refreshes state', () async {
      final api = _MockApi()
        ..getResponse = {
          'onboarding_completed': true,
          'onboarding_completed_at': '2026-07-06T12:00:00Z',
          'cards': [],
        };
      final p = OnboardingProvider(api);
      await p.completeCard('display_name', {'display_name': 'Test'});
      expect(api.lastPostPath, '/me/onboarding/cards/display_name/complete');
      expect(api.lastPostBody, {'display_name': 'Test'});
      expect(api.postCalls, 1);
      expect(api.getCalls, 1); // reload after complete
    });
  });
}
