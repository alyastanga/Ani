/// Tracker service (docs/PLAN.md Phase 4.3): replays the field machine for
/// each planting over the cached real weather days, persists the machine
/// state, emits the five in-season alerts and records outcomes.
///
/// Flow on [TrackerService.refresh] (call it on app open and after a sync):
///   1. for every town with an open planting, sync POWER from the earliest
///      open planting date to today (never throws; offline keeps the cache);
///   2. replay each open planting from its planting date over the cached
///      usable days before today, starting soil water `s0_frac x TAW` with
///      `s0_frac` from the bundle's `tracker.s0_frac_by_doy` (fsm.run_season
///      uses the bucket's S_frac on the sow day; the bundle carries its median
///      by day of year for exactly this case);
///   3. persist a [TrackerSnapshot], add new alerts (deduped by id), and on
///      Failed close the planting and write its outcome record.
///
/// Ticks use `simulating: false`, so the machine waits in Mature once
/// G >= G_mat (alert `harvestReady`); [TrackerService.confirmHarvest] marks
/// the planting and replays with `confirmHarvest: true`, which fires
/// transition 7 (Mature -> Harvest) and writes the Harvest outcome. Closed
/// plantings are frozen at their last snapshot (no more replays).
///
/// See `lib/core/season_replay.dart` for the alert <-> FSM mapping.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/field_machine.dart';
import '../core/season_replay.dart';
import 'bundle.dart';
import 'farm_store.dart';
import 'kv_store.dart';
import 'power_client.dart';
import 'weather_cache.dart';

/// One step of the stage timeline (Prep -> Estab -> Veg -> Repro -> Mature
/// -> Harvest / Failed).
class StageMark {
  const StageMark(this.stage, this.reachedOn, {required this.current});

  final FieldState stage;

  /// Date the stage was reached, or null if not (yet).
  final DateTime? reachedOn;

  /// True for the planting's current stage.
  final bool current;

  bool get reached => reachedOn != null;
}

/// An inclusive date range.
class DateWindow {
  const DateWindow(this.start, this.end);

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) => other is DateWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateWindow(${isoDate(start)}..${isoDate(end)})';
}

/// Everything the My farm screen shows for one planting.
class PlantingView {
  const PlantingView({
    required this.planting,
    required this.stage,
    required this.progress,
    required this.timeline,
    required this.expectedHarvest,
    required this.waitingForDataDays,
    required this.lastDataDay,
    required this.readyOn,
    required this.canConfirmHarvest,
    required this.outcome,
    required this.soilWaterFraction,
    required this.ks,
    required this.daysTracked,
    required this.alerts,
  });

  final Planting planting;

  /// Current stage; after the season it is Harvest or Failed (never Fallow).
  final FieldState stage;

  /// G / G_mat in 0..1 (1 once harvested).
  final double progress;

  /// Prep, Estab, Veg, Repro, Mature, then Harvest or Failed.
  final List<StageMark> timeline;

  /// Expected harvest window; null once failed.
  final DateWindow? expectedHarvest;

  /// Complete days since the last real POWER day that have no usable data
  /// yet ("waiting for data"); 0 once closed.
  final int waitingForDataDays;

  /// Last real weather day replayed, or null if none yet.
  final DateTime? lastDataDay;

  /// Day the crop became ready to harvest (guard 7 held), or null.
  final DateTime? readyOn;

  /// True when "confirm harvest" may be offered.
  final bool canConfirmHarvest;

  /// fsm outcome record of the season so far (stress days, irrigations, ...).
  final FieldOutcome outcome;

  /// Soil water S / TAW after the last day (0..1).
  final double soilWaterFraction;

  /// Water stress coefficient of the last day (1 = no stress).
  final double ks;

  /// Real weather days ticked so far.
  final int daysTracked;

  /// This planting's alerts, newest first.
  final List<AlertRecord> alerts;

