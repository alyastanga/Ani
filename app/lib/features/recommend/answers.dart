import '../../core/planner.dart';
import '../../data/bundle.dart';
import '../../data/planner_profile.dart';

/// The questionnaire's answers while the farmer steps through it.
///
/// [toProfile] maps them one-to-one onto planner.py's `Profile`:
///   step 1 town            -> muni (guimba | munoz | bongabon)
///   step 2 last two crops  -> last, most recent first (None is dropped)
///   step 3 irrigations     -> water (rainfed | limited_2 | limited_4 | full);
///          water source    -> kept for the record only ("rain only" = rainfed)
///   step 4 won't plant     -> wont; cold storage -> cold_storage
///   step 5 ranked top 3    -> priorities (income | risk | water | soil | pest)
class RecommendAnswers {
  RecommendAnswers({
    this.town,
    this.lastRecent,
    this.lastBefore,
    this.waterSource,
    this.water,
    Set<String>? wont,
    this.coldStorage = false,
    List<String>? priorities,
  })  : wont = wont ?? {},
        priorities = priorities ?? [];

  /// Prefills from saved answers; [fallbackTown] (the app's town) is used
  /// when nothing is saved. The saved town is kept even if it differs.
  ///
  /// [recordedLast] is the last two crops from the farm's outcome records
  /// (most recent first) and [recordedAt] the newest outcome's date. They
  /// fill "last two crops" when the saved answers have none, or when the
  /// records are newer than the saved answers (a harvest logged since the
  /// last questionnaire). Otherwise the farmer's saved answer stays.
  factory RecommendAnswers.prefill({
    SavedPlannerProfile? saved,
    Town? fallbackTown,
    List<String>? recordedLast,
    DateTime? recordedAt,
  }) {
    final p = saved?.profile;
    final records = [...?recordedLast?.where(CropId.all.contains).take(2)];
    final useRecords = records.isNotEmpty &&
        (p == null || p.last.isEmpty || (recordedAt != null && recordedAt.isAfter(saved!.savedAt)));
    final last = useRecords ? records : (p?.last ?? const <String>[]);
    final a = p == null
        ? RecommendAnswers(town: fallbackTown)
        : RecommendAnswers(
            town: saved!.town ?? fallbackTown,
            waterSource: saved.waterSource,
            water: p.water,
            wont: {...p.wont},
            coldStorage: p.coldStorage,
            priorities: [...p.priorities.where(kCriteria.contains).take(maxPriorities)],
          );
    a.lastRecent = last.isNotEmpty ? last[0] : null;
    a.lastBefore = last.length > 1 ? last[1] : null;
    a.lastFromRecords = useRecords;
    return a;
  }

  static const int steps = 5;
  static const int maxPriorities = 3;

  Town? town;

  /// Crop ids ([CropId]); null = None.
  String? lastRecent;

  /// True when [lastRecent] / [lastBefore] came from the farm's records.
  bool lastFromRecords = false;
  String? lastBefore;

  /// [WaterSource] id, or null.
  String? waterSource;

  /// [WaterScenario] id, or null until answered.
  String? water;

  final Set<String> wont;
  bool coldStorage;

  /// Ranked, most important first; at most [maxPriorities].
  final List<String> priorities;

  /// Sets the water source; "rain only" also sets the level to rainfed.
  void setWaterSource(String source) {
    waterSource = source;
    if (source == WaterSource.rain) water = WaterScenario.rainfed;
  }

  /// Sets the irrigation level; any irrigation contradicts "rain only".
  void setWater(String level) {
    water = level;
    if (level != WaterScenario.rainfed && waterSource == WaterSource.rain) waterSource = null;
  }

  void toggleWont(String crop) => wont.contains(crop) ? wont.remove(crop) : wont.add(crop);

  /// Tapping a ranked priority removes it (later ones move up); tapping an
  /// unranked one appends it if fewer than [maxPriorities] are ranked.
  void togglePriority(String criterion) {
    if (priorities.remove(criterion)) return;
    if (priorities.length < maxPriorities) priorities.add(criterion);
  }

  /// Whether step [step] (0-based) has what it needs to continue.
  bool isComplete(int step) => switch (step) {
        0 => town != null,
        1 => true,
        2 => water != null,
        3 => true,
        _ => priorities.isNotEmpty,
      };

  bool get isReady => [for (var i = 0; i < steps; i++) isComplete(i)].every((x) => x);

  /// The planner profile. Requires [isReady].
  PlannerProfile toProfile() {
    if (!isReady) throw StateError('questionnaire not finished');
    return PlannerProfile(
      muni: town!.id,
      water: water!,
      last: [?lastRecent, ?lastBefore],
      wont: {...wont},
      coldStorage: coldStorage,
      priorities: [...priorities],
    );
  }

  SavedPlannerProfile toSaved(DateTime now) =>
      SavedPlannerProfile(profile: toProfile(), waterSource: waterSource, savedAt: now);
}
