import 'package:ani/core/alert_machine.dart';
import 'package:ani/core/dekadal.dart';
import 'package:ani/core/dryness.dart';
import 'package:ani/data/bundle.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/tracker_fixtures.dart';

Map<int, DrynessBaseline> _baselines(Town t) => {
      for (final e in bundleOf(t).dryness.reference.entries)
        e.key: DrynessBaseline(
            month: e.key, years: e.value.years, bal1: e.value.bal1, bal3: e.value.bal3, gwet: e.value.gwet),
    };

List<DayBalance> _days(DateTime from, DateTime to, double bal, double gwet) => [
      for (var d = from; !d.isAfter(to); d = addDays(d, 1)) (date: d, balance: bal, gwet: gwet),
    ];

void main() {
  final base = _baselines(Town.guimba);
  final today = DateTime.utc(2026, 11, 15);

  test('dekad helpers', () {
    expect([1, 10, 11, 20, 21, 31].map(dekadOf), [1, 1, 2, 2, 3, 3]);
    expect(dekadEnd(2026, 2, 3), DateTime.utc(2026, 2, 28));
    expect(dekadEnd(2024, 2, 3), DateTime.utc(2024, 2, 29));
  });

  test('no data gives no dekads', () {
    expect(dekadalD(days: const [], baselines: base, today: today), isEmpty);
  });

  test('last dekad is partial, ends yesterday; earlier ones are complete', () {
    final ds = dekadalD(days: _days(DateTime.utc(2026, 5, 1), DateTime.utc(2026, 11, 14), -2, 0.3), baselines: base, today: today);
    expect(ds.length, 9);
    expect(ds.last.partial, isTrue);
    expect((ds.last.month, ds.last.dekad), (11, 2));
    expect(ds.last.end, DateTime.utc(2026, 11, 14));
    expect(ds[ds.length - 2].partial, isFalse);
    expect((ds[ds.length - 2].month, ds[ds.length - 2].dekad), (11, 1));
  });

  test('D equals the month scorer on the same trailing window', () {
    // Nov: k=3, window = Sep+Oct+Nov = 91 days ending 14 Nov.
    final days = _days(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 11, 14), -1.5, 0.3);
    final ds = dekadalD(days: days, baselines: base, today: today);
    final expected = base[11]!.score(2026, bal3: -1.5 * 91, gwet: 0.3).d;
    expect(ds.last.d, closeTo(expected!, 1e-9));
  });

  test('a long dry spell reaches Delikado, rain brings it back down with hysteresis', () {
    final dry = dekadalD(days: _days(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 11, 14), -8, 0.05), baselines: base, today: today);
    expect(dry.last.d!, greaterThanOrEqualTo(2));
    expect(dry.last.state.level, AlertLevel.delikado);
    final wet = dekadalD(days: _days(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 11, 14), 10, 0.95), baselines: base, today: today);
    expect(wet.last.d!, lessThan(0));
    expect(wet.last.state.level, AlertLevel.normal);
  });

  test('too many missing days gives null D and holds the machine state', () {
    final ds = dekadalD(days: _days(DateTime.utc(2026, 11, 1), DateTime.utc(2026, 11, 14), -5, 0.1), baselines: base, today: today);
    expect(ds.every((d) => d.d == null), isTrue);
    expect(ds.last.state, AlertState.initial);
  });

  test('missing baseline month gives null D', () {
    final ds = dekadalD(days: _days(DateTime.utc(2026, 1, 1), DateTime.utc(2026, 11, 14), -2, 0.3), baselines: const {}, today: today);
    expect(ds.every((d) => d.d == null), isTrue);
  });
}
