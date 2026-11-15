/// Dryness Alert Machine: Normal / Bantay / Delikado with hysteresis, driven
/// by the dekadal dryness index D.
///
/// Pure Dart (no Flutter imports), immutable and deterministic: [AlertMachine.step]
/// maps `(state, D) -> state` and [AlertMachine.run] folds it over a series.
///
/// Source: docs/PLAN.md Phase 2 ("up at 1 / 2, down after 2 dekads below
/// 1.5 / 0.5") and the `dryness.thresholds` block written by
/// pipeline/export_json.py. The pipeline has no stateful Python
/// implementation to port; its only labeller is the stateless
/// `zscores.label(d)` (`delikado if d >= 2 else bantay if d >= 1 else
/// normal`), which [AlertMachine.instantLevel] mirrors exactly. The edge-case
/// choices below are therefore this file's spec:
///
/// * **Escalation is immediate and inclusive** (`>=`, as in `zscores.label`):
///   D >= `delikado` goes to Delikado from any state, so Normal may jump
///   straight to Delikado; otherwise D >= `bantay` lifts Normal to Bantay.
/// * **De-escalation is strict** (`<`) and needs `calm_dekads` *consecutive*
///   calm dekads: Delikado -> Bantay when D < `down_bantay`; Bantay -> Normal
///   when D < `down_normal`.
/// * **One level per step down.** Delikado never drops straight to Normal.
///   Stepping down resets the calm counter, so Bantay -> Normal then needs its
///   own fresh run of `calm_dekads` dekads below `down_normal` (Delikado to
///   Normal takes at least `2 * calm_dekads` dekads).
/// * **A non-calm dekad resets the counter**, including one that keeps the
///   level (e.g. Bantay with 0.5 <= D < 1, or Delikado with 1.5 <= D < 2).
/// * **Missing data** (`null` or NaN) holds the level, is not calm, and resets
///   the counter, so a gap breaks a "consecutive" run and the alert never
///   relaxes across missing data. Infinities are ordinary values (+inf
///   escalates to Delikado, -inf is calm).
/// * `calm_dekads <= 1` means a single calm dekad steps down.
/// * The calm counter is always 0 in Normal.
library;

/// Alert level. [label] is the Filipino UI word (kept in Filipino in both
/// languages); [id] matches `DrynessLabel` / `dryness.latest.label`.
enum AlertLevel {
  normal('normal', 'Normal'),
  bantay('bantay', 'Bantay'),
  delikado('delikado', 'Delikado');

  const AlertLevel(this.id, this.label);

  /// Lower-case id as written by the pipeline (`normal` / `bantay` / `delikado`).
  final String id;

  /// Filipino display label: Normal, Bantay ("watch"), Delikado ("danger").
  final String label;

  /// Parses a pipeline id; null if unknown (including the pipeline's "" for NaN).
  static AlertLevel? tryFromId(String id) {
    for (final l in values) {
      if (l.id == id) return l;
    }
    return null;
  }
}

/// Thresholds from the bundle's `dryness.thresholds` block. Mirrors
/// `DrynessThresholds` in lib/data/bundle.dart, redeclared here so this file
/// stays free of Flutter imports (bundle.dart imports flutter/services).
class AlertThresholds {
  const AlertThresholds({
    required this.bantay,
    required this.delikado,
    required this.downBantay,
    required this.downNormal,
    required this.calmDekads,
  });

  /// The values export_json.py writes.
  static const standard = AlertThresholds(
    bantay: 1.0,
    delikado: 2.0,
    downBantay: 1.5,
    downNormal: 0.5,
    calmDekads: 2,
  );

  /// `bantay`: D at/above which Normal goes up to Bantay.
  final double bantay;

  /// `delikado`: D at/above which any level goes up to Delikado.
  final double delikado;

  /// `down_bantay`: D below which a dekad counts as calm in Delikado.
  final double downBantay;

  /// `down_normal`: D below which a dekad counts as calm in Bantay.
  final double downNormal;

  /// `calm_dekads`: consecutive calm dekads required before stepping down.
  final int calmDekads;

