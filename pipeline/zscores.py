"""Step 2: monthly anomalies and drought indices (spec F1-F4).

Usage:
    python pipeline/zscores.py guimba munoz bongabon
    # reads  pipeline/data/processed/power_<muni>.csv   (output of power_prep.py)
    # writes pipeline/data/processed/monthly_<muni>.csv

Every index is computed per calendar month with LEAVE-ONE-YEAR-OUT parameters:
the year being scored is never part of its own baseline (spec F1).

  SPI-k  : gamma fit to k-month rain totals + zero-rain probability
           (McKee et al. 1993; WMO 2012, WMO-No. 1090).
  SPEI-k : 3-parameter log-logistic fit to k-month (P - ET0) by probability-
           weighted moments (Vicente-Serrano et al. 2010).
           Falls back to an empirical (Gringorten) index where the fit fails.
  z_sm   : robust z of monthly mean GWETROOT, (x - median) / (1.4826 MAD);
           SD instead of MAD when values are pinned (e.g. 1.0 in wet months);
           clipped to [-3.5, 3.5].
  D      : dryness index, higher = drier: D = 0.5 * (-SPEI_k - z_sm)   (spec F4),
           k = 3 in the dry season (Nov-Apr), k = 1 otherwise.

LIMITS (state these in method.md and on the technician screen)

  1. In-sample check. The Nov-Apr / SPEI-3 rule was adopted after the Jan-Apr
     SPEI-1 version missed 2015-16. The known-drought gate (11 of 12 El Nino dry
     seasons at D >= 1 across Guimba, Munoz, Bongabon) shows the definition is
     reasonable, not that it has skill. Skill is tested out of sample by H1
     (lead over NDVI stress) and H2 (Fisher's exact test vs PSA yields).
  2. Smoothing trade-off. 3-month accumulation catches long droughts better but
     spreads a sharp one-month drought over its neighbours: 2023-24 peaks fell
     from 1.84 / 1.97 / 2.63 (SPEI-1) to 1.11 / 1.36 / 1.73 (SPEI-3).
     D_spei1 is kept in the output so both can be shown.
  3. Borderline result reported as is. Munoz 2015-16 reaches D = 0.99, below the
     threshold of 1. It is not rounded up and the threshold is not lowered.
  4. The dry-season window is a fixed choice. Nov-Apr follows the crop calendar
     and the citation above; it must not be re-tuned to make a test pass.
  5. Dry-season SPI-1 is bounded. In near-zero-rain months SPI-1 cannot go far
     below Phi^-1(q) (q = share of zero months), so its monthly SD falls short of
     1 (up to 0.41 off at Munoz and Bongabon). This is expected (Wu et al. 2007).
  6. SPEI fallback. A few month-values (2-8 of 300 per town) use the empirical
     index because the log-logistic could not be fitted (negative skew).
  7. Soil term is modelled, not observed. GWETROOT comes from MERRA-2's land
     model driven by its own rainfall, so it is not independent of the rain
     signal and partly double-counts it. SMAP (2015+) is the observed check.
  8. Short baseline. 2001-2025 (25 years; 24 after leave-one-year-out) meets the
     WMO SPI minimum of 20-30 years but holds only about 7 El Nino dry seasons,
     so El Nino frequencies carry wide intervals (Wilson, spec F17).
  9. Rain is IMERG in UTC days. A late-night storm can fall on the neighbouring
     Philippine calendar day; monthly totals are barely affected.
 10. Coarse grid. Guimba and Munoz share one POWER cell for temperature and
     ET0, so only IMERG rain (0.1 deg) separates them. Bongabon's cell
     elevation (282 m) includes foothills, so its heat is likely understated
     for lowland fields.
 11. Labels cover dryness only. D <= -1 (unusually wet) still shows "normal";
     a wet label for onion rot or erosion would need to be added.
"""

import argparse
import sys
from math import gamma as G
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats

PROCESSED = Path("pipeline/data/processed")

# Dry season (Tag-araw) months. In these months single-month rain is near zero in
# most years, so SPI-1/SPEI-1 cannot go very negative; use the 3-month index instead
# (Wu et al., 2007, Int. J. Climatol. 27:65-79; WMO, 2012).
DRY_SEASON = (11, 12, 1, 2, 3, 4)


# ---------------------------------------------------------------- aggregation

