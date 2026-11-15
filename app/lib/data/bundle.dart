/// Typed models for the per-town JSON bundle (pipeline/export_json.py, SCHEMA 2)
/// and a cached loader that reads it from the app's assets.
///
/// Field names follow Dart style; each dartdoc names the JSON / Python key it
/// comes from so planner.py and fsm.py can be ported against these models.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../core/field_machine.dart';

/// The bundle schema this app understands (`SCHEMA` in export_json.py).
const int kBundleSchema = 2;

// ------------------------------------------------------------------ towns

/// The towns that ship with a bundled JSON file.
enum Town {
  guimba('guimba', 'Guimba'),
  munoz('munoz', 'Science City of Muñoz'),
  bongabon('bongabon', 'Bongabon');

  const Town(this.id, this.displayName);

  /// Town id as used in the file name and `meta.muni`.
  final String id;

  /// Human-readable town name.
  final String displayName;

  /// Asset path of this town's bundle.
  String get assetPath => 'assets/data/ani_$id.json';

  /// Looks up a town by [id]; returns null if unknown.
  static Town? tryFromId(String? id) {
    for (final t in Town.values) {
      if (t.id == id) return t;
    }
    return null;
  }
}

// ------------------------------------------------------------------ parsing helpers

Never _bad(String path, String what, Object? got) =>
    throw FormatException('Ani bundle: $path: expected $what, got ${got.runtimeType} ($got)');

Map<String, dynamic> _map(Object? x, String path) {
  if (x is Map) return x.cast<String, dynamic>();
  _bad(path, 'object', x);
}

List<dynamic> _list(Object? x, String path) {
  if (x is List) return x;
  _bad(path, 'array', x);
}

String _str(Object? x, String path) {
  if (x is String) return x;
  _bad(path, 'string', x);
}

String? _strN(Object? x, String path) => x == null ? null : _str(x, path);

bool _bool(Object? x, String path) {
  if (x is bool) return x;
  _bad(path, 'bool', x);
}

double _dbl(Object? x, String path) {
  if (x is num) return x.toDouble();
  _bad(path, 'number', x);
}

double? _dblN(Object? x, String path) => x == null ? null : _dbl(x, path);

int _int(Object? x, String path) {
  if (x is int) return x;
  if (x is num && x == x.roundToDouble()) return x.toInt();
  _bad(path, 'integer', x);
}

int? _intN(Object? x, String path) => x == null ? null : _int(x, path);

List<String> _strList(Object? x, String path) =>
    List.unmodifiable([for (final (i, e) in _list(x, path).indexed) _str(e, '$path[$i]')]);

List<int> _intList(Object? x, String path) =>
    List.unmodifiable([for (final (i, e) in _list(x, path).indexed) _int(e, '$path[$i]')]);

List<double?> _dblNList(Object? x, String path) =>
    List.unmodifiable([for (final (i, e) in _list(x, path).indexed) _dblN(e, '$path[$i]')]);

Map<String, V> _mapOf<V>(Object? x, String path, V Function(String key, Object? v, String path) f) {
  final m = _map(x, path);
  return Map.unmodifiable({for (final e in m.entries) e.key: f(e.key, e.value, '$path.${e.key}')});
}

// ------------------------------------------------------------------ meta

/// Town point (`meta.point`).
class GeoPoint {
  const GeoPoint({required this.lat, required this.lon});

  /// `lat`, degrees north.
  final double lat;

  /// `lon`, degrees east.
  final double lon;

  factory GeoPoint.fromJson(Map<String, dynamic> j, [String p = 'meta.point']) =>
      GeoPoint(lat: _dbl(j['lat'], '$p.lat'), lon: _dbl(j['lon'], '$p.lon'));
}

/// The NASA POWER daily-point request the app makes (`meta.power`, schema 2).
class PowerRequest {
  const PowerRequest({
    required this.endpoint,
    required this.community,
    required this.timeStandard,
    required this.format,
    required this.fillValue,
    required this.parameters,
    required this.rainParameter,
    required this.notes,
  });

  /// `endpoint` URL.
  final String endpoint;

  /// `community` (AG: solar in MJ/m2/day).
  final String community;

  /// `time_standard` (UTC).
  final String timeStandard;

  /// `format` (JSON).
  final String format;

  /// `fill_value`: POWER's missing-value marker (-999).
  final double fillValue;

  /// `parameters` to request.
  final List<String> parameters;

