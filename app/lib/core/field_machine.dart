/// Field machine M_F (spec 5.4): a line-for-line pure-Dart port of
/// `pipeline/fsm.py` (Params, FieldMachine) and the parts of
/// `pipeline/soil_water.py` it uses (F5 bucket step, F6 p adjustment, the
/// refill rule) and F7 (GDD).
///
/// One instance = one crop on one field. Call [FieldMachine.sow], then
/// [FieldMachine.tick] once per day.
///
/// Step order on each tick (fixed, so the Python and app versions agree):
///   1. G += GDD(x); d += 1
///   2. Kc from the stage (FAO-56 curve in thermal time)
///   3. one F5 step of S (irrigation first if the water source allows); Ks
///   4. risk guards update counters and emit Mealy alerts (never change the stage)
///   5. transition guards, lowest priority number wins (Eq. 4.8-4.15):
///        1  Estab..Mature  kappa_sev >= K_FAIL          -> Failed    water_fail
///        3  Prep           d >= D_PREP                  -> Estab
///        4  Estab          G >= f_e G_mat               -> Veg
///        5  Veg            G >= f_v G_mat               -> Repro
///        6  Repro          G >= f_r G_mat               -> Mature
///        7  Mature         G >= G_mat and (confirm or simulating) -> Harvest  harvest_ready
///        8  Harvest        tick                         -> Fallow    outcome
///        9  Failed         tick                         -> Fallow    outcome (failed)
///       10  any            otherwise                    -> same
///      (guard 2, Fallow -> Prep, is the sow event.)
///
/// Pure Dart: no Flutter imports, so it runs in isolates and plain `dart test`.
library;

import 'dart:math' as math;

// ------------------------------------------------------------------ constants

/// `D_PREP`: days in Prep before Estab (the sow date is the day the crop is in the ground).
const int kDPrep = 0;

/// `KS_FAIL`: severe stress means Ks below this.
const double kKsFail = 0.5;

/// `K_FAIL`: consecutive severe-stress days in a sensitive stage that fail the crop.
const int kKFail = 10;

/// `SENSITIVE`: stages where stress counts.
const List<String> kSensitive = ['Veg', 'Repro'];

/// `WATER`: the farmer's answer to "how many times can you irrigate this dry
/// season?" -> (irrigated, max irrigation events; null = as needed).
const Map<String, ({bool irrigated, int? maxIrr})> kWater = {
  'rainfed': (irrigated: false, maxIrr: 0),
  'limited_2': (irrigated: true, maxIrr: 2),
  'limited_4': (irrigated: true, maxIrr: 4),
  'full': (irrigated: true, maxIrr: null),
};

// ------------------------------------------------------------------ states and outputs

/// `Q`: the states of M_F. [label] is the Python state name.
enum FieldState {
  fallow('Fallow'),
  prep('Prep'),
  estab('Estab'),
  veg('Veg'),
  repro('Repro'),
  mature('Mature'),
  harvest('Harvest'),
  failed('Failed');

  const FieldState(this.label);

  /// State name as in fsm.py `STATES`.
  final String label;

  /// `GROWING`: Estab, Veg, Repro, Mature.
  bool get isGrowing => this == estab || this == veg || this == repro || this == mature;

  /// Harvest or Failed: the one-tick end states before Fallow.
  bool get isEnd => this == harvest || this == failed;

  /// Looks up a state by its Python [label]; throws if unknown.
  static FieldState fromLabel(String label) =>
      FieldState.values.firstWhere((s) => s.label == label, orElse: () => throw ArgumentError.value(label, 'label'));
}

/// Mealy output names emitted by [FieldMachine.tick].
abstract final class FieldAlert {
  static const waterStress = 'water_stress';
  static const waterFail = 'water_fail';
  static const heatRisk = 'heat_risk';
  static const rotRisk = 'rot_risk';
  static const harvestReady = 'harvest_ready';
  static const outcome = 'outcome';
}

/// One trace entry `(day, from, to, guard)`, for "Bakit?".
class FieldTransition {
  const FieldTransition(this.day, this.from, this.to, this.guard);

  /// Machine day counter when the transition fired.
  final int day;
  final FieldState from;
  final FieldState to;

