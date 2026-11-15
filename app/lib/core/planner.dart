/// Planner M_P: a farmer profile -> top 3 crop cards, or Hold.
///
/// A line-for-line port of `pipeline/planner.py` (spec 5.5). Pure Dart: the
/// only import is the typed bundle models (the `risk` and `planner` blocks of
/// `assets/data/ani_<town>.json`, which equal the town's `risk_<muni>.csv`).
///
/// M_P states: Idle -> Filter -> Rank -> Advise, or Filter -> Hold when no crop
/// passes the guards.
///
/// GUARDS (hard; a crop that fails one is removed)
///   g1 season   crop is grown in the dry season (all five are)
///   g2 water    failure rate X/n at the farmer's water level > THETA_F
///   g3 storage  onion without cold storage stays, with a price-risk flag (soft)
///   g4 farmer   crop is in the farmer's "won't plant" list
///   g5 heat     share of seasons with >= 1 heat day at flowering >= THETA_H
///   g6 profit   median net income (Monte Carlo p50) <= 0
///   No crop left -> Hold, naming the guard that removed the most crops.
///
/// CRITERIA (F14, min-max scaled; equal values -> 1): income (benefit), risk
/// (cost), water (cost), soil (legume = 1, benefit), pest (family break, benefit).
/// WEIGHTS (F15): ranked k <= 3 criteria share 0.8 by rank-order centroid, the
/// rest share 0.2 equally; El Nino mode multiplies water and risk by BETA.
/// SCORE (F16): U = sum_j w_j x~_j. TOPSIS is reported as a cross-check.
/// "BAKIT?": the two criteria with the largest w_j (x~_j - mean_j).
///
/// Number formatting reproduces Python exactly (`round()` and `format()` are
/// correctly rounded with ties to even), so card text and rounded numbers match
/// the golden fixture `assets/fixtures/planner.json` byte for byte.
library;

import 'dart:math' as math;

import 'package:ani/data/bundle.dart';

// ------------------------------------------------------------------ constants

/// THETA_F: failure-rate gate (g2).
const double kThetaF = 0.5;

/// THETA_H: heat-share gate (g5).
const double kThetaH = 0.5;

/// BETA: El Nino multiplier for the water and risk weights.
const double kBeta = 1.5;

/// RANKED_SHARE: weight share of the farmer's ranked priorities.
const double kRankedShare = 0.8;

/// CRITERIA, in order.
const List<String> kCriteria = ['income', 'risk', 'water', 'soil', 'pest'];

/// BENEFIT: criterion -> true if higher is better.
const Map<String, bool> kBenefit = {
  'income': true,
  'risk': false,
  'water': false,
  'soil': true,
  'pest': true,
};

/// DRY_SEASON_CROPS (g1).
const Set<String> kDrySeasonCrops = {'rice', 'onion', 'mungbean', 'maize', 'sweet_potato'};

/// FAMILY: botanical family per crop (pest-break criterion).
const Map<String, String> kFamily = {
  'rice': 'Poaceae',
  'maize': 'Poaceae',
  'onion': 'Amaryllidaceae',
  'mungbean': 'Fabaceae',
  'sweet_potato': 'Convolvulaceae',
};

/// LEGUME: crops that add nitrogen (soil criterion).
const Set<String> kLegume = {'mungbean'};

/// SMALL_MARKET: crops flagged for a thin local market.
const Set<String> kSmallMarket = {'mungbean', 'sweet_potato'};

/// NAME: Filipino crop names on the cards.
const Map<String, String> kCropName = {
  'rice': 'Palay',
  'onion': 'Sibuyas',
  'mungbean': 'Munggo',
  'maize': 'Mais',
  'sweet_potato': 'Kamote',
};

/// WATER_LABEL: water id -> Filipino phrase.
const Map<String, String> kWaterLabel = {
  'rainfed': 'walang patubig',
  'limited_2': 'mga 2 patubig',
  'limited_4': 'mga 4 na patubig',
  'full': 'patubig kung kailangan',
};

/// Guard names, in the order of planner.py's `blocked` dict.
abstract final class Guard {
  static const season = 'g1 season';
  static const water = 'g2 water';
  static const farmer = 'g4 farmer';
  static const heat = 'g5 heat';
  static const profit = 'g6 profit';
  static const all = [season, water, farmer, heat, profit];
}

