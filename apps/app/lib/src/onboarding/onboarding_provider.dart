import 'package:flutter/foundation.dart';
import '../auth/api_client.dart';
import 'models.dart';

class OnboardingProvider extends ChangeNotifier {
  OnboardingProvider(this._api);
  final ApiClient _api;

  OnboardingState? _state;
  bool _loading = false;
  String? _error;

  OnboardingState? get state => _state;
  bool get loading => _loading;
  String? get error => _error;
  bool get needsOnboarding => _state != null && !_state!.onboardingCompleted;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _api.getJson('/me/onboarding');
      _state = OnboardingState.fromJson(res);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> completeCard(String cardId, Map<String, dynamic> body) async {
    try {
      await _api.postJson('/me/onboarding/cards/$cardId/complete', body);
      await load();
      return _state?.onboardingCompleted ?? false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return _state?.onboardingCompleted ?? false;
    }
  }

  Future<void> skipCards(List<String> cardIds) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _api.postJson('/me/onboarding/skip', {'card_ids': cardIds});
      await load();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> forceComplete() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _api.postJson('/me/onboarding/complete', const {});
      await load();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
