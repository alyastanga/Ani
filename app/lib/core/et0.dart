/// FAO-56 reference evapotranspiration (Eq. 4.1), a line-for-line port of
/// `pipeline/power_prep.py` (`sat_vp`, `extraterrestrial_ra`, `et0_pm`,
/// `et0_hargreaves`). Pure Dart: no Flutter imports.
///
/// Allen et al. (1998), FAO Irrigation and Drainage Paper 56, Eqs. 6-39 and 52.
/// Units: temperatures in deg C, solar radiation `rs` in MJ m-2 day-1 (POWER
/// AG community), wind `u2` in m/s at 2 m, elevation in m, ET0 in mm/day.
library;

import 'dart:math' as math;

/// FAO-56 Eq. 11: saturation vapour pressure at [t] deg C, kPa.
double satVp(double t) => 0.6108 * math.exp(17.27 * t / (t + 237.3));

/// FAO-56 Eq. 14: actual vapour pressure from dew point [tdew] deg C, kPa
/// (`ea = sat_vp(T2MDEW)` in `power_prep.process`).
double actualVp(double tdew) => satVp(tdew);

/// FAO-56 Eqs. 21-25: extraterrestrial radiation, MJ m-2 day-1, for latitude
/// [latDeg] (degrees) and day of year [doy].
double extraterrestrialRa(double latDeg, int doy) {
  final phi = latDeg * math.pi / 180;
  final dr = 1 + 0.033 * math.cos(2 * math.pi * doy / 365);
  final delta = 0.409 * math.sin(2 * math.pi * doy / 365 - 1.39);
  final ws = math.acos((-math.tan(phi) * math.tan(delta)).clamp(-1.0, 1.0));
  return 24 * 60 / math.pi *
      0.0820 *
      dr *
      (ws * math.sin(phi) * math.sin(delta) + math.cos(phi) * math.cos(delta) * math.sin(ws));
}

/// FAO-56 Penman-Monteith daily ET0 (Eq. 6), mm/day. G = 0 for daily steps.
///
/// [ea] is the actual vapour pressure (kPa), normally `actualVp(tdew)`.
double et0Pm({
  required double tmax,
  required double tmin,
  required double ea,
  required double rs,
  required double u2,
  required double latDeg,
  required int doy,
  required double elevM,
}) {
  final tmean = (tmax + tmin) / 2;
  final p = 101.3 * math.pow((293 - 0.0065 * elevM) / 293, 5.26); // Eq. 7
  final gamma = 0.000665 * p; // Eq. 8
  final es = (satVp(tmax) + satVp(tmin)) / 2; // Eq. 12
  final delta = 4098 * satVp(tmean) / math.pow(tmean + 237.3, 2); // Eq. 13
  final ra = extraterrestrialRa(latDeg, doy);
  final rso = (0.75 + 2e-5 * elevM) * ra; // Eq. 37
  final rns = 0.77 * rs; // Eq. 38
  final ratio = (rs / rso).clamp(0.25, 1.0);
  const sigma = 4.903e-9;
  final rnl = sigma *
      (math.pow(tmax + 273.16, 4) + math.pow(tmin + 273.16, 4)) /
      2 *
      (0.34 - 0.14 * math.sqrt(ea)) *
      (1.35 * ratio - 0.35); // Eq. 39
  final rn = rns - rnl; // Eq. 40
  final num = 0.408 * delta * rn + gamma * 900 / (tmean + 273) * u2 * (es - ea);
  return num / (delta + gamma * (1 + 0.34 * u2));
}

/// FAO-56 Eq. 52 (Hargreaves), mm/day. Cross-check only.
double et0Hargreaves({required double tmax, required double tmin, required double latDeg, required int doy}) {
  final ra = extraterrestrialRa(latDeg, doy);
  return 0.0023 * ((tmax + tmin) / 2 + 17.8) * math.sqrt(math.max(tmax - tmin, 0.0)) * 0.408 * ra;
}

/// Daily ET0 as stored in `power_<town>.csv` (`ET0` column): Penman-Monteith
/// with `ea` from the dew point, rounded to 2 dp like pandas `.round(2)`.
double et0Daily({
  required double tmax,
  required double tmin,
  required double tdew,
  required double rs,
  required double u2,
  required double latDeg,
  required int doy,
  required double elevM,
}) =>
    roundHalfEven(
        et0Pm(tmax: tmax, tmin: tmin, ea: actualVp(tdew), rs: rs, u2: u2, latDeg: latDeg, doy: doy, elevM: elevM),
        2);

/// Day of year (1..366) of [d], as pandas `Timestamp.day_of_year`.
int dayOfYear(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(d.year, 1, 1)).inDays + 1;

/// numpy / pandas `round(x, nd)`: scale, round half to even, unscale.
double roundHalfEven(double x, int nd) {
  if (!x.isFinite) return x;
  final s = math.pow(10, nd).toDouble();
  final y = x * s;
  final f = y.floorToDouble();
  final diff = y - f;
  double r;
  if (diff > 0.5) {
    r = f + 1;
  } else if (diff < 0.5) {
    r = f;
  } else {
    r = (f % 2 == 0) ? f : f + 1;
  }
  return r / s;
}
