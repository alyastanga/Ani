/// Replays the field machine over a season of real weather days and turns
/// its Mealy outputs into the five farmer-facing in-season alerts
/// (docs/PLAN.md Phase 4). Pure Dart: no Flutter imports.
///
/// Alert mapping (fsm.py outputs / states -> [TrackerAlertType]):
///
/// | Alert              | Fires on                                                              |
/// |--------------------|-----------------------------------------------------------------------|
/// | `waterNow`         | `water_stress` (Ks < 1 in Veg/Repro), or a tick where the machine     |
/// |                    | irrigated (refill rule, irrigated scenarios: "irrigate today")        |
/// | `heatAtFlowering`  | `heat_risk` (rice in Repro, Tmax >= T_crit)                           |
/// | `onionRot`         | `rot_risk` (onion in Estab, 3-day rain >= the town's p98)             |
/// | `failed`           | `water_fail` (transition 1, kappa_sev >= K_FAIL -> Failed)            |
/// | `harvestReady`     | state Mature with G >= G_mat (guard 7 holds but waits for the         |
/// |                    | farmer's confirm), or the `harvest_ready` output when transition 7    |
/// |                    | fires                                                                  |
///
/// `waterNow`, `heatAtFlowering` and `onionRot` are emitted once per
/// *episode*: the first replayed day of a run of consecutive days with that
/// trigger. `failed` and `harvestReady` are emitted at most once per season.
/// Events are a pure function of (params, s0, days, confirm), so a replay
/// over the same days always yields the same events (callers dedupe by id).
///
/// Live tracking ticks with `simulating: false`: the machine never harvests
/// on its own; once the farmer confirms, the season is replayed with
/// `confirmHarvest: true`, so transition 7 fires on the first day guard 7
/// holds — exactly the day `fsm.run_season` (simulating) harvests.
library;

import 'field_machine.dart';

/// The in-season alerts shown to the farmer.
enum TrackerAlertType {
  waterNow,
  heatAtFlowering,
  onionRot,
  failed,
  harvestReady;

  /// Looks up a type by [name]; null if unknown.
  static TrackerAlertType? tryParse(String? s) {
    for (final t in values) {
      if (t.name == s) return t;
    }
    return null;
  }
}

/// One real weather day as the machine consumes it: `tick(tmax, tmin, P, ET0)`.
class SeasonDay {
  const SeasonDay({required this.date, required this.tmax, required this.tmin, required this.p, required this.et0});

  /// Calendar day (UTC midnight).
  final DateTime date;
  final double tmax;
  final double tmin;

  /// Rain, mm (POWER PRECTOTCORR).
  final double p;

  /// FAO-56 ET0, mm/day.
  final double et0;
}

/// One alert-worthy event found by [replaySeason].
class SeasonEvent {
  const SeasonEvent(this.type, this.dayIndex, this.date, {this.detail});

  final TrackerAlertType type;

  /// Index of the replayed day (tick) it fired on.
  final int dayIndex;
  final DateTime date;

  /// For `waterNow`: `irrigate` (the machine refilled that day) or `stress`.
  final String? detail;

  @override
  String toString() => 'SeasonEvent(${type.name}, $dayIndex, ${date.toIso8601String().substring(0, 10)}, $detail)';
}

/// Result of [replaySeason].
class SeasonReplay {
  SeasonReplay._(this.machine, this.dates, this.events, this.outputs, this.readyOn);

  /// The machine after the last replayed tick.
  final FieldMachine machine;

  /// Replayed days in order; tick `i` used `dates[i]`.
  final List<DateTime> dates;

  final List<SeasonEvent> events;

  /// Mealy outputs of each tick (`outputs[i]` for tick i).
  final List<List<String>> outputs;

  /// First day guard 7 held (Mature with G >= G_mat), or null.
  final DateTime? readyOn;

  /// Last replayed day, or null if none.
  DateTime? get lastDay => dates.isEmpty ? null : dates.last;

  /// Date a trace entry happened: machine day k is tick k (`dates[k]`); the
  /// sow event (and anything before the first tick) is the planting date.
  DateTime dateOfDay(int day, DateTime plantedOn) => day < dates.length ? dates[day] : (dates.isEmpty ? plantedOn : dates.last);
}

