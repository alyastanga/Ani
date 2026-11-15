import 'package:ani/core/field_machine.dart';
import 'package:ani/core/planner.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/farm_store.dart';
import 'package:ani/data/planner_profile.dart';
import 'package:ani/features/farm/add_planting_screen.dart';
import 'package:ani/features/farm/farm_screen.dart';
import 'package:ani/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/farm_harness.dart';
import '../support/tracker_fixtures.dart';

Finder _key(String k) => find.byKey(ValueKey(k));
Finder _in(String k, Finder f) => find.descendant(of: _key(k), matching: f);

SavedPlannerProfile _profile(String water) => SavedPlannerProfile(
      profile: PlannerProfile(muni: 'guimba', water: water, priorities: const ['risk']),
      savedAt: DateTime.utc(2022, 11, 1),
    );

void main() {
  const mungbean = 'guimba|mungbean|2022-23|full';

  testWidgets('empty state, then add planting with irrigation prefilled from the profile', (tester) async {
    final c = fixtureCase(mungbean);
    final days = fixtureWeather(c);
    final h = await FarmHarness.start(tester,
        today: addDays(days.first.date, 20),
        weather: {Town.guimba: days},
        saved: _profile(WaterScenario.limited4));
    await h.pump(tester, const Scaffold(body: FarmScreen()));

    expect(_key('farm-empty'), findsOneWidget);
    expect(find.text('No plantings yet'), findsOneWidget);
    expect(_key('farm-demo'), findsOneWidget);

    await tester.tap(_key('farm-add-empty'));
    await tester.pumpAndSettle();
    expect(find.byType(AddPlantingScreen), findsOneWidget);
    expect(tester.widget<Text>(_key('add-planting-town')).data, contains('Guimba'));

    // Save stays disabled until a crop is picked.
    FilledButton save() => tester.widget<FilledButton>(find.descendant(of: _key('add-save'), matching: find.byType(FilledButton)));
    expect(save().onPressed, isNull);

    // Irrigation is prefilled from the saved planner answers, with a note.
    final water4 = tester.widget<ChoiceTile>(_key('add-water-limited_4'));
    expect(water4.selected, isTrue);
    expect(find.textContaining('Filled in from your last planner answers'), findsOneWidget);
    expect(find.textContaining('Only matters for onion'), findsOneWidget);

    // Crop names come from planner.NAME.
    for (final n in ['Palay', 'Sibuyas', 'Munggo', 'Mais', 'Kamote']) {
      expect(find.text(n), findsOneWidget);
    }
    await tester.tap(_key('add-crop-mungbean'));
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.tap(_key('add-save'));
    await tester.pumpAndSettle();

    expect(find.byType(AddPlantingScreen), findsNothing);
    final p = h.tracker.store.plantings().single;
    expect(p.crop, CropId.mungbean);
    expect(p.water, WaterScenario.limited4);
    expect(p.method, PlantingMethod.direct);
    expect(p.plantedOn, h.tracker.today);
    // Permission is asked once, after the first planting (not on launch).
    expect(h.notifier.permissionRequests, 1);

    expect(_key('farm-empty'), findsNothing);
    expect(_key('planting-row-${p.id}'), findsOneWidget);
    expect(_in('planting-stage-${p.id}', find.text('Prep')), findsOneWidget);
    expect(find.text('0% of the season'), findsOneWidget);
  });

  testWidgets('row shows progress and waiting-for-data; detail timeline, harvest window and confirm harvest',
      (tester) async {
    final c = fixtureCase(mungbean);
    final days = fixtureWeather(c);
    // Data up to day 30; three complete days after it are still missing.
    final h = await FarmHarness.start(tester, today: addDays(days[30].date, 4), weather: {Town.guimba: days.sublist(0, 31)});
    final v0 = await h.tracker.addPlanting(
        town: Town.guimba, crop: CropId.mungbean, plantedOn: days.first.date, water: 'full', s0Frac: n(c['s0_frac']), sync: false);
    final id = v0.planting.id;
    await h.pump(tester, const Scaffold(body: FarmScreen()));

    final v = h.tracker.viewFor(id)!;
    expect(v.waitingForDataDays, 3);
    expect(_key('planting-waiting-$id'), findsOneWidget);
    expect(find.text('3 days waiting for data'), findsOneWidget);
    expect(find.text('${(v.progress * 100).round()}% of the season'), findsOneWidget);

    await tester.tap(_key('planting-row-$id'));
    await tester.pumpAndSettle();
    expect(_key('planting-detail'), findsOneWidget);
    expect(_key('stage-timeline'), findsOneWidget);
    for (final s in ['Prep', 'Estab', 'Veg', 'Repro', 'Mature', 'Harvest']) {
      expect(_key('timeline-$s'), findsOneWidget, reason: s);
    }
    // Reached stages show their date, the rest "Not yet".
    expect(_in('timeline-Mature', find.text('Not yet')), findsOneWidget);
    expect(_in('timeline-Prep', find.text('Not yet')), findsNothing);
    expect(_key('detail-harvest-window'), findsOneWidget);
    expect(_in('detail-last-data', find.textContaining('Weather data up to')), findsOneWidget);
    expect(find.textContaining('NASA POWER publishes a few days late'), findsOneWidget);
    expect(_key('detail-confirm-harvest'), findsNothing);

    // All the data arrives; the crop waits in Mature for the farmer.
    h.today = addDays(days.last.date, 1);
    (h.tracker.weather as FixedWeather).byTown[Town.guimba] = days;
    await h.state.refreshTracker();
    await tester.pumpAndSettle();
    expect(h.tracker.viewFor(id)!.canConfirmHarvest, isTrue);
    expect(_in('detail-stage', find.text('Maturing')), findsOneWidget);
    expect(find.textContaining('Ready since'), findsOneWidget);
    expect(_in('detail-alerts', find.text('Ready to harvest')), findsOneWidget);

    await tester.ensureVisible(_key('detail-confirm-harvest'));
    await tester.tap(_key('detail-confirm-harvest'));
    await tester.pumpAndSettle();

    final done = h.tracker.viewFor(id)!;
    expect(done.stage, FieldState.harvest);
    expect(done.isClosed, isTrue);
    expect(_key('detail-confirm-harvest'), findsNothing);
    expect(_in('detail-outcome', find.textContaining('Harvested on')), findsOneWidget);
    expect(_in('detail-stage', find.text('Harvest')), findsOneWidget);
    expect(h.tracker.outcomes.single.result, OutcomeResult.harvest);

    // Back on My farm it moves to past seasons.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('PAST SEASONS'), findsOneWidget);
    expect(find.text('GROWING NOW'), findsNothing);
  });

  testWidgets('failed planting shows the outcome; remove deletes it after confirming', (tester) async {
    final c = fixtureCase('guimba|rice|2023-24|rainfed');
    final days = fixtureWeather(c);
    final h = await FarmHarness.start(tester, today: addDays(days.last.date, 1), weather: {Town.guimba: days});
    final v0 = await h.tracker.addPlanting(
        town: Town.guimba, crop: CropId.rice, plantedOn: days.first.date, water: 'rainfed', s0Frac: n(c['s0_frac']), sync: false);
    final id = v0.planting.id;
    await h.pump(tester, const Scaffold(body: FarmScreen()));

    expect(_in('planting-stage-$id', find.text('Failed')), findsOneWidget);
    await tester.tap(_key('planting-row-$id'));
    await tester.pumpAndSettle();
    expect(_in('detail-outcome', find.textContaining('Crop failed on')), findsOneWidget);
    expect(_key('timeline-Failed'), findsOneWidget);
    expect(_key('timeline-Harvest'), findsNothing);
    expect(_key('detail-harvest-window'), findsNothing);
    // Failed advice refers to the MAO in Filipino (doc-quoted).
    expect(find.textContaining('Kumonsulta sa MAO'), findsWidgets);

    await tester.ensureVisible(_key('detail-remove'));
    await tester.tap(_key('detail-remove'));
    await tester.pumpAndSettle();
    await tester.tap(_key('remove-confirm'));
    await tester.pumpAndSettle();
    expect(_key('planting-detail'), findsNothing);
    expect(_key('farm-empty'), findsOneWidget);
    expect(h.tracker.store.plantings(), isEmpty);
    // The outcome record stays (feeds next season's "last two crops").
    expect(h.tracker.outcomes.single.crop, CropId.rice);
  });

  testWidgets('small phone in Filipino: my farm, detail and add planting have no overflow', (tester) async {
    final c = fixtureCase('guimba|maize|2022-23|full');
    final days = fixtureWeather(c);
    final h = await FarmHarness.start(tester,
        locale: 'fil',
        size: const Size(360, 640),
        today: addDays(days[60].date, 5),
        weather: {Town.guimba: days.sublist(0, 61)});
    final open = await h.tracker.addPlanting(
        town: Town.guimba, crop: CropId.maize, plantedOn: days.first.date, water: 'full', s0Frac: n(c['s0_frac']), sync: false);
    await h.tracker.addPlanting(
        town: Town.guimba,
        crop: CropId.onion,
        plantedOn: days[10].date,
        method: PlantingMethod.transplant,
        water: 'limited_2',
        sync: false);
    await h.pump(tester, const Scaffold(body: FarmScreen()));
    expect(find.text('Aking bukid'), findsOneWidget);
    await scrollThrough(tester, _key('farm-list'), steps: 6);

    await tester.drag(_key('farm-list'), const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(_key('planting-row-${open.planting.id}'));
    await tester.pumpAndSettle();
    await scrollThrough(tester, _key('planting-detail-list'), steps: 10);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.ensureVisible(_key('farm-add'));
    await tester.tap(_key('farm-add'));
    await tester.pumpAndSettle();
    expect(find.text('Magdagdag ng tanim'), findsWidgets);
    await scrollThrough(tester, _key('add-planting-list'), steps: 10);
  });
}