  /// `rain_parameter` (PRECTOTCORR).
  final String rainParameter;

  /// `notes`.
  final String notes;

  factory PowerRequest.fromJson(Map<String, dynamic> j, [String p = 'meta.power']) => PowerRequest(
        endpoint: _str(j['endpoint'], '$p.endpoint'),
        community: _str(j['community'], '$p.community'),
        timeStandard: _str(j['time_standard'], '$p.time_standard'),
        format: _str(j['format'], '$p.format'),
        fillValue: _dbl(j['fill_value'], '$p.fill_value'),
        parameters: _strList(j['parameters'], '$p.parameters'),
        rainParameter: _str(j['rain_parameter'], '$p.rain_parameter'),
        notes: _strN(j['notes'], '$p.notes') ?? '',
      );
}

/// `meta`: schema, generation date, town point, baseline, sources.
class BundleMeta {
  const BundleMeta({
    required this.schema,
    required this.generated,
    required this.muni,
    required this.point,
    required this.power,
    required this.baseline,
    required this.waterScenarios,
    required this.sources,
  });

  /// `schema` (always [kBundleSchema] once parsed).
  final int schema;

  /// `generated`, ISO date string (yyyy-mm-dd).
  final String generated;

  /// `muni`: town id (matches [Town.id]).
  final String muni;

  /// `point`.
  final GeoPoint point;

  /// `power` (schema 2).
  final PowerRequest power;

  /// `baseline`, e.g. "2001-2025".
  final String baseline;

  /// `water_scenarios`: scenario id -> max irrigation events (null = as needed).
  /// Mirrors fsm.WATER. Keys: rainfed, limited_2, limited_4, full.
  final Map<String, int?> waterScenarios;

  /// `sources`.
  final List<String> sources;

  /// [generated] parsed, or null if unparseable.
  DateTime? get generatedDate => DateTime.tryParse(generated);

  /// Matching [Town], or null if not a bundled town.
  Town? get town => Town.tryFromId(muni);

  /// First baseline year (from [baseline]).
  int? get baselineStart => int.tryParse(baseline.split('-').first);

  /// Last baseline year (from [baseline]).
  int? get baselineEnd => int.tryParse(baseline.split('-').last);

  factory BundleMeta.fromJson(Map<String, dynamic> j, [String p = 'meta']) => BundleMeta(
        schema: _int(j['schema'], '$p.schema'),
        generated: _str(j['generated'], '$p.generated'),
        muni: _str(j['muni'], '$p.muni'),
        point: GeoPoint.fromJson(_map(j['point'], '$p.point'), '$p.point'),
        power: PowerRequest.fromJson(_map(j['power'], '$p.power'), '$p.power'),
        baseline: _str(j['baseline'], '$p.baseline'),
        waterScenarios: _mapOf(j['water_scenarios'], '$p.water_scenarios', (_, v, q) => _intN(v, q)),
        sources: _strList(j['sources'], '$p.sources'),
      );
}

// ------------------------------------------------------------------ enso

/// ENSO tags used in the bundle.
abstract final class EnsoTag {
  static const elNino = 'el_nino';
  static const laNina = 'la_nina';
  static const neutral = 'neutral';
}

/// One past dry season (`enso.past[]`).
class EnsoPastSeason {
  const EnsoPastSeason({required this.season, required this.tag});

  /// `season`, e.g. "2015-16" (Nov..Apr).
  final String season;

  /// `tag` by NOAA episode rule: el_nino / la_nina / neutral.
  final String tag;

  bool get isElNino => tag == EnsoTag.elNino;

  factory EnsoPastSeason.fromJson(Map<String, dynamic> j, String p) =>
      EnsoPastSeason(season: _str(j['season'], '$p.season'), tag: _str(j['tag'], '$p.tag'));
}

/// `enso`: the coming dry season and its tag (JAS rule), plus past seasons.
class Enso {
  const Enso({
    required this.comingSeason,
    required this.tag,
    required this.jas,
    required this.rule,
    required this.past,
  });

  /// `coming_season`, e.g. "2026-27".
  final String comingSeason;

  /// `tag` (JAS rule): el_nino / la_nina / neutral.
  final String tag;

  /// `jas`: Jul-Sep RONI value.
  final double? jas;

  /// `rule` description.
  final String rule;

  /// `past` seasons (episode rule, "pending" excluded).
  final List<EnsoPastSeason> past;

