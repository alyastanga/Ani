/// Local per-town, per-day weather cache and the POWER sync that fills it.
///
/// Storage: one compact JSON string per town under `ani.wx.<town>`:
/// `{"v":1,"lat":..,"elev":..,"synced":"<iso>","err":"..","days":{"yyyymmdd":[tmax,tmin,tdew,rh2m,ws2m,rs,p,gwet]}}`
/// (null = missing). ET0 and heat index are recomputed on read, so only POWER
/// values are stored (~60 bytes a day; days older than [WeatherRepository.keepDays]
/// are pruned).
///
/// [WeatherRepository.sync] never throws: offline / HTTP / parse failures are
/// returned as [SyncStatus.offline] / [SyncStatus.error] and the cache is
/// left as it was, so the app keeps working from the cache.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'bundle.dart';
import 'kv_store.dart';
import 'power_client.dart';

/// Outcome of one sync.
enum SyncStatus {
  /// Nothing to fetch: every complete day in range is cached and usable.
  upToDate,

  /// A request was made and merged (it may still have returned only -999s).
  fetched,

  /// Network failure (no connection, timeout). Cache unchanged.
  offline,

  /// POWER answered with an error status or an unreadable body. Cache unchanged.
  error,
}

/// What a sync did.
class SyncResult {
  const SyncResult(this.town, this.status, {this.newDays = 0, this.requested, this.message});

  final Town town;
  final SyncStatus status;

  /// Days that became usable with this sync.
  final int newDays;

  /// Requested range (start, end), if a request was made.
  final (DateTime, DateTime)? requested;

  /// Error text for [SyncStatus.offline] / [SyncStatus.error].
  final String? message;

  bool get ok => status == SyncStatus.upToDate || status == SyncStatus.fetched;

  @override
  String toString() => 'SyncResult(${town.id}, ${status.name}, new $newDays${message == null ? '' : ', $message'})';
}

/// Daily weather the tracker reads: the POWER-backed [WeatherRepository] or
/// a demo replay source.
abstract interface class WeatherSource {
  /// Brings the cache for [town] up to date for [from]..[today]. Never throws.
  Future<SyncResult> sync(Town town, AniBundle bundle, {required DateTime from, required DateTime today});

  /// Cached days for [town], ascending (usable or not).
  List<DailyWeather> daysFor(Town town);

  /// When [town] last synced successfully, or null.
  DateTime? lastSyncedAt(Town town);
}

/// POWER sync + shared_preferences cache.
class WeatherRepository implements WeatherSource {
  WeatherRepository({required this.kv, PowerClient? client, DateTime Function()? clock})
      : client = client ?? PowerClient(),
        _clock = clock ?? DateTime.now;

  /// Opens the repository on [SharedPreferences] with a default HTTP client.
  static Future<WeatherRepository> open({http.Client? httpClient}) async =>
      WeatherRepository(kv: await PrefsKvStore.open(), client: PowerClient(client: httpClient));

  static String keyFor(Town town) => 'ani.wx.${town.id}';

  /// Days kept in the cache (older ones are pruned on each save).
  static const int keepDays = 400;

  final KvStore kv;
  final PowerClient client;
  final DateTime Function() _clock;
  final Map<Town, _TownCache> _mem = {};

  _TownCache _load(Town town) => _mem.putIfAbsent(town, () => _TownCache.decode(kv.getString(keyFor(town))));

  @override
  List<DailyWeather> daysFor(Town town) => _load(town).days(town);

  @override
  DateTime? lastSyncedAt(Town town) => _load(town).synced;

  /// Last sync error text for [town], or null if the last sync succeeded.
  String? lastError(Town town) => _load(town).err;

