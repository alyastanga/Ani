import 'dart:convert';
import 'dart:io';

import 'package:ani/core/alert_machine.dart';
import 'package:ani/data/bundle.dart';
import 'package:flutter_test/flutter_test.dart';

const m = AlertMachine();
const normal = AlertState(AlertLevel.normal);
const bantay = AlertState(AlertLevel.bantay);
const delikado = AlertState(AlertLevel.delikado);

List<AlertLevel> levels(List<double?> ds, {AlertState from = AlertState.initial}) =>
    m.run(ds, from: from).map((s) => s.level).toList();

const N = AlertLevel.normal, B = AlertLevel.bantay, K = AlertLevel.delikado;

void main() {
  group('labels and thresholds', () {
    test('Filipino labels and pipeline ids', () {
      expect(AlertLevel.values.map((l) => l.label), ['Normal', 'Bantay', 'Delikado']);
      expect(AlertLevel.values.map((l) => l.id),
          [DrynessLabel.normal, DrynessLabel.bantay, DrynessLabel.delikado]);
      expect(AlertLevel.tryFromId('bantay'), B);
      expect(AlertLevel.tryFromId(''), isNull);
      expect(delikado.label, 'Delikado');
    });

    test('fromJson parses the export_json.py block and equals standard', () {
      final t = AlertThresholds.fromJson(
          {'bantay': 1.0, 'delikado': 2.0, 'down_bantay': 1.5, 'down_normal': 0.5, 'calm_dekads': 2});
      expect(t, AlertThresholds.standard);
      expect(t.hashCode, AlertThresholds.standard.hashCode);
      expect(AlertThresholds.fromJson(
          {'bantay': 1, 'delikado': 2, 'down_bantay': 1.5, 'down_normal': 0.5, 'calm_dekads': 2.0}),
          AlertThresholds.standard);
    });

    test('fromJson rejects bad shapes', () {
      final good = {'bantay': 1.0, 'delikado': 2.0, 'down_bantay': 1.5, 'down_normal': 0.5, 'calm_dekads': 2};
      expect(() => AlertThresholds.fromJson({...good, 'bantay': '1'}), throwsFormatException);
      expect(() => AlertThresholds.fromJson({...good}..remove('delikado')), throwsFormatException);
      expect(() => AlertThresholds.fromJson({...good, 'calm_dekads': 1.5}), throwsFormatException);
    });

    test('instantLevel matches zscores.label (>= at both cut-offs)', () {
      expect(m.instantLevel(0.99), N);
      expect(m.instantLevel(1.0), B);
      expect(m.instantLevel(1.99), B);
      expect(m.instantLevel(2.0), K);
      expect(m.instantLevel(-3), N);
      expect(m.instantLevel(null), isNull);
      expect(m.instantLevel(double.nan), isNull);
    });
  });

  group('escalation', () {
    test('Normal -> Bantay at D >= 1, stays Normal below', () {
      expect(m.step(normal, 0.999), normal);
      expect(m.step(normal, 1.0), bantay);
      expect(m.step(normal, 1.7), bantay);
    });

    test('Normal jumps straight to Delikado at D >= 2', () {
      expect(m.step(normal, 2.0), delikado);
      expect(m.step(normal, 5), delikado);
      expect(m.step(normal, double.infinity), delikado);
    });

    test('Bantay -> Delikado at D >= 2, even mid calm run', () {
      expect(m.step(bantay, 1.999), bantay);
      expect(m.step(bantay, 2.0), delikado);
      expect(m.step(const AlertState(B, 1), 2.0), delikado);
    });

    test('Delikado stays Delikado at D >= 2 and resets calm', () {
      expect(m.step(const AlertState(K, 1), 3.0), delikado);
    });
  });

  group('de-escalation', () {
    test('Delikado -> Bantay after 2 consecutive dekads with D < 1.5', () {
      final s1 = m.step(delikado, 1.49);
      expect(s1, const AlertState(K, 1));
      expect(m.step(s1, 1.49), bantay);
    });

    test('D == down_bantay is not calm (strict <)', () {
      expect(m.step(delikado, 1.5), delikado);
      expect(m.step(const AlertState(K, 1), 1.5), delikado);
    });

    test('D in [1, 1.5) counts as calm for Delikado (hysteresis gap)', () {
      expect(levels([1.2, 1.2], from: delikado), [K, B]);
    });

    test('Bantay -> Normal after 2 consecutive dekads with D < 0.5', () {
      final s1 = m.step(bantay, 0.49);
      expect(s1, const AlertState(B, 1));
      expect(m.step(s1, 0.0), normal);
    });

    test('D == down_normal is not calm (strict <)', () {
      expect(m.step(bantay, 0.5), bantay);
      expect(m.step(const AlertState(B, 1), 0.5), bantay);
    });

    test('Delikado never drops straight to Normal; counter restarts at Bantay', () {
      final r = m.run([0.0, 0.0, 0.0, 0.0], from: delikado);
      expect(r, [const AlertState(K, 1), bantay, const AlertState(B, 1), normal]);
      expect(m.step(const AlertState(K, 1), -10), bantay);
    });

    test('calm_dekads is honoured (3) and <= 1 means one dekad', () {
      const m3 = AlertMachine(AlertThresholds(
          bantay: 1, delikado: 2, downBantay: 1.5, downNormal: 0.5, calmDekads: 3));
      expect(m3.run([1, 0, 0, 0]).map((s) => s.level), [B, B, B, N]);
      for (final c in [0, 1, -2]) {
        final mc = AlertMachine(AlertThresholds(
            bantay: 1, delikado: 2, downBantay: 1.5, downNormal: 0.5, calmDekads: c));
        expect(mc.run([2.5, 1.0, 0.0]).map((s) => s.level), [K, B, N], reason: 'calm_dekads=$c');
      }
    });
  });

  group('calm counter reset', () {
    test('a non-calm dekad in Bantay resets the run', () {
      expect(levels([1.0, 0.4, 0.7, 0.4, 0.4]), [B, B, B, B, N]);
      expect(m.run([1.0, 0.4, 0.7])[2], bantay);
    });

    test('a re-escalating dekad in Bantay resets the run', () {
      expect(m.run([1.0, 0.4, 1.2, 0.4]).last, const AlertState(B, 1));
    });

    test('a non-calm dekad in Delikado resets the run', () {
      expect(levels([1.4, 1.6, 1.4, 1.4], from: delikado), [K, K, K, B]);
      expect(m.run([1.4, 1.8], from: delikado).last, delikado);
    });

    test('Normal always has calm 0', () {
      expect(m.run([0.1, -1, 0.9, 0.0]).every((s) => s == normal), isTrue);
    });
  });

  group('hysteresis (no flapping)', () {
    test('oscillating around 1.0 stays Bantay once up', () {
      final ds = [for (var i = 0; i < 20; i++) i.isEven ? 1.05 : 0.95];
      expect(levels(ds).toSet(), {B});
    });

    test('oscillating around 2.0 stays Delikado once up', () {
      final ds = [for (var i = 0; i < 20; i++) i.isEven ? 2.05 : 1.95];
      expect(levels(ds).toSet(), {K});
    });

    test('alternating calm/non-calm never steps down', () {
      final ds = [2.1, for (var i = 0; i < 20; i++) i.isEven ? 1.0 : 1.6];
      expect(levels(ds).toSet(), {K});
      final ds2 = [1.1, for (var i = 0; i < 20; i++) i.isEven ? 0.3 : 0.6];
      expect(levels(ds2).toSet(), {B});
    });

    test('single calm dekad between dry spells never relaxes', () {
      expect(levels([2.2, 0.0, 2.2, 0.0, 2.2]), [K, K, K, K, K]);
    });

    test('a typical El Nino episode', () {
      final ds = [0.2, 0.8, 1.1, 1.6, 2.3, 2.6, 1.8, 1.4, 1.3, 0.9, 0.4, 0.3, 0.1];
      expect(levels(ds), [N, N, B, B, K, K, K, K, B, B, B, N, N]);
    });
  });

  group('missing data', () {
    test('null and NaN hold the level', () {
      for (final s in [normal, bantay, delikado]) {
        expect(m.step(s, null).level, s.level);
        expect(m.step(s, double.nan).level, s.level);
      }
    });

    test('missing is not calm and breaks the consecutive run', () {
      expect(m.step(const AlertState(B, 1), null), bantay);
      expect(m.step(const AlertState(K, 1), double.nan), delikado);
      expect(levels([1.0, 0.0, null, 0.0, 0.0]), [B, B, B, B, N]);
      expect(levels([2.0, 1.0, double.nan, 1.0, 1.0]), [K, K, K, K, B]);
    });

    test('a long gap never relaxes an alert', () {
      expect(levels([2.5, for (var i = 0; i < 30; i++) null]).toSet(), {K});
    });

    test('-infinity is calm', () {
      expect(levels([2.5, double.negativeInfinity, double.negativeInfinity]), [K, K, B]);
    });
  });

  group('run / determinism / totality', () {
    test('run returns one state per input, unmodifiable, and last agrees', () {
      final ds = [0.2, 1.3, 2.4, 1.0, 1.0, 0.1, 0.1];
      final r = m.run(ds);
      expect(r.length, ds.length);
      expect(() => r.add(normal), throwsUnsupportedError);
      expect(m.last(ds), r.last);
      expect(m.run(const []), isEmpty);
      expect(m.last(const [], from: delikado), delikado);
    });

    test('run equals folding step and is repeatable', () {
      final ds = <double?>[0.1, 1.2, null, 2.2, 1.4, double.nan, 1.4, 1.4, 0.2, 0.2];
      var s = AlertState.initial;
      final manual = <AlertState>[];
      for (final d in ds) {
        s = m.step(s, d);
        manual.add(s);
      }
      expect(m.run(ds), manual);
      expect(m.run(ds), m.run(ds));
      expect(const AlertMachine().run(ds), m.run(ds));
    });

    test('step does not depend on anything but (state, D)', () {
      final a = m.step(const AlertState(K, 1), 1.0);
      final b = m.step(const AlertState(K, 1), 1.0);
      expect(identical(a, b) || a == b, isTrue);
      expect(a, bantay);
    });

    test('every state x D sweep yields a defined, consistent state', () {
      final sweep = <double?>[
        null, double.nan, double.negativeInfinity, -5, -0.0, 0, 0.49, 0.5, 0.51, 0.99, 1.0, 1.01,
        1.49, 1.5, 1.51, 1.99, 2.0, 2.01, 10, double.infinity,
        for (var i = -20; i <= 60; i++) i / 20,
      ];
      final states = [
        for (final l in AlertLevel.values)
          for (var c = 0; c <= 3; c++) AlertState(l, c),
      ];
      for (final s in states) {
        for (final d in sweep) {
          final n = m.step(s, d);
          final why = '$s, D=$d';
          expect(AlertLevel.values, contains(n.level), reason: why);
          expect(n.calm, inInclusiveRange(0, m.thresholds.calmDekads - 1), reason: why);
          if (n.level == N) expect(n.calm, 0, reason: why);
          // Moves at most one level down, and never below the instant label.
          expect(n.level.index, greaterThanOrEqualTo(s.level.index - 1), reason: why);
          final inst = m.instantLevel(d);
          if (inst == null) {
            expect(n.level, s.level, reason: why);
          } else {
            expect(n.level.index, greaterThanOrEqualTo(inst.index), reason: why);
          }
        }
      }
    });
  });

  group('bundle smoke test', () {
    for (final town in Town.values) {
      test('runs over ${town.id} dryness.monthly', () {
        final j = jsonDecode(File(town.assetPath).readAsStringSync()) as Map<String, dynamic>;
        final b = AniBundle.fromJson(j);
        final th = b.dryness.thresholds;
        final t = AlertThresholds.fromJson((j['dryness'] as Map<String, dynamic>)['thresholds'] as Map<String, dynamic>);
        expect(t, AlertThresholds(
            bantay: th.bantay, delikado: th.delikado, downBantay: th.downBantay,
            downNormal: th.downNormal, calmDekads: th.calmDekads));
        final mb = AlertMachine(t);
        final ds = [for (final p in b.dryness.monthly) p.d];
        expect(ds, isNotEmpty);
        final r = mb.run(ds);
        expect(r.length, ds.length);
        expect(mb.run(ds), r);
        for (var i = 0; i < ds.length; i++) {
          final inst = mb.instantLevel(ds[i]);
          if (inst != null) expect(r[i].level.index, greaterThanOrEqualTo(inst.index));
        }
        // The real series is dry enough to reach every level at least once.
        expect(r.map((s) => s.level).toSet(), containsAll(AlertLevel.values));
        // Latest label is the stateless one; the machine is never below it.
        final latest = AlertLevel.tryFromId(b.dryness.latest.label);
        if (latest != null) expect(r.last.level.index, greaterThanOrEqualTo(latest.index));
      });
    }
  });
}
