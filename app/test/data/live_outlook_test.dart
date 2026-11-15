import 'package:ani/core/heat_index.dart';
import 'package:ani/data/bundle.dart';
import 'package:ani/data/live_outlook.dart';
import 'package:ani/data/power_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tracker_fixtures.dart';

/// Daily weather with rain / ET0 and heat from tmax / tdew.
List<DailyWeather> weatherDays(DateTime from, DateTime to,
    {double rain = 0, double et0 = 4, double tmax = 33, double tdew = 22, double gwet = 0.3}) {
  return [
    for (var d = from; !d.isAfter(to); d = addDays(d, 1))
      DailyWeather(
          date: d, tmax: tmax, tmin: 24, tdew: tdew, precip: rain, et0: et0, gwetroot: gwet, heat: dailyHeat(tmax, tdew)),
  ];
}

void main() {
  final bundle = bundleOf(Town.guimba);
  final today = DateTime.utc(2026, 11, 15);

  LiveOutlook compute(List<DailyWeather> days) =>
      LiveOutlook.compute(town: Town.guimba, bundle: bundle, days: days, today: today);

  test('empty cache: no live D, no heat', () {
    final o = compute(const []);
    expect(o.hasLiveD, isFalse);
    expect(o.state, isNull);
    expect(o.latestHeat, isNull);
  });

  test('dry cache gives a live D and Delikado', () {
    final o = compute(weatherDays(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 11, 14), et0: 7, gwet: 0.05));
    expect(o.hasLiveD, isTrue);
    expect(o.current!.d!, greaterThan(2));
    expect(o.level!.id, 'delikado');
  });

  test('POWER lag: unusable trailing days keep the last scored dekad as current', () {
    final days = [
      ...weatherDays(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 11, 3), et0: 7, gwet: 0.05),
      for (var d = DateTime.utc(2026, 11, 4); !d.isAfter(DateTime.utc(2026, 11, 14)); d = addDays(d, 1))
        DailyWeather(date: d),
    ];
    final o = compute(days);
    expect(o.hasLiveD, isTrue);
    expect(o.current!.d, isNotNull);
  });

  test('heat: latest day is danger, listed with PAGASA band; last 7 days only', () {
    // tmax 38 C with a 28 C dew point is a danger-level heat index.
    final days = [
      ...weatherDays(DateTime.utc(2026, 11, 1), DateTime.utc(2026, 11, 9)),
      ...weatherDays(DateTime.utc(2026, 11, 10), DateTime.utc(2026, 11, 12), tmax: 38, tdew: 28),
    ];
    final o = compute(days);
    expect(o.heat.length, 7);
    final h = o.latestHeat!;
    expect(h.date, DateTime.utc(2026, 11, 12));
    expect(h.hi, dailyHeat(38, 28).hi);
    expect(h.band, pagasaCategory(h.hi));
    expect(h.isDanger, isTrue);
    expect(o.dangerDays, 3);
  });

  test('cool day is not a danger day', () {
    final o = compute(weatherDays(DateTime.utc(2026, 11, 1), DateTime.utc(2026, 11, 12), tmax: 29, tdew: 20));
    expect(o.latestHeat!.isDanger, isFalse);
    expect(o.dangerDays, 0);
  });
}
