import 'dart:convert';
import 'dart:io';

import 'package:ani/data/bundle.dart';
import 'package:ani/data/kv_store.dart';
import 'package:ani/data/power_client.dart';
import 'package:ani/data/weather_cache.dart';

Map<String, dynamic> readJson(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

final Map<Town, AniBundle> _bundles = {};

AniBundle bundleOf(Town t) => _bundles.putIfAbsent(t, () => AniBundle.fromJson(readJson(t.assetPath)));

Future<AniBundle> bundleFor(Town t) async => bundleOf(t);

List<Map<String, dynamic>> fieldMachineCases() =>
    (readJson('assets/fixtures/field_machine.json')['cases'] as List).cast<Map<String, dynamic>>();

double n(Object? x) => (x as num).toDouble();

DateTime addDays(DateTime d, int k) => DateTime.utc(d.year, d.month, d.day + k);

/// A fixture case's days as weather (consecutive from the sow date, ET0 given).
List<DailyWeather> fixtureWeather(Map<String, dynamic> c) {
  final cols = (c['columns'] as List).cast<String>();
  int ix(String k) => cols.indexOf(k);
  final sow = parseYmd(c['sow'] as String)!;
  final days = (c['days'] as List).cast<List>();
  return [
    for (final (i, r) in days.indexed)
      DailyWeather(
          date: addDays(sow, i), tmax: n(r[ix('tmax')]), tmin: n(r[ix('tmin')]), precip: n(r[ix('p')]), et0: n(r[ix('et0')])),
  ];
}

/// In-memory weather that serves fixed days (no network).
class FixedWeather implements WeatherSource {
  FixedWeather(this.byTown);

  final Map<Town, List<DailyWeather>> byTown;
  int syncs = 0;

  @override
  List<DailyWeather> daysFor(Town town) => byTown[town] ?? const [];

  @override
  DateTime? lastSyncedAt(Town town) => null;

  @override
  Future<SyncResult> sync(Town town, AniBundle bundle, {required DateTime from, required DateTime today}) async {
    syncs++;
    return SyncResult(town, SyncStatus.upToDate);
  }
}

/// A POWER JSON body for [days] (raw values; null -> -999) at elevation [elev].
String powerBody(List<DailyWeather> days, {double lat = 15.66, double lon = 120.77, double? elev = 107.63}) {
  Map<String, num> series(double? Function(DailyWeather) f) => {for (final d in days) ymd(d.date): f(d) ?? -999};
  return jsonEncode({
    'type': 'Feature',
    'geometry': {
      'type': 'Point',
      'coordinates': [lon, lat, ?elev],
    },
    'properties': {
      'parameter': {
        'T2M_MAX': series((d) => d.tmax),
        'T2M_MIN': series((d) => d.tmin),
        'T2MDEW': series((d) => d.tdew),
        'RH2M': series((d) => d.rh2m),
        'WS2M': series((d) => d.ws2m),
        'ALLSKY_SFC_SW_DWN': series((d) => d.rs),
        'PRECTOTCORR': series((d) => d.precip),
        'GWETROOT': series((d) => d.gwetroot),
      },
    },
    'header': {'title': 'NASA/POWER test', 'fill_value': -999.0},
    'messages': [],
  });
}