  /// True when the coming season is El Nino (planner "El Nino mode").
  bool get isElNino => tag == EnsoTag.elNino;

  factory Enso.fromJson(Map<String, dynamic> j, [String p = 'enso']) => Enso(
        comingSeason: _str(j['coming_season'], '$p.coming_season'),
        tag: _str(j['tag'], '$p.tag'),
        jas: _dblN(j['jas'], '$p.jas'),
        rule: _strN(j['rule'], '$p.rule') ?? '',
        past: List.unmodifiable([
          for (final (i, e) in _list(j['past'], '$p.past').indexed)
            EnsoPastSeason.fromJson(_map(e, '$p.past[$i]'), '$p.past[$i]'),
        ]),
      );
}

// ------------------------------------------------------------------ dryness

/// Dryness labels used in `dryness.latest.label`.
abstract final class DrynessLabel {
  static const normal = 'normal';
  static const bantay = 'bantay';
  static const delikado = 'delikado';
}

/// `dryness.thresholds`: D cut-offs with hysteresis.
class DrynessThresholds {
  const DrynessThresholds({
    required this.bantay,
    required this.delikado,
    required this.downBantay,
    required this.downNormal,
    required this.calmDekads,
  });

  /// `bantay`: D at/above which the label goes up to Bantay.
  final double bantay;

  /// `delikado`: D at/above which the label goes up to Delikado.
  final double delikado;

  /// `down_bantay`: D below which Delikado steps down to Bantay.
  final double downBantay;

  /// `down_normal`: D below which Bantay steps down to Normal.
  final double downNormal;

  /// `calm_dekads`: consecutive calm dekads required before stepping down.
  final int calmDekads;

  factory DrynessThresholds.fromJson(Map<String, dynamic> j, [String p = 'dryness.thresholds']) =>
      DrynessThresholds(
        bantay: _dbl(j['bantay'], '$p.bantay'),
        delikado: _dbl(j['delikado'], '$p.delikado'),
        downBantay: _dbl(j['down_bantay'], '$p.down_bantay'),
        downNormal: _dbl(j['down_normal'], '$p.down_normal'),
        calmDekads: _int(j['calm_dekads'], '$p.calm_dekads'),
      );
}

/// `dryness.latest`: the most recent scored month.
class DrynessLatest {
  const DrynessLatest({required this.month, required this.d, required this.label, required this.rank});

  /// `month`, "yyyy-mm".
  final String month;

  /// `D`: dryness index.
  final double d;

  /// `label`: normal / bantay / delikado.
  final String label;

  /// `rank`: plain rank sentence (Filipino), or null.
  final String? rank;

  factory DrynessLatest.fromJson(Map<String, dynamic> j, [String p = 'dryness.latest']) => DrynessLatest(
        month: _str(j['month'], '$p.month'),
        d: _dbl(j['D'], '$p.D'),
        label: _str(j['label'], '$p.label'),
        rank: _strN(j['rank'], '$p.rank'),
      );
}

/// One entry of `dryness.monthly`: `["yyyy-mm", D]`.
class DrynessPoint {
  const DrynessPoint({required this.month, required this.d});

  /// "yyyy-mm".
  final String month;

  /// D for that month.
  final double d;

  int get year => int.parse(month.substring(0, 4));
  int get monthOfYear => int.parse(month.substring(5, 7));

  factory DrynessPoint.fromJson(Object? x, String p) {
    final l = _list(x, p);
    if (l.length != 2) _bad(p, '[month, D]', x);
    return DrynessPoint(month: _str(l[0], '$p[0]'), d: _dbl(l[1], '$p[1]'));
  }
}

/// `dryness.reference["m"]` (schema 2): baseline for one calendar month,
/// arrays aligned by [years]. null entries = month incomplete.
class DrynessReferenceMonth {
  const DrynessReferenceMonth({required this.years, required this.bal1, required this.bal3, required this.gwet});

  /// `years`.
  final List<int> years;

  /// `bal1`: 1-month P - ET0 (mm).
  final List<double?> bal1;

  /// `bal3`: 3-month accumulated P - ET0 ending in this month (mm).
  final List<double?> bal3;

  /// `gwet`: monthly mean GWETROOT (0..1).
  final List<double?> gwet;

