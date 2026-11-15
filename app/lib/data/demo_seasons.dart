/// Demo mode (docs/PLAN.md Phase 4.6): replays a past season through the
/// same [TrackerService] the farmer's plantings use, on an in-memory store,
/// so judges can see a whole season without waiting. Everything it produces
/// is flagged `isDemo` and must be labelled as a replay in the UI.
///
/// Seasons come from `assets/fixtures/demo_seasons.json`
/// (`pipeline/export_demo.py`): real POWER days from the pipeline's
/// processed CSVs. No one season can show all five alerts (heat at flowering
/// is rice only, onion rot is onion only), so there are three:
///
/// | Season                                | Alerts shown                                |
/// |---------------------------------------|---------------------------------------------|
/// | Guimba, rice, 2023-24, full irrigation | waterNow (irrigate days), heatAtFlowering, harvestReady |
/// | Muñoz, onion, 2004-05, rainfed         | onionRot, waterNow, failed                  |
/// | Bongabon, onion, 2011-12, 4 irrigations | onionRot, waterNow, harvestReady           |
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/heat_index.dart';
import '../core/season_replay.dart';
import 'bundle.dart';
import 'farm_store.dart';
import 'kv_store.dart';
import 'power_client.dart';
import 'tracker_service.dart';
import 'weather_cache.dart';

/// One bundled past season.
class DemoSeason {
  const DemoSeason({
    required this.id,
    required this.town,
    required this.crop,
    required this.drySeason,
    required this.enso,
    required this.water,
    required this.sow,
    required this.s0Frac,
    required this.shows,
    required this.days,
    required this.expectedStates,
    required this.expectedHarvestDay,
    required this.expectedFailed,
  });

  /// `<town>|<crop>|<dry season>|<water>`.
  final String id;
  final Town town;
  final String crop;

  /// e.g. `2023-24`.
  final String drySeason;

  /// ENSO tag of the season (`el_nino`, `la_nina`, `neutral`, or empty).
  final String enso;
  final String water;
  final DateTime sow;

  /// Starting soil-water fraction the pipeline used for this season.
  final double s0Frac;

  /// Alert types this season is meant to show.
  final Set<TrackerAlertType> shows;

  /// POWER days from the sow date (ET0 as computed by power_prep.py).
  final List<DailyWeather> days;

  /// fsm.py state after each tick with simulating=True (parity reference).
  final List<String> expectedStates;
  final int? expectedHarvestDay;
  final bool expectedFailed;

  /// Plain-English replay caption (the UI should localise its own).
  String get replayLabel => 'Replay: ${town.displayName}, $crop, dry season $drySeason';

  factory DemoSeason.fromJson(Map<String, dynamic> j) {
    final cols = (j['columns'] as List).cast<String>();
    int ix(String k) => cols.indexOf(k);
    double? v(List r, String k) => (r[ix(k)] as num?)?.toDouble();
    final town = Town.tryFromId(j['muni'] as String?) ?? (throw FormatException('demo: bad town ${j['muni']}'));
    final exp = j['expect'] as Map<String, dynamic>;
    return DemoSeason(
      id: j['id'] as String,
      town: town,
      crop: j['crop'] as String,
      drySeason: j['dry_season'] as String,
      enso: (j['enso'] as String?) ?? '',
      water: j['water'] as String,
      sow: parseYmd(j['sow'] as String) ?? (throw FormatException('demo: bad sow ${j['sow']}')),
      s0Frac: (j['s0_frac'] as num).toDouble(),
      shows: {for (final s in j['shows'] as List) ?TrackerAlertType.tryParse(s as String)},
      days: [
        for (final r in (j['days'] as List).cast<List>())
          DailyWeather(
            date: parseYmd(r[ix('date')] as String)!,
            tmax: v(r, 'T2M_MAX'),
            tmin: v(r, 'T2M_MIN'),
            tdew: v(r, 'T2MDEW'),
            rh2m: v(r, 'RH2M'),
            ws2m: v(r, 'WS2M'),
            rs: v(r, 'ALLSKY_SFC_SW_DWN'),
            precip: v(r, 'PRECTOTCORR'),
            gwetroot: v(r, 'GWETROOT'),
            et0: v(r, 'ET0'),
            heat: v(r, 'T2M_MAX') != null && v(r, 'T2MDEW') != null
                ? dailyHeat(v(r, 'T2M_MAX')!, v(r, 'T2MDEW')!)
                : null,
          ),
      ],
      expectedStates: (exp['q'] as List).cast<String>(),
      expectedHarvestDay: (exp['harvest_day'] as num?)?.toInt(),
      expectedFailed: exp['failed'] == true,
    );
  }
}