/// Card confidence label (planner.py `confidence`).
abstract final class Confidence {
  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';
}

/// Tunable constants of M_P. Defaults are planner.py's; [PlannerParams.fromConfig]
/// takes them from a bundle's `planner` block.
class PlannerParams {
  const PlannerParams({
    this.thetaF = kThetaF,
    this.thetaH = kThetaH,
    this.beta = kBeta,
    this.rankedShare = kRankedShare,
    this.waterLabel = kWaterLabel,
  });

  final double thetaF;
  final double thetaH;
  final double beta;
  final double rankedShare;
  final Map<String, String> waterLabel;

  factory PlannerParams.fromConfig(PlannerConfig c) => PlannerParams(
        thetaF: c.thetaF,
        thetaH: c.thetaH,
        beta: c.beta,
        rankedShare: c.rankedShare,
        waterLabel: c.waterLabel,
      );
}

// ------------------------------------------------------------------ profile

/// The farmer's five answers (planner.py `Profile`).
class PlannerProfile {
  const PlannerProfile({
    required this.muni,
    required this.water,
    this.last = const [],
    this.wont = const {},
    this.coldStorage = false,
    this.priorities = const [],
  });

  /// guimba | munoz | bongabon.
  final String muni;

  /// rainfed | limited_2 | limited_4 | full.
  final String water;

  /// Last two crops, most recent first.
  final List<String> last;

  /// Crops the farmer will not plant.
  final Set<String> wont;

  final bool coldStorage;

  /// Up to 3 ranked from income, risk, water, soil, pest.
  final List<String> priorities;
}

// ------------------------------------------------------------------ F15

/// Rank-order-centroid weights for [n] ranks (Barron & Barrett 1996).
List<double> roc(int n) => [
      for (var k = 1; k <= n; k++) _sumRange(k, n) / n,
    ];

double _sumRange(int k, int n) {
  var s = 0.0;
  for (var i = k; i <= n; i++) {
    s += 1.0 / i;
  }
  return s;
}

/// F15 criterion weights (sum to 1), in [kCriteria] order.
Map<String, double> weights(List<String> priorities, bool elNino,
    [PlannerParams params = const PlannerParams()]) {
  final pr = priorities.where(kCriteria.contains).take(3).toList();
  final w = <String, double>{for (final c in kCriteria) c: 0.0};
  if (pr.isNotEmpty) {
    final r = roc(pr.length);
    for (var i = 0; i < pr.length; i++) {
      w[pr[i]] = params.rankedShare * r[i];
    }
    final rest = kCriteria.where((c) => !pr.contains(c)).toList();
    for (final c in rest) {
      w[c] = (1 - params.rankedShare) / rest.length;
    }
  } else {
    for (final c in kCriteria) {
      w[c] = 1 / kCriteria.length;
    }
  }
  if (elNino) {
    w['water'] = w['water']! * params.beta;
    w['risk'] = w['risk']! * params.beta;
  }
  var s = 0.0;
  for (final c in kCriteria) {
    s += w[c]!;
  }
  return {for (final c in kCriteria) c: w[c]! / s};
}

// ------------------------------------------------------------------ criteria

/// 1 if [crop]'s family differs from both last crops, 0.5 from one, 0 from neither.
double pestScore(String crop, List<String> last) {
  final fam = kFamily[crop];
  final l = last.take(2).where(kFamily.containsKey).toList();
  if (l.isEmpty) return 1.0;
  final differs = l.where((x) => kFamily[x] != fam).length;
  return differs / l.length;
}

/// A crops x criteria matrix (rows in [crops] order).
typedef CriteriaMatrix = Map<String, Map<String, double>>;

/// F14: min-max per criterion; cost criteria reversed; equal values -> 1.
CriteriaMatrix scale(CriteriaMatrix raw) {
  final crops = raw.keys.toList();
  final out = <String, Map<String, double>>{for (final c in crops) c: {}};
  for (final k in kCriteria) {
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final c in crops) {
      lo = math.min(lo, raw[c]![k]!);
      hi = math.max(hi, raw[c]![k]!);
    }
    for (final c in crops) {
      final x = hi > lo ? (raw[c]![k]! - lo) / (hi - lo) : 1.0;
      out[c]![k] = kBenefit[k]! ? x : (hi > lo ? 1 - x : x);
    }
  }
  return out;
}