  factory DrynessReferenceMonth.fromJson(Map<String, dynamic> j, String p) {
    final r = DrynessReferenceMonth(
      years: _intList(j['years'], '$p.years'),
      bal1: _dblNList(j['bal1'], '$p.bal1'),
      bal3: _dblNList(j['bal3'], '$p.bal3'),
      gwet: _dblNList(j['gwet'], '$p.gwet'),
    );
    final n = r.years.length;
    if (r.bal1.length != n || r.bal3.length != n || r.gwet.length != n) {
      throw FormatException('Ani bundle: $p: years/bal1/bal3/gwet lengths differ');
    }
    return r;
  }
}

/// `dryness`: latest D, thresholds, monthly series and the schema-2 reference.
class Dryness {
  const Dryness({required this.latest, required this.thresholds, required this.monthly, required this.reference});

  /// `latest`.
  final DrynessLatest latest;

  /// `thresholds`.
  final DrynessThresholds thresholds;

  /// `monthly`: D series, oldest first.
  final List<DrynessPoint> monthly;

  /// `reference`: calendar month 1..12 -> baseline.
  final Map<int, DrynessReferenceMonth> reference;

  factory Dryness.fromJson(Map<String, dynamic> j, [String p = 'dryness']) {
    final ref = _map(j['reference'], '$p.reference');
    final reference = <int, DrynessReferenceMonth>{};
    for (final e in ref.entries) {
      final m = int.tryParse(e.key);
      if (m == null || m < 1 || m > 12) _bad('$p.reference', 'month keys "1".."12"', e.key);
      reference[m] = DrynessReferenceMonth.fromJson(_map(e.value, '$p.reference.${e.key}'), '$p.reference.${e.key}');
    }
    return Dryness(
      latest: DrynessLatest.fromJson(_map(j['latest'], '$p.latest'), '$p.latest'),
      thresholds: DrynessThresholds.fromJson(_map(j['thresholds'], '$p.thresholds'), '$p.thresholds'),
      monthly: List.unmodifiable([
        for (final (i, e) in _list(j['monthly'], '$p.monthly').indexed) DrynessPoint.fromJson(e, '$p.monthly[$i]'),
      ]),
      reference: Map.unmodifiable(reference),
    );
  }
}

// ------------------------------------------------------------------ crops

/// Crop ids used as keys in `crops`, `risk.*` and `tracker`.
abstract final class CropId {
  static const rice = 'rice';
  static const onion = 'onion';
  static const mungbean = 'mungbean';
  static const maize = 'maize';
  static const sweetPotato = 'sweet_potato';
  static const all = [rice, onion, mungbean, maize, sweetPotato];
}

/// `crops[id]`: names, family, flags, duration, sowing window.
class CropInfo {
  const CropInfo({
    required this.id,
    required this.name,
    required this.family,
    required this.legume,
    required this.smallMarket,
    required this.durationDays,
    required this.sowWindowStart,
    required this.sowWindowEnd,
  });

  /// Crop id (the map key).
  final String id;

  /// `name`: local name (planner.NAME), e.g. Palay.
  final String name;

  /// `family`: botanical family (planner.FAMILY), used for rotation.
  final String family;

  /// `legume` (planner.LEGUME).
  final bool legume;

  /// `small_market` (planner.SMALL_MARKET).
  final bool smallMarket;

  /// `duration_days`.
  final int durationDays;

  /// `sow_window_days_after_nov1[0]`.
  final int sowWindowStart;

  /// `sow_window_days_after_nov1[1]`.
  final int sowWindowEnd;

  factory CropInfo.fromJson(String id, Map<String, dynamic> j, String p) {
    final w = _intList(j['sow_window_days_after_nov1'], '$p.sow_window_days_after_nov1');
    if (w.length != 2) _bad('$p.sow_window_days_after_nov1', '[start, end]', w);
    return CropInfo(
      id: id,
      name: _str(j['name'], '$p.name'),
      family: _str(j['family'], '$p.family'),
      legume: _bool(j['legume'], '$p.legume'),
      smallMarket: _bool(j['small_market'], '$p.small_market'),
      durationDays: _int(j['duration_days'], '$p.duration_days'),
      sowWindowStart: w[0],
      sowWindowEnd: w[1],
    );
  }
}

// ------------------------------------------------------------------ risk

/// Which season set a risk number refers to: `en` (El Nino) or `other`.
enum RiskMode {
  elNino('en'),
  other('other');

  const RiskMode(this.key);

  /// The infix used in JSON keys (`fail_<key>_x`, ...).
  final String key;

  static RiskMode forEnso(bool elNino) => elNino ? RiskMode.elNino : RiskMode.other;
}

