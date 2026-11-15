import 'package:ani/app_shell.dart';
import 'package:ani/app_state.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/farm_store.dart';
import 'package:ani/data/kv_store.dart';
import 'package:ani/data/power_client.dart';
import 'package:ani/data/settings_store.dart';
import 'package:ani/data/tracker_service.dart';
import 'package:ani/data/weather_cache.dart';
import 'package:ani/features/about/about_screen.dart';
import 'package:ani/features/alerts/alerts_screen.dart';
import 'package:ani/features/farm/demo_screen.dart';
import 'package:ani/l10n/app_localizations.dart';
import 'package:ani/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/farm_harness.dart';
import '../support/tracker_fixtures.dart';

/// Airplane-mode run-through: every screen and tab renders with the real
/// POWER client / weather repository wired to an HTTP client that always
/// fails, with an empty weather cache (nothing ever synced).
Finder _key(String k) => find.byKey(ValueKey(k));

class _Offline {
  _Offline(this.state, this.tracker, this.requests);
  final AppState state;
  final TrackerService tracker;
  final List<Uri> requests;
}

Future<_Offline> _start(WidgetTester tester, {required String locale, required Size size, bool withPlanting = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    SettingsStore.keyLocale: locale,
    SettingsStore.keyTown: Town.guimba.id,
    SettingsStore.keyOnboardingComplete: true,
  });
  final requests = <Uri>[];
  final client = MockClient((req) async {
    requests.add(req.url);
    throw http.ClientException('Network is unreachable', req.url);
  });
  final now = DateTime.utc(2026, 11, 15);
  final kv = MemoryKvStore();
  final tracker = TrackerService(
    store: FarmStore(kv),
    weather: WeatherRepository(kv: kv, client: PowerClient(client: client), clock: () => now),
    bundleFor: bundleFor,
    clock: () => now,
  );
  final state = AppState(
    loader: FileBundleLoader(),
    openTracker: (_) async => tracker,
    notifier: RecordingNotifier(),
    loadDemoSeasons: () async => demoSeasonsFromFile(),
  );
  addTearDown(state.dispose);
  await tester.runAsync(state.init);
  if (withPlanting) {
    // A planting with no weather at all: tracker shows "waiting for data".
    await tracker.addPlanting(
        town: Town.guimba, crop: CropId.mungbean, plantedOn: DateTime.utc(2026, 11, 1), water: 'full', sync: false);
  }
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
        home: const AppShell(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return _Offline(state, tracker, requests);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).hitTestable().first);
  }
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _pop(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _answer(WidgetTester tester, String water) async {
  await _tap(tester, _key('questionnaire-next')); // town (prefilled)
  await _tap(tester, _key('questionnaire-next')); // last crops: none
  await _tap(tester, _key('q-water-$water'));
  await _tap(tester, _key('questionnaire-next'));
  await _tap(tester, _key('questionnaire-next')); // optional step
  // Answers are kept when starting over, so only pick it if not already.
  if (!tester.widget<ChoiceTile>(_key('q-priority-income')).selected) await _tap(tester, _key('q-priority-income'));
  await _tap(tester, _key('questionnaire-next'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(BundleLoader.instance.clear);

  for (final (locale, size) in [('en', const Size(900, 1800)), ('fil', const Size(360, 640))]) {
    testWidgets('no network ($locale ${size.width.toInt()}x${size.height.toInt()}): every screen and tab renders', (tester) async {
      final o = await _start(tester, locale: locale, size: size);
      void ok() => expect(tester.takeException(), isNull);

      // Home (bundled data only).
      expect(_key('home-dryness'), findsOneWidget);
      ok();

      // Settings sheet, About, demo picker.
      await _tap(tester, _key('home-settings'));
      await _tap(tester, _key('settings-about'));
      expect(find.byType(AboutScreen), findsOneWidget);
      await _pop(tester);
      await _tap(tester, _key('home-settings'));
      await _tap(tester, _key('settings-demo'));
      expect(find.byType(DemoPickerScreen), findsOneWidget);
      await _pop(tester);
      ok();

      // Alerts (empty: nothing synced).
      final ctx = tester.element(find.byType(AppShell));
      openAlerts(ctx).ignore();
      await tester.pumpAndSettle();
      expect(find.byType(AlertsScreen), findsOneWidget);
      ok();
      await _pop(tester);

      // Start -> questionnaire -> Result cards (2 irrigations) and Hold (rainfed).
      await _tap(tester, _key('home-cta'));
      await _answer(tester, 'limited_2');
      await pumpUntilFound(tester, _key('result-screen'));
      expect(_key('result-title'), findsOneWidget);
      ok();
      await _tap(tester, _key('result-again'));
      await _answer(tester, 'rainfed');
      await pumpUntilFound(tester, _key('hold-view'));
      expect(_key('hold-reason'), findsOneWidget);
      ok();
      await _tap(tester, _key('result-close'));

      // Tabs: Outlook, Library (crops), My farm.
      final nav = find.byType(AniBottomNav);
      expect(nav, findsOneWidget);
      for (final i in [1, 2, 3]) {
        final icons = [Icons.home_outlined, Icons.wb_sunny_outlined, Icons.eco_outlined, Icons.agriculture_outlined];
        await tester.tap(find.descendant(of: nav, matching: find.byIcon(icons[i])));
        await tester.pumpAndSettle();
        ok();
      }
      // My farm shows the planting (waiting for data) and its detail.
      expect(_key('farm-list'), findsOneWidget);
      final id = o.tracker.views.single.planting.id;
      await _tap(tester, _key('planting-row-$id'));
      expect(_key('planting-detail'), findsOneWidget);
      await _pop(tester);

      // The app really tried the network and survived the failure.
      o.state.refreshTracker().ignore();
      await tester.pumpAndSettle();
      expect(o.requests, isNotEmpty);
      ok();
    });
  }
}

Future<void> pumpUntilFound(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(f, findsOneWidget);
}
