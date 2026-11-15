/// Live outlook for the Outlook tab and the Home heat strip: dekadal dryness
/// D and the daily heat index, both from the synced POWER cache.
///
/// Heat is people-safety advice only: nothing here is read by the planner or
/// the field machine.
library;

import '../core/alert_machine.dart';
import '../core/dekadal.dart';
import '../core/dryness.dart';
import '../core/heat_index.dart';
import 'bundle.dart';
import 'power_client.dart';

/// One day's heat index for the safety strip.
class HeatDay {
  const HeatDay({required this.date, required this.hi, required this.band});

  final DateTime date;

  /// Heat index, deg C (1 dp).
  final double hi;
  final PagasaBand band;

  /// PAGASA danger or extreme danger: "Magtrabaho nang maaga".
  bool get isDanger => band == PagasaBand.danger || band == PagasaBand.extremeDanger;
}

/// What the cache says about [town] as of [asOf].
class LiveOutlook {
  const LiveOutlook({
    required this.town,
    required this.asOf,
    required this.dekads,
    required this.heat,
    this.state,
    this.current,
    this.latestWeather,
  });

  final Town town;

  /// The day it was computed for ("today").
  final DateTime asOf;

  /// Recent dekads, oldest first; empty if the cache is too thin to score.
  final List<DekadD> dekads;

  /// Alert state after the last complete dekad, or null with no live D.
  final AlertState? state;

  /// The latest scored dekad (may be partial), or null with no live D.
  final DekadD? current;

  /// Daily heat for the last days that have data, oldest first.
  final List<HeatDay> heat;

  /// True when a live D is available (otherwise show `dryness.latest`).
  bool get hasLiveD => current != null;

  /// Latest cached day with a Tmax (for the Home conditions card), or null.
  final DailyWeather? latestWeather;

  /// Latest day with a heat index, or null.
  HeatDay? get latestHeat => heat.isEmpty ? null : heat.last;

  /// Alert level to show: the machine state including a partial dekad.
  AlertLevel? get level => state?.level;

  /// Days of the heat list that are danger days.
  int get dangerDays => heat.where((h) => h.isDanger).length;

  /// How far back the cache should reach to score the dekads (days).
  static const int lookbackDays = 200;

  /// Builds the outlook from cached [days] (any order, usable or not).
  static LiveOutlook compute({
    required Town town,
    required AniBundle bundle,
    required List<DailyWeather> days,
    required DateTime today,
    int heatDays = 7,
  }) {
    final baselines = <int, DrynessBaseline>{
      for (final e in bundle.dryness.reference.entries)
        e.key: DrynessBaseline(
          month: e.key,
          years: e.value.years,
          bal1: e.value.bal1,
          bal3: e.value.bal3,
          gwet: e.value.gwet,
        ),
    };
    final t = bundle.dryness.thresholds;
    final th = AlertThresholds(
      bantay: t.bantay,
      delikado: t.delikado,
      downBantay: t.downBantay,
      downNormal: t.downNormal,
      calmDekads: t.calmDekads,
    );
    final dekads = dekadalD(
      days: [
        for (final d in days)
          (
            date: d.date,
            balance: d.precip != null && d.et0 != null ? d.precip! - d.et0! : null,
            gwet: d.gwetroot,
          ),
      ],
      baselines: baselines,
      today: today,
      thresholds: th,
    );
    DekadD? current;
    for (final k in dekads.reversed) {
      if (k.d != null) {
        current = k;
        break;
      }
    }
    AlertState? state;
    if (current != null) {
      final machine = AlertMachine(th);
      state = dekads.where((k) => !k.partial).isEmpty
          ? machine.step(AlertState.initial, current.d)
          : dekads.lastWhere((k) => !k.partial).state;
      if (current.partial) state = machine.step(state, current.d);
    }
    final heat = <HeatDay>[
      for (final d in days)
        if (d.heat?.category != null) HeatDay(date: d.date, hi: d.heat!.hi, band: d.heat!.category!),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return LiveOutlook(
      town: town,
      asOf: today,
      dekads: dekads,
      heat: heat.length > heatDays ? heat.sublist(heat.length - heatDays) : heat,
      state: state,
      current: current,
      latestWeather: days.where((d) => d.tmax != null).fold<DailyWeather?>(
          null, (a, d) => a == null || d.date.isAfter(a.date) ? d : a),
    );
  }
}