/// The risk numbers for one crop x water x [RiskMode] (keys `*_<mode>_*`).
class RiskModeStats {
  const RiskModeStats({
    required this.failX,
    required this.failN,
    required this.failLo,
    required this.failHi,
    required this.mcFailP10,
    required this.mcFailP50,
    required this.mcFailP90,
    required this.mcIrrP50,
    required this.mcNetP10,
    required this.mcNetP50,
    required this.mcNetP90,
  });

  /// `fail_<m>_x`: failed seasons in the historical replay.
  final int failX;

  /// `fail_<m>_n`: seasons replayed.
  final int failN;

  /// `fail_<m>_lo`: Wilson lower bound of the failure rate.
  final double failLo;

  /// `fail_<m>_hi`: Wilson upper bound of the failure rate.
  final double failHi;

  /// `mc_fail_<m>_p10`: Monte Carlo failure share, 10th pct.
  final double mcFailP10;

  /// `mc_fail_<m>_p50`.
  final double mcFailP50;

  /// `mc_fail_<m>_p90`.
  final double mcFailP90;

  /// `mc_irr_<m>_p50`: median irrigation applied (mm).
  final double mcIrrP50;

  /// `mc_net_<m>_p10`: net income, PHP/ha, 10th pct.
  final double mcNetP10;

  /// `mc_net_<m>_p50`.
  final double mcNetP50;

  /// `mc_net_<m>_p90`.
  final double mcNetP90;

  /// failX / max(failN, 1), as planner.py computes it.
  double get failRate => failX / (failN < 1 ? 1 : failN);

  factory RiskModeStats.fromJson(Map<String, dynamic> j, String m, String p) {
    String k(String pre, String post) => '${pre}_${m}_$post';
    return RiskModeStats(
      failX: _int(j[k('fail', 'x')], '$p.${k('fail', 'x')}'),
      failN: _int(j[k('fail', 'n')], '$p.${k('fail', 'n')}'),
      failLo: _dbl(j[k('fail', 'lo')], '$p.${k('fail', 'lo')}'),
      failHi: _dbl(j[k('fail', 'hi')], '$p.${k('fail', 'hi')}'),
      mcFailP10: _dbl(j[k('mc_fail', 'p10')], '$p.${k('mc_fail', 'p10')}'),
      mcFailP50: _dbl(j[k('mc_fail', 'p50')], '$p.${k('mc_fail', 'p50')}'),
      mcFailP90: _dbl(j[k('mc_fail', 'p90')], '$p.${k('mc_fail', 'p90')}'),
      mcIrrP50: _dbl(j[k('mc_irr', 'p50')], '$p.${k('mc_irr', 'p50')}'),
      mcNetP10: _dbl(j[k('mc_net', 'p10')], '$p.${k('mc_net', 'p10')}'),
      mcNetP50: _dbl(j[k('mc_net', 'p50')], '$p.${k('mc_net', 'p50')}'),
      mcNetP90: _dbl(j[k('mc_net', 'p90')], '$p.${k('mc_net', 'p90')}'),
    );
  }
}

/// `risk[water][crop]`: the card numbers for one water scenario x crop.
class RiskRow {
  const RiskRow({
    required this.water,
    required this.crop,
    required this.elNino,
    required this.other,
    required this.heatShare,
  });

  /// Water scenario id (outer key).
  final String water;

  /// Crop id (inner key).
  final String crop;

  /// The `*_en_*` numbers (El Nino seasons).
  final RiskModeStats elNino;

  /// The `*_other_*` numbers (all other seasons).
  final RiskModeStats other;

  /// `heat_share`: share of seasons with >= 1 heat day at flowering.
  final double heatShare;

  RiskModeStats forMode(RiskMode m) => m == RiskMode.elNino ? elNino : other;

  factory RiskRow.fromJson(String water, String crop, Map<String, dynamic> j, String p) => RiskRow(
        water: water,
        crop: crop,
        elNino: RiskModeStats.fromJson(j, RiskMode.elNino.key, p),
        other: RiskModeStats.fromJson(j, RiskMode.other.key, p),
        heatShare: _dblN(j['heat_share'], '$p.heat_share') ?? 0.0,
      );
}

/// Water scenario ids (keys of `risk`, `meta.water_scenarios`, `planner.water_label`).
abstract final class WaterScenario {
  static const rainfed = 'rainfed';
  static const limited2 = 'limited_2';
  static const limited4 = 'limited_4';
  static const full = 'full';
  static const all = [rainfed, limited2, limited4, full];
}

