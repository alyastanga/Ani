import 'dart:convert';
import 'dart:io';

import 'package:ani/core/dryness.dart';
import 'package:ani/data/bundle.dart';
import 'package:flutter_test/flutter_test.dart';

const _tol = 1e-6;

final Map<String, dynamic> _fx =
    jsonDecode(File('assets/fixtures/numeric.json').readAsStringSync()) as Map<String, dynamic>;

double? _dn(Object? v) => (v as num?)?.toDouble();
List<double?> _refs(Object? v) => [for (final x in v as List) _dn(x)];

DrynessBaseline _baseline(int month, DrynessReferenceMonth r) =>
    DrynessBaseline(month: month, years: r.years, bal1: r.bal1, bal3: r.bal3, gwet: r.gwet);

void main() {
  final rows = (_fx['zscores'] as List).cast<Map<String, dynamic>>();
  final edge = (_fx['robust_z_edge'] as List).cast<Map<String, dynamic>>();

  test('fixture covers dry/wet season and the SPEI rank fallback', () {
    expect(rows.where((r) => r['dry_season'] == true), isNotEmpty);
    expect(rows.where((r) => r['dry_season'] == false), isNotEmpty);
    expect(rows.where((r) => r['spei']['fallback'] == true), isNotEmpty);
  });

  group('robust z, SPEI, D vs numeric.json zscores', () {
    for (final (i, r) in rows.indexed) {
      test('#$i ${r['muni']} ${r['month']}', () {
        final month = int.parse((r['month'] as String).substring(5, 7));
        expect(r['dry_season'], kDrySeason.contains(month));
        expect(r['k'], accumulationFor(month));

        final sp = r['spei'] as Map<String, dynamic>;
        final s = spei(_dn(sp['x']), _refs(sp['ref']));
        final se = _dn(sp['expect']);
        if (se == null) {
          expect(s, isNull);
        } else {
          expect(s!.value, closeTo(se, _tol), reason: 'spei');
        }
        expect(s?.fallback ?? false, sp['fallback'], reason: 'fallback');
        expect(loglogisticPwm([for (final v in _refs(sp['ref'])) v!]) == null, sp['fallback']);

        final rz = r['robust_z'] as Map<String, dynamic>;
        final z = robustZ(_dn(rz['x']), _refs(rz['ref']));
        final ze = _dn(rz['expect']);
        if (ze == null) {
          expect(z, isNull);
        } else {
          expect(z, closeTo(ze, _tol), reason: 'robust_z');
        }

        final dd = r['D'] as Map<String, dynamic>;
        final d = combinedD(s?.value, z);
        final de = _dn(dd['expect']);
        if (de == null) {
          expect(d, isNull);
        } else {
          expect(d, closeTo(de, _tol), reason: 'D');
          // Combination from the fixture's own spei / z_sm too.
          expect(combinedD(_dn(dd['spei']), _dn(dd['z_sm'])), closeTo(de, _tol));
        }
        expect(drynessLabel(d), dd['label'], reason: 'label');
        final csv = dd['csv'] as Map<String, dynamic>;
        if (csv['D'] != null) {
          expect(d, closeTo(_dn(csv['D'])!, 5e-4 + 1e-9), reason: 'monthly csv D (3 dp)');
          expect(drynessLabel(d), csv['label']);
        }
      });
    }
  });

  group('robust_z edge cases', () {
    for (final (i, e) in edge.indexed) {
      test('#$i x=${e['x']} n=${(e['ref'] as List).length}', () {
        final z = robustZ(_dn(e['x']), _refs(e['ref']));
        final ze = _dn(e['expect']);
        if (ze == null) {
          expect(z, isNull);
        } else {
          expect(z, closeTo(ze, _tol));
        }
      });
    }
    test('missing x / missing refs', () {
      final ref = [for (var i = 0; i < 12; i++) 0.4 + i * 0.01];
      expect(robustZ(null, ref), isNull);
      expect(robustZ(double.nan, ref), isNull);
      expect(robustZ(0.5, [...ref.take(9), null, null, null]), isNull); // 9 valid < 10
      expect(spei(null, ref), isNull);
      expect(spei(1, ref.take(9)), isNull);
    });
  });

  group('helpers', () {
    test('normPpf', () {
      expect(normPpf(0.5), 0);
      expect(normPpf(0.975), closeTo(1.959963984540054, 1e-14));
      expect(normPpf(0.025), closeTo(-1.959963984540054, 1e-14));
      expect(normPpf(1e-6), closeTo(-4.753424308822899, 1e-12));
      expect(normPpf(1 - 1e-6), closeTo(4.753424308817088, 1e-9));
      expect(normPpf(1e-300), closeTo(-37.0470962993612, 1e-9)); // scipy
      expect(normPpf(0), double.negativeInfinity);
      expect(normPpf(1), double.infinity);
    });
    test('median, std', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 3, 2]), 2.5);
      expect(stdDdof1([1, 2, 3, 4]), closeTo(1.2909944487358056, 1e-15));
    });
    test('empirical index uses average ranks for ties', () {
      // x = 2 in {1, 2, 2, 3} + {2}: ranks of 2 are 2,3,4 -> 3.
      expect(empiricalIndex(2, [1, 2, 2, 3]), closeTo(normPpf((3 - 0.44) / (5 + 0.12)), 1e-15));
    });
    test('D, label, rank text', () {
      expect(combinedD(null, 1), isNull);
      expect(combinedD(-1.2, null), 1.2);
      expect(combinedD(-1, -1), 1);
      expect(drynessLabel(null), isNull);
      expect(drynessLabel(0.99), 'normal');
      expect(drynessLabel(1), 'bantay');
      expect(drynessLabel(2), 'delikado');
      expect(dryRank(1.0, [0.5, 1.0, 2.0, null]), (rank: 2, n: 4));
      expect(rankText(1.2, 2, 25), 'pinakatuyo: ika-2 sa 25 na taon');
      expect(rankText(-0.3, 24, 25), 'pinakabasa: ika-2 sa 25 na taon');
      expect(rankText(0, 1, 25), 'pinakatuyo: ika-1 sa 25 na taon');
      expect(rankText(null, 1, 2), isNull);
    });
  });

  for (final town in Town.values) {
    group('${town.id}: scoring from bundle dryness.reference', () {
      final b = AniBundle.fromJsonString(File(town.assetPath).readAsStringSync());
      final dry = b.dryness;
      final base = {for (final e in dry.reference.entries) e.key: _baseline(e.key, e.value)};

      // The bundle stores reference balances at 2 dp, GWETROOT at 5 dp, and D at 2 dp.
      test('reproduces dryness.monthly D', () {
        expect(base.keys.toSet(), {for (var m = 1; m <= 12; m++) m});
        final diffs = <double>[];
        final labelMismatch = <String>[];
        for (final p in dry.monthly) {
          final s = base[p.monthOfYear]!.scoreYear(p.year,
              bantay: dry.thresholds.bantay, delikado: dry.thresholds.delikado);
          expect(s.d, isNotNull, reason: p.month);
          final diff = (s.d! - p.d).abs();
          diffs.add(diff);
          expect(diff, lessThan(0.02), reason: '${p.month}: device ${s.d} vs bundle ${p.d}');
          if (drynessLabel(p.d) != s.label) {
            labelMismatch.add(p.month);
            // Only allowed right at a threshold, within the rounding error.
            final t = [dry.thresholds.bantay, dry.thresholds.delikado];
            expect(t.any((x) => (p.d - x).abs() < 0.1), isTrue, reason: '${p.month} label');
          }
        }
        diffs.sort();
        final p95 = diffs[(diffs.length * 0.95).floor()];
        // ignore: avoid_print
        print('${town.id}: ${diffs.length} months, |D_device - D_bundle| p95 ${p95.toStringAsFixed(4)}, '
            'max ${diffs.last.toStringAsFixed(4)}, threshold label flips $labelMismatch');
        expect(diffs.length, dry.monthly.length);
        expect(p95, lessThan(0.01));
        expect(labelMismatch.length, lessThanOrEqualTo(1));
      });

      test('reproduces dryness.latest (D, label, rank sentence)', () {
        final l = dry.latest;
        final year = int.parse(l.month.substring(0, 4));
        final month = int.parse(l.month.substring(5, 7));
        final s = base[month]!.scoreYear(year);
        expect(s.d, closeTo(l.d, 0.05));
        expect(s.label, l.label);
        final others = [
          for (final p in dry.monthly)
            if (p.monthOfYear == month && p.year != year) p.d,
        ];
        final r = dryRank(l.d, others);
        expect(rankText(l.d, r.rank, r.n), l.rank);
      });
    });
  }
}
