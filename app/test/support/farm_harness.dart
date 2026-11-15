import 'dart:io';

import 'package:ani/app_state.dart';
import 'package:ani/data/alert_notifier.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/demo_seasons.dart';
import 'package:ani/data/farm_store.dart';
import 'package:ani/data/kv_store.dart';
import 'package:ani/data/planner_profile.dart';
import 'package:ani/data/power_client.dart';
import 'package:ani/data/settings_store.dart';
import 'package:ani/data/tracker_service.dart';
import 'package:ani/l10n/app_localizations.dart';
import 'package:ani/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tracker_fixtures.dart';

/// Serves town bundles from the asset files synchronously (no rootBundle
/// isolate work inside fake async).
class FileBundleLoader extends BundleLoader {
  @override
  Future<AniBundle> load(Town town, {AssetBundle? bundle}) async => bundleOf(town);
}

/// Records what the app asked the notifier to do.
class RecordingNotifier implements AlertNotifier {
  final List<List<AlertNotice>> shown = [];
  int permissionRequests = 0;

  @override
  Future<bool?> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> show(List<AlertNotice> notices) async => shown.add(notices);
}

List<DemoSeason> demoSeasonsFromFile() => DemoSeasons.parse(File(DemoSeasons.assetPath).readAsStringSync());

Map<String, dynamic> fixtureCase(String id) => fieldMachineCases().firstWhere((c) => c['id'] == id);

/// App state + tracker wired for widget tests: in-memory farm store, fixed
/// fixture weather, a movable clock and a recording notifier.
class FarmHarness {
  FarmHarness._(this.state, this.tracker, this.notifier, this._setToday);

  final AppState state;
  final TrackerService tracker;
  final RecordingNotifier notifier;
  final void Function(DateTime) _setToday;

  set today(DateTime d) => _setToday(d);

  static Future<FarmHarness> start(
    WidgetTester tester, {
    String locale = 'en',
    Town town = Town.guimba,
    Size size = const Size(900, 3000),
    required DateTime today,
    Map<Town, List<DailyWeather>> weather = const {},
    SavedPlannerProfile? saved,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      SettingsStore.keyLocale: locale,
      SettingsStore.keyTown: town.id,
      SettingsStore.keyOnboardingComplete: true,
      if (saved != null) SettingsStore.keyPlannerProfile: saved.encode(),
    });
    var now = today;
    final svc = TrackerService(
      // Same key the app shares with the settings store, so defaultWater
      // follows the saved planner profile.
      store: FarmStore(MemoryKvStore({if (saved != null) SettingsStore.keyPlannerProfile: saved.encode()})),
      weather: FixedWeather(weather),
      bundleFor: bundleFor,
      clock: () => now,
    );
    final notifier = RecordingNotifier();
    final state = AppState(
      loader: FileBundleLoader(),
      openTracker: (_) async => svc,
      notifier: notifier,
      loadDemoSeasons: () async => demoSeasonsFromFile(),
    );
    addTearDown(state.dispose);
    await tester.runAsync(state.init);
    return FarmHarness._(state, svc, notifier, (d) => now = d);
  }

  /// Pumps [home] inside the app's theme, localizations and [AppScope].
  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          theme: AniTheme.light(),
          locale: state.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: home,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  AppLocalizations get l => lookupAppLocalizations(Locale(state.localeCode ?? 'en'));
}

/// Scrolls [list] to the end in steps, failing on any layout exception.
Future<void> scrollThrough(WidgetTester tester, Finder list, {int steps = 25}) async {
  for (var i = 0; i < steps; i++) {
    await tester.drag(list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
}