  bool get isDemo => planting.isDemo;
  bool get isClosed => planting.isClosed;
}

/// Result of [TrackerService.refresh].
class TrackerRefresh {
  const TrackerRefresh({required this.plantings, required this.newAlerts, required this.syncs, required this.errors});

  /// Every planting's view, newest planting first.
  final List<PlantingView> plantings;

  /// Alerts first emitted by this refresh (for local notifications).
  final List<AlertRecord> newAlerts;

  /// One per synced town (empty if sync was skipped).
  final List<SyncResult> syncs;

  /// Planting id -> error, for plantings that could not be replayed
  /// (e.g. their town bundle failed to load). Their last snapshot is kept.
  final Map<String, Object> errors;

  /// True if any town could not reach POWER.
  bool get offline => syncs.any((s) => !s.ok);
}

/// Days after the ready day the harvest window stays open.
const int kHarvestGraceDays = 7;

/// Tracks the farmer's plantings. Listen to it for changes.
class TrackerService extends ChangeNotifier {
  TrackerService({
    required this.store,
    required this.weather,
    required Future<AniBundle> Function(Town town) bundleFor,
    DateTime Function()? clock,
  })  : _bundleFor = bundleFor, // ignore: prefer_initializing_formals
        _clock = clock ?? DateTime.now;

  /// The service on the device's [SharedPreferences] with a POWER client.
  static Future<TrackerService> open({
    required Future<AniBundle> Function(Town town) bundleFor,
    http.Client? httpClient,
    DateTime Function()? clock,
  }) async {
    final kv = await PrefsKvStore.open();
    return TrackerService(
      store: FarmStore(kv),
      weather: WeatherRepository(kv: kv, client: PowerClient(client: httpClient), clock: clock),
      bundleFor: bundleFor,
      clock: clock,
    );
  }

  final FarmStore store;
  final WeatherSource weather;
  final Future<AniBundle> Function(Town town) _bundleFor;
  final DateTime Function() _clock;

  List<PlantingView> _views = const [];
  Future<void> _queue = Future.value();

  /// Today's date per the clock.
  DateTime get today => dateOnly(_clock());

  /// Views from the last refresh / change (empty until the first one).
  List<PlantingView> get views => _views;

  /// View of planting [id] from the last refresh, or null.
  PlantingView? viewFor(String id) {
    for (final v in _views) {
      if (v.planting.id == id) return v;
    }
    return null;
  }

  /// All alerts, newest first.
  List<AlertRecord> get alerts => store.alerts();

  /// Alerts not yet marked seen.
  int get unseenAlertCount => store.alerts().where((a) => !a.seen).length;

  /// Outcome records (Harvest / Failed).
  List<OutcomeRecord> get outcomes => store.outcomes();

  /// The last two crops from the outcome records, most recent first
  /// (prefill for the questionnaire's "last two crops").
  List<String> lastTwoCrops({Town? town}) => store.lastTwoCrops(town: town);

  /// Irrigation level to preselect when adding a planting (saved planner
  /// profile, else rainfed).
  String get defaultWater => store.defaultWater();

  // ---------------------------------------------------------------- actions

  // Serialises mutations so overlapping refreshes cannot interleave writes.
  Future<T> _locked<T>(Future<T> Function() f) {
    final c = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await f());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  /// Syncs (unless [sync] is false), replays every open planting and
  /// rebuilds the views. Never throws for network problems.
  Future<TrackerRefresh> refresh({bool sync = true}) => _locked(() => _refresh(sync: sync));

