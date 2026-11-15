import 'dart:convert';

import '../core/planner.dart';
import 'bundle.dart';

/// Where the farmer's dry-season water comes from (questionnaire step 3).
///
/// Informational only: the planner reads the irrigation level
/// ([PlannerProfile.water]); "rain only" implies `rainfed`.
abstract final class WaterSource {
  static const rain = 'rain';
  static const pump = 'pump';
  static const canal = 'canal';
  static const river = 'river';
  static const all = [rain, pump, canal, river];
}

/// The planner answers saved on the device, so the last recommendation can be
/// reopened (re-planned from the bundle) and reused by the tracker (Phase 4).
class SavedPlannerProfile {
  const SavedPlannerProfile({required this.profile, this.waterSource, required this.savedAt});

  /// The five answers exactly as fed to [plan].
  final PlannerProfile profile;

  /// [WaterSource] id, or null if not answered.
  final String? waterSource;

  final DateTime savedAt;

  /// Town of [profile], or null if the id is unknown.
  Town? get town => Town.tryFromId(profile.muni);

  Map<String, Object?> toJson() => {
        'version': 1,
        'muni': profile.muni,
        'water': profile.water,
        'last': profile.last,
        'wont': profile.wont.toList()..sort(),
        'cold_storage': profile.coldStorage,
        'priorities': profile.priorities,
        'water_source': waterSource,
        'saved_at': savedAt.toUtc().toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  /// Parses [toJson] output. Throws [FormatException] on a bad shape or an
  /// unknown town / water level.
  factory SavedPlannerProfile.fromJson(Map<String, dynamic> j) {
    List<String> strings(Object? v, String name) {
      if (v is! List) throw FormatException('planner profile: $name is not a list');
      return [for (final x in v) x is String ? x : throw FormatException('planner profile: $name')];
    }

    final muni = j['muni'];
    final water = j['water'];
    if (muni is! String || Town.tryFromId(muni) == null) {
      throw FormatException('planner profile: unknown town $muni');
    }
    if (water is! String || !WaterScenario.all.contains(water)) {
      throw FormatException('planner profile: unknown water $water');
    }
    final source = j['water_source'];
    final saved = DateTime.tryParse('${j['saved_at']}');
    return SavedPlannerProfile(
      profile: PlannerProfile(
        muni: muni,
        water: water,
        last: strings(j['last'], 'last'),
        wont: strings(j['wont'], 'wont').toSet(),
        coldStorage: j['cold_storage'] == true,
        priorities: strings(j['priorities'], 'priorities'),
      ),
      waterSource: WaterSource.all.contains(source) ? source as String : null,
      savedAt: saved ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// Decodes [encode] output; null if [s] is null or invalid.
  static SavedPlannerProfile? tryDecode(String? s) {
    if (s == null) return null;
    try {
      final v = jsonDecode(s);
      return v is Map ? SavedPlannerProfile.fromJson(v.cast<String, dynamic>()) : null;
    } on FormatException {
      return null;
    }
  }
}

/// Runs the planner for [profile] on [bundle]: the town's risk table, the
/// coming season's El Niño flag and the bundle's planner constants. The
/// bundle's 3-dp `heat_share` gives the same plans as planner.py (tested).
PlanResult planWithBundle(PlannerProfile profile, AniBundle bundle) => plan(
      profile,
      bundle.risk,
      elNino: bundle.enso.isElNino,
      params: PlannerParams.fromConfig(bundle.planner),
    );
