import 'dart:convert';
import 'dart:io';

import 'package:ani/core/et0.dart' show roundHalfEven;
import 'package:ani/core/heat_index.dart';
import 'package:ani/data/bundle.dart';
import 'package:flutter_test/flutter_test.dart';

const _tol = 1e-6;

final Map<String, dynamic> _fx =
    jsonDecode(File('assets/fixtures/numeric.json').readAsStringSync()) as Map<String, dynamic>;

double _d(Object? v) => (v as num).toDouble();

void main() {
  final rows = (_fx['heat_index'] as List).cast<Map<String, dynamic>>();

  test('fixture covers every PAGASA band', () {
    final cats = {for (final r in rows) r['expect']['category'] as String};
    expect(cats, {for (final b in PagasaBand.values) b.key});
  });

  group('RH at Tmax, NWS heat index, PAGASA band vs numeric.json heat_index', () {
    for (final (i, r) in rows.indexed) {
      final inp = r['in'] as Map<String, dynamic>;
      final e = r['expect'] as Map<String, dynamic>;
      test('#$i ${r['muni']} ${r['date'] ?? '${inp['tmax']} C / ${inp['rh']} %'}', () {
        final tmax = _d(inp['tmax']);
        final double rhIn;
        if (inp.containsKey('tdew')) {
          final tdew = _d(inp['tdew']);
          final rh = rhAtTmax(tmax, tdew);
          expect(rh, closeTo(_d(e['rh_tmax']), _tol), reason: 'rh_tmax');
          expect(roundHalfEven(rh, 1), closeTo(_d(e['rh_tmax_rounded']), 1e-9), reason: 'rh_tmax_rounded');
          rhIn = roundHalfEven(rh, 1);
          final day = dailyHeat(tmax, tdew);
          expect(day.rhTmax, closeTo(_d(e['rh_tmax_rounded']), 1e-9), reason: 'daily RH_TMAX');
          expect(day.hi, closeTo(_d(e['hi_csv']), 1e-9), reason: 'hi_csv');
          expect(day.category?.key, e['category'], reason: 'daily HI_CAT');
        } else {
          rhIn = _d(inp['rh']);
        }
        final hi = heatIndexC(tmax, rhIn);
        expect(hi, closeTo(_d(e['hi']), _tol), reason: 'hi');
        expect(roundHalfEven(hi, 1), closeTo(_d(e['hi_rounded']), 1e-9), reason: 'hi_rounded');
        expect(pagasaCategory(roundHalfEven(hi, 1))?.key, e['category'], reason: 'category');
      });
    }
  });

  test('NWS branches: simple form, low-RH and high-RH adjustments', () {
    // Simple (Steadman) form below 80 F.
    final t = 20 * 9 / 5 + 32;
    expect(heatIndexC(20, 50), closeTo((0.5 * (t + 61.0 + (t - 68.0) * 1.2 + 50 * 0.094) - 32) * 5 / 9, 1e-12));
    // Low-RH adjustment lowers the index; high-RH adjustment raises it.
    expect(heatIndexC(36, 10), lessThan(heatIndexC(36, 13)));
    expect(heatIndexC(29, 90) - heatIndexC(29, 85), greaterThan(0));
  });

  test('PAGASA bin edges are left-closed', () {
    expect(pagasaCategory(26.9), PagasaBand.none);
    expect(pagasaCategory(27), PagasaBand.caution);
    expect(pagasaCategory(32.99), PagasaBand.caution);
    expect(pagasaCategory(33), PagasaBand.extremeCaution);
    expect(pagasaCategory(42), PagasaBand.danger);
    expect(pagasaCategory(51.9), PagasaBand.danger);
    expect(pagasaCategory(52), PagasaBand.extremeDanger);
    expect(pagasaCategory(double.nan), isNull);
    expect(PagasaBand.fromKey('extreme_caution'), PagasaBand.extremeCaution);
    expect(PagasaBand.fromKey('x'), isNull);
  });

  for (final town in Town.values) {
    test('${town.id}: bundle heat block matches PAGASA bands', () {
      final b = AniBundle.fromJsonString(File(town.assetPath).readAsStringSync());
      final cats = b.heat.indexCategoriesC;
      final bands = PagasaBand.values.skip(1).toList();
      expect(cats.length, bands.length);
      for (final (i, c) in cats.indexed) {
        expect(c.label, bands[i].bundleLabel);
        expect(c.from, bands[i].fromC);
        expect(c.to, i + 1 < bands.length ? bands[i + 1].fromC - 1 : isNull);
      }
      for (var hi = 20.0; hi <= 60.0; hi += 0.1) {
        final h = roundHalfEven(hi, 1);
        expect(b.heat.categoryFor(h)?.label, pagasaCategory(h)!.bundleLabel, reason: 'HI $h');
      }
    });
  }
}
