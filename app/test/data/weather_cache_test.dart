import 'package:ani/data/bundle.dart';
import 'package:ani/data/kv_store.dart';
import 'package:ani/data/power_client.dart';
import 'package:ani/data/weather_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/tracker_fixtures.dart';

/// A fake POWER server over [truth]: days on/after [lagFrom] come back as -999.
class FakePower {
  FakePower(this.truth);

  final List<DailyWeather> truth;
  DateTime? lagFrom;
  bool down = false;
  final List<Uri> requests = [];

  http.Client get client => MockClient((rq) async {
        requests.add(rq.url);
        if (down) throw http.ClientException('offline');
        final s = parseYmd(rq.url.queryParameters['start'])!, e = parseYmd(rq.url.queryParameters['end'])!;
        final out = <DailyWeather>[];
        for (var d = s; !d.isAfter(e); d = addDays(d, 1)) {
          final t = truth.where((x) => x.date == d).firstOrNull;
          final lag = lagFrom != null && !d.isBefore(lagFrom!);
          out.add(t == null || lag ? DailyWeather(date: d) : t);
        }
        return http.Response(powerBody(out), 200);
      });
}

List<DailyWeather> _truth(DateTime start, int n) => [
      for (var i = 0; i < n; i++)
        DailyWeather(
            date: addDays(start, i), tmax: 31 + i % 3, tmin: 22, tdew: 21, rh2m: 80, ws2m: 2, rs: 18, precip: i % 5 == 0 ? 3 : 0, gwetroot: 0.6),
    ];

void main() {
  final b = bundleOf(Town.guimba);
  final start = DateTime.utc(2024, 12, 1);

  test('sync fetches from the start date to today, then only from the first missing day', () async {
    final kv = MemoryKvStore();
    final fake = FakePower(_truth(start, 40))..lagFrom = addDays(start, 17);
    final repo = WeatherRepository(kv: kv, client: PowerClient(client: fake.client));
    final today = addDays(start, 20);
    final r1 = await repo.sync(Town.guimba, b, from: start, today: today);
    expect(r1.status, SyncStatus.fetched);
    expect(r1.newDays, 17);
    expect(fake.requests.single.queryParameters['start'], '20241201');
    expect(fake.requests.single.queryParameters['end'], ymd(today));
    final days = repo.daysFor(Town.guimba);
    expect(days.where((d) => d.usable), hasLength(17));
    expect(days.last.usable, isFalse, reason: 'lagging days cached as not usable');

    // POWER catches up by two days
    fake.lagFrom = addDays(start, 19);
    final r2 = await repo.sync(Town.guimba, b, from: start, today: today);
    expect(r2.newDays, 2);
    expect(fake.requests.last.queryParameters['start'], ymd(addDays(start, 17)));

    // all complete days cached: no request
    fake.lagFrom = null;
    await repo.sync(Town.guimba, b, from: start, today: today);
    final n = fake.requests.length;
    final r4 = await repo.sync(Town.guimba, b, from: start, today: today);
    expect(r4.status, SyncStatus.upToDate);
    expect(fake.requests.length, n);
  });

  test('offline sync does not throw and keeps the cache; a real day is never replaced by -999', () async {
    final kv = MemoryKvStore();
    final fake = FakePower(_truth(start, 30));
    final repo = WeatherRepository(kv: kv, client: PowerClient(client: fake.client));
    await repo.sync(Town.guimba, b, from: start, today: addDays(start, 10));
    final before = repo.daysFor(Town.guimba).where((d) => d.usable).length;
    expect(before, greaterThan(0));

    fake.down = true;
    final r = await repo.sync(Town.guimba, b, from: start, today: addDays(start, 15));
    expect(r.status, SyncStatus.offline);
    expect(r.ok, isFalse);
    expect(repo.lastError(Town.guimba), contains('offline'));
    expect(repo.daysFor(Town.guimba).where((d) => d.usable).length, before);

    // a server that has "lost" old days (all -999) must not wipe them
    fake
      ..down = false
      ..lagFrom = start;
    await repo.sync(Town.guimba, b, from: start, today: addDays(start, 15));
    expect(repo.daysFor(Town.guimba).where((d) => d.usable).length, before);

    // HTTP errors and garbage are reported, not thrown
    final broken = WeatherRepository(kv: kv, client: PowerClient(client: MockClient((_) async => http.Response('oops', 500))));
    expect((await broken.sync(Town.guimba, b, from: start, today: addDays(start, 15))).status, SyncStatus.error);
    final garbage = WeatherRepository(kv: kv, client: PowerClient(client: MockClient((_) async => http.Response('<html>', 200))));
    expect((await garbage.sync(Town.guimba, b, from: start, today: addDays(start, 15))).status, SyncStatus.error);
  });

  test('cache survives a new repository on the same storage, ET0 recomputed identically', () async {
    final kv = MemoryKvStore();
    final fake = FakePower(_truth(start, 30));
    final repo = WeatherRepository(kv: kv, client: PowerClient(client: fake.client));
    await repo.sync(Town.guimba, b, from: start, today: addDays(start, 12));
    final again = WeatherRepository(kv: kv, client: PowerClient(client: MockClient((_) async => throw http.ClientException('x'))));
    final a = repo.daysFor(Town.guimba), c = again.daysFor(Town.guimba);
    expect(c.length, a.length);
    for (var i = 0; i < a.length; i++) {
      expect(c[i].date, a[i].date);
      expect(c[i].et0, a[i].et0);
      expect(c[i].precip, a[i].precip);
    }
    expect(again.lastSyncedAt(Town.guimba), isNotNull);
    expect(again.daysFor(Town.munoz), isEmpty);
    // stored compactly: well under 100 bytes a day
    expect(kv.values[WeatherRepository.keyFor(Town.guimba)]!.length, lessThan(13 * 100));
  });

  test('an unreadable cache starts empty', () {
    final kv = MemoryKvStore({WeatherRepository.keyFor(Town.guimba): '{not json'});
    expect(WeatherRepository(kv: kv).daysFor(Town.guimba), isEmpty);
  });
}
