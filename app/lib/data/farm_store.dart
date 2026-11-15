/// Farm records on the device: plantings (with the persisted field-machine
/// state), in-season alerts already emitted, and outcome records
/// (Harvest / Failed) that feed next season's "last two crops" answer.
///
/// Storage keys (JSON strings): `ani.farm.plantings`, `ani.farm.alerts`,
/// `ani.farm.outcomes`. Demo mode uses the same store on a [MemoryKvStore],
/// so a replay never touches the farmer's own records.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../core/field_machine.dart' show kWater;
import '../core/season_replay.dart';
import 'bundle.dart';
import 'kv_store.dart';
import 'planner_profile.dart';
import 'settings_store.dart';

/// How the crop went in (doc Fig. 4). Only onion distinguishes it (duration
/// counted from transplanting); informational for the other crops.
enum PlantingMethod {
  direct,
  transplant;

  static PlantingMethod parse(String? s) => s == transplant.name ? transplant : direct;
}

/// How a planting ended.
enum OutcomeResult {
  harvest,
  failed;

  static OutcomeResult? tryParse(String? s) => s == harvest.name ? harvest : (s == failed.name ? failed : null);
}

/// The persisted result of the last replay of a planting.
class TrackerSnapshot {
  const TrackerSnapshot({
    required this.machine,
    required this.lastDay,
    required this.replayedDays,
    required this.reached,
    this.readyOn,
  });

  /// `fieldMachineToJson` of the machine after the last replayed day.
  final Map<String, dynamic> machine;

  /// Last real day replayed, or null if none yet.
  final DateTime? lastDay;

  /// Number of real days ticked.
  final int replayedDays;

  /// Stage label (fsm state name) -> date first reached.
  final Map<String, DateTime> reached;

  /// First day guard 7 held (ready to harvest), or null.
  final DateTime? readyOn;

  Map<String, Object?> toJson() => {
        'machine': machine,
        'last_day': lastDay == null ? null : isoDate(lastDay!),
        'n': replayedDays,
        'reached': {for (final e in reached.entries) e.key: isoDate(e.value)},
        'ready_on': readyOn == null ? null : isoDate(readyOn!),
      };

  static TrackerSnapshot? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final m = j['machine'];
    final r = j['reached'];
    if (m is! Map) return null;
    return TrackerSnapshot(
      machine: m.cast<String, dynamic>(),
      lastDay: parseYmd(j['last_day'] as String?),
      replayedDays: (j['n'] as num?)?.toInt() ?? 0,
      reached: {
        if (r is Map)
          for (final e in r.entries) '${e.key}': ?parseYmd('${e.value}'),
      },
      readyOn: parseYmd(j['ready_on'] as String?),
    );
  }
}

/// One crop the farmer is tracking (or tracked).
class Planting {
  const Planting({
    required this.id,
    required this.town,
    required this.crop,
    required this.plantedOn,
    required this.method,
    required this.water,
    required this.createdAt,
    this.harvestConfirmedOn,
    this.closedAs,
    this.closedOn,
    this.s0Frac,
    this.isDemo = false,
    this.snapshot,
  });

  final String id;
  final Town town;

  /// Crop id ([CropId]).
  final String crop;

  /// Sow / transplant date (UTC midnight): the sow event, tick 0.
  final DateTime plantedOn;
  final PlantingMethod method;

  /// Water scenario id (`rainfed`, `limited_2`, `limited_4`, `full`).
  final String water;
  final DateTime createdAt;

  /// Set by "confirm harvest" (fires transition 7 on replay).
  final DateTime? harvestConfirmedOn;

  /// Set when the season ended (harvest confirmed or the machine failed).
  final OutcomeResult? closedAs;
  final DateTime? closedOn;

  /// Starting soil-water fraction override (demo seasons use the value the
  /// pipeline used); null = bundle `tracker.s0_frac_by_doy`.
  final double? s0Frac;

  /// A demo replay planting (never stored in the farmer's records).
  final bool isDemo;

  /// Persisted machine state after the last replay.
  final TrackerSnapshot? snapshot;

  bool get isClosed => closedAs != null;

