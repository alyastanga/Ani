import 'dart:io';

import 'package:ani/core/field_machine.dart';
import 'package:ani/core/season_replay.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/demo_seasons.dart';
import 'package:ani/data/farm_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tracker_fixtures.dart';

void main() {
  final seasons = DemoSeasons.parse(File(DemoSeasons.assetPath).readAsStringSync());

  test('three demo seasons, one per town', () {
    expect(seasons.map((s) => s.id), [
      'guimba|rice|2023-24|full',
      'munoz|onion|2004-05|rainfed',
      'bongabon|onion|2011-12|limited_4',
    ]);
    for (final s in seasons) {
      expect(s.days.first.date, s.sow);
      expect(s.days.every((d) => d.usable), isTrue);
      expect(s.days.length, greaterThan(s.expectedStates.length));
      expect(s.replayLabel, startsWith('Replay: '));
    }
  });

  final emitted = <TrackerAlertType>{};

  for (final s in seasons) {
    test('${s.id}: replay matches fsm.py day by day and shows ${s.shows.map((t) => t.name).join(', ')}', () async {
      final demo = DemoReplay(s, bundleOf(s.town));
      expect(demo.isDemo, isTrue);
      final prm = bundleOf(s.town).tracker.crops[s.crop]!.toFieldParams(s.water);
      for (var i = 0; i < s.expectedStates.length; i++) {
        await demo.advanceTo(i + 1);
        var v = demo.view!;
        if (v.canConfirmHarvest) v = await demo.confirmHarvest();
        final m = fieldMachineFromJson(prm, v.planting.snapshot!.machine);
        expect(m.q.label, s.expectedStates[i], reason: '${s.id} day $i');
        if (v.isClosed) break;
      }
      final v = demo.view!;
      expect(v.isDemo, isTrue);
      expect(v.planting.isDemo, isTrue);
      expect(v.stage, s.expectedFailed ? FieldState.failed : FieldState.harvest);
      expect(v.planting.closedAs, s.expectedFailed ? OutcomeResult.failed : OutcomeResult.harvest);
      final types = demo.alerts.map((a) => a.type).toSet();
      expect(types, containsAll(s.shows));
      expect(demo.alerts.every((a) => a.isDemo), isTrue);
      emitted.addAll(types);
      demo.dispose();
    });
  }

  test('across the demo every alert type appears', () async {
    final all = <TrackerAlertType>{};
    for (final s in seasons) {
      final demo = DemoReplay(s, bundleOf(s.town));
      final alerts = await demo.runToEnd();
      expect(alerts.map((a) => a.id).toSet(), hasLength(alerts.length), reason: 'no duplicates');
      expect(demo.alerts, hasLength(alerts.length));
      all.addAll(alerts.map((a) => a.type));
    }
    expect(all, TrackerAlertType.values.toSet());
    expect(emitted, anyOf(isEmpty, all), reason: 'per-season tests agree when run together');
  });

  test('runToEnd plays a season through and confirms the harvest', () async {
    final s = seasons.first;
    final demo = DemoReplay(s, bundleOf(s.town));
    final alerts = await demo.runToEnd();
    expect(demo.view!.stage, FieldState.harvest);
    expect(demo.view!.planting.snapshot!.readyOn, addDays(s.sow, s.expectedHarvestDay!));
    expect(alerts.map((a) => a.type), containsAll([TrackerAlertType.heatAtFlowering, TrackerAlertType.harvestReady]));
    expect(demo.service.outcomes.single.result, OutcomeResult.harvest);
    // unconfirmed: waits in Mature to the end of the bundled days
    final d2 = DemoReplay(s, bundleOf(s.town));
    await d2.runToEnd(confirmHarvest: false);
    expect(d2.atEnd, isTrue);
    expect(d2.view!.stage, FieldState.mature);
    expect(d2.view!.canConfirmHarvest, isTrue);
  });
}