  /// Guard text, e.g. `g4 G >= f_e G_mat`.
  final String guard;

  /// Same shape as the Python tuple / fixture row: `[day, from, to, guard]`.
  List<Object> toList() => [day, from.label, to.label, guard];

  @override
  bool operator ==(Object other) =>
      other is FieldTransition && other.day == day && other.from == from && other.to == to && other.guard == guard;

  @override
  int get hashCode => Object.hash(day, from, to, guard);

  @override
  String toString() => 'FieldTransition($day, ${from.label} -> ${to.label}, $guard)';
}

// ------------------------------------------------------------------ F7

/// Daily growing degree days (McMaster & Wilhelm style, with optional upper cap).
double gdd(double tmax, double tmin, double tBase, [double? tUp]) {
  final hi = tUp == null ? tmax : math.min(tmax, tUp);
  return math.max(0.0, (hi + math.max(tmin, tBase)) / 2.0 - tBase);
}

// ------------------------------------------------------------------ F5 / F6 (soil_water.py)

double _clip(double x, double lo, double hi) => math.min(math.max(x, lo), hi);

/// FAO-56 depletion fraction adjusted for evaporative demand, bounded 0.1-0.8.
double pAdjusted(double p, double etc) => _clip(p + 0.04 * (5.0 - etc), 0.1, 0.8);

/// Ks: 1 above the readily available water, linear to 0 at wilting point.
double stressCoefficient(double s, double taw, double p) {
  final thr = (1.0 - p) * taw;
  final ks = s >= thr ? 1.0 : (thr > 0 ? s / thr : 0.0);
  return _clip(ks, 0.0, 1.0);
}

/// Result of one [bucketStep]: new S and the amounts over the step.
typedef BucketStep = ({double s, double eta, double dp, double ks});

/// One Euler step of F5. Rates in mm/day, dt in days.
/// Returns (S_new, ETa_mm, DP_mm, Ks) where the amounts are over the step.
BucketStep bucketStep(double s, double p, double i, double et0, double kc, double taw, double pDep,
    [double dt = 1.0]) {
  final etc = kc * et0;
  // irrigation is applied at the start of the day, so it counts towards that day's Ks
  final sMorning = math.min(s + dt * i, taw);
  final ks = stressCoefficient(sMorning, taw, pAdjusted(pDep, etc));
  var eta = ks * etc * dt;
  final sStar = s + dt * (p + i) - eta;
  final dp = math.max(0.0, sStar - taw);
  eta = eta + math.min(0.0, sStar); // cannot use water that is not there
  final sNew = _clip(sStar, 0.0, taw);
  return (s: sNew, eta: eta, dp: dp, ks: ks);
}

/// Upland crop with a water source: refill to field capacity once Ks would drop below 1.
double refillWhenStressed(double s, double taw, double pAdj) => s < (1.0 - pAdj) * taw ? taw - s : 0.0;

// ------------------------------------------------------------------ Params

/// fsm.Params: everything M_F needs for one crop on one field.
class Params {
  const Params({
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
    this.tCrit,
    this.tUp,
    this.irrigated = false,
    this.maxIrr,
    this.rotP98,
    this.dPrep = kDPrep,
    this.ksFail = kKsFail,
    this.kFail = kKFail,
    this.sensitive = kSensitive,
  });

  final String crop;

  /// Total available water in the root zone (mm).
  final double taw;

  /// FAO-56 depletion fraction before stress.
  final double p;
  final double kcIni;
  final double kcMid;
  final double kcEnd;
  final double tBase;

  /// GDD to maturity at this site.
  final double gMat;

  /// Cumulative stage fractions (ini, +dev, +mid).
  final double fE;
  final double fV;
  final double fR;

  /// Heat-damage Tmax in Repro (C); null = no heat guard.
  final double? tCrit;

  /// Upper GDD cut-off (C); null = none.
  final double? tUp;
  final bool irrigated;

  /// Cap on irrigation events per season (null = as needed).
  final int? maxIrr;

  /// 98th percentile of 3-day rain (mm), onion rot trigger.
  final double? rotP98;
  final int dPrep;
  final double ksFail;
  final int kFail;