/// Loads the bundled demo seasons.
abstract final class DemoSeasons {
  static const assetPath = 'assets/fixtures/demo_seasons.json';

  static List<DemoSeason> parse(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    return [for (final s in j['seasons'] as List) DemoSeason.fromJson((s as Map).cast<String, dynamic>())];
  }

  static Future<List<DemoSeason>> load({AssetBundle? bundle}) async =>
      parse(await (bundle ?? rootBundle).loadString(assetPath));
}

/// Weather source that "delivers" a demo season's days up to the simulated today.
class DemoWeatherSource implements WeatherSource {
  DemoWeatherSource(this.season, this._today);

  final DemoSeason season;
  final DateTime Function() _today;

  @override
  List<DailyWeather> daysFor(Town town) => town != season.town
      ? const []
      : [for (final d in season.days) if (d.date.isBefore(dateOnly(_today()))) d];

  @override
  DateTime? lastSyncedAt(Town town) => _today();

  @override
  Future<SyncResult> sync(Town town, AniBundle bundle, {required DateTime from, required DateTime today}) async =>
      SyncResult(town, SyncStatus.upToDate);
}

/// A running replay of one [DemoSeason] through a [TrackerService] on an
/// in-memory store. Reveal days with [advanceTo] / [advanceBy] / [runToEnd].
class DemoReplay extends ChangeNotifier {
  DemoReplay(this.season, AniBundle bundle) : _today = season.sow {
    if (bundle.meta.town != season.town) {
      throw ArgumentError('bundle is ${bundle.meta.muni}, season is ${season.town.id}');
    }
    service = TrackerService(
      store: FarmStore.memory(),
      weather: DemoWeatherSource(season, () => _today),
      bundleFor: (_) async => bundle,
      clock: () => _today,
    );
  }

  /// Loads [season]'s town bundle with [loader] and starts the replay.
  static Future<DemoReplay> start(DemoSeason season, {BundleLoader? loader, AssetBundle? assets}) async {
    final b = await (loader ?? BundleLoader.instance).load(season.town, bundle: assets);
    final r = DemoReplay(season, b);
    await r._start();
    return r;
  }

  final DemoSeason season;
  late final TrackerService service;
  DateTime _today;
  String? _plantingId;
  int _revealed = 0;

  /// Always true: this is a replay, not the farmer's field.
  bool get isDemo => true;

  /// The simulated "today" (day after the last revealed day).
  DateTime get simulatedToday => _today;

  /// Days revealed so far / available.
  int get dayIndex => _revealed;
  int get totalDays => season.days.length;
  bool get atEnd => _revealed >= totalDays;

  /// The demo planting's view (null before [start]).
  PlantingView? get view => _plantingId == null ? null : service.viewFor(_plantingId!);

  /// Demo alerts, newest first.
  List<AlertRecord> get alerts => service.alerts;

  Future<void> _start() async {
    if (_plantingId != null) return;
    final v = await service.addPlanting(
      town: season.town,
      crop: season.crop,
      plantedOn: season.sow,
      water: season.water,
      s0Frac: season.s0Frac,
      isDemo: true,
      sync: false,
    );
    _plantingId = v.planting.id;
    notifyListeners();
  }

  /// Reveals the first [n] days (clamped) and refreshes the tracker.
  Future<TrackerRefresh> advanceTo(int n) async {
    await _start();
    _revealed = n.clamp(0, totalDays);
    final last = _revealed == 0 ? null : season.days[_revealed - 1].date;
    _today = last == null ? season.sow : DateTime.utc(last.year, last.month, last.day + 1);
    final r = await service.refresh(sync: false);
    notifyListeners();
    return r;
  }

  Future<TrackerRefresh> advanceBy(int days) => advanceTo(_revealed + days);

  /// Reveals day after day until the season closes (or the data ends); if
  /// [confirmHarvest], confirms the harvest as soon as it is ready. Returns
  /// every alert emitted along the way.
  Future<List<AlertRecord>> runToEnd({bool confirmHarvest = true}) async {
    final out = <AlertRecord>[];
    while (!atEnd) {
      out.addAll((await advanceBy(1)).newAlerts);
      final v = view;
      if (v == null || v.isClosed) break;
      if (confirmHarvest && v.canConfirmHarvest) {
        await this.confirmHarvest();
        break;
      }
    }
    return out;
  }

  /// Confirms the demo harvest on the simulated today.
  Future<PlantingView> confirmHarvest() async {
    final v = await service.confirmHarvest(_plantingId!, on: _today);
    notifyListeners();
    return v;
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }
}