  @override
  Future<SyncResult> sync(Town town, AniBundle bundle, {required DateTime from, required DateTime today}) async {
    final c = _load(town);
    final t = dateOnly(today);
    var start = dateOnly(from);
    final floor = DateTime.utc(t.year, t.month, t.day - keepDays);
    if (start.isBefore(floor)) start = floor;
    // first complete day (before today) that is missing or not usable
    DateTime? first;
    for (var d = start; d.isBefore(t); d = DateTime.utc(d.year, d.month, d.day + 1)) {
      if (!c.usable(ymd(d))) {
        first = d;
        break;
      }
    }
    if (first == null) return SyncResult(town, SyncStatus.upToDate);
    final range = (first, t);
    try {
      final res = await client.fetchDaily(
        request: bundle.meta.power,
        point: bundle.meta.point,
        start: first,
        end: t,
        fallbackElevationM: kTownElevationM[town],
      );
      var added = 0;
      for (final day in res.days) {
        final k = ymd(day.date);
        final had = c.usable(k);
        if (had && !day.usable) continue; // never replace a real day with -999s
        c.put(k, day);
        if (!had && day.usable) added++;
      }
      c
        ..lat = res.lat
        ..elev = res.elevationM
        ..synced = _clock().toUtc()
        ..err = null
        ..prune(DateTime.utc(t.year, t.month, t.day - keepDays));
      await kv.setString(keyFor(town), c.encode());
      return SyncResult(town, SyncStatus.fetched, newDays: added, requested: range);
    } on PowerException catch (e) {
      final offline = e.statusCode == null && !e.message.startsWith('bad JSON');
      await _saveError(town, c, e.message);
      return SyncResult(town, offline ? SyncStatus.offline : SyncStatus.error, requested: range, message: e.message);
    } catch (e) {
      // anything else (socket errors on some platforms, bad shapes) must not escape
      await _saveError(town, c, '$e');
      return SyncResult(town, SyncStatus.offline, requested: range, message: '$e');
    }
  }

  Future<void> _saveError(Town town, _TownCache c, String msg) async {
    c.err = msg;
    try {
      await kv.setString(keyFor(town), c.encode());
    } catch (_) {
      // storage failure: keep the in-memory cache
    }
  }

  /// Removes the cached weather for [town].
  Future<void> clear(Town town) async {
    _mem.remove(town);
    await kv.remove(keyFor(town));
  }
}

class _TownCache {
  _TownCache();

  double? lat;
  double? elev;
  DateTime? synced;
  String? err;

  /// yyyymmdd -> [tmax, tmin, tdew, rh2m, ws2m, rs, p, gwet]
  final Map<String, List<double?>> raw = {};

  bool usable(String key) {
    final r = raw[key];
    return r != null && r[0] != null && r[1] != null && r[2] != null && r[4] != null && r[5] != null && r[6] != null;
  }

  void put(String key, DailyWeather d) =>
      raw[key] = [d.tmax, d.tmin, d.tdew, d.rh2m, d.ws2m, d.rs, d.precip, d.gwetroot];

  void prune(DateTime before) {
    final k = ymd(before);
    raw.removeWhere((key, _) => key.compareTo(k) < 0);
  }

  List<DailyWeather> days(Town town) {
    final la = lat ?? 15.7, el = elev ?? kTownElevationM[town] ?? kDefaultElevationM;
    final keys = raw.keys.toList()..sort();
    return [
      for (final k in keys)
        if (parseYmd(k) case final date?)
          DailyWeather.compute(
            date: date,
            tmax: raw[k]![0],
            tmin: raw[k]![1],
            tdew: raw[k]![2],
            rh2m: raw[k]![3],
            ws2m: raw[k]![4],
            rs: raw[k]![5],
            precip: raw[k]![6],
            gwetroot: raw[k]![7],
            latDeg: la,
            elevM: el,
          ),
    ];
  }

  String encode() => jsonEncode({
        'v': 1,
        'lat': lat,
        'elev': elev,
        'synced': synced?.toIso8601String(),
        'err': err,
        'days': raw,
      });

  static _TownCache decode(String? s) {
    final c = _TownCache();
    if (s == null) return c;
    try {
      final j = jsonDecode(s);
      if (j is! Map || j['v'] != 1) return c;
      c
        ..lat = (j['lat'] as num?)?.toDouble()
        ..elev = (j['elev'] as num?)?.toDouble()
        ..synced = DateTime.tryParse('${j['synced']}')
        ..err = j['err'] as String?;
      final days = j['days'];
      if (days is Map) {
        for (final e in days.entries) {
          final l = e.value;
          if (l is List && l.length == 8) {
            c.raw['${e.key}'] = [for (final x in l) x is num ? x.toDouble() : null];
          }
        }
      }
    } catch (_) {
      return _TownCache(); // unreadable cache: start empty rather than crash
    }
    return c;
  }
}