/// TOPSIS closeness on the same criteria (cross-check only).
Map<String, double> topsis(CriteriaMatrix raw, Map<String, double> w) {
  final crops = raw.keys.toList();
  final norm = <String, double>{};
  for (final k in kCriteria) {
    var s = 0.0;
    for (final c in crops) {
      final v = raw[c]![k]!;
      s += v * v;
    }
    final n = math.sqrt(s);
    norm[k] = n == 0 ? 1.0 : n;
  }
  final v = {
    for (final c in crops) c: {for (final k in kCriteria) k: raw[c]![k]! / norm[k]! * w[k]!},
  };
  final best = <String, double>{}, worst = <String, double>{};
  for (final k in kCriteria) {
    var mx = double.negativeInfinity, mn = double.infinity;
    for (final c in crops) {
      mx = math.max(mx, v[c]![k]!);
      mn = math.min(mn, v[c]![k]!);
    }
    best[k] = kBenefit[k]! ? mx : mn;
    worst[k] = kBenefit[k]! ? mn : mx;
  }
  final out = <String, double>{};
  for (final c in crops) {
    var sp = 0.0, sm = 0.0;
    for (final k in kCriteria) {
      final a = v[c]![k]! - best[k]!, b = v[c]![k]! - worst[k]!;
      sp += a * a;
      sm += b * b;
    }
    final dp = math.sqrt(sp), dm = math.sqrt(sm);
    final tot = dp + dm;
    out[c] = tot > 0 ? dm / tot : 1.0;
  }
  return out;
}

/// Low if the Wilson interval or the Monte Carlo failure range (p10-p90) is
/// >= 0.5 wide, or net p10 < 0; Medium if either range is >= 0.3; else High.
String confidence(RiskModeStats r) {
  final wil = r.failHi - r.failLo;
  final mc = r.mcFailP90 - r.mcFailP10;
  if (wil >= 0.5 || mc >= 0.5 || r.mcNetP10 < 0) return Confidence.low;
  if (wil >= 0.3 || mc >= 0.3) return Confidence.medium;
  return Confidence.high;
}

// ------------------------------------------------------------------ results

/// Net income band on a card, PHP/ha rounded to hundreds.
class NetBand {
  const NetBand(this.p10, this.p50, this.p90);
  final double p10, p50, p90;
  Map<String, Object?> toJson() => {'p10': p10, 'p50': p50, 'p90': p90};
}

/// One crop card (planner.py `card`).
class PlanCard {
  const PlanCard({
    required this.crop,
    required this.name,
    required this.score,
    required this.riskText,
    required this.failed,
    required this.seasons,
    required this.failLo,
    required this.failHi,
    required this.waterMm,
    required this.net,
    required this.confidence,
    required this.why,
    required this.flags,
    required this.trace,
  });

  final String crop;
  final String name;

  /// U rounded to 3 dp.
  final double score;
  final String riskText;
  final int failed;
  final int seasons;
  final double failLo;
  final double failHi;
  final int waterMm;
  final NetBand net;
  final String confidence;

  /// "Bakit?" reasons.
  final List<String> why;
  final List<String> flags;
  final List<String> trace;

  Map<String, Object?> toJson() => {
        'crop': crop,
        'name': name,
        'score': score,
        'risk_text': riskText,
        'failed': failed,
        'seasons': seasons,
        'fail_lo': failLo,
        'fail_hi': failHi,
        'water_mm': waterMm,
        'net_php_ha': net.toJson(),
        'confidence': confidence,
        'why': why,
        'flags': flags,
        'trace': trace,
      };
}

/// The Hold screen text (planner.py `hold_message`).
class HoldMessage {
  const HoldMessage({required this.title, required this.reason, required this.tip, required this.refer});
  final String title, reason, tip, refer;
  Map<String, Object?> toJson() => {'title': title, 'reason': reason, 'tip': tip, 'refer': refer};
}

