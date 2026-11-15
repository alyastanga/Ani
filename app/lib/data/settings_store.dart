import 'package:shared_preferences/shared_preferences.dart';

import 'bundle.dart';
import 'planner_profile.dart';

/// Locally persisted user settings (language, town, onboarding state, the
/// last planner answers).
///
/// Backed by [SharedPreferences]; in tests seed values with
/// `SharedPreferences.setMockInitialValues({...})` before [SettingsStore.load].
class SettingsStore {
  SettingsStore._(this._prefs);

  /// Opens the store.
  static Future<SettingsStore> load() async =>
      SettingsStore._(await SharedPreferences.getInstance());

  static const keyLocale = 'ani.locale';
  static const keyTown = 'ani.town';
  static const keyOnboardingComplete = 'ani.onboardingComplete';
  static const keyPlannerProfile = 'ani.plannerProfile';
  static const keyNotificationsAsked = 'ani.notificationsAsked';

  /// Language codes the app supports.
  static const supportedLocales = {'en', 'fil'};

  final SharedPreferences _prefs;

  /// Saved language code ('en' or 'fil'), or null if none / unknown.
  String? get locale {
    final v = _prefs.getString(keyLocale);
    return supportedLocales.contains(v) ? v : null;
  }

  /// Saved town, or null if none / unknown.
  Town? get town => Town.tryFromId(_prefs.getString(keyTown));

  /// Whether onboarding has been finished (requires a saved town).
  bool get onboardingComplete =>
      (_prefs.getBool(keyOnboardingComplete) ?? false) && town != null;

  Future<void> setLocale(String code) {
    if (!supportedLocales.contains(code)) {
      throw ArgumentError.value(code, 'code', 'unsupported locale');
    }
    return _prefs.setString(keyLocale, code);
  }

  Future<void> setTown(Town town) => _prefs.setString(keyTown, town.id);

  Future<void> setOnboardingComplete(bool value) =>
      _prefs.setBool(keyOnboardingComplete, value);

  /// The last saved planner answers, or null if none / unreadable.
  SavedPlannerProfile? get plannerProfile =>
      SavedPlannerProfile.tryDecode(_prefs.getString(keyPlannerProfile));

  Future<void> setPlannerProfile(SavedPlannerProfile profile) =>
      _prefs.setString(keyPlannerProfile, profile.encode());

  /// Whether the app already asked for notification permission.
  bool get notificationsAsked => _prefs.getBool(keyNotificationsAsked) ?? false;

  Future<void> setNotificationsAsked() => _prefs.setBool(keyNotificationsAsked, true);

  /// Removes all Ani settings.
  Future<void> clear() async {
    await _prefs.remove(keyLocale);
    await _prefs.remove(keyTown);
    await _prefs.remove(keyOnboardingComplete);
    await _prefs.remove(keyPlannerProfile);
    await _prefs.remove(keyNotificationsAsked);
  }
}