  /// Adds a planting and refreshes. [water] defaults to [defaultWater].
  /// [s0Frac] and [isDemo] are for demo replays only.
  /// Throws [ArgumentError] for an unknown crop / water or a future date.
  Future<PlantingView> addPlanting({
    required Town town,
    required String crop,
    required DateTime plantedOn,
    PlantingMethod method = PlantingMethod.direct,
    String? water,
    bool sync = true,
    double? s0Frac,
    bool isDemo = false,
  }) async {
    final b = await _bundleFor(town);
    if (!b.tracker.crops.containsKey(crop)) throw ArgumentError.value(crop, 'crop', 'not in the ${town.id} bundle');
    final w = water ?? defaultWater;
    if (!kWater.containsKey(w)) throw ArgumentError.value(w, 'water', 'unknown water scenario');
    final date = dateOnly(plantedOn);
    if (date.isAfter(today)) throw ArgumentError.value(plantedOn, 'plantedOn', 'is in the future');
    final p = Planting(
      id: store.newPlantingId(),
      town: town,
      crop: crop,
      plantedOn: date,
      method: method,
      water: w,
      createdAt: _clock().toUtc(),
      s0Frac: s0Frac,
      isDemo: isDemo,
    );
    await _locked(() => store.savePlanting(p));
    await refresh(sync: sync);
    return viewFor(p.id)!;
  }

  /// Deletes a planting and its alerts (its outcome record stays).
  Future<void> removePlanting(String id) => _locked(() async {
        await store.removePlanting(id);
        _views = [for (final v in _views) if (v.planting.id != id) v];
        notifyListeners();
      });

  /// "Confirm harvest": fires transition 7 (Mature -> Harvest) by replaying
  /// with `confirmHarvest: true`, closes the planting and writes the Harvest
  /// outcome dated [on] (default today). Throws [StateError] unless the
  /// crop is ready ([PlantingView.canConfirmHarvest]).
  Future<PlantingView> confirmHarvest(String plantingId, {DateTime? on}) => _locked(() async {
        final p = store.planting(plantingId);
        if (p == null) throw StateError('no planting $plantingId');
        if (p.isClosed || p.snapshot?.readyOn == null) throw StateError('planting $plantingId is not ready to harvest');
        final date = dateOnly(on ?? today);
        final b = await _bundleFor(p.town);
        var q = p.copyWith(harvestConfirmedOn: date);
        q = await _replay(q, b, force: true, newAlerts: []);
        q = q.copyWith(closedAs: OutcomeResult.harvest, closedOn: date);
        await store.savePlanting(q);
        await store.addOutcome(OutcomeRecord(
            plantingId: q.id, crop: q.crop, town: q.town, sowDate: q.plantedOn, result: OutcomeResult.harvest, date: date));
        await _rebuildViews();
        return viewFor(plantingId)!;
      });

  /// Marks [ids] (or all) as seen.
  Future<void> markAlertsSeen([Iterable<String>? ids]) => _locked(() async {
        await store.markAlertsSeen(ids);
        await _rebuildViews();
      });

  // ---------------------------------------------------------------- internals

  Future<TrackerRefresh> _refresh({required bool sync}) async {
    final t = today;
    final plantings = store.plantings();
    final syncs = <SyncResult>[];
    final errors = <String, Object>{};
    if (sync) {
      final from = <Town, DateTime>{};
      for (final p in plantings) {
        if (p.isClosed) continue;
        final f = from[p.town];
        if (f == null || p.plantedOn.isBefore(f)) from[p.town] = p.plantedOn;
      }
      for (final e in from.entries) {
        try {
          final b = await _bundleFor(e.key);
          syncs.add(await weather.sync(e.key, b, from: e.value, today: t));
        } catch (err) {
          syncs.add(SyncResult(e.key, SyncStatus.error, message: '$err'));
        }
      }
    }
    final newAlerts = <AlertRecord>[];
    for (final p in plantings) {
      if (p.isClosed && p.snapshot != null) continue;
      try {
        final b = await _bundleFor(p.town);
        final q = await _replay(p, b, newAlerts: newAlerts);
        await store.savePlanting(q);
      } catch (err) {
        errors[p.id] = err;
      }
    }
    await _rebuildViews(errors: errors);
    return TrackerRefresh(plantings: _views, newAlerts: newAlerts, syncs: syncs, errors: errors);
  }