  /// Stages where stress counts (fsm.SENSITIVE; bundle `sensitive`).
  final List<String> sensitive;

  /// From a raw `asdict(Params)` map (the fixture's `params`).
  factory Params.fromJson(Map<String, dynamic> j) => Params(
        crop: j['crop'] as String,
        taw: _d(j['taw']),
        p: _d(j['p']),
        kcIni: _d(j['kc_ini']),
        kcMid: _d(j['kc_mid']),
        kcEnd: _d(j['kc_end']),
        tBase: _d(j['t_base']),
        gMat: _d(j['g_mat']),
        fE: _d(j['f_e']),
        fV: _d(j['f_v']),
        fR: _d(j['f_r']),
        tCrit: _dN(j['t_crit']),
        tUp: _dN(j['t_up']),
        irrigated: (j['irrigated'] as bool?) ?? false,
        maxIrr: (j['max_irr'] as num?)?.toInt(),
        rotP98: _dN(j['rot_p98']),
        dPrep: (j['d_prep'] as num?)?.toInt() ?? kDPrep,
        ksFail: _dN(j['ks_fail']) ?? kKsFail,
        kFail: (j['k_fail'] as num?)?.toInt() ?? kKFail,
        sensitive: (j['sensitive'] as List?)?.cast<String>() ?? kSensitive,
      );

  /// From the bundle's raw `tracker[crop]` block plus a water scenario id
  /// (`rainfed`, `limited_2`, `limited_4`, `full`; see [kWater]).
  /// The tracker block has no `irrigated` / `max_irr`: the farmer picks water.
  factory Params.fromTracker(String crop, Map<String, dynamic> tracker, String water) {
    final w = kWater[water];
    if (w == null) throw ArgumentError.value(water, 'water', 'unknown water scenario');
    return Params.fromJson({...tracker, 'crop': crop, 'irrigated': w.irrigated, 'max_irr': w.maxIrr});
  }

  Params copyWith({bool? irrigated, int? maxIrr, bool clearMaxIrr = false}) => Params(
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
        irrigated: irrigated ?? this.irrigated,
        maxIrr: clearMaxIrr ? null : (maxIrr ?? this.maxIrr),
        rotP98: rotP98,
        dPrep: dPrep,
        ksFail: ksFail,
        kFail: kFail,
        sensitive: sensitive,
      );

  static double _d(Object? x) => (x as num).toDouble();
  static double? _dN(Object? x) => x == null ? null : (x as num).toDouble();
}

// ------------------------------------------------------------------ outcome

/// Python `round(x, 1)` (correctly rounded, ties to even).
double _round1(double x) {
  // Only quarters are exact binary ties at one decimal (n.25, n.75).
  final q = x * 4;
  if (q == q.roundToDouble() && q.toInt().isOdd) {
    final t = x * 10; // exact tie k + 0.5
    final lo = t.floorToDouble();
    final r = lo.toInt().isEven ? lo : lo + 1;
    return r / 10;
  }
  return double.parse(x.toStringAsFixed(1));
}

/// The outcome record `o` at the end of a season (fsm.FieldMachine.outcome).
class FieldOutcome {
  const FieldOutcome({
    required this.failed,
    required this.stressed,
    required this.stressDays,
    required this.severeRunMax,
    required this.heatDays,
    required this.irrigationMm,
    required this.irrigations,
    required this.etaMm,
    required this.drainageMm,
    required this.rainMm,
    required this.harvestDay,
    required this.nBalance,
    required this.mainReason,
  });

  final bool failed;
  final bool stressed;
  final int stressDays;
  final int severeRunMax;
  final int heatDays;
  final double irrigationMm;
  final int irrigations;
  final double etaMm;
  final double drainageMm;
  final double rainMm;
  final int? harvestDay;
  final double nBalance;
  final String mainReason;

  /// fsm.run_season's `matured`: harvested or failed.
  bool get matured => harvestDay != null || failed;

