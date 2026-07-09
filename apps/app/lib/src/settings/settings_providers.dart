import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage = FlutterSecureStorage();

// ────────────────────────────────────────────────────────────────────────────
// unitsProvider
//
// 0 = Metric (km, °C)
// 1 = Imperial (mi, °F)
// ────────────────────────────────────────────────────────────────────────────

const _kUnitsKey = 'settings_units';

class UnitsNotifier extends Notifier<int> {
  @override
  int build() {
    _hydrate();
    return 0; // default metric
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_kUnitsKey) ?? 0;
    if (state != v && (v == 0 || v == 1)) state = v;
  }

  Future<void> setUnits(int v) async {
    assert(v == 0 || v == 1, 'units must be 0 or 1');
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUnitsKey, v);
  }
}

final unitsProvider = NotifierProvider<UnitsNotifier, int>(UnitsNotifier.new);

// ────────────────────────────────────────────────────────────────────────────
// discreetIconProvider
//
// bool — true if user has enabled the discreet (alternate) app icon.
// ────────────────────────────────────────────────────────────────────────────

const _kDiscreetIconKey = 'settings_discreet_icon';

class DiscreetIconNotifier extends Notifier<bool> {
  @override
  bool build() {
    _hydrate();
    return false;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_kDiscreetIconKey) ?? false;
    if (state != v) state = v;
  }

  Future<void> setDiscreetIcon(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDiscreetIconKey, v);
  }
}

final discreetIconProvider =
    NotifierProvider<DiscreetIconNotifier, bool>(DiscreetIconNotifier.new);

// ────────────────────────────────────────────────────────────────────────────
// pinEnabledProvider
//
// bool — true if user has a PIN lock on app launch.
// ────────────────────────────────────────────────────────────────────────────

const _kPinEnabledKey = 'settings_pin_enabled';

class PinEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    _hydrate();
    return false;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_kPinEnabledKey) ?? false;
    if (state != v) state = v;
  }

  Future<void> setPinEnabled(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPinEnabledKey, v);
  }
}

final pinEnabledProvider =
    NotifierProvider<PinEnabledNotifier, bool>(PinEnabledNotifier.new);

// ────────────────────────────────────────────────────────────────────────────
// pinCodeProvider
//
// String — 4-digit PIN code stored in platform keychain via
// flutter_secure_storage.
// ────────────────────────────────────────────────────────────────────────────

const _kPinCodeKey = 'settings_pin_code';

class PinCodeNotifier extends Notifier<String> {
  @override
  String build() {
    _hydrate();
    return '';
  }

  Future<void> _hydrate() async {
    final v = await _secureStorage.read(key: _kPinCodeKey) ?? '';
    if (state != v) state = v;
  }

  Future<void> setPinCode(String code) async {
    state = code;
    if (code.isEmpty) {
      await _secureStorage.delete(key: _kPinCodeKey);
    } else {
      await _secureStorage.write(key: _kPinCodeKey, value: code);
    }
  }
}

final pinCodeProvider =
    NotifierProvider<PinCodeNotifier, String>(PinCodeNotifier.new);

// ────────────────────────────────────────────────────────────────────────────
// visitorStatusProvider
//
// int — 0=disabled, 1=enabled, 2=auto (mirrors backend visitor_status column
// from T2.1, but kept LOCAL for now — no backend sync in this task).
// ────────────────────────────────────────────────────────────────────────────

const _kVisitorStatusKey = 'settings_visitor_status';

class VisitorStatusNotifier extends Notifier<int> {
  @override
  int build() {
    _hydrate();
    return 0; // default disabled
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_kVisitorStatusKey) ?? 0;
    if (state != v && (v == 0 || v == 1 || v == 2)) state = v;
  }

  Future<void> setVisitorStatus(int v) async {
    assert(v >= 0 && v <= 2, 'visitor_status must be 0, 1, or 2');
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kVisitorStatusKey, v);
  }
}

final visitorStatusProvider =
    NotifierProvider<VisitorStatusNotifier, int>(VisitorStatusNotifier.new);

// ────────────────────────────────────────────────────────────────────────────
// Boolean display/privacy preference toggles (device-local, SharedPreferences).
// Previously these lived as ephemeral local state in SettingsScreen and reset
// on navigation; now each persists via its own key.
// ────────────────────────────────────────────────────────────────────────────

class _BoolPrefNotifier extends Notifier<bool> {
  _BoolPrefNotifier(this._key, this._default);
  final String _key;
  final bool _default;

  @override
  bool build() {
    _hydrate();
    return _default;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_key) ?? _default;
    if (state != v) state = v;
  }

  Future<void> set(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, v);
  }
}

final showAlbumUpdatesProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier('settings_show_album_updates', true));

final showCarouselProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier('settings_show_carousel', true));

final markChattedProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier('settings_mark_chatted', true));

final chatSyncProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier('settings_chat_sync', true));

final keepScreenUnlockedProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier('settings_keep_unlocked', false));