def monthly(daily):
    """Daily POWER table -> monthly totals/means. Months with < 25 valid days -> NaN."""
    agg = pd.DataFrame({
        "rain_mm": daily["PRECTOTCORR"].resample("MS").sum(min_count=25),
        "et0_mm": daily["ET0"].resample("MS").sum(min_count=25),
        "tmax_c": daily["T2M_MAX"].resample("MS").mean(),
    })
    if "GWETROOT" in daily:
        agg["gwetroot"] = daily["GWETROOT"].resample("MS").mean()
    agg["wb_mm"] = agg["rain_mm"] - agg["et0_mm"]
    return agg


def accumulate(s, k):
    return s.rolling(k, min_periods=k).sum()


# ---------------------------------------------------------------- distributions

def spi_value(x, ref):
    """F2. x = target total, ref = baseline totals for the same calendar month (target excluded)."""
    ref = np.asarray(ref, float)
    ref = ref[~np.isnan(ref)]
    if np.isnan(x) or len(ref) < 10:
        return np.nan
    q = np.mean(ref == 0)
    pos = ref[ref > 0]
    if len(pos) < 5:
        return np.nan
    a, _, scale = stats.gamma.fit(pos, floc=0)
    h = q + (1 - q) * stats.gamma.cdf(x, a, loc=0, scale=scale) if x > 0 else q
    h = np.clip(h, 1e-6, 1 - 1e-6)
    return float(stats.norm.ppf(h))


def loglogistic_pwm(ref):
    """Vicente-Serrano et al. (2010): log-logistic parameters from PWMs w0, w1, w2."""
    x = np.sort(np.asarray(ref, float))
    n = len(x)
    f = (np.arange(1, n + 1) - 0.35) / n
    w0 = np.mean(x)
    w1 = np.mean((1 - f) * x)
    w2 = np.mean((1 - f) ** 2 * x)
    beta = (2 * w1 - w0) / (6 * w1 - w0 - 6 * w2)
    if not np.isfinite(beta) or beta <= 1:
        return None
    g = G(1 + 1 / beta) * G(1 - 1 / beta)
    alpha = (w0 - 2 * w1) * beta / g
    gam = w0 - alpha * g
    return alpha, beta, gam


def empirical_index(x, ref):
    """Non-parametric standardized index: Gringorten plotting position of x within
    ref + {x}, mapped to a normal quantile (Farahmand & AghaKouchak, 2015). Used when
    the log-logistic cannot be fitted, e.g. negatively skewed dry-season balances."""
    allv = np.r_[ref, x]
    n = len(allv)
    rank = stats.rankdata(allv, method="average")[-1]
    return float(stats.norm.ppf((rank - 0.44) / (n + 0.12)))


FALLBACKS = {"spei": 0}


def spei_value(x, ref):
    """F3. x = target water balance (mm), ref = baseline for the same month."""
    ref = np.asarray(ref, float)
    ref = ref[~np.isnan(ref)]
    if np.isnan(x) or len(ref) < 10:
        return np.nan
    p = loglogistic_pwm(ref)
    if p is None:
        FALLBACKS["spei"] += 1
        return empirical_index(x, ref)
    alpha, beta, gam = p
    if x <= gam:
        f = 1e-6
    else:
        f = 1 / (1 + (alpha / (x - gam)) ** beta)
    return float(stats.norm.ppf(np.clip(f, 1e-6, 1 - 1e-6)))


def robust_z(x, ref):
    ref = np.asarray(ref, float)
    ref = ref[~np.isnan(ref)]
    if np.isnan(x) or len(ref) < 10:
        return np.nan
    med = np.median(ref)
    scale = 1.4826 * np.median(np.abs(ref - med))
    if scale < 1e-9:                       # e.g. GWETROOT pinned at 1.0 in wet months
        scale = np.std(ref, ddof=1)
    if scale < 1e-9:
        return np.nan
    return float(np.clip((x - med) / scale, -3.5, 3.5))   # same bound as SPI tables


def loo_index(series, fn):
    """Apply fn(x, baseline) with leave-one-year-out baselines per calendar month (F1)."""
    out = pd.Series(np.nan, index=series.index)
    for m in range(1, 13):
        s = series[series.index.month == m]
        for t, x in s.items():
            out[t] = fn(x, s.drop(t).values)
    return out


# ---------------------------------------------------------------- pipeline

def label(d):
    if np.isnan(d):
        return ""
    return "delikado" if d >= 2 else "bantay" if d >= 1 else "normal"