  /// Same keys as the Python dict (plus `matured`, as run_season adds it).
  Map<String, Object?> toMap() => {
        'failed': failed,
        'stressed': stressed,
        'stress_days': stressDays,
        'severe_run_max': severeRunMax,
        'heat_days': heatDays,
        'irrigation_mm': irrigationMm,
        'irrigations': irrigations,
        'eta_mm': etaMm,
        'drainage_mm': drainageMm,
        'rain_mm': rainMm,
        'harvest_day': harvestDay,
        'n_balance': nBalance,
        'main_reason': mainReason,
        'matured': matured,
      };
}

// ------------------------------------------------------------------ the machine

/// M_F for one crop on one field. Call [sow], then [tick] once per day.
///
/// Fields mirror the Python dataclass and are mutable so a machine can be
/// restored from storage.
class FieldMachine {
  FieldMachine(this.prm);

  final Params prm;
  FieldState q = FieldState.fallow;

  /// Days in the current state.
  int d = 0;

  /// Accumulated GDD.
  double G = 0.0; // ignore: non_constant_identifier_names

  /// Soil water in the root zone (mm).
  double S = 0.0; // ignore: non_constant_identifier_names

  /// Water stress coefficient of the last tick.
  double Ks = 1.0; // ignore: non_constant_identifier_names

  /// kappa_w: stressed days in sensitive stages.
  int kw = 0;

  /// kappa_sev: consecutive severe-stress days in a sensitive stage.
  int ksev = 0;
  int ksevMax = 0;

  /// kappa_h: days Tmax >= T_crit in Repro.
  int kh = 0;
  double irr = 0.0;
  int nIrr = 0;
  double eta = 0.0;
  double dp = 0.0;
  double rain = 0.0;

  /// Machine day counter (ticks since creation).
  int day = 0;
  List<double> rain3 = [];
  final List<FieldTransition> trace = [];
  String reason = '';
  int? harvestDay;

  // -- events
  /// Sow event (guard 2): Fallow -> Prep with starting soil water [s0] mm.
  void sow(double s0) {
    if (q != FieldState.fallow) throw StateError('sow only from Fallow');
    _go(FieldState.prep, 'g2 sow');
    S = s0;
  }

  // -- Kc in thermal time (FAO-56 Fig. 25 shape)
  double kc() {
    final p = prm;
    final g = G / prm.gMat;
    if (q == FieldState.prep || q == FieldState.estab) return p.kcIni;
    if (q == FieldState.veg) return p.kcIni + (g - p.fE) / (p.fV - p.fE) * (p.kcMid - p.kcIni);
    if (q == FieldState.repro) return p.kcMid;
    if (q == FieldState.mature) return p.kcMid + math.min(1.0, (g - p.fR) / (1 - p.fR)) * (p.kcEnd - p.kcMid);
    return 0.0;
  }

  void _go(FieldState to, String guard) {
    trace.add(FieldTransition(day, q, to, guard));
    q = to;
    d = 0;
  }

  bool get _sensitive => prm.sensitive.contains(q.label);