  /// Starting soil-water fraction for a planting date: the bundle median for
  /// that day of year, else the nearest day with a value (±30 d), else 0.5.
  static double s0FracFor(Tracker tracker, DateTime date) {
    final v = tracker.s0FracFor(date);
    if (v != null) return v;
    final n = tracker.s0FracByDoy.length;
    if (n > 0) {
      final i0 = Tracker.doyIndex(date);
      for (var k = 1; k <= 30; k++) {
        for (final i in [i0 - k, i0 + k]) {
          final x = tracker.s0FracByDoy[(i % n + n) % n];
          if (x != null) return x;
        }
      }
    }
    return 0.5;
  }

  /// The machine input days for [p]: cached usable days from its planting
  /// date up to (not including) today.
  List<SeasonDay> _daysFor(Planting p) => [
        for (final d in weather.daysFor(p.town))
          if (d.usable && !d.date.isBefore(p.plantedOn) && d.date.isBefore(today)) d.toSeasonDay(),
      ];

  Future<Planting> _replay(Planting p, AniBundle b, {bool force = false, required List<AlertRecord> newAlerts}) async {
    if (p.isClosed && p.snapshot != null && !force) return p;
    final tp = b.tracker.crops[p.crop];
    if (tp == null) throw StateError('crop ${p.crop} not in the ${p.town.id} bundle');
    final prm = tp.toFieldParams(p.water);
    final s0 = (p.s0Frac ?? s0FracFor(b.tracker, p.plantedOn)) * prm.taw;
    final r = replaySeason(prm, s0, _daysFor(p), plantedOn: p.plantedOn, confirmHarvest: p.harvestConfirmedOn != null);

    // Never move backwards (e.g. a cleared cache): keep the longer snapshot.
    final old = p.snapshot;
    if (!force && old != null && old.replayedDays > r.dates.length) return p;

    final reached = <String, DateTime>{FieldState.prep.label: p.plantedOn};
    for (final t in r.machine.trace) {
      if (t.guard == 'g2 sow' || t.to == FieldState.fallow) continue;
      reached.putIfAbsent(t.to.label, () => r.dateOfDay(t.day, p.plantedOn));
    }
    final snap = TrackerSnapshot(
      machine: fieldMachineToJson(r.machine),
      lastDay: r.lastDay,
      replayedDays: r.dates.length,
      reached: reached,
      readyOn: r.readyOn,
    );
    var q = p.copyWith(snapshot: snap);

    final incoming = [
      for (final e in r.events)
        AlertRecord(
          id: AlertRecord.idFor(p.id, e.type, e.date),
          type: e.type,
          date: e.date,
          plantingId: p.id,
          crop: p.crop,
          detail: e.detail,
          isDemo: p.isDemo,
        ),
    ];
    newAlerts.addAll(await store.addAlerts(incoming));

    final failedOn = reached[FieldState.failed.label];
    if (failedOn != null && !q.isClosed) {
      q = q.copyWith(closedAs: OutcomeResult.failed, closedOn: failedOn);
      await store.addOutcome(OutcomeRecord(
          plantingId: q.id, crop: q.crop, town: q.town, sowDate: q.plantedOn, result: OutcomeResult.failed, date: failedOn));
    }
    return q;
  }

  Future<void> _rebuildViews({Map<String, Object>? errors}) async {
    final alerts = store.alerts();
    final views = <PlantingView>[];
    for (final p in store.plantings()) {
      try {
        final b = await _bundleFor(p.town);
        views.add(_view(p, b, [for (final a in alerts) if (a.plantingId == p.id) a]));
      } catch (err) {
        errors?[p.id] = err;
      }
    }
    views.sort((a, b) => b.planting.plantedOn.compareTo(a.planting.plantedOn));
    _views = List.unmodifiable(views);
    notifyListeners();
  }