/// Output of [plan]: state Advise (with [cards]) or Hold (with [message]).
class PlanResult {
  const PlanResult._({
    required this.state,
    required this.trace,
    required this.blocked,
    this.blockingGuard,
    this.message,
    this.weights,
    this.elNino,
    this.cards = const [],
    this.topsisTop,
    this.topsisAgrees,
  });

  /// 'Advise' or 'Hold'.
  final String state;
  final List<String> trace;

  /// Guard name -> crops it removed (sorted), in [Guard.all] order.
  final Map<String, List<String>> blocked;

  /// Hold only.
  final String? blockingGuard;
  final HoldMessage? message;

  /// Advise only.
  final Map<String, double>? weights;
  final bool? elNino;
  final List<PlanCard> cards;
  final String? topsisTop;
  final bool? topsisAgrees;

  bool get isHold => state == 'Hold';

  /// Same shape as planner.py's returned dict.
  Map<String, Object?> toJson() => isHold
      ? {
          'state': state,
          'trace': trace,
          'blocked': blocked,
          'blocking_guard': blockingGuard,
          'message': message!.toJson(),
        }
      : {
          'state': state,
          'trace': trace,
          'blocked': blocked,
          'weights': weights,
          'el_nino': elNino,
          'cards': [for (final c in cards) c.toJson()],
          'topsis_top': topsisTop,
          'topsis_agrees': topsisAgrees,
        };
}

// ------------------------------------------------------------------ M_P

/// Run M_P for [profile] on a town's [risk] table.
///
/// [heatShare] overrides the per-row `heat_share` of the bundle (g5); planner.py
/// reads it unrounded from `outcomes_<muni>.csv`.
PlanResult plan(
  PlannerProfile profile,
  RiskTable risk, {
  required bool elNino,
  int top = 3,
  PlannerParams params = const PlannerParams(),
  double Function(String crop, String water)? heatShare,
}) {
  final trace = ['Idle', 'Filter'];
  final mode = RiskMode.forEnso(elNino);
  final rows = risk.byWater[profile.water] ?? const <String, RiskRow>{};
  final blocked = <String, List<String>>{for (final g in Guard.all) g: []};
  final keep = <String>[];
  for (final crop in rows.keys.toList()..sort()) {
    final row = rows[crop]!;
    final r = row.forMode(mode);
    final hs = heatShare != null ? heatShare(crop, profile.water) : row.heatShare;
    if (!kDrySeasonCrops.contains(crop)) {
      blocked[Guard.season]!.add(crop);
    } else if (profile.wont.contains(crop)) {
      blocked[Guard.farmer]!.add(crop);
    } else if (r.failX / math.max(r.failN, 1) > params.thetaF) {
      blocked[Guard.water]!.add(crop);
    } else if (hs >= params.thetaH) {
      blocked[Guard.heat]!.add(crop);
    } else if (r.mcNetP50 <= 0) {
      blocked[Guard.profit]!.add(crop);
    } else {
      keep.add(crop);
    }
  }
  if (keep.isEmpty) {
    // max over (count, name): ties go to the larger guard name.
    var guard = Guard.all.first;
    for (final g in Guard.all) {
      final a = blocked[g]!.length, b = blocked[guard]!.length;
      if (a > b || (a == b && g.compareTo(guard) > 0)) guard = g;
    }
    trace.add('Hold');
    return PlanResult._(
      state: 'Hold',
      trace: trace,
      blocked: blocked,
      blockingGuard: guard,
      message: holdMessage(guard, profile, params),
    );
  }
  trace.addAll(['Rank', 'Advise']);
  final w = weights(profile.priorities, elNino, params);
  final CriteriaMatrix raw = {
    for (final c in keep)
      c: {
        'income': rows[c]!.forMode(mode).mcNetP50,
        'risk': rows[c]!.forMode(mode).mcFailP50,
        'water': rows[c]!.forMode(mode).mcIrrP50,
        'soil': kLegume.contains(c) ? 1.0 : 0.0,
        'pest': pestScore(c, profile.last),
      },
  };
  final x = scale(raw);
  final score = <String, double>{};
  for (final c in keep) {
    var s = 0.0;
    for (final k in kCriteria) {
      s += w[k]! * x[c]![k]!;
    }
    score[c] = s;
  }
  int byScore(Map<String, double> s, String a, String b) {
    final d = pyRound(s[b]!, 9).compareTo(pyRound(s[a]!, 9));
    return d != 0 ? d : a.compareTo(b);
  }

  final order = [...keep]..sort((a, b) => byScore(score, a, b));
  final tp = topsis(raw, w);
  final tpOrder = [...keep]..sort((a, b) => byScore(tp, a, b));
  // what sets each crop apart: x~ minus the column mean over the candidates
  final mean = <String, double>{};
  for (final k in kCriteria) {
    var s = 0.0;
    for (final c in keep) {
      s += x[c]![k]!;
    }
    mean[k] = s / keep.length;
  }
  final single = keep.length == 1;
  final cards = [
    for (final c in order.take(top))
      card(
        c,
        rows[c]!.forMode(mode),
        raw[c]!,
        {for (final k in kCriteria) k: x[c]![k]! - mean[k]!},
        w,
        score[c]!,
        mode,
        profile,
        single: single,
        params: params,
      ),
  ];
  return PlanResult._(
    state: 'Advise',
    trace: trace,
    blocked: blocked,
    weights: w,
    elNino: elNino,
    cards: cards,
    topsisTop: tpOrder.first,
    topsisAgrees: tpOrder.first == order.first,
  );
}

