import 'dart:io';

import 'package:ani/app_state.dart';
import 'package:ani/core/planner.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/planner_profile.dart';
import 'package:ani/data/settings_store.dart';
import 'package:ani/features/recommend/recommend_flow.dart';
import 'package:ani/features/recommend/recommend_labels.dart' show pct0, peso;
import 'package:ani/l10n/app_localizations.dart';
import 'package:ani/theme/theme.dart';
import 'package:flutter/material.dart';
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

AniBundle _bundle(Town t) => AniBundle.fromJsonString(File(t.assetPath).readAsStringSync());

/// A host page with buttons for the two public entry points.
Widget _host(AppState state, {Widget? home}) => AppScope(
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
          home: home ??
              Builder(
                builder: (context) => Scaffold(
                  body: Column(
                    children: [
                      TextButton(
                        key: const ValueKey('open-flow'),
                        onPressed: () => openRecommendFlow(context),
                        child: const Text('open'),
                      ),
                      TextButton(
                        key: const ValueKey('reopen'),
                        onPressed: () => openLastRecommendation(context),
                        child: const Text('reopen'),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      ),
    );

Future<AppState> _start(WidgetTester tester,
    {required String locale, String town = 'guimba', Widget? home, Size size = const Size(900, 3200)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    SettingsStore.keyLocale: locale,
    SettingsStore.keyTown: town,
    SettingsStore.keyOnboardingComplete: true,
  });
  final state = AppState();
  addTearDown(state.dispose);
  await tester.runAsync(state.init);
  await tester.pumpWidget(_host(state, home: home));
  await tester.pumpAndSettle();
  return state;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) =>
    tester.widget<PrimaryButton>(find.byKey(ValueKey(key))).onPressed != null;

void main() {
  setUp(BundleLoader.instance.clear);

  testWidgets('questionnaire: Guimba, ~2 irrigations -> Munggo card, saved and reopened', (tester) async {
    final state = await _start(tester, locale: 'en');
    await _tap(tester, 'open-flow');

    // Step 1: town prefilled from app state.
    expect(find.text('Question 1 of 5'.toUpperCase()), findsOneWidget);
    expect(find.text('Which town is your farm in?'), findsOneWidget);
    expect(tester.widget<ChoiceTile>(find.byKey(const ValueKey('q-town-guimba'))).selected, isTrue);
    await _tap(tester, 'questionnaire-next');

    // Step 2: last two crops.
    expect(find.text('What were your last two crops?'), findsOneWidget);
    await _tap(tester, 'q-recent-rice');
    await _tap(tester, 'q-before-rice');
    await _tap(tester, 'questionnaire-next');

    // Step 3: water source + irrigations (required).
    expect(_enabled(tester, 'questionnaire-next'), isFalse);
    await _tap(tester, 'q-source-rain');
    expect(tester.widget<ChoiceTile>(find.byKey(const ValueKey('q-water-rainfed'))).selected, isTrue);
    await _tap(tester, 'q-source-pump');
    await _tap(tester, 'q-water-limited_2');
    await _tap(tester, 'questionnaire-next');

    // Step 4: won't plant + cold storage (optional).
    expect(find.text("Any crops you won't plant?"), findsOneWidget);
    await _tap(tester, 'questionnaire-next');

    // Step 5: rank top 3.
    expect(find.text('See advice'), findsOneWidget);
    expect(_enabled(tester, 'questionnaire-next'), isFalse);
    for (final c in ['risk', 'water', 'income', 'soil']) {
      await _tap(tester, 'q-priority-$c');
    }
    expect(find.text('3 of 3 picked'.toUpperCase()), findsOneWidget);
    expect(tester.widget<ChoiceTile>(find.byKey(const ValueKey('q-priority-soil'))).selected, isFalse);

    // Back keeps answers.
    await _tap(tester, 'questionnaire-back');
    await _tap(tester, 'questionnaire-next');
    expect(find.text('3 of 3 picked'.toUpperCase()), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('questionnaire-next')));
    await pumpUntil(tester, find.byKey(const ValueKey('result-screen')));
    await tester.pumpAndSettle();

    final want = planWithBundle(
      const PlannerProfile(
        muni: 'guimba',
        water: 'limited_2',
        last: ['rice', 'rice'],
        priorities: ['risk', 'water', 'income'],
      ),
      _bundle(Town.guimba),
    );
    final card = want.cards.single;
    expect(find.text('Suggested crops'), findsOneWidget);
    expect(find.byKey(const ValueKey('card-mungbean')), findsOneWidget);
    expect(find.text('Munggo'), findsOneWidget);
    expect(find.text('Mung bean'), findsOneWidget);
    expect(find.text('Bakit?'.toUpperCase()), findsOneWidget);
    for (final w in card.why) {
      expect(find.text(w), findsOneWidget);
    }
    expect(find.text('Failed in ${card.failed} of ${card.seasons} El Niño years'), findsOneWidget);
    expect(find.text('Likely range ${pct0(card.failLo)}–${pct0(card.failHi)}'), findsOneWidget);
    expect(find.text('Water needed: ${card.waterMm} mm'), findsOneWidget);
    expect(find.text('Net income: ${peso(card.net.p10)} to ${peso(card.net.p90)} per hectare'), findsOneWidget);
    expect(find.text('Confidence: ${card.confidence == Confidence.medium ? 'Medium' : card.confidence}'),
        findsOneWidget);
    expect(find.text('Small local market: check with the MAO'), findsOneWidget);

    // Saved locally.
    final saved = state.plannerProfile!;
    expect(saved.profile.muni, 'guimba');
    expect(saved.profile.water, 'limited_2');
    expect(saved.profile.last, ['rice', 'rice']);
    expect(saved.profile.priorities, ['risk', 'water', 'income']);
    expect(saved.waterSource, WaterSource.pump);
    final prefs = await SharedPreferences.getInstance();
    expect(SavedPlannerProfile.tryDecode(prefs.getString(SettingsStore.keyPlannerProfile))!.profile.water,
        'limited_2');

    // Done -> host; reopen shows the same card.
    await _tap(tester, 'result-done');
    expect(find.byKey(const ValueKey('result-screen')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reopen')));
    await pumpUntil(tester, find.byKey(const ValueKey('card-mungbean')));
    await tester.pumpAndSettle();

    // "Answer again" reopens the questionnaire with the saved answers.
    await _tap(tester, 'result-again');
    expect(find.byKey(const ValueKey('questionnaire')), findsOneWidget);
    await _tap(tester, 'questionnaire-next');
    expect(tester.widget<ChoiceTile>(find.byKey(const ValueKey('q-recent-rice'))).selected, isTrue);
  });

  testWidgets('questionnaire (Filipino): rainfed Guimba -> Hold screen with planner text', (tester) async {
    await _start(tester, locale: 'fil');
    await _tap(tester, 'open-flow');
    expect(find.text('Saang bayan ang inyong bukid?'), findsOneWidget);
    await _tap(tester, 'questionnaire-next');
    await _tap(tester, 'questionnaire-next'); // last crops: None
    await _tap(tester, 'q-water-rainfed');
    await _tap(tester, 'questionnaire-next');
    await _tap(tester, 'questionnaire-next');
    await _tap(tester, 'q-priority-income');
    expect(find.text('Tingnan ang payo'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('questionnaire-next')));
    await pumpUntil(tester, find.byKey(const ValueKey('hold-view')));
    await tester.pumpAndSettle();

    final want = planWithBundle(
      const PlannerProfile(muni: 'guimba', water: 'rainfed', priorities: ['income']),
      _bundle(Town.guimba),
    );
    expect(want.isHold, isTrue);
    final m = want.message!;
    expect(find.text('Huwag munang magtanim'), findsOneWidget);
    expect(find.text(m.reason), findsOneWidget);
    expect(m.reason, contains('walang patubig'));
    expect(find.text(m.tip), findsOneWidget);
    expect(find.text('Kumonsulta sa MAO'), findsOneWidget);
    expect(find.text('Tinanggal: Mais, Munggo, Sibuyas, Palay, Kamote'), findsOneWidget);
    expect(find.byKey(const ValueKey('card-mungbean')), findsNothing);
  });

  testWidgets('close on step 1 returns to the caller', (tester) async {
    await _start(tester, locale: 'en');
    await _tap(tester, 'open-flow');
    await _tap(tester, 'questionnaire-close');
    expect(find.byKey(const ValueKey('questionnaire')), findsNothing);
    expect(find.byKey(const ValueKey('open-flow')), findsOneWidget);
  });

  testWidgets('reopen with nothing saved opens the questionnaire', (tester) async {
    await _start(tester, locale: 'en');
    await _tap(tester, 'reopen');
    expect(find.byKey(const ValueKey('questionnaire')), findsOneWidget);
  });

  group('result rendering', () {
    SavedPlannerProfile saved(PlannerProfile p) =>
        SavedPlannerProfile(profile: p, savedAt: DateTime.utc(2026, 11, 15));

    testWidgets('as needed, no cold storage: Sibuyas with the onion price-risk warning', (tester) async {
      const p = PlannerProfile(
        muni: 'bongabon',
        water: 'full',
        last: ['rice', 'rice'],
        priorities: ['income', 'risk', 'water'],
      );
      final r = planWithBundle(p, _bundle(Town.bongabon));
      await _start(tester, locale: 'en', town: 'bongabon', home: ResultScreen(saved: saved(p), result: r));
      expect(r.cards, hasLength(3));
      for (final (i, c) in r.cards.indexed) {
        expect(find.byKey(ValueKey('card-${c.crop}')), findsOneWidget);
        expect(find.text('No. ${i + 1}'.toUpperCase()), findsOneWidget);
      }
      expect(find.text('Sibuyas'), findsOneWidget);
      expect(find.byKey(const ValueKey('card-onion-price-risk')), findsOneWidget);
      expect(find.text('No cold storage: high price risk'), findsOneWidget);
      expect(find.text('Bakit?'.toUpperCase()), findsNWidgets(3));
      expect(find.text('Bongabon · Irrigate as needed'), findsOneWidget);
    });

    testWidgets('Low confidence card shows the MAO referral', (tester) async {
      const p = PlannerProfile(muni: 'bongabon', water: 'rainfed', priorities: ['risk']);
      final r = planWithBundle(p, _bundle(Town.bongabon));
      final card = r.cards.single;
      expect(card.confidence, Confidence.low);
      await _start(tester, locale: 'fil', town: 'bongabon', home: ResultScreen(saved: saved(p), result: r));
      expect(find.byKey(const ValueKey('card-mungbean-mao')), findsOneWidget);
      expect(find.text('Kumonsulta sa MAO'), findsOneWidget);
      expect(find.text('Katiyakan: Mababa'), findsOneWidget);
      // Filipino risk line is the planner's own "X sa Y" sentence.
      final fil = lookupAppLocalizations(const Locale('fil'));
      final line = fil.cardFailedSeasonsElNino(card.failed, card.seasons);
      expect(card.riskText, '$line (${pct0(card.failLo)}–${pct0(card.failHi)})');
      expect(find.text(line), findsOneWidget);
    });

    testWidgets('English Hold screen names the blocking guard and crops', (tester) async {
      const p = PlannerProfile(muni: 'munoz', water: 'rainfed');
      final r = planWithBundle(p, _bundle(Town.munoz));
      await _start(tester, locale: 'en', town: 'munoz', home: ResultScreen(saved: saved(p), result: r));
      expect(find.text('Huwag munang magtanim'), findsOneWidget);
      expect(find.text('The chance of crop failure is too high for your water supply this El Niño.'),
          findsOneWidget);
      expect(find.text('Ruled out: Mais, Munggo, Sibuyas, Palay, Kamote'), findsOneWidget);
      expect(find.byKey(const ValueKey('hold-tip')), findsOneWidget);
      expect(find.text('Kumonsulta sa MAO'), findsOneWidget);
    });

    testWidgets('small phone (360x640, Filipino): no overflow on any step or the cards', (tester) async {
      await _start(tester, locale: 'fil', town: 'bongabon', size: const Size(360, 640));
      await _tap(tester, 'open-flow');
      await _tap(tester, 'questionnaire-next');
      await _tap(tester, 'questionnaire-next');
      await tester.scrollUntilVisible(find.byKey(const ValueKey('q-water-full')), 200,
          scrollable: find.byType(Scrollable).first);
      await _tap(tester, 'q-water-full');
      await _tap(tester, 'questionnaire-next');
      await _tap(tester, 'questionnaire-next');
      await _tap(tester, 'q-priority-income');
      await tester.tap(find.byKey(const ValueKey('questionnaire-next')));
      await pumpUntil(tester, find.byKey(const ValueKey('result-screen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('card-onion')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('result-done')), 300,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });
  });
}