/// Runs M_F from [plantedOn] (the sow event, start soil water [s0] mm) over
/// [days] (ascending; days before [plantedOn] are ignored), stopping when
/// the machine returns to Fallow, as `fsm.run_season` does. Days missing
/// from [days] are simply not ticked (the pipeline also drops NaN days).
SeasonReplay replaySeason(
  Params prm,
  double s0,
  Iterable<SeasonDay> days, {
  required DateTime plantedOn,
  bool confirmHarvest = false,
  bool simulating = false,
  void Function(int index, SeasonDay day, FieldMachine m, List<String> out)? onTick,
}) {
  final m = FieldMachine(prm)..sow(s0);
  final dates = <DateTime>[];
  final events = <SeasonEvent>[];
  final outputs = <List<String>>[];
  DateTime? readyOn;
  final active = <TrackerAlertType>{};
  var failed = false, ready = false;
  DateTime? prev;
  for (final day in days) {
    if (day.date.isBefore(plantedOn)) continue;
    if (prev != null && !day.date.isAfter(prev)) {
      throw ArgumentError('season days must be strictly ascending (${day.date} after $prev)');
    }
    prev = day.date;
    final i = dates.length;
    final irrBefore = m.nIrr;
    final out = m.tick(day.tmax, day.tmin, day.p, day.et0, confirmHarvest: confirmHarvest, simulating: simulating);
    dates.add(day.date);
    outputs.add(out);
    onTick?.call(i, day, m, out);

    final irrigated = m.nIrr > irrBefore;
    final today = <TrackerAlertType, String?>{};
    if (out.contains(FieldAlert.waterStress) || irrigated) {
      today[TrackerAlertType.waterNow] = irrigated ? 'irrigate' : 'stress';
    }
    if (out.contains(FieldAlert.heatRisk)) today[TrackerAlertType.heatAtFlowering] = null;
    if (out.contains(FieldAlert.rotRisk)) today[TrackerAlertType.onionRot] = null;
    for (final e in today.entries) {
      if (!active.contains(e.key)) events.add(SeasonEvent(e.key, i, day.date, detail: e.value));
    }
    active
      ..clear()
      ..addAll(today.keys);

    if (!failed && out.contains(FieldAlert.waterFail)) {
      failed = true;
      events.add(SeasonEvent(TrackerAlertType.failed, i, day.date));
    }
    final guard7 = m.q == FieldState.mature && m.G >= prm.gMat;
    if (!ready && (out.contains(FieldAlert.harvestReady) || guard7)) {
      ready = true;
      readyOn = day.date;
      events.add(SeasonEvent(TrackerAlertType.harvestReady, i, day.date));
    }
    if (m.q == FieldState.fallow) break;
  }
  return SeasonReplay._(m, List.unmodifiable(dates), List.unmodifiable(events), List.unmodifiable(outputs), readyOn);
}

// ------------------------------------------------------------------ snapshot

/// Serialises a machine's mutable state (not its [Params]) for storage.
Map<String, Object?> fieldMachineToJson(FieldMachine m) => {
      'q': m.q.label,
      'd': m.d,
      'G': m.G,
      'S': m.S,
      'Ks': m.Ks,
      'kw': m.kw,
      'ksev': m.ksev,
      'ksev_max': m.ksevMax,
      'kh': m.kh,
      'irr': m.irr,
      'n_irr': m.nIrr,
      'eta': m.eta,
      'dp': m.dp,
      'rain': m.rain,
      'day': m.day,
      'rain3': m.rain3,
      'trace': [for (final t in m.trace) t.toList()],
      'reason': m.reason,
      'harvest_day': m.harvestDay,
    };

/// Restores a machine saved with [fieldMachineToJson] on [prm].
/// Throws [FormatException] on a bad shape.
FieldMachine fieldMachineFromJson(Params prm, Map<String, dynamic> j) {
  double d(String k) => (j[k] as num).toDouble();
  int n(String k) => (j[k] as num).toInt();
  try {
    final m = FieldMachine(prm)
      ..q = FieldState.fromLabel(j['q'] as String)
      ..d = n('d')
      ..G = d('G')
      ..S = d('S')
      ..Ks = d('Ks')
      ..kw = n('kw')
      ..ksev = n('ksev')
      ..ksevMax = n('ksev_max')
      ..kh = n('kh')
      ..irr = d('irr')
      ..nIrr = n('n_irr')
      ..eta = d('eta')
      ..dp = d('dp')
      ..rain = d('rain')
      ..day = n('day')
      ..rain3 = [for (final x in j['rain3'] as List) (x as num).toDouble()]
      ..reason = j['reason'] as String
      ..harvestDay = (j['harvest_day'] as num?)?.toInt();
    for (final t in j['trace'] as List) {
      final l = t as List;
      m.trace.add(FieldTransition((l[0] as num).toInt(), FieldState.fromLabel(l[1] as String),
          FieldState.fromLabel(l[2] as String), l[3] as String));
    }
    return m;
  } on TypeError catch (e) {
    throw FormatException('field machine snapshot: $e');
  } on ArgumentError catch (e) {
    throw FormatException('field machine snapshot: $e');
  }
}