  PlantingView _view(Planting p, AniBundle b, List<AlertRecord> alerts) {
    final tp = b.tracker.crops[p.crop]!;
    final prm = tp.toFieldParams(p.water);
    final snap = p.snapshot;
    final s0 = (p.s0Frac ?? s0FracFor(b.tracker, p.plantedOn)) * prm.taw;
    final m = snap == null ? (FieldMachine(prm)..sow(s0)) : fieldMachineFromJson(prm, snap.machine);
    final reached = snap?.reached ?? {FieldState.prep.label: p.plantedOn};
    final failed = p.closedAs == OutcomeResult.failed || reached.containsKey(FieldState.failed.label);

    var stage = m.q;
    if (stage == FieldState.fallow) stage = failed ? FieldState.failed : FieldState.harvest;
    final end = failed ? FieldState.failed : FieldState.harvest;
    final timeline = [
      for (final s in [FieldState.prep, FieldState.estab, FieldState.veg, FieldState.repro, FieldState.mature, end])
        StageMark(s, reached[s.label], current: s == stage),
    ];

    final harvested = stage == FieldState.harvest || p.closedAs == OutcomeResult.harvest;
    final progress = harvested ? 1.0 : (m.G / prm.gMat).clamp(0.0, 1.0);
    final t = today;
    var waiting = 0;
    if (!p.isClosed) {
      final last = snap?.lastDay;
      var start = last == null ? p.plantedOn : DateTime.utc(last.year, last.month, last.day + 1);
      if (start.isBefore(p.plantedOn)) start = p.plantedOn;
      waiting = math.max(0, t.difference(start).inDays);
    }
    final duration = b.crops[p.crop]?.durationDays ?? 100;
    return PlantingView(
      planting: p,
      stage: stage,
      progress: progress.toDouble(),
      timeline: List.unmodifiable(timeline),
      expectedHarvest: failed ? null : _harvestWindow(p, m, snap, prm, duration),
      waitingForDataDays: waiting,
      lastDataDay: snap?.lastDay,
      readyOn: snap?.readyOn,
      canConfirmHarvest: !p.isClosed && snap?.readyOn != null && m.q == FieldState.mature,
      outcome: m.outcome(),
      soilWaterFraction: prm.taw > 0 ? (m.S / prm.taw).clamp(0.0, 1.0).toDouble() : 0.0,
      ks: m.Ks,
      daysTracked: snap?.replayedDays ?? 0,
      alerts: List.unmodifiable(alerts),
    );
  }

  /// Expected harvest window:
  /// - harvested: ready day .. confirmed day;
  /// - ready: ready day .. ready day + [kHarvestGraceDays];
  /// - growing: last real day + remaining GDD / GDD rate (rate observed so
  ///   far once 7+ days are tracked, else G_mat / guide duration),
  ///   ± max(3, 15% of the remaining days).
  static DateWindow _harvestWindow(Planting p, FieldMachine m, TrackerSnapshot? snap, Params prm, int durationDays) {
    DateTime add(DateTime d, int n) => DateTime.utc(d.year, d.month, d.day + n);
    final ready = snap?.readyOn;
    final confirmed = p.harvestConfirmedOn;
    if (confirmed != null) return DateWindow(ready ?? confirmed, confirmed);
    if (ready != null) return DateWindow(ready, add(ready, kHarvestGraceDays));
    final n = snap?.replayedDays ?? 0;
    final rate = n >= 7 && m.G > 0 ? m.G / n : prm.gMat / math.max(1, durationDays);
    final remaining = math.max(0.0, prm.gMat - m.G) / rate;
    final base = snap?.lastDay ?? add(p.plantedOn, -1);
    final est = add(base, remaining.ceil());
    final margin = math.max(3, (0.15 * remaining).round());
    var start = add(est, -margin);
    if (!start.isAfter(base)) start = add(base, 1);
    return DateWindow(start, add(est, margin));
  }
}
