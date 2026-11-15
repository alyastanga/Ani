import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ani/core/field_machine.dart';
import 'package:ani/data/bundle.dart';
import 'package:flutter_test/flutter_test.dart';

const _tol = 1e-6; // fixture floats are rounded to 8 dp

Map<String, dynamic> _fixture() =>
    jsonDecode(File('assets/fixtures/field_machine.json').readAsStringSync()) as Map<String, dynamic>;

double _n(Object? x) => (x as num).toDouble();

/// fsm tests' `_prm`: maize-like defaults.
Params _prm({
  String crop = 'maize',
  double taw = 150.0,
  double gMat = 1650.0,
  double fE = 0.16,
  double fV = 0.44,
  double fR = 0.76,
  double? tCrit,
  bool irrigated = false,
  int? maxIrr,
  double? rotP98,
  int kFail = kKFail,
}) =>
    Params(
      crop: crop,
      taw: taw,
      p: 0.55,
      kcIni: 0.3,
      kcMid: 1.2,
      kcEnd: 0.475,
      tBase: 10.0,
      gMat: gMat,
      fE: fE,
      fV: fV,
      fR: fR,
      tCrit: tCrit,
      irrigated: irrigated,
      maxIrr: maxIrr,
      rotP98: rotP98,
      kFail: kFail,
    );

/// fsm tests' `_weather`: constant days.
List<(double, double, double, double)> _weather(
        {int n = 220, double tmax = 33.0, double tmin = 23.0, double p = 0.0, double et0 = 5.0}) =>
    List.generate(n, (_) => (tmax, tmin, p, et0));

/// Replays one fixture case; returns the machine.
FieldMachine _replay(Map<String, dynamic> c, Params prm, {void Function(int, List<dynamic>, FieldMachine, List<String>)? onDay}) {
  final cols = (c['columns'] as List).cast<String>();
  int ix(String k) => cols.indexOf(k);
  final m = FieldMachine(prm)..sow(_n(c['s0_frac']) * prm.taw);
  final days = c['days'] as List;
  for (var i = 0; i < days.length; i++) {
    final r = days[i] as List;
    final out = m.tick(_n(r[ix('tmax')]), _n(r[ix('tmin')]), _n(r[ix('p')]), _n(r[ix('et0')]));
    onDay?.call(i, r, m, out);
    if (m.q == FieldState.fallow) break;
  }
  return m;
}

