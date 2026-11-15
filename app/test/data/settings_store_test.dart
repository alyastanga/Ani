import 'package:ani/data/bundle.dart';
import 'package:ani/data/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('empty store has no settings', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await SettingsStore.load();
    expect(s.locale, isNull);
    expect(s.town, isNull);
    expect(s.onboardingComplete, isFalse);
  });

  test('setters persist across loads', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await SettingsStore.load();
    await s.setLocale('fil');
    await s.setTown(Town.munoz);
    await s.setOnboardingComplete(true);
    final again = await SettingsStore.load();
    expect(again.locale, 'fil');
    expect(again.town, Town.munoz);
    expect(again.onboardingComplete, isTrue);
    await again.clear();
    expect(again.locale, isNull);
    expect(again.onboardingComplete, isFalse);
  });

  test('unknown values are ignored', () async {
    SharedPreferences.setMockInitialValues({
      SettingsStore.keyLocale: 'de',
      SettingsStore.keyTown: 'manila',
      SettingsStore.keyOnboardingComplete: true,
    });
    final s = await SettingsStore.load();
    expect(s.locale, isNull);
    expect(s.town, isNull);
    // Onboarding without a valid town is not complete.
    expect(s.onboardingComplete, isFalse);
    expect(() => s.setLocale('de'), throwsArgumentError);
  });
}