  /// One daily tick; returns the list of Mealy outputs emitted.
  List<String> tick(double tmax, double tmin, double P, double et0, // ignore: non_constant_identifier_names
      {bool confirmHarvest = false, bool simulating = true}) {
    final out = <String>[];
    final p = prm;
    if (q == FieldState.fallow) {
      day += 1;
      return out;
    }
    // 1. thermal time and days in state
    if (!q.isEnd) G += gdd(tmax, tmin, p.tBase, p.tUp);
    d += 1;
    // 2-3. water
    if (!q.isEnd) {
      final kcNow = kc();
      var i = 0.0;
      if (p.irrigated && (p.maxIrr == null || nIrr < p.maxIrr!)) {
        i = refillWhenStressed(S, p.taw, pAdjusted(p.p, kcNow * et0));
        if (i > 0) nIrr += 1;
      }
      final b = bucketStep(S, P, i, et0, kcNow, p.taw, p.p);
      S = b.s;
      Ks = b.ks;
      irr += i;
      eta += b.eta;
      dp += b.dp;
      rain += P;
      // 4. risk guards (counters + Mealy alerts, no stage change)
      if (_sensitive && Ks < 1) {
        kw += 1;
        out.add(FieldAlert.waterStress);
      }
      if (_sensitive && Ks < p.ksFail) {
        ksev += 1;
        ksevMax = math.max(ksevMax, ksev);
      } else {
        ksev = 0;
      }
      if (q == FieldState.repro && p.tCrit != null && tmax >= p.tCrit!) {
        kh += 1;
        out.add(FieldAlert.heatRisk);
      }
      rain3 = [...rain3, P];
      if (rain3.length > 3) rain3 = rain3.sublist(rain3.length - 3);
      if (p.crop == 'onion' &&
          q == FieldState.estab &&
          p.rotP98 != null &&
          rain3.length == 3 &&
          rain3.fold<double>(0.0, (a, x) => a + x) >= p.rotP98!) {
        out.add(FieldAlert.rotRisk);
      }
    }
    // 5. transition guards by priority
    final g = G;
    if (q.isGrowing && ksev >= p.kFail) {
      // 1
      reason = '$ksev days with Ks < ${_pyFloat(p.ksFail)} in ${q.label}';
      _go(FieldState.failed, 'g1 kappa_sev >= K_fail');
      out.add(FieldAlert.waterFail);
    } else if (q == FieldState.prep && d >= p.dPrep) {
      // 3
      _go(FieldState.estab, 'g3 d >= d_prep');
    } else if (q == FieldState.estab && g >= p.fE * p.gMat) {
      // 4
      _go(FieldState.veg, 'g4 G >= f_e G_mat');
    } else if (q == FieldState.veg && g >= p.fV * p.gMat) {
      // 5
      _go(FieldState.repro, 'g5 G >= f_v G_mat');
    } else if (q == FieldState.repro && g >= p.fR * p.gMat) {
      // 6
      _go(FieldState.mature, 'g6 G >= f_r G_mat');
    } else if (q == FieldState.mature && g >= p.gMat && (confirmHarvest || simulating)) {
      // 7
      harvestDay = day;
      _go(FieldState.harvest, 'g7 G >= G_mat');
      out.add(FieldAlert.harvestReady);
    } else if (q.isEnd) {
      // 8, 9
      _go(FieldState.fallow, q == FieldState.harvest ? 'g8 tick' : 'g9 tick');
      out.add(FieldAlert.outcome);
    }
    // 10: otherwise stay
    day += 1;
    return out;
  }

  /// The outcome record `o` for the season so far.
  FieldOutcome outcome() {
    final failed = trace.any((t) => t.to == FieldState.failed);
    final String main;
    if (failed) {
      main = 'water: $reason';
    } else if (kh > 0) {
      main = 'heat: $kh days at flowering >= ${_pyFloat(prm.tCrit)} C';
    } else if (kw > 0) {
      main = 'water: $kw stressed days in Veg/Repro';
    } else {
      main = 'none';
    }
    return FieldOutcome(
      failed: failed,
      stressed: kw > 0,
      stressDays: kw,
      severeRunMax: ksevMax,
      heatDays: kh,
      irrigationMm: _round1(irr),
      irrigations: nIrr,
      etaMm: _round1(eta),
      drainageMm: _round1(dp),
      rainMm: _round1(rain),
      harvestDay: harvestDay,
      nBalance: 0.0,
      mainReason: main,
    );
  }
}

/// Python `str(float)` for the values used in reasons (Dart's shortest
/// round-trip form matches Python's repr for ordinary magnitudes).
String _pyFloat(double? x) => x == null ? 'None' : x.toString();

/// fsm.run_season: run M_F from the sowing day until it returns to Fallow.
/// [weather] rows are (tmax, tmin, P, et0). Returns the outcome, the trace and
/// the (day index, alert) pairs.
({FieldOutcome outcome, List<FieldTransition> trace, List<(int, String)> alerts}) runSeason(
    Params prm, Iterable<(double, double, double, double)> weather, double s0Frac) {
  final m = FieldMachine(prm)..sow(s0Frac * prm.taw);
  final alerts = <(int, String)>[];
  var i = 0;
  for (final (tmax, tmin, p, et0) in weather) {
    for (final a in m.tick(tmax, tmin, p, et0)) {
      alerts.add((i, a));
    }
    i++;
    if (m.q == FieldState.fallow) break;
  }
  return (outcome: m.outcome(), trace: List.unmodifiable(m.trace), alerts: alerts);
}