void main() {
  final fx = _fixture();
  final cases = (fx['cases'] as List).cast<Map<String, dynamic>>();

  group('fixture parity (pipeline/export_fixtures.py)', () {
    test('fixture has 45 cases with the expected columns', () {
      expect(cases, hasLength(45));
      expect(cases.first['columns'], [
        'tmax', 'tmin', 'p', 'et0', 'q', 'd', 'G', 'S', 'Ks', 'kw', 'ksev', 'kh', //
        'irr', 'n_irr', 'eta', 'dp', 'alerts',
      ]);
    });

    for (final c in cases) {
      test(c['id'], () {
        final prm = Params.fromJson(c['params'] as Map<String, dynamic>);
        final cols = (c['columns'] as List).cast<String>();
        int ix(String k) => cols.indexOf(k);
        var ticks = 0;
        final m = _replay(c, prm, onDay: (i, r, m, out) {
          ticks++;
          final at = '${c['id']} day $i';
          expect(m.q.label, r[ix('q')], reason: '$at q');
          expect(m.d, r[ix('d')], reason: '$at d');
          expect(m.kw, r[ix('kw')], reason: '$at kw');
          expect(m.ksev, r[ix('ksev')], reason: '$at ksev');
          expect(m.kh, r[ix('kh')], reason: '$at kh');
          expect(m.nIrr, r[ix('n_irr')], reason: '$at n_irr');
          for (final (k, v) in [('G', m.G), ('S', m.S), ('Ks', m.Ks), ('irr', m.irr), ('eta', m.eta), ('dp', m.dp)]) {
            expect(v, closeTo(_n(r[ix(k)]), _tol), reason: '$at $k');
          }
          expect(out, (r[ix('alerts')] as List).cast<String>(), reason: '$at alerts');
        });
        expect(ticks, (c['days'] as List).length, reason: 'every fixture day replayed');
        expect(m.trace.map((t) => t.toList()).toList(), c['transitions']);
        final o = m.outcome().toMap();
        final want = c['outcome'] as Map<String, dynamic>;
        expect(o.keys.toSet(), want.keys.toSet());
        for (final e in want.entries) {
          final got = o[e.key];
          if (e.value is num) {
            expect(got, closeTo(_n(e.value), 1e-9), reason: e.key);
          } else {
            expect(got, e.value, reason: e.key);
          }
        }
      });
    }
  });

  group('Params from the bundle tracker block', () {
    final bundles = <String, AniBundle>{
      for (final t in Town.values)
        t.id: AniBundle.fromJson(jsonDecode(File(t.assetPath).readAsStringSync()) as Map<String, dynamic>),
    };
    final raw = <String, Map<String, dynamic>>{
      for (final t in Town.values)
        t.id: (jsonDecode(File(t.assetPath).readAsStringSync()) as Map<String, dynamic>)['tracker']
            as Map<String, dynamic>,
    };

    test('typed and raw tracker paths agree and match fixture params', () {
      for (final c in cases) {
        final want = Params.fromJson(c['params'] as Map<String, dynamic>);
        final typed = bundles[c['muni']]!.tracker.crops[c['crop']]!.toFieldParams(c['water'] as String);
        final rawP = Params.fromTracker(
            c['crop'] as String, (raw[c['muni']]![c['crop']] as Map).cast<String, dynamic>(), c['water'] as String);
        for (final p in [typed, rawP]) {
          expect(p.crop, want.crop);
          expect(p.irrigated, want.irrigated, reason: c['id']);
          expect(p.maxIrr, want.maxIrr, reason: c['id']);
          // the bundle rounds to 3 dp
          for (final (a, b) in [
            (p.taw, want.taw), (p.p, want.p), (p.kcIni, want.kcIni), (p.kcMid, want.kcMid), //
            (p.kcEnd, want.kcEnd), (p.tBase, want.tBase), (p.gMat, want.gMat), (p.fE, want.fE),
            (p.fV, want.fV), (p.fR, want.fR), (p.rotP98!, want.rotP98!),
          ]) {
            expect(a, closeTo(b, 1e-3 + 1e-9), reason: c['id']);
          }
          expect(p.tCrit, want.tCrit);
          expect(p.tUp, want.tUp);
          expect(p.dPrep, want.dPrep);
          expect(p.ksFail, want.ksFail);
          expect(p.kFail, want.kFail);
          expect(p.sensitive, kSensitive);
        }
      }
    });

    // Stage fractions and g_mat are exported to 6 dp, so the bundle reproduces the fixture exactly.
    test('bundle-derived Params reproduce the fixture transitions exactly', () {
      final diff = <String>[];
      for (final c in cases) {
        final prm = bundles[c['muni']]!.tracker.crops[c['crop']]!.toFieldParams(c['water'] as String);
        final got = _replay(c, prm).trace;
        final want = (c['transitions'] as List).cast<List<dynamic>>();
        final ok = got.length == want.length &&
            [
              for (var i = 0; i < got.length; i++)
                got[i].from.label == want[i][1] &&
                    got[i].to.label == want[i][2] &&
                    got[i].guard == want[i][3] &&
                    got[i].day == want[i][0],
            ].every((x) => x);
        if (!ok) diff.add('${c['id']}: ${got.map((t) => t.toList()).toList()} vs $want');
      }
      expect(diff, isEmpty);
    });

    test('unknown water scenario is rejected', () {
      final tp = bundles['guimba']!.tracker.crops['rice']!;
      expect(() => tp.toFieldParams('lots'), throwsArgumentError);
    });
  });

  // ---------------------------------------------------------------- ports of pipeline/tests/test_fsm.py

  group('F7 and soil water', () {
    test('gdd', () {
      expect(gdd(33, 23, 10), closeTo(18, 1e-12));
      expect(gdd(12, 5, 10), closeTo(1, 1e-12)); // Tmin raised to T_base
      expect(gdd(8, 2, 10), 0);
      expect(gdd(40, 25, 10, 34), closeTo(19.5, 1e-12));
    });

    test('pAdjusted is bounded 0.1-0.8', () {
      expect(pAdjusted(0.5, 5), closeTo(0.5, 1e-12));
      expect(pAdjusted(0.9, 0), 0.8);
      expect(pAdjusted(0.1, 20), 0.1);
    });

    test('bucketStep conserves water and refill tops up to TAW', () {
      final b = bucketStep(10, 3, 0, 6, 1.1, 80, 0.5);
      expect(10 + 3 - b.eta - b.dp - b.s, closeTo(0, 1e-12));
      expect(refillWhenStressed(10, 80, 0.5), 70);
      expect(refillWhenStressed(70, 80, 0.5), 0);
      final full = bucketStep(79, 50, 0, 2, 1.0, 80, 0.5);
      expect(full.s, 80);
      expect(full.dp, greaterThan(0));
    });
  });

  group('stages, determinism, totality', () {
    test('normal season runs all stages in order and harvests on time', () {
      final r = runSeason(_prm(gMat: 110 * 18, irrigated: true), _weather(), 1.0);
      expect(r.trace.map((t) => t.to.label), ['Prep', 'Estab', 'Veg', 'Repro', 'Mature', 'Harvest', 'Fallow']);
      expect((r.outcome.harvestDay! - 110).abs(), lessThanOrEqualTo(1));
      expect(r.outcome.failed, isFalse);
    });

    test('hot season matures earlier', () {
      final hot = runSeason(_prm(gMat: 110 * 18, irrigated: true), _weather(tmax: 36, tmin: 25), 1.0);
      expect(hot.outcome.harvestDay, lessThan(100));
    });

    test('deterministic: same inputs give same outputs', () {
      final prm = _prm(gMat: 1980);
      final a = runSeason(prm, _weather(p: 2.0), 0.6);
      final b = runSeason(prm, _weather(p: 2.0), 0.6);
      expect(a.outcome.toMap(), b.outcome.toMap());
      expect(a.trace, b.trace);
      expect(a.alerts, b.alerts);
      // and on every fixture case, twice
      for (final c in cases.take(9)) {
        final p = Params.fromJson(c['params'] as Map<String, dynamic>);
        final m1 = _replay(c, p), m2 = _replay(c, p);
        expect(m1.trace, m2.trace);
        expect(m1.outcome().toMap(), m2.outcome().toMap());
        expect([m1.G, m1.S, m1.eta, m1.dp], [m2.G, m2.S, m2.eta, m2.dp]);
      }
    });

    test('total and single transition per tick (random weather)', () {
      final rng = math.Random(0);
      double u(double a, double b) => a + (b - a) * rng.nextDouble();
      for (var run = 0; run < 20; run++) {
        final m = FieldMachine(_prm(gMat: 900, irrigated: run.isOdd, maxIrr: run % 4 == 1 ? 2 : null))..sow(80);
        for (var k = 0; k < 400; k++) {
          final before = m.trace.length;
          // gamma(0.5, 10)-like heavy-tailed rain
          final rain = rng.nextDouble() < 0.6 ? 0.0 : -10 * math.log(1 - rng.nextDouble());
          m.tick(u(20, 40), u(15, 27), rain, u(2, 7));
          expect(m.trace.length - before, lessThanOrEqualTo(1));
          expect(FieldState.values, contains(m.q));
          if (m.q == FieldState.fallow) break;
        }
        expect(m.q, FieldState.fallow);
      }
    });

    test('every state has exactly one defined successor for any input', () {
      const inputs = [
        (33.0, 23.0, 0.0, 5.0),
        (40.0, 28.0, 0.0, 8.0),
        (25.0, 18.0, 120.0, 1.0),
        (8.0, 2.0, 0.0, 0.0),
        (36.0, 25.0, 30.0, 6.0),
      ];
      for (final q in FieldState.values) {
        for (final x in inputs) {
          for (final g in [0.0, 50.0, 500.0, 2000.0]) {
            for (final s in [0.0, 20.0, 150.0]) {
              for (final ksev in [0, 9, 10]) {
                for (final confirm in [false, true]) {
                  for (final sim in [false, true]) {
                    final m = FieldMachine(_prm(gMat: 1000, tCrit: 35, rotP98: 60, irrigated: s == 20))
                      ..q = q
                      ..G = g
                      ..S = s
                      ..ksev = ksev;
                    final before = m.trace.length;
                    final out = m.tick(x.$1, x.$2, x.$3, x.$4, confirmHarvest: confirm, simulating: sim);
                    expect(m.trace.length - before, lessThanOrEqualTo(1));
                    expect(m.S, inInclusiveRange(0, m.prm.taw));
                    expect(m.Ks, inInclusiveRange(0, 1));
                    final moved = m.trace.length > before;
                    if (q == FieldState.fallow) {
                      expect(moved, isFalse); // only the sow event leaves Fallow
                      expect(out, isEmpty);
                    }
                    if (q.isEnd) expect(m.q, FieldState.fallow); // guards 8, 9
                    if (q == FieldState.prep) expect(m.q, FieldState.estab); // guard 3 (D_PREP = 0)
                    if (moved) expect(m.trace.last.from, q);
                    if (!moved) expect(m.q, q); // guard 10
                  }
                }
              }
            }
          }
        }
      }
    });

    test('sow only from Fallow', () {
      final m = FieldMachine(_prm())..sow(10);
      expect(() => m.sow(10), throwsStateError);
    });

    test('Mature waits for confirm when not simulating', () {
      final m = FieldMachine(_prm(gMat: 100, irrigated: true))
        ..q = FieldState.mature
        ..G = 200
        ..S = 150;
      m.tick(33, 23, 0, 5, simulating: false);
      expect(m.q, FieldState.mature);
      final out = m.tick(33, 23, 0, 5, simulating: false, confirmHarvest: true);
      expect(m.q, FieldState.harvest);
      expect(out, contains(FieldAlert.harvestReady));
    });
  });

  group('guards', () {
    test('rainfed drought fails and irrigated does not', () {
      final dry = _weather(p: 0.0, et0: 6.0);
      final rf = runSeason(_prm(gMat: 1980), dry, 0.3);
      final ir = runSeason(_prm(gMat: 1980, irrigated: true), dry, 0.3);
      expect(rf.outcome.failed, isTrue);
      expect(rf.trace.map((t) => t.to), contains(FieldState.failed));
      expect(rf.outcome.mainReason, startsWith('water'));
      expect(rf.alerts.map((a) => a.$2), contains(FieldAlert.waterFail));
      expect(ir.outcome.failed, isFalse);
      expect(ir.outcome.stressDays, 0);
      expect(ir.outcome.irrigationMm, greaterThan(0));
    });

    test('failure guard outranks stage progress', () {
      final m = FieldMachine(_prm(gMat: 100, fE: 0.1, fV: 0.5, fR: 0.9, kFail: 1, taw: 10))..sow(0.0);
      m.tick(33, 23, 0, 6); // Prep -> Estab
      m.tick(33, 23, 0, 6); // Estab -> Veg
      m.tick(33, 23, 0, 6); // in Veg, Ks = 0 -> ksev 1 >= k_fail -> Failed
      expect(m.q, FieldState.failed);
    });

    test('heat days counted only in Repro for crops with t_crit', () {
      final w = _weather(tmax: 33);
      for (var i = 5; i < 15; i++) {
        w[i] = (36.0, w[i].$2, w[i].$3, w[i].$4); // early season: Estab/Veg
      }
      for (var i = 60; i < 70; i++) {
        w[i] = (36.0, w[i].$2, w[i].$3, w[i].$4); // inside Repro
      }
      final r = runSeason(_prm(crop: 'rice', gMat: 110 * 18, tCrit: 35.0, irrigated: true), w, 1.0);
      expect(r.outcome.heatDays, 10);
      expect(r.outcome.mainReason, startsWith('heat'));
      expect(r.outcome.mainReason, 'heat: 10 days at flowering >= 35.0 C');
      final noTcrit = runSeason(_prm(gMat: 110 * 18, irrigated: true), w, 1.0);
      expect(noTcrit.outcome.heatDays, 0);
    });

    test('onion rot alert', () {
      final w = _weather();
      for (var i = 2; i < 5; i++) {
        w[i] = (w[i].$1, w[i].$2, 25.0, w[i].$4); // 75 mm in 3 days while in Estab
      }
      final r = runSeason(_prm(crop: 'onion', gMat: 110 * 18, fE: 0.1, rotP98: 60.0, irrigated: true), w, 1.0);
      expect(r.alerts.map((a) => a.$2), contains(FieldAlert.rotRisk));
    });

    test('water balance closes inside the machine', () {
      final m = FieldMachine(_prm(gMat: 1980, irrigated: true))..sow(90.0);
      for (final (a, b, p, e) in _weather(p: 3.0)) {
        m.tick(a, b, p, e);
        if (m.q.isEnd || m.q == FieldState.fallow) break;
      }
      expect(90.0 + m.rain + m.irr - m.eta - m.dp - m.S, closeTo(0, 1e-9));
    });

    test('limited irrigation caps events and sits between rainfed and full', () {
      final dry = _weather(p: 0.0, et0: 6.0);
      final res = {
        for (final k in [0, 2, 4, 99])
          k: runSeason(_prm(gMat: 1980, irrigated: k > 0, maxIrr: k == 99 ? null : k), dry, 0.5).outcome,
      };
      expect(res[2]!.irrigations, 2);
      expect(res[4]!.irrigations, 4);
      expect(res[0]!.irrigationMm, lessThan(res[2]!.irrigationMm));
      expect(res[2]!.irrigationMm, lessThan(res[4]!.irrigationMm));
      expect(res[4]!.irrigationMm, lessThan(res[99]!.irrigationMm));
      expect(res[99]!.stressDays, 0);
      expect(res[0]!.stressDays, greaterThanOrEqualTo(res[4]!.stressDays));
    });
  });
}
