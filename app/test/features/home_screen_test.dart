import 'dart:convert';
import 'dart:io';

import 'package:ani/app_state.dart';
import 'package:ani/core/dryness.dart' show dryRank, rankText;
import 'package:ani/core/planner.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/planner_profile.dart';
import 'package:ani/data/settings_store.dart';
import 'package:ani/features/home/home_screen.dart';
import 'package:ani/l10n/app_localizations.dart';
import 'package:ani/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Map<String, dynamic> _json(Town t) => jsonDecode(File(t.assetPath).readAsStringSync()) as Map<String, dynamic>;

/// Serves town bundles from in-memory JSON (falls back to the real files).
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.overrides);

  final Map<String, String> overrides;

  @override
  Future<ByteData> load(String key) async {
    final s = overrides[key] ?? File(key).readAsStringSync();
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(s)));
  }
}

Widget _host(AppState state) => AppScope(
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
          home: const Scaffold(body: HomeScreen()),
        ),
      ),
    );

Future<AppState> _start(
  WidgetTester tester, {
  String locale = 'en',
  Town town = Town.guimba,
  Size size = const Size(900, 3200),
  SavedPlannerProfile? saved,
  Map<String, dynamic>? bundleJson,
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
  final state = bundleJson == null
      ? AppState()
      : AppState(loader: BundleLoader(), assets: _MapBundle({town.assetPath: jsonEncode(bundleJson)}));
  addTearDown(state.dispose);
  await tester.runAsync(state.init);
  await tester.pumpWidget(_host(state));
  await tester.pumpAndSettle();
  return state;
}

SavedPlannerProfile _profile({String muni = 'guimba', String water = WaterScenario.limited2}) => SavedPlannerProfile(
      profile: PlannerProfile(muni: muni, water: water, last: const ['rice', 'rice'], priorities: const ['risk', 'water', 'income']),
      waterSource: WaterSource.pump,
      savedAt: DateTime.utc(2026, 11, 15),
    );

Finder _inKey(String key, Finder f) => find.descendant(of: find.byKey(ValueKey(key)), matching: f);

/// Scrolls the home list to the end, failing on any layout exception.
Future<void> _scrollThrough(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.drag(find.byKey(const ValueKey('home-list')), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }
  expect(find.byKey(const ValueKey('home-alerts')), findsOneWidget);
}

void main() {
  setUp(BundleLoader.instance.clear);

  testWidgets('English Guimba: El Niño card, dryness banner, heat strip, empty states', (tester) async {
    final state = await _start(tester);
    final b = state.bundle!;
    expect(b.enso.isElNino, isTrue);

    // El Niño outlook card.
    expect(_inKey('home-enso', find.text('Inaasahan ang El Niño ngayong tag-araw')), findsOneWidget);
    expect(_inKey('home-enso', find.text('Very strong')), findsOneWidget);
    expect(_inKey('home-enso', find.text('El Niño')), findsOneWidget);
    expect(_inKey('home-enso', find.textContaining(b.enso.comingSeason.toUpperCase())), findsOneWidget);

    // Dryness banner: label, D, rank sentence (D < 0 -> wettest, as in the bundle's "pinakabasa: ika-2").
    expect(b.dryness.latest.label, DrynessLabel.normal);
    expect(b.dryness.latest.rank, 'pinakabasa: ika-2 sa 25 na taon');
    expect(_inKey('home-dryness', find.text('Normal')), findsOneWidget);
    expect(_inKey('home-dryness', find.text('D -1.45')), findsOneWidget);
    expect(_inKey('home-dryness', find.text('No. 2 wettest of 25 years')), findsOneWidget);
    final banner = tester.widget<Container>(find.byKey(const ValueKey('home-dryness')));
    expect((banner.decoration! as BoxDecoration).color, AniColors.statusNormalBg);
    final label = tester.widget<Text>(find.byKey(const ValueKey('home-dryness-label')));
    expect(label.style!.color, AniColors.statusNormal);

    // Heat-safety strip: PAGASA categories from the bundle, safety-only advice.
    expect(_inKey('home-heat', find.text('Heat safety'.toUpperCase())), findsOneWidget);
    expect(_inKey('home-heat', find.text('On Danger days (heat index 42°C and up):')), findsOneWidget);
    expect(_inKey('home-heat', find.text('Magtrabaho nang maaga')), findsOneWidget);
    expect(_inKey('home-heat', find.text('Caution 27–32°C')), findsOneWidget);
    expect(_inKey('home-heat', find.text('Extreme danger 52+°C')), findsOneWidget);
    expect(_inKey('home-heat', find.text("For people's safety only. Not used to choose crops.")), findsOneWidget);

    // CTA, no saved recommendation, empty tracked crop and alerts.
    expect(find.text('What should I plant?'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-last-rec')), findsNothing);
    expect(_inKey('home-crops', find.text('No crop tracked yet.')), findsOneWidget);
    expect(_inKey('home-alerts', find.text('No alerts right now.')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-settings')), findsOneWidget);
  });

  testWidgets('Filipino: doc words stay Filipino, rank sentence in Filipino', (tester) async {
    await _start(tester, locale: 'fil', town: Town.bongabon);
    expect(find.text('Bongabon'), findsOneWidget);
    expect(_inKey('home-enso', find.text('Inaasahan ang El Niño ngayong tag-araw')), findsOneWidget);
    expect(_inKey('home-dryness', find.text('Normal')), findsOneWidget);
    expect(_inKey('home-dryness', find.text('D -1.06')), findsOneWidget);
    expect(_inKey('home-dryness', find.text('Ika-3 sa pinakabasa sa 25 na taon')), findsOneWidget);
    expect(_inKey('home-heat', find.text('Magtrabaho nang maaga')), findsOneWidget);
    expect(find.text('Ano ang dapat kong itanim?'), findsOneWidget);
    expect(find.text('Wala pang binabantayang tanim.'), findsOneWidget);
  });

  test('rank from dryness.monthly matches the bundle rank sentence for every town', () {
    for (final t in Town.values) {
      final dry = AniBundle.fromJsonString(File(t.assetPath).readAsStringSync()).dryness;
      final latest = dry.latest;
      final m = int.parse(latest.month.substring(5, 7));
      final r = dryRank(latest.d, [
        for (final p in dry.monthly)
          if (p.monthOfYear == m && p.month != latest.month) p.d,
      ]);
      expect(rankText(latest.d, r.rank, r.n), latest.rank, reason: t.id);
    }
  });

  testWidgets('Delikado dryness (D >= 0) shows the driest sentence in the Delikado colour', (tester) async {
    final j = _json(Town.guimba);
    final dry = j['dryness'] as Map<String, dynamic>;
    final monthly = [for (final e in dry['monthly'] as List) List<Object?>.from(e as List)];
    monthly.last[1] = 9.0; // the latest month becomes the driest December
    dry['monthly'] = monthly;
    final latestMonth = monthly.last[0] as String;
    dry['latest'] = {'month': latestMonth, 'D': 9.0, 'label': 'delikado', 'rank': null};
    final decembers = monthly.where((e) => (e[0] as String).substring(5) == latestMonth.substring(5)).length;

    await _start(tester, bundleJson: j);
    expect(_inKey('home-dryness', find.text('Delikado')), findsOneWidget);
    expect(_inKey('home-dryness', find.text('D +9.00')), findsOneWidget);
    expect(_inKey('home-dryness', find.text('Driest of $decembers years')), findsOneWidget);
    final banner = tester.widget<Container>(find.byKey(const ValueKey('home-dryness')));
    expect((banner.decoration! as BoxDecoration).color, AniColors.statusDelikadoBg);
    expect(tester.widget<Text>(find.byKey(const ValueKey('home-dryness-label'))).style!.color,
        AniColors.statusDelikado);
  });

  testWidgets('non-El Niño season shows the tag instead of the El Niño headline', (tester) async {
    final j = _json(Town.munoz);
    (j['enso'] as Map<String, dynamic>)
      ..['tag'] = 'neutral'
      ..['jas'] = -0.3;
    await _start(tester, town: Town.munoz, bundleJson: j);
    expect(find.text('Inaasahan ang El Niño ngayong tag-araw'), findsNothing);
    expect(_inKey('home-enso', find.text('Neutral')), findsWidgets);
    expect(_inKey('home-enso', find.text('Weak')), findsNothing);
  });

  testWidgets('CTA opens the questionnaire', (tester) async {
    await _start(tester);
    await tester.tap(find.byKey(const ValueKey('home-cta')));
    await tester.pumpAndSettle();
    expect(find.text('Question 1 of 5'.toUpperCase()), findsOneWidget);
    expect(find.text('Which town is your farm in?'), findsOneWidget);
  });

  testWidgets('last-recommendation button appears only after a profile is saved', (tester) async {
    final state = await _start(tester);
    expect(find.byKey(const ValueKey('home-last-rec')), findsNothing);
    expect(find.text('See last recommendation'), findsNothing);

    await tester.runAsync(() => state.savePlannerProfile(_profile()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-last-rec')), findsOneWidget);
    expect(_inKey('home-last-rec', find.text('Guimba · About 2 irrigations')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-last-rec-open')));
    await pumpUntil(tester, find.byKey(const ValueKey('result-screen')));
    expect(find.text('Munggo'), findsWidgets);
  });

  testWidgets('saved profile from storage shows its town and water level', (tester) async {
    await _start(tester, locale: 'fil', saved: _profile(muni: 'bongabon', water: WaterScenario.full));
    expect(_inKey('home-last-rec', find.text('Bongabon · Patubig kung kailangan')), findsOneWidget);
    expect(find.text('Tingnan ang huling payo'), findsOneWidget);
  });

  for (final locale in ['en', 'fil']) {
    testWidgets('small phone (360x640, $locale): no overflow, every card reachable', (tester) async {
      await _start(tester, locale: locale, town: Town.munoz, size: const Size(360, 640), saved: _profile(muni: 'munoz'));
      expect(tester.takeException(), isNull);
      await _scrollThrough(tester);
    });
  }

  testWidgets('small phone with large text: no overflow', (tester) async {
    await _start(tester, town: Town.munoz, size: const Size(360, 640), saved: _profile(muni: 'munoz'));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _scrollThrough(tester);
  });
}
