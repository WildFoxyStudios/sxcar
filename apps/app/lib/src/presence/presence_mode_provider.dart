import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPresenceIncognitoKey = 'presence_incognito';

/// Tracks whether the current user is in Incognito mode (true) or Online
/// (false). The state is eagerly initialised to false and then hydrated from
/// SharedPreferences on the first build, so the UI starts as Online and
/// transitions as soon as the pref is read.
class PresenceModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    _hydrate();
    return false; // default: online
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final incognito = prefs.getBool(_kPresenceIncognitoKey) ?? false;
    // Only mutate if actually different to avoid unnecessary rebuilds.
    if (state != incognito) state = incognito;
  }

  /// Switches between Online (false) and Incognito (true) and persists the
  /// preference so it survives app restarts.
  Future<void> setIncognito(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPresenceIncognitoKey, value);
  }
}

/// Provider for the current presence mode.
/// `true` → Incognito (heartbeat disabled, profile hidden from grids).
/// `false` → Online (default).
final presenceModeProvider =
    NotifierProvider<PresenceModeNotifier, bool>(PresenceModeNotifier.new);