/// `risk`: water scenario -> crop -> [RiskRow].
class RiskTable {
  const RiskTable(this.byWater);

  /// water id -> crop id -> row.
  final Map<String, Map<String, RiskRow>> byWater;

  /// Water scenarios present, in file order.
  Iterable<String> get waters => byWater.keys;

  /// Row for [water] x [crop], or null.
  RiskRow? row(String water, String crop) => byWater[water]?[crop];

  factory RiskTable.fromJson(Map<String, dynamic> j, [String p = 'risk']) => RiskTable(
        _mapOf(j, p, (w, v, q) => _mapOf(v, q, (c, r, qq) => RiskRow.fromJson(w, c, _map(r, qq), qq))),
      );
}

// ------------------------------------------------------------------ planner

/// `planner`: the constants M_P (planner.py) uses.
class PlannerConfig {
  const PlannerConfig({
    required this.thetaF,
    required this.thetaH,
    required this.beta,
    required this.rankedShare,
    required this.criteria,
    required this.benefit,
    required this.waterLabel,
  });

  /// `theta_f` (THETA_F): failure-rate gate.
  final double thetaF;

  /// `theta_h` (THETA_H): heat-share gate.
  final double thetaH;

  /// `beta` (BETA): El Nino weight multiplier for water and risk.
  final double beta;

  /// `ranked_share` (RANKED_SHARE): weight share for the farmer's ranked priorities.
  final double rankedShare;

  /// `criteria` (CRITERIA), in order: income, risk, water, soil, pest.
  final List<String> criteria;

  /// `benefit` (BENEFIT): criterion -> true if higher is better.
  final Map<String, bool> benefit;

  /// `water_label` (WATER_LABEL): water id -> Filipino phrase.
  final Map<String, String> waterLabel;

  factory PlannerConfig.fromJson(Map<String, dynamic> j, [String p = 'planner']) => PlannerConfig(
        thetaF: _dbl(j['theta_f'], '$p.theta_f'),
        thetaH: _dbl(j['theta_h'], '$p.theta_h'),
        beta: _dbl(j['beta'], '$p.beta'),
        rankedShare: _dbl(j['ranked_share'], '$p.ranked_share'),
        criteria: _strList(j['criteria'], '$p.criteria'),
        benefit: _mapOf(j['benefit'], '$p.benefit', (_, v, q) => _bool(v, q)),
        waterLabel: _mapOf(j['water_label'], '$p.water_label', (_, v, q) => _str(v, q)),
      );
}

// ------------------------------------------------------------------ tracker

/// `tracker[crop]`: field-machine parameters (fsm.Params) for this town.
class TrackerParams {
  const TrackerParams({
    required this.crop,
    required this.taw,
    required this.p,
    required this.kcIni,
    required this.kcMid,
    required this.kcEnd,
    required this.tBase,
    required this.gMat,
    required this.fE,
    required this.fV,
    required this.fR,
    required this.tCrit,
    required this.rotP98,
    required this.ksFail,
    required this.kFail,
    required this.dPrep,
    required this.sensitive,
    required this.tUp,
  });

  /// Crop id (`crop`).
  final String crop;

  /// `taw`: total available water (mm).
  final double taw;

  /// `p`: depletion fraction before stress (FAO-56).
  final double p;

  /// `kc_ini`: crop coefficient, initial stage.
  final double kcIni;

  /// `kc_mid`: crop coefficient, mid stage.
  final double kcMid;

  /// `kc_end`: crop coefficient, end stage.
  final double kcEnd;

  /// `t_base`: base temperature for GDD (C).
  final double tBase;

  /// `g_mat`: GDD to maturity.
  final double gMat;

  /// `f_e`: GDD fraction ending Estab.
  final double fE;

  /// `f_v`: GDD fraction ending Veg.
  final double fV;

  /// `f_r`: GDD fraction ending Repro.
  final double fR;

  /// `t_crit`: heat-damage Tmax in Repro (C); null = no heat check.
  final double? tCrit;

  /// `rot_p98`: 98th pct of 3-day rain (mm), the rot/flood trigger.
  final double? rotP98;

  /// `ks_fail` (KS_FAIL): severe-stress Ks threshold.
  final double ksFail;

  /// `k_fail` (K_FAIL): consecutive severe-stress days that fail the crop.
  final int kFail;