  Planting copyWith({
    DateTime? harvestConfirmedOn,
    OutcomeResult? closedAs,
    DateTime? closedOn,
    TrackerSnapshot? snapshot,
  }) =>
      Planting(
        id: id,
        town: town,
        crop: crop,
        plantedOn: plantedOn,
        method: method,
        water: water,
        createdAt: createdAt,
        harvestConfirmedOn: harvestConfirmedOn ?? this.harvestConfirmedOn,
        closedAs: closedAs ?? this.closedAs,
        closedOn: closedOn ?? this.closedOn,
        s0Frac: s0Frac,
        isDemo: isDemo,
        snapshot: snapshot ?? this.snapshot,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'town': town.id,
        'crop': crop,
        'planted_on': isoDate(plantedOn),
        'method': method.name,
        'water': water,
        'created_at': createdAt.toUtc().toIso8601String(),
        'harvest_confirmed_on': harvestConfirmedOn == null ? null : isoDate(harvestConfirmedOn!),
        'closed_as': closedAs?.name,
        'closed_on': closedOn == null ? null : isoDate(closedOn!),
        's0_frac': s0Frac,
        'demo': isDemo,
        'snapshot': snapshot?.toJson(),
      };

  static Planting? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final town = Town.tryFromId(j['town'] as String?);
    final planted = parseYmd(j['planted_on'] as String?);
    final id = j['id'], crop = j['crop'], water = j['water'];
    if (town == null || planted == null || id is! String || crop is! String || water is! String) return null;
    if (!kWater.containsKey(water)) return null;
    return Planting(
      id: id,
      town: town,
      crop: crop,
      plantedOn: planted,
      method: PlantingMethod.parse(j['method'] as String?),
      water: water,
      createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      harvestConfirmedOn: parseYmd(j['harvest_confirmed_on'] as String?),
      closedAs: OutcomeResult.tryParse(j['closed_as'] as String?),
      closedOn: parseYmd(j['closed_on'] as String?),
      s0Frac: (j['s0_frac'] as num?)?.toDouble(),
      isDemo: j['demo'] == true,
      snapshot: TrackerSnapshot.tryFromJson(j['snapshot']),
    );
  }
}

/// One in-season alert that has been emitted.
class AlertRecord {
  const AlertRecord({
    required this.id,
    required this.type,
    required this.date,
    required this.plantingId,
    required this.crop,
    this.detail,
    this.seen = false,
    this.isDemo = false,
  });

  /// Deterministic id `<plantingId>|<type>|<yyyy-mm-dd>` (one per episode),
  /// so replays never duplicate an alert.
  final String id;
  final TrackerAlertType type;

  /// Weather day the alert is about.
  final DateTime date;
  final String plantingId;
  final String crop;

  /// `waterNow`: `irrigate` or `stress`.
  final String? detail;
  final bool seen;
  final bool isDemo;

  static String idFor(String plantingId, TrackerAlertType type, DateTime date) =>
      '$plantingId|${type.name}|${isoDate(date)}';

  AlertRecord copyWith({bool? seen}) => AlertRecord(
      id: id,
      type: type,
      date: date,
      plantingId: plantingId,
      crop: crop,
      detail: detail,
      seen: seen ?? this.seen,
      isDemo: isDemo);

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'date': isoDate(date),
        'planting': plantingId,
        'crop': crop,
        'detail': detail,
        'seen': seen,
        'demo': isDemo,
      };

  static AlertRecord? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final type = TrackerAlertType.tryParse(j['type'] as String?);
    final date = parseYmd(j['date'] as String?);
    final id = j['id'], pid = j['planting'];
    if (type == null || date == null || id is! String || pid is! String) return null;
    return AlertRecord(
      id: id,
      type: type,
      date: date,
      plantingId: pid,
      crop: '${j['crop'] ?? ''}',
      detail: j['detail'] as String?,
      seen: j['seen'] == true,
      isDemo: j['demo'] == true,
    );
  }
}

/// Outcome record of a finished planting.
class OutcomeRecord {
  const OutcomeRecord({
    required this.plantingId,
    required this.crop,
    required this.town,
    required this.sowDate,
    required this.result,
    required this.date,
  });

  final String plantingId;
  final String crop;
  final Town town;
  final DateTime sowDate;
  final OutcomeResult result;

  /// Harvest confirmed on / failed on.
  final DateTime date;

  Map<String, Object?> toJson() => {
        'planting': plantingId,
        'crop': crop,
        'town': town.id,
        'sow': isoDate(sowDate),
        'result': result.name,
        'date': isoDate(date),
      };

  static OutcomeRecord? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final town = Town.tryFromId(j['town'] as String?);
    final sow = parseYmd(j['sow'] as String?), date = parseYmd(j['date'] as String?);
    final result = OutcomeResult.tryParse(j['result'] as String?);
    final pid = j['planting'], crop = j['crop'];
    if (town == null || sow == null || date == null || result == null || pid is! String || crop is! String) {
      return null;
    }
    return OutcomeRecord(plantingId: pid, crop: crop, town: town, sowDate: sow, result: result, date: date);
  }
}

