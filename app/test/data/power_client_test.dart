import 'dart:convert';

import 'package:ani/data/bundle.dart';
import 'package:ani/data/kv_store.dart';
import 'package:ani/data/power_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/tracker_fixtures.dart';

void main() {
  final b = bundleOf(Town.guimba);
  final req = b.meta.power;
  final pt = b.meta.point;

  test('request URL carries exactly the bundle parameters', () {
    final u = PowerClient.buildUri(req, pt, DateTime.utc(2024, 12, 1), DateTime.utc(2025, 1, 5));
    expect(u.toString(), startsWith('https://power.larc.nasa.gov/api/temporal/daily/point?'));
    expect(u.queryParameters, {
      'community': 'AG',
      'latitude': '15.6623',
      'longitude': '120.7657',
      'start': '20241201',
      'end': '20250105',
      'format': 'JSON',
      'parameters': 'T2M_MAX,T2M_MIN,T2MDEW,RH2M,WS2M,ALLSKY_SFC_SW_DWN,PRECTOTCORR,GWETROOT',
    });
  });

  test('ET0 and heat index computed as power_prep.py (numeric fixture rows)', () {
    final rows = (readJson('assets/fixtures/numeric.json')['et0'] as List).cast<Map<String, dynamic>>();
    final heat = {
      for (final h in (readJson('assets/fixtures/numeric.json')['heat_index'] as List).cast<Map<String, dynamic>>())
        '${h['muni']}${h['date']}': h,
    };
    for (final r in rows) {
      final i = r['in'] as Map<String, dynamic>;
      final d = DailyWeather.compute(
        date: parseYmd(r['date'] as String)!,
        tmax: n(i['tmax']),
        tmin: n(i['tmin']),
        tdew: n(i['tdew']),
        ws2m: n(i['u2']),
        rs: n(i['rs']),
        precip: 0,
        latDeg: n(i['lat']),
        elevM: n(i['elev']),
      );
      expect(d.et0, n((r['expect'] as Map)['et0_csv']), reason: '${r['muni']} ${r['date']}');
      final h = heat['${r['muni']}${r['date']}'];
      if (h != null) expect(d.heat!.hi, n((h['expect'] as Map)['hi_csv']));
      expect(d.usable, isTrue);
    }
  });

  group('parse', () {
    final days = [
      DailyWeather(date: DateTime.utc(2024, 12, 1), tmax: 30.96, tmin: 22.62, tdew: 23.52, rh2m: 87.2, ws2m: 1.95, rs: 17.07, precip: 0.06, gwetroot: 0.71),
      DailyWeather(date: DateTime.utc(2024, 12, 2), tmax: 31.2, tmin: 21.7, tdew: 22.0, rh2m: 80.0, ws2m: 2.1, rs: -999, precip: 0.0, gwetroot: 0.70),
      DailyWeather(date: DateTime.utc(2024, 12, 3)), // lag: every value -999
      DailyWeather(date: DateTime.utc(2024, 12, 4)),
    ];

    test('-999 is missing; lagging days are not usable', () {
      final r = PowerClient.parse(powerBody(days), request: req, point: pt);
      expect(r.days.map((d) => d.date), [for (var k = 1; k <= 4; k++) DateTime.utc(2024, 12, k)]);
      expect(r.elevationM, 107.63);
      final d1 = r.days[0];
      expect(d1.usable, isTrue);
      expect(d1.tmax, 30.96);
      expect(d1.precip, 0.06);
      expect(d1.gwetroot, 0.71);
      expect(d1.et0, isNotNull);
      expect(d1.heat, isNotNull);
      final d2 = r.days[1];
      expect(d2.rs, isNull);
      expect(d2.et0, isNull, reason: 'no solar -> no ET0');
      expect(d2.usable, isFalse);
      expect(r.days[2].usable, isFalse);
      expect(r.days[2].tmax, isNull);
      expect(r.days[3].heat, isNull);
    });

    test('elevation falls back to the town when the geometry has none', () {
      final r = PowerClient.parse(powerBody(days, elev: null), request: req, point: pt, fallbackElevationM: 282.04);
      expect(r.elevationM, 282.04);
      final r2 = PowerClient.parse(powerBody(days, elev: null), request: req, point: pt);
      expect(r2.elevationM, kDefaultElevationM);
    });

    test('bad bodies throw PowerException', () {
      expect(() => PowerClient.parse('nope', request: req, point: pt), throwsA(isA<PowerException>()));
      expect(() => PowerClient.parse('[]', request: req, point: pt), throwsA(isA<PowerException>()));
      expect(() => PowerClient.parse(jsonEncode({'properties': {}}), request: req, point: pt),
          throwsA(isA<PowerException>()));
    });

    test('fetchDaily over a mocked client', () async {
      Uri? seen;
      final client = PowerClient(client: MockClient((rq) async {
        seen = rq.url;
        return http.Response(powerBody(days), 200);
      }));
      final r = await client.fetchDaily(request: req, point: pt, start: DateTime.utc(2024, 12, 1), end: DateTime.utc(2024, 12, 4));
      expect(seen!.queryParameters['start'], '20241201');
      expect(seen!.queryParameters['end'], '20241204');
      expect(r.days.where((d) => d.usable), hasLength(1));

      final bad = PowerClient(client: MockClient((_) async => http.Response('{"messages":["x"]}', 422)));
      await expectLater(
          bad.fetchDaily(request: req, point: pt, start: DateTime.utc(2024, 12, 1), end: DateTime.utc(2024, 12, 4)),
          throwsA(isA<PowerException>().having((e) => e.statusCode, 'status', 422)));
      final down = PowerClient(client: MockClient((_) async => throw http.ClientException('no route')));
      await expectLater(
          down.fetchDaily(request: req, point: pt, start: DateTime.utc(2024, 12, 1), end: DateTime.utc(2024, 12, 4)),
          throwsA(isA<PowerException>().having((e) => e.statusCode, 'status', isNull)));
    });
  });
}