  /// `d_prep` (D_PREP): days in Prep before Estab.
  final int dPrep;

  /// `sensitive`: stages where stress counts (e.g. Veg, Repro).
  final List<String> sensitive;

  /// `t_up`: upper GDD cut-off temperature (C); null = none.
  final double? tUp;

  factory TrackerParams.fromJson(String crop, Map<String, dynamic> j, String p) => TrackerParams(
        crop: crop,
        taw: _dbl(j['taw'], '$p.taw'),
        p: _dbl(j['p'], '$p.p'),
        kcIni: _dbl(j['kc_ini'], '$p.kc_ini'),
        kcMid: _dbl(j['kc_mid'], '$p.kc_mid'),
        kcEnd: _dbl(j['kc_end'], '$p.kc_end'),
        tBase: _dbl(j['t_base'], '$p.t_base'),
        gMat: _dbl(j['g_mat'], '$p.g_mat'),
        fE: _dbl(j['f_e'], '$p.f_e'),
        fV: _dbl(j['f_v'], '$p.f_v'),
        fR: _dbl(j['f_r'], '$p.f_r'),
        tCrit: _dblN(j['t_crit'], '$p.t_crit'),
        rotP98: _dblN(j['rot_p98'], '$p.rot_p98'),
        ksFail: _dbl(j['ks_fail'], '$p.ks_fail'),
        kFail: _int(j['k_fail'], '$p.k_fail'),
        dPrep: _int(j['d_prep'], '$p.d_prep'),
        sensitive: _strList(j['sensitive'], '$p.sensitive'),
        tUp: _dblN(j['t_up'], '$p.t_up'),
      );
}

/// `tracker`: per-crop [TrackerParams] plus `s0_frac_by_doy` (schema 2).
class Tracker {
  const Tracker({required this.crops, required this.s0FracByDoy});

  /// crop id -> params.
  final Map<String, TrackerParams> crops;

  /// `s0_frac_by_doy`: 366 values, index = day-of-year - 1 in leap-year
  /// numbering (Feb 29 = 59). Median starting soil-water fraction.
  final List<double?> s0FracByDoy;

  /// Leap-year day-of-year index (0..365) for [date].
  static int doyIndex(DateTime date) {
    const cum = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335];
    return cum[date.month - 1] + date.day - 1;
  }

  /// Starting soil-water fraction for [date], or null if missing.
  double? s0FracFor(DateTime date) {
    final i = doyIndex(date);
    return i < s0FracByDoy.length ? s0FracByDoy[i] : null;
  }

  factory Tracker.fromJson(Map<String, dynamic> j, [String p = 'tracker']) {
    const s0Key = 's0_frac_by_doy';
    return Tracker(
      crops: Map.unmodifiable({
        for (final e in j.entries)
          if (e.key != s0Key) e.key: TrackerParams.fromJson(e.key, _map(e.value, '$p.${e.key}'), '$p.${e.key}'),
      }),
      s0FracByDoy: j[s0Key] == null ? const [] : _dblNList(j[s0Key], '$p.$s0Key'),
    );
  }
}

/// Bridge from the typed `tracker[crop]` block to the field machine's [Params].
extension TrackerParamsFieldMachine on TrackerParams {
  /// fsm.Params for this crop under water scenario [water] (see [kWater]).
  Params toFieldParams(String water) {
    final w = kWater[water];
    if (w == null) throw ArgumentError.value(water, 'water', 'unknown water scenario');
    return Params(
      crop: crop,
      taw: taw,
      p: p,
      kcIni: kcIni,
      kcMid: kcMid,
      kcEnd: kcEnd,
      tBase: tBase,
      gMat: gMat,
      fE: fE,
      fV: fV,
      fR: fR,
      tCrit: tCrit,
      tUp: tUp,
      irrigated: w.irrigated,
      maxIrr: w.maxIrr,
      rotP98: rotP98,
      dPrep: dPrep,
      ksFail: ksFail,
      kFail: kFail,
      sensitive: sensitive,
    );
  }
}

// ------------------------------------------------------------------ heat

/// One PAGASA heat-index category (`heat.index_categories_c[]`).
class HeatCategory {
  const HeatCategory({required this.from, required this.to, required this.label});

  /// `from`: lower bound, C (inclusive).
  final double from;

  /// `to`: upper bound, C (inclusive); null = open-ended.
  final double? to;

  /// `label`: caution / extreme caution / danger / extreme danger.
  final String label;

