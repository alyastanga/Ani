/// Live dekadal dryness index D from daily water balance.
///
/// The pipeline scores whole calendar months (`dryness.dart`). On device the
/// same scorer is applied to a dekad (10-day block: days 1-10, 11-20, 21-end)
/// by taking the trailing window that matches the month's accumulation
/// (1 month in Apr-Oct, 3 months in Nov-Apr: the window is the summed length
/// of those calendar months, ending on the dekad's last day), scaled up if a
/// few days are missing, and scoring it against that calendar month's
/// baseline. The result feeds [AlertMachine] for the Normal / Bantay /
/// Delikado state. Pure Dart: no Flutter imports.
library;

import 'alert_machine.dart';
import 'dryness.dart';

/// One day of input: balance = rain - ET0 (mm), soil moisture (GWETROOT 0..1).
typedef DayBalance = ({DateTime date, double? balance, double? gwet});

/// The score of one dekad.
class DekadD {
  const DekadD({
    required this.year,
    required this.month,
    required this.dekad,
    required this.end,
    required this.partial,
    required this.d,
    required this.instant,
    required this.state,
  });

  final int year;
  final int month;

  /// 1, 2 or 3.
  final int dekad;

  /// Last day included (the dekad's last day, or yesterday if it is not over).
  final DateTime end;

  /// True when the dekad is not over yet (score so far).
  final bool partial;

  /// D, or null when too many days are missing or no baseline exists.
  final double? d;

  /// Stateless label of [d] (null when missing).
  final AlertLevel? instant;

  /// Alert machine state after this dekad (complete dekads only feed the machine).
  final AlertState state;
}

int _daysInMonth(int y, int m) => DateTime.utc(y, m + 1, 0).day;

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Dekad number (1..3) of day-of-month [dom].
int dekadOf(int dom) => dom <= 10 ? 1 : (dom <= 20 ? 2 : 3);

/// Last day of dekad [dekad] in month [month] of [year].
DateTime dekadEnd(int year, int month, int dekad) =>
    DateTime.utc(year, month, dekad == 1 ? 10 : (dekad == 2 ? 20 : _daysInMonth(year, month)));

/// Scores the last [count] dekads up to yesterday ([today] is not complete).
/// Returns oldest first; empty if there is no data at all.
List<DekadD> dekadalD({
  required Iterable<DayBalance> days,
  required Map<int, DrynessBaseline> baselines,
  required DateTime today,
  AlertThresholds thresholds = AlertThresholds.standard,
  int count = 9,
  double minCoverage = 0.9,
}) {
  final byDay = <DateTime, DayBalance>{for (final d in days) _day(d.date): d};
  if (byDay.isEmpty) return const [];
  final yesterday = _day(today).subtract(const Duration(days: 1));
  // walk back over dekads
  var y = yesterday.year, m = yesterday.month, k = dekadOf(yesterday.day);
  final spec = <(int, int, int)>[];
  for (var i = 0; i < count; i++) {
    spec.add((y, m, k));
    if (--k == 0) {
      k = 3;
      if (--m == 0) {
        m = 12;
        y--;
      }
    }
  }
  final machine = AlertMachine(thresholds);
  var state = AlertState.initial;
  final out = <DekadD>[];
  for (final (yy, mm, kk) in spec.reversed) {
    final full = dekadEnd(yy, mm, kk);
    final partial = full.isAfter(yesterday);
    final end = partial ? yesterday : full;
    final d = _score(byDay, baselines[mm], yy, mm, end, thresholds, minCoverage);
    if (!partial) state = machine.step(state, d);
    out.add(DekadD(
      year: yy,
      month: mm,
      dekad: kk,
      end: end,
      partial: partial,
      d: d,
      instant: machine.instantLevel(d),
      state: state,
    ));
  }
  return out;
}

double? _score(Map<DateTime, DayBalance> byDay, DrynessBaseline? base, int year, int month, DateTime end,
    AlertThresholds t, double minCoverage) {
  if (base == null) return null;
  final k = accumulationFor(month);
  var window = 0;
  var yy = year, mm = month;
  for (var i = 0; i < k; i++) {
    window += _daysInMonth(yy, mm);
    if (--mm == 0) {
      mm = 12;
      yy--;
    }
  }
  var sum = 0.0, n = 0;
  for (var i = 0; i < window; i++) {
    final b = byDay[end.subtract(Duration(days: i))]?.balance;
    if (b != null && !b.isNaN) {
      sum += b;
      n++;
    }
  }
  if (n < window * minCoverage) return null;
  final bal = sum * window / n;
  // soil moisture: mean over the last calendar-month length
  final gLen = _daysInMonth(year, month);
  var gs = 0.0, gn = 0;
  for (var i = 0; i < gLen; i++) {
    final g = byDay[end.subtract(Duration(days: i))]?.gwet;
    if (g != null && !g.isNaN) {
      gs += g;
      gn++;
    }
  }
  final gwet = gn >= gLen / 2 ? gs / gn : null;
  final s = base.score(year,
      bal1: k == 1 ? bal : null,
      bal3: k == 3 ? bal : null,
      gwet: gwet,
      bantay: t.bantay,
      delikado: t.delikado);
  return s.d;
}
