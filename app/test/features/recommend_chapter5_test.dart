import 'dart:io';

import 'package:ani/core/planner.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/planner_profile.dart';
import 'package:ani/features/recommend/answers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Doc Chapter 5 results, reproduced through the questionnaire's answer
/// mapping ([RecommendAnswers.toProfile]) and the bundled town JSON
/// ([planWithBundle]), as the app runs them.
final Map<Town, AniBundle> _bundles = {
  for (final t in Town.values) t: AniBundle.fromJsonString(File(t.assetPath).readAsStringSync()),
};

const _priorityOrders = [
  ['risk', 'water', 'income'],
  ['income', 'risk', 'water'],
  ['soil', 'pest', 'water'],
  ['income'],
];

const _lastCrops = [
  ('rice', 'rice'),
  (null, null),
];

PlanResult _run(Town town, String water, List<String> priorities, (String?, String?) last) {
  final a = RecommendAnswers(
    town: town,
    lastRecent: last.$1,
    lastBefore: last.$2,
    water: water,
    priorities: [...priorities],
  );
  return planWithBundle(a.toProfile(), _bundles[town]!);
}

Set<String> _kept(PlanResult r) =>
    CropId.all.toSet().difference(r.blocked.values.expand((v) => v).toSet());

void main() {
  test('coming season is El Niño in every bundle (doc: El Niño mode)', () {
    for (final b in _bundles.values) {
      expect(b.enso.isElNino, isTrue);
    }
  });

  for (final town in [Town.guimba, Town.munoz]) {
    group('${town.id} (doc Ch.5)', () {
      for (final pr in _priorityOrders) {
        for (final last in _lastCrops) {
          final tag = '$pr last=${last.$1},${last.$2}';

          test('rainfed -> Hold, g2 water $tag', () {
            final r = _run(town, WaterScenario.rainfed, pr, last);
            expect(r.isHold, isTrue);
            expect(r.blockingGuard, Guard.water);
            expect(r.message!.title, 'Huwag munang magtanim');
            expect(r.message!.refer, 'Kumonsulta sa MAO');
          });

          test('about 2 irrigations -> Munggo $tag', () {
            final r = _run(town, WaterScenario.limited2, pr, last);
            expect(r.state, 'Advise');
            expect(r.cards.map((c) => c.name), ['Munggo']);
          });

          test('about 4 irrigations -> Kamote / Mais / Munggo $tag', () {
            final r = _run(town, WaterScenario.limited4, pr, last);
            expect(_kept(r), {CropId.sweetPotato, CropId.maize, CropId.mungbean});
            expect(r.cards.map((c) => c.name).toSet(), {'Kamote', 'Mais', 'Munggo'});
          });

          test('as needed -> all five pass, Sibuyas on the cards with price-risk $tag', () {
            final r = _run(town, WaterScenario.full, pr, last);
            expect(_kept(r), CropId.all.toSet());
            expect(r.cards, hasLength(3));
            final onion = r.cards.singleWhere((c) => c.name == 'Sibuyas');
            expect(onion.flags, contains('Walang cold storage: mataas ang panganib sa presyo'));
          });
        }
      }
    });
  }

  test('cold storage removes the onion price-risk flag (g3 is soft)', () {
    final a = RecommendAnswers(
      town: Town.guimba,
      lastRecent: 'rice',
      lastBefore: 'rice',
      water: WaterScenario.full,
      coldStorage: true,
      priorities: ['income'],
    );
    final r = planWithBundle(a.toProfile(), _bundles[Town.guimba]!);
    final onion = r.cards.singleWhere((c) => c.crop == CropId.onion);
    expect(onion.flags, isNot(contains('Walang cold storage: mataas ang panganib sa presyo')));
  });

  test('won\'t-plant answers feed g4', () {
    final a = RecommendAnswers(
      town: Town.munoz,
      water: WaterScenario.limited2,
      wont: {CropId.mungbean},
      priorities: ['risk'],
    );
    final r = planWithBundle(a.toProfile(), _bundles[Town.munoz]!);
    expect(r.isHold, isTrue);
    expect(r.blocked[Guard.farmer], [CropId.mungbean]);
  });
}