/// One card for [crop]; [edge] is x~ minus the candidates' mean.
PlanCard card(
  String crop,
  RiskModeStats r,
  Map<String, double> raw,
  Map<String, double> edge,
  Map<String, double> w,
  double score,
  RiskMode mode,
  PlannerProfile profile, {
  required bool single,
  PlannerParams params = const PlannerParams(),
}) {
  final years = mode == RiskMode.elNino ? 'El Niño na taon' : 'taon';
  // sorted((w*edge, c), reverse=True): by value, then name, both descending
  final contrib = [for (final c in kCriteria) (w[c]! * edge[c]!, c)]
    ..sort((a, b) {
      final d = b.$1.compareTo(a.$1);
      return d != 0 ? d : b.$2.compareTo(a.$2);
    });
  var why = [
    for (final (v, c) in contrib.take(2))
      if (v > 1e-9) reason(c, crop, raw, profile),
  ];
  if (why.isEmpty && single) {
    why = [
      'Tanging pananim na kaya ang tag-araw na ito sa ${params.waterLabel[profile.water]}',
      reason('risk', crop, raw, profile),
    ];
  } else if (why.isEmpty) {
    why = ['Halos kapantay ng ibang pagpipilian'];
  }
  final flags = <String>[];
  if (kSmallMarket.contains(crop)) flags.add('Maliit ang lokal na pamilihan: kumonsulta sa MAO');
  if (crop == 'onion' && !profile.coldStorage) {
    flags.add('Walang cold storage: mataas ang panganib sa presyo');
  }
  final conf = confidence(r);
  if (conf == Confidence.low) flags.add('Mababang katiyakan: kumonsulta sa MAO');
  return PlanCard(
    crop: crop,
    name: kCropName[crop]!,
    score: pyRound(score, 3),
    riskText: 'Nasira sa ${r.failX} sa ${r.failN} na $years '
        '(${_pct0(r.failLo)}–${_pct0(r.failHi)})',
    failed: r.failX,
    seasons: r.failN,
    failLo: r.failLo,
    failHi: r.failHi,
    waterMm: pyRound(raw['water']!, 0).toInt(),
    net: NetBand(pyRound(r.mcNetP10, -2), pyRound(r.mcNetP50, -2), pyRound(r.mcNetP90, -2)),
    confidence: conf,
    why: why,
    flags: flags,
    trace: [
      'g1 season: pass',
      'g2 water: fail rate ${_pct0(r.mcFailP50)} <= ${_pct0(params.thetaF)}',
      'g4 farmer: pass',
      'g5 heat: pass',
    ],
  );
}

