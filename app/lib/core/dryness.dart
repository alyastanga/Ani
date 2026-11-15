/// Dryness index (Eq. 4.3, 4.5, 4.6), a line-for-line port of
/// `pipeline/zscores.py` (`robust_z`, `loglogistic_pwm`, `empirical_index`,
/// `spei_value`, `label`, the D combination in `build`) and `rank_text` from
/// `pipeline/export_json.py`. Pure Dart: no Flutter imports.
///
///   z_sm : robust z of monthly mean GWETROOT, (x - median) / (1.4826 MAD),
///          SD when MAD = 0, clipped to [-3.5, 3.5].
///   SPEI : 3-parameter log-logistic fit by probability-weighted moments
///          (Vicente-Serrano et al. 2010), empirical (Gringorten) fallback.
///   D    : 0.5 (-SPEI_k - z_sm), -SPEI_k when z_sm is undefined;
///          k = 3 in the dry season (Nov-Apr), k = 1 otherwise.
///
/// Missing values (NaN in the pipeline) are `null` here.
///
/// On-device scoring of a new month uses [DrynessBaseline], built from the
/// bundle's `dryness.reference[month]` arrays (years, bal1, bal3, gwet), with
/// the leave-one-year-out rule of `zscores.loo_index`.
library;

import 'dart:math' as math;

/// Dry season (Tag-araw) months: the 3-month index is used (zscores.DRY_SEASON).
const Set<int> kDrySeason = {11, 12, 1, 2, 3, 4};

/// Accumulation k for calendar [month]: 3 in the dry season, 1 otherwise.
int accumulationFor(int month) => kDrySeason.contains(month) ? 3 : 1;

/// Minimum baseline length (after dropping missing values).
const int kMinRef = 10;

// ------------------------------------------------------------------ helpers

List<double> _valid(Iterable<double?> ref) => [
      for (final v in ref)
        if (v != null && !v.isNaN) v,
    ];