/// The last two crops grown (most recent first, by outcome date then sow
/// date), for the questionnaire's "last two crops" answer. Failed seasons
/// count: the crop was in the field. Optionally only [town]'s records.
List<String> lastTwoCrops(Iterable<OutcomeRecord> outcomes, {Town? town}) {
  final l = [
    for (final o in outcomes)
      if (town == null || o.town == town) o
  ]..sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.sowDate.compareTo(a.sowDate);
    });
  return [for (final o in l.take(2)) o.crop];
}

/// Plantings, alerts and outcomes on a [KvStore].
class FarmStore {
  FarmStore(this.kv, {math.Random? random}) : _random = random ?? math.Random();

  /// The farmer's store on [SharedPreferences].
  static Future<FarmStore> open() async => FarmStore(await PrefsKvStore.open());

  /// A throwaway in-memory store (demo mode).
  factory FarmStore.memory() => FarmStore(MemoryKvStore());

  static const keyPlantings = 'ani.farm.plantings';
  static const keyAlerts = 'ani.farm.alerts';
  static const keyOutcomes = 'ani.farm.outcomes';

  final KvStore kv;
  final math.Random _random;

  List<T> _list<T>(String key, T? Function(Object?) f) {
    final s = kv.getString(key);
    if (s == null) return [];
    try {
      final j = jsonDecode(s);
      if (j is! List) return [];
      return [for (final x in j) ?f(x)];
    } on FormatException {
      return [];
    }
  }

  Future<void> _put(String key, List<Map<String, Object?>> rows) => kv.setString(key, jsonEncode(rows));

  // -- plantings

  List<Planting> plantings() => _list(keyPlantings, Planting.tryFromJson);

  Planting? planting(String id) {
    for (final p in plantings()) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Inserts or replaces [p] (by id).
  Future<void> savePlanting(Planting p) async {
    final all = plantings();
    final i = all.indexWhere((x) => x.id == p.id);
    if (i < 0) {
      all.add(p);
    } else {
      all[i] = p;
    }
    await _put(keyPlantings, [for (final x in all) x.toJson()]);
  }

  /// Removes a planting and its alerts (its outcome record, if any, stays).
  Future<void> removePlanting(String id) async {
    await _put(keyPlantings, [
      for (final x in plantings())
        if (x.id != id) x.toJson()
    ]);
    await _put(keyAlerts, [
      for (final a in alerts())
        if (a.plantingId != id) a.toJson()
    ]);
  }

  /// A new random planting id.
  String newPlantingId() =>
      'p${DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 30).toRadixString(36)}';

  /// The irrigation level to preselect: the saved planner profile's water
  /// answer, else `rainfed`.
  String defaultWater() {
    final w = SavedPlannerProfile.tryDecode(kv.getString(SettingsStore.keyPlannerProfile))?.profile.water;
    return w != null && kWater.containsKey(w) ? w : 'rainfed';
  }

  // -- alerts

  /// All alerts, newest weather day first.
  List<AlertRecord> alerts() => _list(keyAlerts, AlertRecord.tryFromJson)..sort((a, b) => b.date.compareTo(a.date));

  /// Adds the alerts whose id is not stored yet; returns those added.
  Future<List<AlertRecord>> addAlerts(Iterable<AlertRecord> incoming) async {
    final all = alerts();
    final ids = {for (final a in all) a.id};
    final added = <AlertRecord>[];
    for (final a in incoming) {
      if (ids.add(a.id)) added.add(a);
    }
    if (added.isNotEmpty) await _put(keyAlerts, [for (final a in [...all, ...added]) a.toJson()]);
    return added;
  }

  /// Marks [ids] (or every alert, if null) as seen.
  Future<void> markAlertsSeen([Iterable<String>? ids]) async {
    final set = ids?.toSet();
    await _put(keyAlerts, [
      for (final a in alerts()) (set == null || set.contains(a.id) ? a.copyWith(seen: true) : a).toJson()
    ]);
  }

  // -- outcomes

  List<OutcomeRecord> outcomes() => _list(keyOutcomes, OutcomeRecord.tryFromJson);

  /// Stores [o] unless the planting already has an outcome; returns whether added.
  Future<bool> addOutcome(OutcomeRecord o) async {
    final all = outcomes();
    if (all.any((x) => x.plantingId == o.plantingId)) return false;
    await _put(keyOutcomes, [for (final x in [...all, o]) x.toJson()]);
    return true;
  }

  /// [lastTwoCrops] over the stored outcomes.
  List<String> lastTwoCrops({Town? town}) => _lastTwo(outcomes(), town: town);
}

const _lastTwo = lastTwoCrops;
