import 'package:ani/core/planner.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/planner_profile.dart';
import 'package:ani/features/recommend/recommend_flow.dart';
import 'package:ani/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/farm_harness.dart';
import '../support/tracker_fixtures.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

SavedPlannerProfile _saved(List<String> last, DateTime at) => SavedPlannerProfile(
      profile: PlannerProfile(muni: 'guimba', water: WaterScenario.limited2, last: last, priorities: const ['risk']),
      savedAt: at,
    );

void main() {
  group('RecommendAnswers.prefill last two crops', () {
    test('records fill in when nothing is saved', () {
      final a = RecommendAnswers.prefill(fallbackTown: Town.guimba, recordedLast: ['onion', 'rice']);
      expect([a.lastRecent, a.lastBefore], ['onion', 'rice']);
      expect(a.lastFromRecords, isTrue);
    });

    test("the saved answer stays unless the records are newer", () {
      final saved = _saved(const ['maize'], DateTime.utc(2025, 6, 1));
      final older = RecommendAnswers.prefill(
          saved: saved, recordedLast: ['onion', 'rice'], recordedAt: DateTime.utc(2025, 3, 1));
      expect([older.lastRecent, older.lastBefore], ['maize', null]);
      expect(older.lastFromRecords, isFalse);
      final newer = RecommendAnswers.prefill(
          saved: saved, recordedLast: ['onion', 'rice'], recordedAt: DateTime.utc(2025, 8, 1));
      expect([newer.lastRecent, newer.lastBefore], ['onion', 'rice']);
      expect(newer.water, WaterScenario.limited2, reason: 'other answers keep the saved values');
    });

    test('saved answer with no last crops takes the records', () {
      final a = RecommendAnswers.prefill(
          saved: _saved(const [], DateTime.utc(2025, 6, 1)), recordedLast: ['mungbean'], recordedAt: DateTime.utc(2024));
      expect([a.lastRecent, a.lastBefore], ['mungbean', null]);
    });
  });

  testWidgets('questionnaire step 2 is prefilled from the farm outcome records', (tester) async {
    final c = fixtureCase('guimba|rice|2023-24|rainfed');
    final days = fixtureWeather(c);
    final h = await FarmHarness.start(tester, today: addDays(days.last.date, 1), weather: {Town.guimba: days});
    await h.tracker.addPlanting(
        town: Town.guimba, crop: CropId.rice, plantedOn: days.first.date, water: 'rainfed', s0Frac: n(c['s0_frac']), sync: false);
    expect(h.tracker.lastTwoCrops(town: Town.guimba), [CropId.rice]);
    await h.state.tracker();

    await h.pump(tester, const QuestionnaireScreen());
    await tester.tap(_key('questionnaire-next'));
    await tester.pumpAndSettle();
    expect(_key('q-last-from-records'), findsOneWidget);
    expect(tester.widget<ChoiceTile>(_key('q-recent-rice')).selected, isTrue);
    expect(tester.widget<ChoiceTile>(_key('q-before-none')).selected, isTrue);
  });
}