/// numpy `median`.
double median(List<double> xs) {
  final s = [...xs]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// numpy `std(ddof=1)`.
double stdDdof1(List<double> xs) {
  final n = xs.length;
  if (n < 2) return double.nan;
  final m = xs.reduce((a, b) => a + b) / n;
  var ss = 0.0;
  for (final x in xs) {
    ss += (x - m) * (x - m);
  }
  return math.sqrt(ss / (n - 1));
}

double _mean(Iterable<double> xs) {
  var s = 0.0;
  var n = 0;
  for (final x in xs) {
    s += x;
    n++;
  }
  return s / n;
}

/// Standard normal quantile (scipy `norm.ppf`): Wichura (1988) AS 241,
/// PPND16, relative accuracy about 1e-16. Returns +-infinity at 0 / 1.
double normPpf(double p) {
  if (p.isNaN || p < 0 || p > 1) return double.nan;
  if (p == 0) return double.negativeInfinity;
  if (p == 1) return double.infinity;
  final q = p - 0.5;
  if (q.abs() <= 0.425) {
    final r = 0.180625 - q * q;
    return q *
        (((((((r * 2509.0809287301226727 + 33430.575583588128105) * r + 67265.770927008700853) * r +
                                45921.953931549871457) *
                            r +
                        13731.693765509461125) *
                    r +
                1971.5909503065514427) *
                r +
            133.14166789178437745) *
                r +
            3.387132872796366608) /
        (((((((r * 5226.495278852545925 + 28729.085735721942674) * r + 39307.89580009271061) * r +
                                21213.794301586595867) *
                            r +
                        5394.1960214247511077) *
                    r +
                687.1870074920579083) *
                r +
            42.313330701600911252) *
                r +
            1.0);
  }
  var r = q < 0 ? p : 1 - p;
  r = math.sqrt(-math.log(r));
  double val;
  if (r <= 5) {
    r -= 1.6;
    val = (((((((r * 7.7454501427834140764e-4 + 0.0227238449892691845833) * r + 0.24178072517745061177) * r +
                                1.27045825245236838258) *
                            r +
                        3.64784832476320460504) *
                    r +
                5.7694972214606914055) *
                r +
            4.6303378461565452959) *
                r +
            1.42343711074968357734) /
        (((((((r * 1.05075007164441684324e-9 + 5.475938084995344946e-4) * r + 0.0151986665636164571966) * r +
                                0.14810397642748007459) *
                            r +
                        0.68976733498510000455) *
                    r +
                1.6763848301838038494) *
                r +
            2.05319162663775882187) *
                r +
            1.0);
  } else {
    r -= 5;
    val = (((((((r * 2.01033439929228813265e-7 + 2.71155556874348757815e-5) * r + 0.0012426609473880784386) * r +
                                0.026532189526576123093) *
                            r +
                        0.29656057182850489123) *
                    r +
                1.7848265399172913358) *
                r +
            5.4637849111641143699) *
                r +
            6.6579046435011037772) /
        (((((((r * 2.04426310338993978564e-15 + 1.4215117583164458887e-7) * r + 1.8463183175100546818e-5) * r +
                                7.868691311456132591e-4) *
                            r +
                        0.0148753612908506148525) *
                    r +
                0.13692988092273580531) *
                r +
            0.59983220655588793769) *
                r +
            1.0);
  }
  return q < 0 ? -val : val;
}

// ------------------------------------------------------------------ robust z (Eq. 4.3)

/// `robust_z(x, ref)`: robust z of [x] against the baseline [ref] (same
/// calendar month, target year excluded). null when undefined.
double? robustZ(double? x, Iterable<double?> ref) {
  final r = _valid(ref);
  if (x == null || x.isNaN || r.length < kMinRef) return null;
  final med = median(r);
  var scale = 1.4826 * median([for (final v in r) (v - med).abs()]);
  if (scale < 1e-9) scale = stdDdof1(r); // e.g. GWETROOT pinned at 1.0 in wet months
  if (scale < 1e-9) return null;
  return ((x - med) / scale).clamp(-3.5, 3.5).toDouble(); // same bound as SPI tables
}

// ------------------------------------------------------------------ SPEI (Eq. 4.5)

/// Log-logistic parameters (alpha, beta, gamma) of `loglogistic_pwm`.
typedef LogLogistic = ({double alpha, double beta, double gamma});

/// `loglogistic_pwm(ref)`: Vicente-Serrano et al. (2010) PWM fit; null when
/// beta is not finite or <= 1 (no fit).
LogLogistic? loglogisticPwm(List<double> ref) {
  final x = [...ref]..sort();
  final n = x.length;
  final f = [for (var i = 1; i <= n; i++) (i - 0.35) / n];
  final w0 = _mean(x);
  final w1 = _mean([for (var i = 0; i < n; i++) (1 - f[i]) * x[i]]);
  final w2 = _mean([for (var i = 0; i < n; i++) (1 - f[i]) * (1 - f[i]) * x[i]]);
  final beta = (2 * w1 - w0) / (6 * w1 - w0 - 6 * w2);
  if (!beta.isFinite || beta <= 1) return null;
  // G(1 + 1/beta) * G(1 - 1/beta) = (pi a) / sin(pi a), a = 1/beta (reflection formula).
  final a = 1 / beta;
  final g = math.pi * a / math.sin(math.pi * a);
  final alpha = (w0 - 2 * w1) * beta / g;
  final gam = w0 - alpha * g;
  return (alpha: alpha, beta: beta, gamma: gam);
}

/// `empirical_index(x, ref)`: Gringorten plotting position of [x] within
/// ref + {x} (average rank for ties), mapped to a normal quantile.
double empiricalIndex(double x, List<double> ref) {
  final n = ref.length + 1;
  var less = 0;
  var equal = 1; // x itself
  for (final v in ref) {
    if (v < x) {
      less++;
    } else if (v == x) {
      equal++;
    }
  }
  final rank = less + (equal + 1) / 2; // scipy rankdata(method="average")
  return normPpf((rank - 0.44) / (n + 0.12));
}

/// Result of [spei]: the index and whether the empirical fallback was used.
typedef SpeiResult = ({double value, bool fallback});

/// `spei_value(x, ref)` with the fallback flag. null when undefined.
SpeiResult? spei(double? x, Iterable<double?> ref) {
  final r = _valid(ref);
  if (x == null || x.isNaN || r.length < kMinRef) return null;
  final p = loglogisticPwm(r);
  if (p == null) return (value: empiricalIndex(x, r), fallback: true);
  final double f;
  if (x <= p.gamma) {
    f = 1e-6;
  } else {
    f = 1 / (1 + math.pow(p.alpha / (x - p.gamma), p.beta));
  }
  final v = normPpf(f.clamp(1e-6, 1 - 1e-6).toDouble());
  return v.isNaN ? null : (value: v, fallback: false);
}

/// `spei_value(x, ref)`: SPEI of water balance [x] (mm). null when undefined.
double? speiValue(double? x, Iterable<double?> ref) => spei(x, ref)?.value;

// ------------------------------------------------------------------ D and label (Eq. 4.6)

/// D = 0.5 (-spei - zSm); -spei when [zSm] is undefined; null without [spei].
double? combinedD(double? spei, double? zSm) {
  if (spei == null || spei.isNaN) return null;
  if (zSm == null || zSm.isNaN) return -spei; // spec F4: climate term alone
  return 0.5 * (-spei - zSm);
}

/// `label(d)`: delikado (D >= 2), bantay (D >= 1), normal; null when undefined.
String? drynessLabel(double? d, {double bantay = 1.0, double delikado = 2.0}) {
  if (d == null || d.isNaN) return null;
  return d >= delikado ? 'delikado' : d >= bantay ? 'bantay' : 'normal';
}

// ------------------------------------------------------------------ rank sentence

/// `dry_rank` / `dry_n` of [d] among [others] (the D values of the same
/// calendar month in other years): rank 1 = driest, ties share the best
/// rank (pandas `rank(ascending=False, method="min")`).
({int rank, int n}) dryRank(double d, Iterable<double?> others) {
  final o = _valid(others);
  return (rank: 1 + o.where((v) => v > d).length, n: o.length + 1);
}

/// `rank_text(d, rank, n)`: "driest r of n" when D >= 0, "wettest" otherwise.
String? rankText(double? d, int? rank, int? n) {
  if (d == null || rank == null || n == null) return null;
  return d >= 0 ? 'pinakatuyo: ika-$rank sa $n na taon' : 'pinakabasa: ika-${n - rank + 1} sa $n na taon';
}

// ------------------------------------------------------------------ on-device scoring

/// Scores for one month.
class DrynessScore {
  const DrynessScore({
    required this.year,
    required this.month,
    required this.k,
    required this.balance,
    required this.spei,
    required this.speiFallback,
    required this.zSm,
    required this.d,
    required this.label,
    required this.nRef,
  });

  final int year;
  final int month;

  /// Accumulation used (3 in Nov-Apr, else 1).
  final int k;

  /// The water balance scored (bal3 or bal1), mm.
  final double? balance;
  final double? spei;

  /// True if SPEI used the empirical (rank) fallback.
  final bool speiFallback;
  final double? zSm;
  final double? d;
  final String? label;

  /// Baseline years used (after leave-one-year-out).
  final int nRef;
}

/// Baseline for one calendar month: arrays aligned by [years], as in the
/// bundle's `dryness.reference["m"]` (build it from `DrynessReferenceMonth`).
class DrynessBaseline {
  DrynessBaseline({
    required this.month,
    required List<int> years,
    required List<double?> bal1,
    required List<double?> bal3,
    required List<double?> gwet,
  })  : years = List.unmodifiable(years),
        bal1 = List.unmodifiable(bal1),
        bal3 = List.unmodifiable(bal3),
        gwet = List.unmodifiable(gwet) {
    if (bal1.length != years.length || bal3.length != years.length || gwet.length != years.length) {
      throw ArgumentError('DrynessBaseline: years/bal1/bal3/gwet lengths differ');
    }
  }

  /// Calendar month 1..12.
  final int month;
  final List<int> years;
  final List<double?> bal1;
  final List<double?> bal3;
  final List<double?> gwet;

  int get k => accumulationFor(month);

  /// The balance series used for this month (bal3 in the dry season, else bal1).
  List<double?> get balance => k == 3 ? bal3 : bal1;

  List<double?> _loo(List<double?> s, int year) => [
        for (var i = 0; i < years.length; i++)
          if (years[i] != year) s[i],
      ];

  /// Scores a month of [year] with balances [bal1] / [bal3] (mm) and mean
  /// GWETROOT [gwet]. The baseline excludes [year] if it is in [years]
  /// (leave-one-year-out). Only the balance for this month's k is used.
  DrynessScore score(int year, {double? bal1, double? bal3, double? gwet, double bantay = 1.0, double delikado = 2.0}) {
    final x = k == 3 ? bal3 : bal1;
    final balRef = _loo(balance, year);
    final s = spei(x, balRef);
    final z = robustZ(gwet, _loo(this.gwet, year));
    final d = combinedD(s?.value, z);
    return DrynessScore(
      year: year,
      month: month,
      k: k,
      balance: x,
      spei: s?.value,
      speiFallback: s?.fallback ?? false,
      zSm: z,
      d: d,
      label: drynessLabel(d, bantay: bantay, delikado: delikado),
      nRef: _valid(balRef).length,
    );
  }

  /// Re-scores a year already in the baseline from its own stored values.
  DrynessScore scoreYear(int year, {double bantay = 1.0, double delikado = 2.0}) {
    final i = years.indexOf(year);
    if (i < 0) throw ArgumentError('DrynessBaseline: year $year not in baseline for month $month');
    return score(year, bal1: bal1[i], bal3: bal3[i], gwet: gwet[i], bantay: bantay, delikado: delikado);
  }

  /// D for every baseline year, in [years] order (null where undefined).
  List<double?> allD() => [for (final y in years) scoreYear(y).d];
}