/// The "Bakit?" sentence for [criterion].
String reason(String criterion, String crop, Map<String, double> raw, PlannerProfile profile) {
  switch (criterion) {
    case 'income':
      return 'Kita: mga ₱${pyFixed(raw['income']! / 1000, 0, group: true)}k bawat ektarya (gitnang tantiya)';
    case 'risk':
      return raw['risk']! < 0.2
          ? 'Mababa ang tsansang masira ngayong tag-araw'
          : 'Tsansang masira: ${_pct0(raw['risk']!)}';
    case 'water':
      return 'Kaunting tubig: mga ${pyFixed(raw['water']!, 0)} mm sa buong panahon';
    case 'soil':
      return 'Nagdadagdag ng nitrogen sa lupa (legume)';
    case 'pest':
      return 'Iba ang pamilya sa huling tanim: pumuputol sa siklo ng peste';
  }
  return criterion;
}

/// The Hold screen for the blocking [guard].
HoldMessage holdMessage(String guard, PlannerProfile profile,
    [PlannerParams params = const PlannerParams()]) {
  final why = switch (guard) {
    Guard.water =>
      'Masyadong mataas ang tsansang masira sa ${params.waterLabel[profile.water]} ngayong El Niño',
    Guard.farmer => 'Wala nang natirang pananim matapos alisin ang ayaw ninyong itanim',
    Guard.heat => 'Masyadong mainit sa panahon ng pamumulaklak',
    Guard.profit => 'Walang pananim na inaasahang kikita ngayong tag-araw sa inyong patubig',
    Guard.season => 'Walang pananim na angkop sa tag-araw',
    _ => throw ArgumentError.value(guard, 'guard'),
  };
  return HoldMessage(
    title: 'Huwag munang magtanim',
    reason: why,
    tip: 'Takpan ng dayami (mulch) o iwanang pahinga ang lupa; ihanda ang patubig para sa susunod',
    refer: 'Kumonsulta sa MAO',
  );
}

// ------------------------------------------------------------------ Python-exact rounding

/// Python `round(x, nd)`: correctly rounded, ties to even (nd may be negative).
double pyRound(double x, int nd) {
  if (!x.isFinite) return x;
  final (neg, digits) = _roundDigits(x, nd);
  final v = nd >= 0
      ? double.parse(_place(digits, nd))
      : (BigInt.parse(digits) * BigInt.from(10).pow(-nd)).toDouble();
  return neg ? -v : v;
}

/// Python `format(x, f'.{nd}f')` (with `,` grouping when [group]).
String pyFixed(double x, int nd, {bool group = false}) {
  final (neg, digits) = _roundDigits(x, nd);
  var s = _place(digits, nd);
  if (group) {
    final dot = s.indexOf('.');
    final ip = dot < 0 ? s : s.substring(0, dot);
    final fp = dot < 0 ? '' : s.substring(dot);
    final b = StringBuffer();
    for (var i = 0; i < ip.length; i++) {
      if (i > 0 && (ip.length - i) % 3 == 0) b.write(',');
      b.write(ip[i]);
    }
    s = '$b$fp';
  }
  return neg || x.isNegative ? '-$s' : s;
}

/// Python `format(x, '.0%')`.
String _pct0(double x) => '${pyFixed(x * 100, 0)}%';

/// Integer digit string of |x| * 10^nd rounded half-to-even on the exact
/// binary value, plus the sign.
(bool, String) _roundDigits(double x, int nd) {
  final neg = x < 0;
  // 20 decimals resolve any double in the planner's range exactly enough to
  // tell a true tie from a neighbour (doubles here have ulp >> 1e-20 relative).
  final s = x.abs().toStringAsFixed(20);
  final dot = s.indexOf('.');
  final ip = '000${s.substring(0, dot)}';
  final fp = s.substring(dot + 1);
  final all = ip + fp;
  final cut = ip.length + nd;
  final keep = all.substring(0, cut);
  final rest = all.substring(cut);
  var d = BigInt.parse(keep);
  final first = rest.isEmpty ? 0 : rest.codeUnitAt(0) - 48;
  final tail = rest.length > 1 && rest.substring(1).split('').any((c) => c != '0');
  if (first > 5 || (first == 5 && (tail || d.isOdd))) d += BigInt.one;
  return (neg, d.toString());
}

/// Places a decimal point [nd] digits from the right of [digits] (nd >= 0).
String _place(String digits, int nd) {
  if (nd <= 0) return digits;
  final p = digits.padLeft(nd + 1, '0');
  return '${p.substring(0, p.length - nd)}.${p.substring(p.length - nd)}';
}
