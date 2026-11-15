/// NASA POWER Daily Point API client (docs/PLAN.md "APIs needed").
///
/// ```text
/// GET <meta.power.endpoint>?community=AG&latitude=..&longitude=..&start=YYYYMMDD&end=YYYYMMDD
///     &format=JSON&parameters=<meta.power.parameters>
/// ```
///
/// No key, no account. POWER marks missing values with `-999`
/// (`meta.power.fill_value`) and publishes with a lag of a few days, so the
/// trailing days of a response are usually all -999: those days are kept as
/// "not usable" and never fed to the field machine.
///
/// ET0 and the heat index are not POWER parameters; [DailyWeather.compute]
/// derives them on device exactly as `pipeline/power_prep.py` `process()`:
/// `ea = sat_vp(T2MDEW)`, Penman-Monteith ET0 rounded to 2 dp, RH at Tmax
/// (1 dp) -> NWS heat index (1 dp) -> PAGASA band.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/et0.dart';
import '../core/heat_index.dart';
import '../core/season_replay.dart';
import 'bundle.dart';
import 'kv_store.dart';

/// Site elevation (m) per town, used for ET0 when a POWER response has no
/// elevation (same fallback as `pipeline/export_fixtures.py` `ELEV_M`, read
/// from the POWER CSV headers the pipeline used).
const Map<Town, double> kTownElevationM = {Town.guimba: 107.63, Town.munoz: 107.63, Town.bongabon: 282.04};

/// power_prep.py's default elevation when the header has none.
const double kDefaultElevationM = 50.0;

/// One day of POWER values plus the derived ET0 / heat index.
class DailyWeather {
  const DailyWeather({
    required this.date,
    this.tmax,
    this.tmin,
    this.tdew,
    this.rh2m,
    this.ws2m,
    this.rs,
    this.precip,
    this.gwetroot,
    this.et0,
    this.heat,
  });

  /// Calendar day (UTC midnight; POWER daily values are UTC days).
  final DateTime date;

  /// `T2M_MAX`, `T2M_MIN`, `T2MDEW` (C).
  final double? tmax;
  final double? tmin;
  final double? tdew;

  /// `RH2M` (%).
  final double? rh2m;

  /// `WS2M` (m/s).
  final double? ws2m;

  /// `ALLSKY_SFC_SW_DWN` (MJ/m2/day, AG community).
  final double? rs;

  /// Rain (mm/day), the bundle's `rain_parameter` (`PRECTOTCORR`).
  final double? precip;

  /// `GWETROOT` (0-1); optional, not needed by the field machine.
  final double? gwetroot;

  /// FAO-56 ET0 (mm/day, 2 dp), or null if an input is missing.
  final double? et0;

  /// Heat index of the day, or null if Tmax / dew point is missing.
  final DailyHeat? heat;

  /// True if the field machine can tick on this day: Tmax, Tmin, rain and
  /// ET0 present (the pipeline's `dropna` on T2M_MAX, T2M_MIN, PRECTOTCORR, ET0).
  bool get usable => tmax != null && tmin != null && precip != null && et0 != null;

  /// The machine input for a [usable] day.
  SeasonDay toSeasonDay() => SeasonDay(date: date, tmax: tmax!, tmin: tmin!, p: precip!, et0: et0!);

  /// Builds a day from raw POWER values, computing ET0 and heat index as
  /// power_prep.py does, at latitude [latDeg] and elevation [elevM].
  factory DailyWeather.compute({
    required DateTime date,
    double? tmax,
    double? tmin,
    double? tdew,
    double? rh2m,
    double? ws2m,
    double? rs,
    double? precip,
    double? gwetroot,
    required double latDeg,
    required double elevM,
  }) {
    double? et0;
    if (tmax != null && tmin != null && tdew != null && rs != null && ws2m != null) {
      final v = et0Daily(
          tmax: tmax, tmin: tmin, tdew: tdew, rs: rs, u2: ws2m, latDeg: latDeg, doy: dayOfYear(date), elevM: elevM);
      et0 = v.isFinite ? v : null;
    }
    return DailyWeather(
      date: dateOnly(date),
      tmax: tmax,
      tmin: tmin,
      tdew: tdew,
      rh2m: rh2m,
      ws2m: ws2m,
      rs: rs,
      precip: precip,
      gwetroot: gwetroot,
      et0: et0,
      heat: tmax != null && tdew != null ? dailyHeat(tmax, tdew) : null,
    );
  }
}

/// POWER request / response failure (HTTP status, bad JSON, timeout).
class PowerException implements Exception {
  const PowerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'PowerException(${statusCode ?? '-'}): $message';
}