  factory HeatCategory.fromJson(Map<String, dynamic> j, String p) => HeatCategory(
        from: _dbl(j['from'], '$p.from'),
        to: _dblN(j['to'], '$p.to'),
        label: _str(j['label'], '$p.label'),
      );
}

/// `heat`: PAGASA heat-index categories for the safety channel.
class HeatInfo {
  const HeatInfo({required this.indexCategoriesC});

  /// `index_categories_c`, ascending.
  final List<HeatCategory> indexCategoriesC;

  /// Highest category whose `from` <= [heatIndexC], or null if below all.
  HeatCategory? categoryFor(double heatIndexC) {
    HeatCategory? hit;
    for (final c in indexCategoriesC) {
      if (heatIndexC >= c.from) hit = c;
    }
    return hit;
  }

  factory HeatInfo.fromJson(Map<String, dynamic> j, [String p = 'heat']) => HeatInfo(
        indexCategoriesC: List.unmodifiable([
          for (final (i, e) in _list(j['index_categories_c'], '$p.index_categories_c').indexed)
            HeatCategory.fromJson(_map(e, '$p.index_categories_c[$i]'), '$p.index_categories_c[$i]'),
        ]),
      );
}

// ------------------------------------------------------------------ root

/// One town's bundle (`ani_<town>.json`).
class AniBundle {
  const AniBundle({
    required this.meta,
    required this.enso,
    required this.dryness,
    required this.crops,
    required this.risk,
    required this.planner,
    required this.tracker,
    required this.heat,
    required this.raw,
  });

  final BundleMeta meta;
  final Enso enso;
  final Dryness dryness;

  /// `crops`: crop id -> info, in file order.
  final Map<String, CropInfo> crops;
  final RiskTable risk;
  final PlannerConfig planner;
  final Tracker tracker;
  final HeatInfo heat;

  /// The decoded JSON as-is, for anything not yet modelled.
  final Map<String, dynamic> raw;

  /// Crop ids in file order.
  List<String> get cropIds => crops.keys.toList(growable: false);

  /// Parses a decoded bundle. Throws [FormatException] if `meta.schema` is
  /// not [kBundleSchema] or any field has the wrong shape.
  factory AniBundle.fromJson(Map<String, dynamic> j) {
    final meta = _map(j['meta'], 'meta');
    final schema = meta['schema'];
    if (schema != kBundleSchema) {
      throw FormatException(
          'Ani bundle: unsupported schema $schema (this app reads schema $kBundleSchema); '
          're-export with pipeline/export_json.py');
    }
    return AniBundle(
      meta: BundleMeta.fromJson(meta),
      enso: Enso.fromJson(_map(j['enso'], 'enso')),
      dryness: Dryness.fromJson(_map(j['dryness'], 'dryness')),
      crops: _mapOf(j['crops'], 'crops', (id, v, p) => CropInfo.fromJson(id, _map(v, p), p)),
      risk: RiskTable.fromJson(_map(j['risk'], 'risk')),
      planner: PlannerConfig.fromJson(_map(j['planner'], 'planner')),
      tracker: Tracker.fromJson(_map(j['tracker'], 'tracker')),
      heat: HeatInfo.fromJson(_map(j['heat'], 'heat')),
      raw: j,
    );
  }

  /// Decodes and parses a JSON string.
  factory AniBundle.fromJsonString(String s) {
    final decoded = jsonDecode(s);
    if (decoded is! Map) throw const FormatException('Ani bundle: top level is not an object');
    return AniBundle.fromJson(decoded.cast<String, dynamic>());
  }
}

// ------------------------------------------------------------------ loader

/// Loads town bundles from assets, caching one parse per (asset bundle, town).
class BundleLoader {
  BundleLoader();

  /// Shared app-wide instance.
  static final BundleLoader instance = BundleLoader();

  final Map<(AssetBundle, Town), Future<AniBundle>> _cache = {};

  /// Loads [town]'s bundle from [bundle] (default [rootBundle]).
  Future<AniBundle> load(Town town, {AssetBundle? bundle}) {
    final b = bundle ?? rootBundle;
    final key = (b, town);
    return _cache.putIfAbsent(key, () async {
      try {
        final s = await b.loadString(town.assetPath, cache: false);
        return AniBundle.fromJsonString(s);
      } catch (_) {
        _cache.remove(key);
        rethrow;
      }
    });
  }

  /// Drops all cached bundles.
  void clear() => _cache.clear();
}
