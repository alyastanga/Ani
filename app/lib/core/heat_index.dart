/// Heat index for the safety channel (Eq. 4.2), a line-for-line port of
/// `pipeline/power_prep.py` (`rh_at_tmax`, `heat_index_c`, `pagasa_category`,
/// and the rounding in `process`). Pure Dart: no Flutter imports.
///
/// NWS heat index: Rothfusz (1990) regression with the NWS low/high humidity
/// adjustments, Steadman's simple form when the averaged simple value is
/// below 80 F. PAGASA bands as in the bundle's `heat.index_categories_c`.
library;

import 'dart:math' as math;

import 'et0.dart' show roundHalfEven, satVp;

/// F10: relative humidity at the time of Tmax from the dew point, % (0..100).
double rhAtTmax(double tmax, double tdew) => (100 * satVp(tdew) / satVp(tmax)).clamp(0.0, 100.0);

/// NWS heat index (Rothfusz 1990 + adjustments); [tC] in deg C, [rh] in %,
/// result in deg C.
double heatIndexC(double tC, double rh) {
  final t = tC * 9 / 5 + 32;
  final r = rh;
  final simple = 0.5 * (t + 61.0 + (t - 68.0) * 1.2 + r * 0.094);
  var full = -42.379 +
      2.04901523 * t +
      10.14333127 * r -
      0.22475541 * t * r -
      0.00683783 * t * t -
      0.05481717 * r * r +
      0.00122874 * t * t * r +
      0.00085282 * t * r * r -
      0.00000199 * t * t * r * r;
  final adjLow = (r < 13 && t >= 80 && t <= 112)
      ? -((13 - r) / 4) * math.sqrt(math.max(17 - (t - 95).abs(), 0.0) / 17)
      : 0.0;
  final adjHigh = (r > 85 && t >= 80 && t <= 87) ? ((r - 85) / 10) * ((87 - t) / 5) : 0.0;
  full = full + adjLow + adjHigh;
  final useFull = (simple + t) / 2 >= 80;
  final hiF = useFull ? full : simple;
  return (hiF - 32) * 5 / 9;
}

/// PAGASA heat-index band. Bins are left-closed, right-open
/// (`pd.cut(..., right=False)`): none < 27 <= caution < 33 <= extreme caution
/// < 42 <= danger < 52 <= extreme danger.
enum PagasaBand {
  none('none', null, double.negativeInfinity),
  caution('caution', 'caution', 27),
  extremeCaution('extreme_caution', 'extreme caution', 33),
  danger('danger', 'danger', 42),
  extremeDanger('extreme_danger', 'extreme danger', 52);

  const PagasaBand(this.key, this.bundleLabel, this.fromC);

  /// Pipeline label (`HI_CAT` column / fixtures), e.g. `extreme_caution`.
  final String key;

  /// Label used in the bundle `heat.index_categories_c[].label`, or null for [none].
  final String? bundleLabel;

  /// Inclusive lower bound, deg C.
  final double fromC;

  static PagasaBand? fromKey(String key) {
    for (final b in values) {
      if (b.key == key) return b;
    }
    return null;
  }
}

/// `pagasa_category`: band of heat index [hiC] (deg C); null for NaN.
PagasaBand? pagasaCategory(double hiC) {
  if (hiC.isNaN) return null;
  var hit = PagasaBand.none;
  for (final b in PagasaBand.values) {
    if (hiC >= b.fromC) hit = b;
  }
  return hit;
}

/// One day's heat values exactly as `power_prep.process` stores them.
class DailyHeat {
  const DailyHeat({required this.rhTmax, required this.hi, required this.category});

  /// `RH_TMAX`, %, rounded to 1 dp.
  final double rhTmax;

  /// `HI`, deg C, computed from the 1-dp RH and rounded to 1 dp.
  final double hi;

  /// `HI_CAT` of the rounded [hi].
  final PagasaBand? category;
}

/// `process`: RH at Tmax (1 dp) -> heat index (1 dp) -> PAGASA band.
DailyHeat dailyHeat(double tmax, double tdew) {
  final rh = roundHalfEven(rhAtTmax(tmax, tdew), 1);
  final hi = roundHalfEven(heatIndexC(tmax, rh), 1);
  return DailyHeat(rhTmax: rh, hi: hi, category: pagasaCategory(hi));
}
