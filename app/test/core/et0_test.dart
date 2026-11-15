import 'dart:convert';
import 'dart:io';

import 'package:ani/core/et0.dart';
import 'package:flutter_test/flutter_test.dart';

const _tol = 1e-6;

final Map<String, dynamic> _fx =
    jsonDecode(File('assets/fixtures/numeric.json').readAsStringSync()) as Map<String, dynamic>;

double _d(Object? v) => (v as num).toDouble();

void main() {
  final rows = (_fx['et0'] as List).cast<Map<String, dynamic>>();

  test('fixture has et0 rows', () {
    expect(_fx['header']['kind'], 'numeric');
    expect(rows, isNotEmpty);
  });

  group('FAO-56 Penman-Monteith vs numeric.json et0', () {
    for (final (i, r) in rows.indexed) {
      final inp = r['in'] as Map<String, dynamic>;
      final e = r['expect'] as Map<String, dynamic>;
      test('#$i ${r['muni']} ${r['date']}', () {
        final tmax = _d(inp['tmax']), tmin = _d(inp['tmin']), tdew = _d(inp['tdew']);
        final rs = _d(inp['rs']), u2 = _d(inp['u2']), lat = _d(inp['lat']), elev = _d(inp['elev']);
        final doy = inp['doy'] as int;
        expect(dayOfYear(DateTime.parse(r['date'] as String)), doy);
        final ea = actualVp(tdew);
        expect(ea, closeTo(_d(r['ea']), _tol), reason: 'ea');
        expect(extraterrestrialRa(lat, doy), closeTo(_d(r['ra']), _tol), reason: 'Ra');
        final v = et0Pm(tmax: tmax, tmin: tmin, ea: ea, rs: rs, u2: u2, latDeg: lat, doy: doy, elevM: elev);
        expect(v, closeTo(_d(e['et0']), _tol), reason: 'et0');
        expect(roundHalfEven(v, 2), closeTo(_d(e['et0_rounded']), 1e-9), reason: 'et0_rounded');
        expect(
            et0Daily(tmax: tmax, tmin: tmin, tdew: tdew, rs: rs, u2: u2, latDeg: lat, doy: doy, elevM: elev),
            closeTo(_d(e['et0_csv']), 1e-9),
            reason: 'et0_csv');
        expect(et0Hargreaves(tmax: tmax, tmin: tmin, latDeg: lat, doy: doy), closeTo(_d(e['et0_harg']), _tol),
            reason: 'et0_harg');
      });
    }
  });

  test('satVp at 0 C is 0.6108 kPa; Ra clamps at polar night', () {
    expect(satVp(0), closeTo(0.6108, 1e-12));
    expect(extraterrestrialRa(80, 355), closeTo(0, 1e-9));
  });

  test('roundHalfEven matches numpy rounding', () {
    expect(roundHalfEven(2.5, 0), 2);
    expect(roundHalfEven(3.5, 0), 4);
    expect(roundHalfEven(-1.26, 1), closeTo(-1.3, 1e-12));
    expect(roundHalfEven(3.14159, 2), closeTo(3.14, 1e-12));
  });
}
