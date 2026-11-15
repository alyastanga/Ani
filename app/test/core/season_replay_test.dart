import 'package:ani/core/field_machine.dart';
import 'package:ani/core/season_replay.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/kv_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tracker_fixtures.dart';

const _tol = 1e-6;

/// The bundle rounds TAW to 2 dp, so S drifts by ~1e-6 mm from the fixture's exact TAW.
const _tolS = 1e-4;

void main() {
  final cases = fieldMachineCases();

  List<SeasonDay> days(Map<String, dynamic> c) => [for (final d in fixtureWeather(c)) d.toSeasonDay()];

  Params prmOf(Map<String, dynamic> c) =>
      bundleOf(Town.tryFromId(c['muni'] as String)!).tracker.crops[c['crop']]!.toFieldParams(c['water'] as String);

  group('replaySeason matches the fixtures (bundle params, simulating)', () {
    for (final c in cases) {
      test(c['id'], () {
        final cols = (c['columns'] as List).cast<String>();
        int ix(String k) => cols.indexOf(k);
        final rows = (c['days'] as List).cast<List>();
        final prm = prmOf(c);
        final sow = parseYmd(c['sow'] as String)!;
        final r = replaySeason(prm, n(c['s0_frac']) * prm.taw, days(c), plantedOn: sow, simulating: true,
            onTick: (i, d, m, out) {
          final row = rows[i];
          expect(m.q.label, row[ix('q')], reason: 'day $i q');
          expect(m.G, closeTo(n(row[ix('G')]), _tol), reason: 'day $i G');
          expect(m.S, closeTo(n(row[ix('S')]), _tolS), reason: 'day $i S');
          expect(out, (row[ix('alerts')] as List).cast<String>(), reason: 'day $i alerts');
        });
        expect(r.dates, hasLength(rows.length));
        expect([for (final t in r.machine.trace) t.toList()], c['transitions']);
      });
    }
  });

  test('live mode waits in Mature until confirmed; confirm reproduces the simulating run', () {
    var checked = 0;
    for (final c in cases.where((c) => c['outcome']['harvest_day'] != null)) {
      final prm = prmOf(c);
      final sow = parseYmd(c['sow'] as String)!;
      final hd = (c['outcome']['harvest_day'] as num).toInt();
      final live = replaySeason(prm, n(c['s0_frac']) * prm.taw, days(c), plantedOn: sow);
      expect(live.machine.q, FieldState.mature, reason: c['id']);
      expect(live.readyOn, addDays(sow, hd), reason: c['id']);
      expect(live.events.where((e) => e.type == TrackerAlertType.harvestReady).single.dayIndex, hd);
      final confirmed = replaySeason(prm, n(c['s0_frac']) * prm.taw, days(c), plantedOn: sow, confirmHarvest: true);
      expect(confirmed.machine.q, FieldState.fallow);
      expect(confirmed.machine.harvestDay, hd);
      expect([for (final t in confirmed.machine.trace) t.toList()], c['transitions']);
      checked++;
    }
    expect(checked, greaterThan(20));
  });

  test('alert mapping: episodes of water_stress, water_fail -> failed', () {
    for (final c in cases) {
      final rows = (c['days'] as List).cast<List>();
      final cols = (c['columns'] as List).cast<String>();
      final alertsAt = [for (final r in rows) (r[cols.indexOf('alerts')] as List).cast<String>()];
      final irrAt = [for (final r in rows) (r[cols.indexOf('n_irr')] as num).toInt()];
      final prm = prmOf(c);
      final r = replaySeason(prm, n(c['s0_frac']) * prm.taw, days(c),
          plantedOn: parseYmd(c['sow'] as String)!, simulating: true);
      // expected waterNow episode starts
      final starts = <int>[];
      var prev = false;
      for (var i = 0; i < rows.length; i++) {
        final now = alertsAt[i].contains('water_stress') || irrAt[i] > (i == 0 ? 0 : irrAt[i - 1]);
        if (now && !prev) starts.add(i);
        prev = now;
      }
      expect([for (final e in r.events) if (e.type == TrackerAlertType.waterNow) e.dayIndex], starts, reason: c['id']);
      final failDay = alertsAt.indexWhere((a) => a.contains('water_fail'));
      final failed = [for (final e in r.events) if (e.type == TrackerAlertType.failed) e.dayIndex];
      expect(failed, failDay < 0 ? isEmpty : [failDay], reason: c['id']);
      if (failDay >= 0) expect(r.readyOn, isNull);
    }
  });

  test('heat and rot episodes are emitted once per run of days', () {
    final prm = Params(
        crop: 'onion', taw: 100, p: 0.3, kcIni: 0.7, kcMid: 1.05, kcEnd: 0.75, tBase: 1.7, gMat: 3000,
        fE: 0.1, fV: 0.27, fR: 0.73, rotP98: 100);
    final rain = <double>[0, 60, 60, 10, 0, 0, 90, 20, 0];
    final d0 = DateTime.utc(2024, 12, 1);
    final r = replaySeason(prm, 80, [
      for (final (i, p) in rain.indexed) SeasonDay(date: addDays(d0, i), tmax: 30, tmin: 20, p: p.toDouble(), et0: 4),
    ], plantedOn: d0);
    // 3-day sums: day2 120, day3 130 (episode 1); day6 90, day7 110 (episode 2, day 7)
    expect([for (final e in r.events) (e.type, e.dayIndex)], [(TrackerAlertType.onionRot, 2), (TrackerAlertType.onionRot, 7)]);

    final rice = Params(
        crop: 'rice', taw: 80, p: 0.2, kcIni: 1.05, kcMid: 1.2, kcEnd: 0.75, tBase: 10, gMat: 200,
        fE: 0.05, fV: 0.1, fR: 0.9, tCrit: 35, irrigated: true);
    final tmax = <double>[30, 30, 30, 36, 37, 30, 36, 30, 30, 30, 30, 30, 30, 30];
    final h = replaySeason(rice, 80, [
      for (final (i, t) in tmax.indexed) SeasonDay(date: addDays(d0, i), tmax: t, tmin: 20, p: 0, et0: 4),
    ], plantedOn: d0);
    final heat = [for (final e in h.events) if (e.type == TrackerAlertType.heatAtFlowering) e.dayIndex];
    expect(heat, [3, 6]);
    expect(h.machine.kh, 3);
  });

  test('days before planting are skipped and dates must ascend', () {
    final c = cases.first;
    final prm = prmOf(c);
    final sow = parseYmd(c['sow'] as String)!;
    final all = days(c);
    final r = replaySeason(prm, 10, all, plantedOn: addDays(sow, 5));
    expect(r.dates.first, addDays(sow, 5));
    expect(() => replaySeason(prm, 10, [all[1], all[0]], plantedOn: sow), throwsArgumentError);
  });

  test('machine snapshot round trip continues identically', () {
    final c = cases.firstWhere((c) => c['id'] == 'bongabon|onion|2024-25|limited_2');
    final prm = prmOf(c);
    final ds = days(c);
    final sow = parseYmd(c['sow'] as String)!;
    final half = replaySeason(prm, n(c['s0_frac']) * prm.taw, ds.take(50), plantedOn: sow, simulating: true);
    final restored = fieldMachineFromJson(prm, fieldMachineToJson(half.machine));
    final full = replaySeason(prm, n(c['s0_frac']) * prm.taw, ds, plantedOn: sow, simulating: true);
    for (final d in ds.skip(50)) {
      restored.tick(d.tmax, d.tmin, d.p, d.et0);
      if (restored.q == FieldState.fallow) break;
    }
    expect(fieldMachineToJson(restored), fieldMachineToJson(full.machine));
    expect(() => fieldMachineFromJson(prm, {'q': 'Nope'}), throwsFormatException);
  });
}
