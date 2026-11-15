import 'dart:convert';
import 'dart:io';

import 'package:ani/core/planner.dart';
import 'package:ani/data/bundle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixture floats are rounded to 8 dp; Dart computes in full double precision.
const double _tol = 1e-6;

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

final Map<String, dynamic> _fixture = _json('assets/fixtures/planner.json');
final Map<String, Map<String, dynamic>> _bundles = {
  for (final t in Town.values) t.id: _json(t.assetPath),
};
final Map<String, RiskTable> _risk = {
  for (final e in _bundles.entries)
    e.key: RiskTable.fromJson((e.value['risk'] as Map).cast<String, dynamic>()),
};

double Function(String, String) _heat(String muni) {
  final hs = (_fixture['heat_share'][muni] as Map).cast<String, dynamic>();
  return (crop, water) => ((hs['$crop|$water'] ?? 0) as num).toDouble();
}

PlannerProfile _profile(Map<String, dynamic> p) => PlannerProfile(
      muni: p['muni'] as String,
      water: p['water'] as String,
      last: (p['last'] as List).cast<String>(),
      wont: (p['wont'] as List).cast<String>().toSet(),
      coldStorage: p['cold_storage'] as bool,
      priorities: (p['priorities'] as List).cast<String>(),
    );

/// Recursive comparison: same keys, same list order, strings/bools equal,
/// numbers within [_tol]. Returns the first mismatch path, or null.
String? _diff(Object? got, Object? want, String path) {
  if (want is num && got is num) {
    return (got - want).abs() <= _tol ? null : '$path: got $got, want $want';
  }
  if (want is Map) {
    if (got is! Map) return '$path: got ${got.runtimeType}, want map';
    final gk = got.keys.map((k) => '$k').toList(), wk = want.keys.map((k) => '$k').toList();
    if (gk.toSet().length != wk.toSet().length || !gk.toSet().containsAll(wk)) {
      return '$path: keys $gk, want $wk';
    }
    for (final k in wk) {
      final d = _diff(got[k], want[k], '$path.$k');
      if (d != null) return d;
    }
    return null;
  }
  if (want is List) {
    if (got is! List) return '$path: got ${got.runtimeType}, want list';
    if (got.length != want.length) return '$path: length ${got.length}, want ${want.length} ($got vs $want)';
    for (var i = 0; i < want.length; i++) {
      final d = _diff(got[i], want[i], '$path[$i]');
      if (d != null) return d;
    }
    return null;
  }
  return got == want ? null : '$path: got $got, want $want';
}

PlanResult _run(Map<String, dynamic> c, {bool bundleHeat = false}) {
  final p = _profile((c['profile'] as Map).cast<String, dynamic>());
  return plan(p, _risk[p.muni]!,
      elNino: c['el_nino'] as bool, heatShare: bundleHeat ? null : _heat(p.muni));
}

PlanResult _sanity(String muni, String water) => plan(
      PlannerProfile(muni: muni, water: water, last: const ['rice', 'rice'],
          priorities: const ['risk', 'water', 'income']),
      _risk[muni]!,
      elNino: true,
    );

Set<String> _kept(PlanResult r) =>
    {'maize', 'mungbean', 'onion', 'rice', 'sweet_potato'}.difference(
        r.blocked.values.expand((v) => v).toSet());