  /// Parses the `dryness.thresholds` JSON object.
  factory AlertThresholds.fromJson(Map<String, dynamic> j) {
    double dbl(String k) {
      final v = j[k];
      if (v is num) return v.toDouble();
      throw FormatException('dryness.thresholds.$k: expected a number, got $v');
    }

    final c = j['calm_dekads'];
    if (c is! num || c != c.roundToDouble()) {
      throw FormatException('dryness.thresholds.calm_dekads: expected an integer, got $c');
    }
    return AlertThresholds(
      bantay: dbl('bantay'),
      delikado: dbl('delikado'),
      downBantay: dbl('down_bantay'),
      downNormal: dbl('down_normal'),
      calmDekads: c.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AlertThresholds &&
      other.bantay == bantay &&
      other.delikado == delikado &&
      other.downBantay == downBantay &&
      other.downNormal == downNormal &&
      other.calmDekads == calmDekads;

  @override
  int get hashCode => Object.hash(bantay, delikado, downBantay, downNormal, calmDekads);
}

/// Machine state: the current [level] and how many consecutive calm dekads
/// have been seen at that level ([calm], always 0 in Normal).
class AlertState {
  const AlertState(this.level, [this.calm = 0]) : assert(calm >= 0);

  /// The starting state: Normal, no calm run.
  static const initial = AlertState(AlertLevel.normal);

  final AlertLevel level;

  /// Consecutive calm dekads at [level] so far.
  final int calm;

  /// Filipino display label of [level].
  String get label => level.label;

  @override
  bool operator ==(Object other) => other is AlertState && other.level == level && other.calm == calm;

  @override
  int get hashCode => Object.hash(level, calm);

  @override
  String toString() => 'AlertState(${level.label}, calm: $calm)';
}

/// The hysteresis state machine. Stateless itself; all state is in [AlertState].
class AlertMachine {
  const AlertMachine([this.thresholds = AlertThresholds.standard]);

  final AlertThresholds thresholds;

  /// True for missing data: null or NaN.
  static bool isMissing(double? d) => d == null || d.isNaN;

  /// Stateless label for one D, identical to pipeline `zscores.label`;
  /// null for missing data (the pipeline writes "").
  AlertLevel? instantLevel(double? d) {
    if (isMissing(d)) return null;
    if (d! >= thresholds.delikado) return AlertLevel.delikado;
    if (d >= thresholds.bantay) return AlertLevel.bantay;
    return AlertLevel.normal;
  }

  /// Advances one dekad. Total: every state and every D (incl. null/NaN)
  /// yields a defined state.
  AlertState step(AlertState s, double? d) {
    if (isMissing(d)) return AlertState(s.level);
    final t = thresholds;
    final need = t.calmDekads < 1 ? 1 : t.calmDekads;
    if (d! >= t.delikado) return const AlertState(AlertLevel.delikado);
    switch (s.level) {
      case AlertLevel.normal:
        return d >= t.bantay ? const AlertState(AlertLevel.bantay) : AlertState.initial;
      case AlertLevel.bantay:
        if (d >= t.downNormal) return const AlertState(AlertLevel.bantay);
        final calm = s.calm + 1;
        return calm >= need ? AlertState.initial : AlertState(AlertLevel.bantay, calm);
      case AlertLevel.delikado:
        if (d >= t.downBantay) return const AlertState(AlertLevel.delikado);
        final calm = s.calm + 1;
        return calm >= need ? const AlertState(AlertLevel.bantay) : AlertState(AlertLevel.delikado, calm);
    }
  }

  /// Runs [step] over [ds] (oldest first) from [from]; returns the state after
  /// each dekad (same length as [ds], unmodifiable).
  List<AlertState> run(Iterable<double?> ds, {AlertState from = AlertState.initial}) {
    final out = <AlertState>[];
    var s = from;
    for (final d in ds) {
      s = step(s, d);
      out.add(s);
    }
    return List.unmodifiable(out);
  }

  /// The state after the whole series ([from] if [ds] is empty).
  AlertState last(Iterable<double?> ds, {AlertState from = AlertState.initial}) =>
      ds.fold(from, step);
}