/// A parsed POWER daily response.
class PowerResponse {
  const PowerResponse({required this.lat, required this.lon, required this.elevationM, required this.days});

  /// Latitude used for ET0 (the requested point, as power_prep reads it from
  /// the POWER header).
  final double lat;
  final double lon;

  /// Elevation used for ET0: from the response geometry, else the town fallback.
  final double elevationM;

  /// Every date in the response, ascending; missing values are null.
  final List<DailyWeather> days;
}

/// NASA POWER daily-point client. Inject [client] in tests
/// (`package:http/testing.dart` `MockClient`).
class PowerClient {
  PowerClient({http.Client? client, this.timeout = const Duration(seconds: 30)}) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// The request URL, parameters exactly as `meta.power`.
  static Uri buildUri(PowerRequest req, GeoPoint point, DateTime start, DateTime end) {
    final base = Uri.parse(req.endpoint);
    return base.replace(queryParameters: {
      ...base.queryParameters,
      'community': req.community,
      'latitude': point.lat.toString(),
      'longitude': point.lon.toString(),
      'start': ymd(start),
      'end': ymd(end),
      'format': req.format,
      'parameters': req.parameters.join(','),
    });
  }

  /// Fetches [start]..[end] (inclusive) for [point]. Throws [PowerException].
  Future<PowerResponse> fetchDaily({
    required PowerRequest request,
    required GeoPoint point,
    required DateTime start,
    required DateTime end,
    double? fallbackElevationM,
  }) async {
    final uri = buildUri(request, point, start, end);
    final http.Response res;
    try {
      res = await _client.get(uri, headers: const {'Accept': 'application/json'}).timeout(timeout);
    } on TimeoutException {
      throw const PowerException('timed out');
    } on http.ClientException catch (e) {
      throw PowerException('network: ${e.message}');
    }
    if (res.statusCode != 200) {
      throw PowerException('HTTP ${res.statusCode}', statusCode: res.statusCode);
    }
    return parse(res.body, request: request, point: point, fallbackElevationM: fallbackElevationM);
  }

  /// Parses a POWER JSON body. Values equal to the fill value (or <= -999)
  /// and absent dates become null. Throws [PowerException] on a bad shape.
  static PowerResponse parse(String body,
      {required PowerRequest request, required GeoPoint point, double? fallbackElevationM}) {
    final Object? j;
    try {
      j = jsonDecode(body);
    } on FormatException catch (e) {
      throw PowerException('bad JSON: ${e.message}');
    }
    if (j is! Map) throw const PowerException('bad JSON: top level is not an object');
    final props = j['properties'];
    final param = props is Map ? props['parameter'] : null;
    if (param is! Map) throw const PowerException('bad JSON: no properties.parameter');
    final header = j['header'];
    final fill = header is Map && header['fill_value'] is num ? (header['fill_value'] as num).toDouble() : request.fillValue;

    double? elev;
    final geom = j['geometry'];
    if (geom is Map && geom['coordinates'] is List) {
      final c = geom['coordinates'] as List;
      if (c.length >= 3 && c[2] is num && (c[2] as num).isFinite && (c[2] as num) > fill) {
        elev = (c[2] as num).toDouble();
      }
    }
    final elevation = elev ?? fallbackElevationM ?? kDefaultElevationM;

    final dates = <String>{};
    final series = <String, Map>{};
    for (final e in param.entries) {
      if (e.value is Map) {
        series['${e.key}'.toUpperCase()] = e.value as Map;
        for (final k in (e.value as Map).keys) {
          dates.add('$k');
        }
      }
    }
    double? v(String name, String date) {
      final x = series[name]?[date];
      if (x is! num) return null;
      final d = x.toDouble();
      if (!d.isFinite || d == fill || d <= -999) return null;
      return d;
    }

    final days = <DailyWeather>[];
    for (final key in dates.toList()..sort()) {
      final date = parseYmd(key);
      if (date == null) continue;
      days.add(DailyWeather.compute(
        date: date,
        tmax: v('T2M_MAX', key),
        tmin: v('T2M_MIN', key),
        tdew: v('T2MDEW', key),
        rh2m: v('RH2M', key),
        ws2m: v('WS2M', key),
        rs: v('ALLSKY_SFC_SW_DWN', key),
        precip: v(request.rainParameter.toUpperCase(), key),
        gwetroot: v('GWETROOT', key),
        latDeg: point.lat,
        elevM: elevation,
      ));
    }
    return PowerResponse(lat: point.lat, lon: point.lon, elevationM: elevation, days: List.unmodifiable(days));
  }

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}