void main() {
  final cases = (_fixture['cases'] as List).cast<Map<String, dynamic>>();

  test('fixture header and constants match the port', () {
    expect(cases, hasLength(192));
    final k = _fixture['header']['constants'] as Map;
    expect(k['theta_f'], kThetaF);
    expect(k['theta_h'], kThetaH);
    expect(k['beta'], kBeta);
    expect(k['ranked_share'], kRankedShare);
    expect(k['top'], 3);
    for (final b in _bundles.values) {
      final cfg = PlannerConfig.fromJson((b['planner'] as Map).cast<String, dynamic>());
      final pp = PlannerParams.fromConfig(cfg);
      expect([pp.thetaF, pp.thetaH, pp.beta, pp.rankedShare], [kThetaF, kThetaH, kBeta, kRankedShare]);
      expect(pp.waterLabel, kWaterLabel);
      expect(cfg.criteria, kCriteria);
      expect(cfg.benefit, kBenefit);
    }
  });

  group('golden parity with planner.py', () {
    for (final c in cases) {
      test(c['id'] as String, () {
        final want = (c['expect'] as Map).cast<String, dynamic>();
        final res = _run(c);
        final got = res.toJson();

        // explicit headline checks (clear failure messages)
        expect(res.state, want['state']);
        expect(res.trace, want['trace']);
        expect(res.blocked, (want['blocked'] as Map).map((k, v) => MapEntry(k, (v as List).cast<String>())));
        if (res.isHold) {
          expect(res.blockingGuard, want['blocking_guard']);
          expect(res.message!.toJson(), want['message']);
        } else {
          final wc = (want['cards'] as List).cast<Map<String, dynamic>>();
          expect(res.cards.map((k) => k.crop), wc.map((k) => k['crop']), reason: 'card order');
          expect(res.cards.map((k) => k.why), wc.map((k) => k['why']), reason: 'Bakit reasons');
          expect(res.cards.map((k) => k.confidence), wc.map((k) => k['confidence']));
          expect(res.cards.map((k) => k.flags), wc.map((k) => k['flags']));
          expect(res.topsisTop, want['topsis_top']);
          expect(res.topsisAgrees, want['topsis_agrees']);
        }

        // full structural + numeric equality
        expect(_diff(got, want, 'expect'), isNull);

        // determinism: same input -> same output
        expect(jsonEncode(_run(c).toJson()), jsonEncode(got));
      });
    }
  });

  test('bundle heat_share (3 dp) gives the same plans as the CSV heat share', () {
    for (final c in cases) {
      expect(_diff(_run(c, bundleHeat: true).toJson(), c['expect'], c['id'] as String), isNull);
    }
  });

  group('doc Ch.5 sanity (El Nino mode, last rice+rice)', () {
    for (final muni in ['guimba', 'munoz']) {
      test('$muni rainfed -> Hold (g2 water)', () {
        final r = _sanity(muni, 'rainfed');
        expect(r.isHold, isTrue);
        expect(r.blockingGuard, Guard.water);
        expect(r.trace, ['Idle', 'Filter', 'Hold']);
      });
      test('$muni ~2 irrigations -> Munggo', () {
        final r = _sanity(muni, 'limited_2');
        expect(r.state, 'Advise');
        expect(r.cards.map((c) => c.name), ['Munggo']);
      });
      test('$muni ~4 irrigations -> Kamote / Mais / Munggo', () {
        final r = _sanity(muni, 'limited_4');
        expect(_kept(r), {'sweet_potato', 'maize', 'mungbean'});
        expect(r.cards.map((c) => c.name).toSet(), {'Kamote', 'Mais', 'Munggo'});
      });
      test('$muni full irrigation -> all five pass, incl. Sibuyas', () {
        final r = _sanity(muni, 'full');
        expect(_kept(r), {'maize', 'mungbean', 'onion', 'rice', 'sweet_potato'});
        expect(r.cards, hasLength(3));
        expect(r.cards.map((c) => c.name), contains('Sibuyas'));
      });
    }
  });

  group('helpers', () {
    test('roc and weights', () {
      expect(roc(1), [1.0]);
      expect(roc(3)[0], closeTo(11 / 18, 1e-12));
      final w = weights(const ['risk', 'water', 'income'], false);
      expect(w.values.fold<double>(0, (a, b) => a + b), closeTo(1, 1e-12));
      expect(weights(const [], false).values.toSet(), {0.2});
    });
    test('pestScore', () {
      expect(pestScore('mungbean', const ['rice', 'rice']), 1.0);
      expect(pestScore('maize', const ['rice', 'mungbean']), 0.5);
      expect(pestScore('rice', const ['maize']), 0.0);
      expect(pestScore('rice', const []), 1.0);
    });
    test('Python-exact rounding (ties to even)', () {
      expect(pyRound(0.0625, 3), 0.062);
      expect(pyRound(2.5, 0), 2.0);
      expect(pyRound(3.5, 0), 4.0);
      expect(pyRound(2050, -2), 2000);
      expect(pyRound(2150, -2), 2200);
      expect(pyRound(-61156, -2), -61200);
      expect(pyFixed(726123.4 / 1000, 0, group: true), '726');
      expect(pyFixed(1234567.0, 0, group: true), '1,234,567');
      expect(pyFixed(0.125 * 100, 0), '12');
    });
  });
}
