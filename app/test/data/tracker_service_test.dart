import 'dart:io';

import 'package:ani/core/field_machine.dart';
import 'package:ani/core/season_replay.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/demo_seasons.dart';
import 'package:ani/data/farm_store.dart';
import 'package:ani/data/kv_store.dart';
import 'package:ani/data/power_client.dart';
import 'package:ani/data/tracker_service.dart';
import 'package:ani/data/weather_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tracker_fixtures.dart';

void main() {
  final cases = {for (final c in fieldMachineCases()) c['id'] as String: c};

  /// A service over a fixture case's days with a movable clock.
  ({TrackerService svc, void Function(DateTime) setToday, List<DailyWeather> days}) serviceFor(Map<String, dynamic> c) {
    final town = Town.tryFromId(c['muni'] as String)!;
    final days = fixtureWeather(c);
    var today = parseYmd(c['sow'] as String)!;
    final svc = TrackerService(
      store: FarmStore.memory(),
      weather: FixedWeather({town: days}),
      bundleFor: bundleFor,
      clock: () => today,
    );
    return (svc: svc, setToday: (d) => today = d, days: days);
  }

  group('tracker replay matches the fixtures day by day', () {
    for (final id in [
      'guimba|rice|2023-24|rainfed',
      'guimba|maize|2024-25|limited_2',
      'munoz|onion|2022-23|full',
      'bongabon|rice|2024-25|limited_2',
      'bongabon|mungbean|2023-24|rainfed',
      'bongabon|sweet_potato|2024-25|limited_2',
    ]) {
      test(id, () async {
        final c = cases[id]!;
        final t = serviceFor(c);
        final cols = (c['columns'] as List).cast<String>();
        final rows = (c['days'] as List).cast<List>();
        final v0 = await t.svc.addPlanting(
            town: Town.tryFromId(c['muni'] as String)!,
            crop: c['crop'] as String,
            plantedOn: t.days.first.date,
            water: c['water'] as String,
            s0Frac: n(c['s0_frac']));
        final pid = v0.planting.id;
        expect(v0.stage, FieldState.prep);
        expect(v0.daysTracked, 0);
        final prm = bundleOf(v0.planting.town).tracker.crops[c['crop']]!.toFieldParams(c['water'] as String);
        for (var i = 0; i < rows.length; i++) {
          t.setToday(addDays(t.days[i].date, 1));
          await t.svc.refresh();
          var v = t.svc.viewFor(pid)!;
          if (v.canConfirmHarvest) v = await t.svc.confirmHarvest(pid);
          final m = fieldMachineFromJson(prm, v.planting.snapshot!.machine);
          expect(m.q.label, rows[i][cols.indexOf('q')], reason: '$id day $i');
          expect(m.G, closeTo(n(rows[i][cols.indexOf('G')]), 1e-6));
          expect(m.S, closeTo(n(rows[i][cols.indexOf('S')]), 1e-4));
          expect(v.waitingForDataDays, 0);
          expect(v.lastDataDay, t.days[i].date);
          if (v.isClosed) break;
        }
        final v = t.svc.viewFor(pid)!;
        final failed = c['outcome']['failed'] as bool;
        expect(v.stage, failed ? FieldState.failed : FieldState.harvest);
        expect(v.planting.closedAs, failed ? OutcomeResult.failed : OutcomeResult.harvest);
        expect(t.svc.outcomes.single.result, v.planting.closedAs);
        expect(t.svc.lastTwoCrops(), [c['crop']]);
        // the timeline has every stage reached in order with dates
        final reached = [for (final s in v.timeline) if (s.reached) s.stage];
        expect(reached.first, FieldState.prep);
        expect(reached.last, v.stage);
        expect(v.timeline.last.stage, v.stage);
        expect(v.timeline.where((s) => s.current).single.stage, v.stage);
        if (failed) {
          expect(v.expectedHarvest, isNull);
          expect(v.alerts.map((a) => a.type), contains(TrackerAlertType.failed));
        } else {
          expect(v.progress, 1.0);
          expect(v.alerts.map((a) => a.type), contains(TrackerAlertType.harvestReady));
        }
      });
    }
  });

  test('alerts are emitted once; replays do not duplicate them', () async {
    final c = cases['guimba|onion|2023-24|rainfed']!;
    final t = serviceFor(c);
    t.setToday(addDays(t.days.first.date, 20));
    final v = await t.svc.addPlanting(
        town: Town.guimba, crop: 'onion', plantedOn: t.days.first.date, water: 'rainfed', s0Frac: n(c['s0_frac']));
    final after20 = t.svc.alerts.length;
    expect((await t.svc.refresh()).newAlerts, isEmpty);
    expect(t.svc.alerts.length, after20);
    t.setToday(addDays(t.days.last.date, 1));
    final r = await t.svc.refresh();
    expect(r.newAlerts.map((a) => a.type), contains(TrackerAlertType.failed));
    expect((await t.svc.refresh()).newAlerts, isEmpty);
    final types = t.svc.alerts.map((a) => a.type).toList();
    expect(types.where((x) => x == TrackerAlertType.failed), hasLength(1));
    expect(types.where((x) => x == TrackerAlertType.waterNow), hasLength(1), reason: 'one stress episode');
    expect(t.svc.unseenAlertCount, t.svc.alerts.length);
    await t.svc.markAlertsSeen();
    expect(t.svc.unseenAlertCount, 0);
    expect(t.svc.viewFor(v.planting.id)!.isClosed, isTrue);
  });

  test('confirm harvest fires transition 7 only once the crop is ready', () async {
    final c = cases['guimba|mungbean|2022-23|full']!;
    final t = serviceFor(c);
    final hd = (c['outcome']['harvest_day'] as num).toInt();
    t.setToday(addDays(t.days.first.date, hd)); // ready day not yet delivered
    final v = await t.svc.addPlanting(
        town: Town.guimba, crop: 'mungbean', plantedOn: t.days.first.date, water: 'full', s0Frac: n(c['s0_frac']));
    expect(v.stage, FieldState.mature);
    expect(v.canConfirmHarvest, isFalse);
    expect(v.expectedHarvest, isNotNull);
    expect(() => t.svc.confirmHarvest(v.planting.id), throwsStateError);

    t.setToday(addDays(t.days.first.date, hd + 5)); // waits in Mature without a confirm
    var w = (await t.svc.refresh()).plantings.single;
    expect(w.stage, FieldState.mature);
    expect(w.canConfirmHarvest, isTrue);
    expect(w.readyOn, addDays(t.days.first.date, hd));
    expect(w.expectedHarvest, DateWindow(w.readyOn!, addDays(w.readyOn!, kHarvestGraceDays)));
    expect(w.alerts.where((a) => a.type == TrackerAlertType.harvestReady).single.date, w.readyOn);

    w = await t.svc.confirmHarvest(v.planting.id, on: t.svc.today);
    final m = fieldMachineFromJson(
        bundleOf(Town.guimba).tracker.crops['mungbean']!.toFieldParams('full'), w.planting.snapshot!.machine);
    expect(m.trace.any((x) => x.guard.startsWith('g7') && x.to == FieldState.harvest), isTrue);
    expect(m.harvestDay, hd);
    expect(w.stage, FieldState.harvest);
    expect(w.isClosed, isTrue);
    expect(w.progress, 1.0);
    expect(w.canConfirmHarvest, isFalse);
    expect(t.svc.outcomes.single.result, OutcomeResult.harvest);
    expect(t.svc.outcomes.single.date, t.svc.today);
    expect(t.svc.lastTwoCrops(), ['mungbean']);
    // closed plantings are frozen
    t.setToday(addDays(t.svc.today, 30));
    expect((await t.svc.refresh()).plantings.single.planting.snapshot!.toJson(), w.planting.snapshot!.toJson());
    expect(() => t.svc.confirmHarvest(v.planting.id), throwsStateError);
  });

  test('add planting validates and defaults the water level', () async {
    final c = cases['guimba|rice|2023-24|rainfed']!;
    final t = serviceFor(c);
    expect(t.svc.defaultWater, 'rainfed');
    await expectLater(
        t.svc.addPlanting(town: Town.guimba, crop: 'wheat', plantedOn: t.days.first.date), throwsArgumentError);
    await expectLater(
        t.svc.addPlanting(town: Town.guimba, crop: 'rice', plantedOn: addDays(t.svc.today, 1)), throwsArgumentError);
    final v = await t.svc.addPlanting(town: Town.guimba, crop: 'rice', plantedOn: t.days.first.date);
    expect(v.planting.water, 'rainfed');
    expect(v.planting.s0Frac, isNull);
    // s0 from the bundle's s0_frac_by_doy
    final s0 = bundleOf(Town.guimba).tracker.s0FracFor(t.days.first.date)!;
    expect(TrackerService.s0FracFor(bundleOf(Town.guimba).tracker, t.days.first.date), s0);
    expect(v.soilWaterFraction, closeTo(s0, 1e-9));
    await t.svc.removePlanting(v.planting.id);
    expect(t.svc.views, isEmpty);
  });

  group('with POWER over a mocked HTTP client', () {
    // raw POWER values of a real season, delivered with a 3-day lag
    final season = DemoSeasons.parse(File('assets/fixtures/demo_seasons.json').readAsStringSync())
        .firstWhere((s) => s.town == Town.bongabon);
    var today = addDays(season.sow, 40);
    var down = false;
    var requests = 0;
    http.Client client() => MockClient((rq) async {
          requests++;
          if (down) throw http.ClientException('airplane mode');
          final s = parseYmd(rq.url.queryParameters['start'])!, e = parseYmd(rq.url.queryParameters['end'])!;
          final out = [
            for (var d = s; !d.isAfter(e); d = addDays(d, 1))
              if (!d.isBefore(addDays(today, -3))) DailyWeather(date: d)
              else season.days.where((x) => x.date == d).firstOrNull ?? DailyWeather(date: d),
          ];
          return http.Response(powerBody(out, elev: 282.04), 200);
        });

    setUp(() {
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues({});
      today = addDays(season.sow, 40);
      down = false;
      requests = 0;
    });

    test('waiting for data, then survives a restart offline', () async {
      final svc = await TrackerService.open(bundleFor: bundleFor, httpClient: client(), clock: () => today);
      final v = await svc.addPlanting(town: Town.bongabon, crop: 'onion', plantedOn: season.sow, water: 'limited_4');
      expect(requests, 1);
      expect(v.daysTracked, 37);
      expect(v.waitingForDataDays, 3, reason: 'days 38-40 not published yet');
      expect(v.lastDataDay, addDays(season.sow, 36));
      expect(v.stage.isGrowing, isTrue);
      expect(v.expectedHarvest!.start.isAfter(v.lastDataDay!), isTrue);

      // on-device ET0 (bundle point, response elevation) matches power_prep within rounding
      final repo = svc.weather as WeatherRepository;
      final cached = {for (final d in repo.daysFor(Town.bongabon)) d.date: d};
      for (final d in season.days.take(37)) {
        expect(cached[d.date]!.et0!, closeTo(d.et0!, 0.011), reason: '${d.date}');
      }

      // restart: same storage, no network
      final saved = <String, Object>{};
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        saved[k] = prefs.get(k)!;
      }
      SharedPreferences.resetStatic();
      SharedPreferences.setMockInitialValues(saved);
      down = true;
      today = addDays(today, 2);
      final svc2 = await TrackerService.open(bundleFor: bundleFor, httpClient: client(), clock: () => today);
      final r = await svc2.refresh();
      expect(r.offline, isTrue);
      expect(r.syncs.single.status, SyncStatus.offline);
      final v2 = r.plantings.single;
      expect(v2.planting.id, v.planting.id);
      expect(v2.stage, v.stage);
      expect(v2.daysTracked, 37);
      expect(v2.waitingForDataDays, 5);
      expect(v2.planting.snapshot!.toJson(), v.planting.snapshot!.toJson());
      expect(svc2.alerts.map((a) => a.id), svc.alerts.map((a) => a.id));
      expect(r.newAlerts, isEmpty);

      // back online: POWER catches up
      down = false;
      final r3 = await svc2.refresh();
      expect(r3.syncs.single.status, SyncStatus.fetched);
      expect(r3.plantings.single.daysTracked, 39);
      expect(r3.plantings.single.waitingForDataDays, 3);
    });
  });
}