def build(daily):
    m = monthly(daily)
    m["spi1"] = loo_index(m["rain_mm"], spi_value)
    m["spi3"] = loo_index(accumulate(m["rain_mm"], 3), spi_value)
    m["spei1"] = loo_index(m["wb_mm"], spei_value)
    m["spei3"] = loo_index(accumulate(m["wb_mm"], 3), spei_value)
    m["z_tmax"] = loo_index(m["tmax_c"], robust_z)
    # climate term: SPEI-3 in the dry season, SPEI-1 otherwise
    ds = m.index.month.isin(DRY_SEASON)
    m["spei_d"] = np.where(ds, m["spei3"], m["spei1"])
    m["spei_d_k"] = np.where(ds, 3, 1)
    if "gwetroot" in m:
        m["z_sm"] = loo_index(m["gwetroot"], robust_z)
        m["D"] = 0.5 * (-m["spei_d"] - m["z_sm"])
        # where the soil term is undefined, fall back to the climate term alone (spec F4)
        m["D"] = m["D"].fillna(-m["spei_d"])
        m["D_spei1"] = 0.5 * (-m["spei1"] - m["z_sm"])     # old definition, kept for comparison
    else:
        m["D"] = -m["spei_d"]
        m["D_spei1"] = -m["spei1"]
    m["label"] = m["D"].map(label)
    # "driest r of n years" for that calendar month (r = 1 is the driest)
    m["dry_rank"] = m.groupby(m.index.month)["D"].rank(ascending=False, method="min")
    m["dry_n"] = m.groupby(m.index.month)["D"].transform("count")
    return m.round(3)


def report(name, m, n_fallback=0, enso=None):
    print(f"\n== {name} ==  {m.index.min():%Y-%m} to {m.index.max():%Y-%m}")
    if n_fallback:
        print(f"SPEI: {n_fallback} month-values used the empirical fallback "
              f"(log-logistic not fittable); note this in method.md")
    cols = [c for c in ["spi1", "spi3", "spei1", "spei3", "z_sm", "D"] if c in m]
    g = m.groupby(m.index.month)[cols]
    mean_dev = g.mean().abs().max()
    sd_dev = (g.std() - 1).abs().max()
    print("worst |monthly mean| (gate ~0, LOO gives slight spread):",
          ", ".join(f"{c} {mean_dev[c]:.2f}" for c in cols))
    print("worst |monthly SD - 1|:", ", ".join(f"{c} {sd_dev[c]:.2f}" for c in cols if c != "z_sm"),
          "(z_sm is robust, SD need not be 1)")
    if enso is None or enso.empty:
        print("  (no enso_dryseason.csv: run pipeline/enso.py for the El Nino check)")
    else:
        rows = []
        for r in enso.itertuples():
            y = r.harvest_year
            sub = m.loc[f"{y - 1}-11":f"{y}-04"]
            if sub["D"].notna().sum() < 6:
                continue                      # season not fully inside the record
            rows.append((r.dry_season, r.tag_episode, sub["D"].max(), sub["D"].idxmax()))
        el = [x for x in rows if x[1] == "el_nino"]
        hits = sum(mx >= 1 for _, _, mx, _ in el)
        print("  El Nino dry season (Nov-Apr, NOAA episode rule)   max D")
        for tag, _, mx, when in el:
            print(f"  {tag}: {mx:5.2f} in {when:%Y-%m} ({'pass' if mx >= 1 else 'below 1'})")
        for kind in ("el_nino", "neutral", "la_nina"):
            v = [mx for _, k, mx, _ in rows if k == kind]
            if v:
                share = sum(x >= 1 for x in v) / len(v)
                print(f"  {kind:8s}: {len(v):2d} seasons, mean max D {np.mean(v):5.2f}, "
                      f"{share:4.0%} reach D >= 1")
        need = int(np.ceil(0.75 * len(el)))
        print(f"known-drought gate: {hits}/{len(el)} El Nino dry seasons reach D >= 1 "
              f"(gate >= {need}) -> {'PASS' if hits >= need else 'CHECK'}")
    now = m.dropna(subset=["D"]).iloc[-1]
    print(f"latest {now.name:%Y-%m}: D = {now.D:.2f} ({now.label}), "
          f"driest {int(now.dry_rank)} of {int(now.dry_n)} years for this month")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("munis", nargs="+")
    ap.add_argument("--dir", default=str(PROCESSED))
    a = ap.parse_args(argv)
    d = Path(a.dir)
    ef = d / "enso_dryseason.csv"
    enso = pd.read_csv(ef) if ef.exists() else None
    for name in a.munis:
        daily = pd.read_csv(d / f"power_{name}.csv", index_col="date", parse_dates=True)
        FALLBACKS["spei"] = 0
        m = build(daily)
        m.index.name = "month"
        m.to_csv(d / f"monthly_{name}.csv")
        report(name, m, FALLBACKS["spei"], enso)
    return 0


if __name__ == "__main__":
    sys.exit(main())