"""Step 7: uncertainty (spec F17): Wilson intervals and a Monte Carlo over the inputs.

Usage:
    python pipeline/uncertainty.py guimba munoz bongabon            # N = 200 runs
    python pipeline/uncertainty.py --n 50 guimba                     # quicker
    # reads  power_<muni>.csv, bucket_<muni>.csv, soil.csv, enso_dryseason.csv,
    #        outcomes_<muni>.csv (fsm.py), raw/crops.csv
    # writes pipeline/data/processed/risk_<muni>.csv   (one row per crop x water scenario)

Two kinds of uncertainty, reported side by side:

1. SAMPLING (few years). From fsm.py's single best-estimate run: failed seasons X of Y,
   with a Wilson (1927) 95% interval, for all seasons, El Nino seasons and other seasons.
   "Failed in 5 of 9 El Nino years" has an interval of 27-79%: that range goes on the card.

2. PARAMETERS (Monte Carlo, N runs). Each run draws, per crop:
     root depth, Kc ini/mid/end, duration, T_base, yield, price,
     production cost                                              uniform on [low, high]
                                                                  in crops.csv; onion price
                                                                  triangular (skewed series)
     sowing day                                                   uniform 16 Nov - 16 Dec
     Ks_fail                                                      uniform 0.4 - 0.6 (+-20%)
     K_fail                                                       integer 8 - 12 days (+-20%)
   and replays every dry season with the vectorised field machine (same rules as fsm.py;
   test_uncertainty.py checks run-for-run parity). Reported: p10 / p50 / p90 across runs of
   the El Nino and other-season failure rates, irrigation need and income.

RISK = share of seasons that FAILED (spec F14, revised): "stressed" (>= 1 stressed day) is
true in almost every rainfed season and cannot separate crops. Stress days are kept as a
separate, graded figure.

INCOME per ha per season: gross = yield [t/ha] x 1000 x farmgate price [PHP/kg] in a season
that did not fail, 0 in a failed season; net = gross - total production cost (cost_php_ha in
crops.csv, PSA costs and returns; paid even when the crop fails). No partial yield loss from
stress short of failure (see Known limits).
"""

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

if __package__ in (None, ""):                      # run as `python pipeline/uncertainty.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pipeline.fsm import WATER, stage_fractions                          # noqa: E402
from pipeline.soil_water import (awc_for_depth, bucket_step, load_crops,  # noqa: E402
                                 p_adjusted)

PROC = Path("pipeline/data/processed")
Z95 = 1.959964


# ---------------------------------------------------------------- Wilson (F17)

def wilson(x, n, z=Z95):
    """Wilson score interval for x successes in n trials -> (low, high). (nan, nan) if n = 0."""
    if n == 0:
        return float("nan"), float("nan")
    p = x / n
    den = 1 + z * z / n
    mid = (p + z * z / (2 * n)) / den
    half = z * np.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return max(0.0, mid - half), min(1.0, mid + half)


# ---------------------------------------------------------------- vectorised M_F

PREP, ESTAB, VEG, REPRO, MATURE, HARVEST, FAILED, DONE = 1, 2, 3, 4, 5, 6, 7, 0


def gdd_vec(tmax, tmin, t_base):
    return np.maximum(0.0, (tmax + np.maximum(tmin, t_base)) / 2.0 - t_base)


def simulate_runs(tmax, tmin, P, et0, prm, d_prep=0):
    """Field machine for R runs at once. Weather arrays are (days, R), already aligned so that
    row 0 is each run's sowing day. prm: dict of (R,) arrays: taw p kc_ini kc_mid kc_end
    t_base g_mat f_e f_v f_r t_crit (nan = none) irrigated (bool) max_irr (inf = as needed)
    ks_fail k_fail s0. Returns a dict of (R,) outcome arrays. Mirrors FieldMachine exactly."""
    D, R = tmax.shape
    q = np.full(R, PREP)
    d = np.zeros(R, int)
    G = np.zeros(R)
    S = prm["s0"].astype(float).copy()
    ksev = np.zeros(R, int)
    kw = np.zeros(R, int)
    kh = np.zeros(R, int)
    n_irr = np.zeros(R, int)
    irr = np.zeros(R)
    harvest_day = np.full(R, np.nan)
    failed = np.zeros(R, bool)
    for t in range(D):
        active = q != DONE
        if not active.any():
            break
        grow = (q >= PREP) & (q <= MATURE)
        G = np.where(grow, G + gdd_vec(tmax[t], tmin[t], prm["t_base"]), G)
        d = np.where(active, d + 1, d)
        g = G / prm["g_mat"]
        kc = np.select(
            [q <= ESTAB, q == VEG, q == REPRO, q == MATURE],
            [prm["kc_ini"],
             prm["kc_ini"] + (g - prm["f_e"]) / (prm["f_v"] - prm["f_e"]) * (prm["kc_mid"] - prm["kc_ini"]),
             prm["kc_mid"],
             prm["kc_mid"] + np.minimum(1.0, (g - prm["f_r"]) / (1 - prm["f_r"])) * (prm["kc_end"] - prm["kc_mid"])],
            0.0)
        can = grow & prm["irrigated"] & (n_irr < prm["max_irr"])
        pa = p_adjusted(prm["p"], kc * et0[t])
        I = np.where(can & (S < (1.0 - pa) * prm["taw"]), prm["taw"] - S, 0.0)
        n_irr += I > 0
        S_new, eta, dp, ks = bucket_step(S, P[t], I, et0[t], kc, prm["taw"], prm["p"])
        S = np.where(grow, S_new, S)
        irr += np.where(grow, I, 0.0)
        sens = grow & ((q == VEG) | (q == REPRO))
        kw += sens & (ks < 1)
        ksev = np.where(grow, np.where(sens & (ks < prm["ks_fail"]), ksev + 1, 0), ksev)
        kh += grow & (q == REPRO) & (tmax[t] >= prm["t_crit"])
        # transitions by priority (one per run)
        new = q.copy()
        fail = (q >= ESTAB) & (q <= MATURE) & (ksev >= prm["k_fail"])
        new = np.where(fail, FAILED, new)
        rest = ~fail
        new = np.where(rest & (q == PREP) & (d >= d_prep), ESTAB, new)
        new = np.where(rest & (q == ESTAB) & (G >= prm["f_e"] * prm["g_mat"]), VEG, new)
        new = np.where(rest & (q == VEG) & (G >= prm["f_v"] * prm["g_mat"]), REPRO, new)
        new = np.where(rest & (q == REPRO) & (G >= prm["f_r"] * prm["g_mat"]), MATURE, new)
        harv = rest & (q == MATURE) & (G >= prm["g_mat"])
        new = np.where(harv, HARVEST, new)
        harvest_day = np.where(harv, t, harvest_day)
        new = np.where((q == HARVEST) | (q == FAILED), DONE, new)
        failed |= fail
        d = np.where(new != q, 0, d)
        q = new
    return {"failed": failed, "harvest_day": harvest_day, "stress_days": kw, "heat_days": kh,
            "irrigation_mm": irr, "irrigations": n_irr, "matured": q == DONE}


# ---------------------------------------------------------------- Monte Carlo draws

def draw(c, crop, n, rng):
    """Per-run parameter draws for one crop -> dict of (n,) arrays."""
    u = lambda k: rng.uniform(c[k][1], c[k][2], n) if c[k][2] > c[k][1] else np.full(n, c[k][0])
    out = {k: u(k) for k in ("root_depth_m", "kc_ini", "kc_mid", "kc_end", "duration_days",
                             "t_base_c", "yield_t_ha")}
    v, lo, hi = c["price_php_kg"]                  # crops.csv tuples are (value, low, high)
    out["price"] = (rng.triangular(lo, v, hi, n) if crop == "onion" and hi > lo
                    else rng.uniform(lo, hi, n) if hi > lo else np.full(n, v))
    lo_c, hi_c = c["cost_php_ha"][1], c["cost_php_ha"][2]
    out["cost"] = rng.uniform(lo_c, hi_c, n) if hi_c > lo_c else np.full(n, c["cost_php_ha"][0])
    out["sow_day"] = rng.integers(int(c["sow_day"][1]), int(c["sow_day"][2]) + 1, n)
    out["ks_fail"] = rng.uniform(0.4, 0.6, n)
    out["k_fail"] = rng.integers(8, 13, n)
    return out


def central(c, crop, n=1):
    """The single best-estimate run (every parameter at its value) as draw-shaped arrays."""
    out = {k: np.full(n, c[k][0]) for k in ("root_depth_m", "kc_ini", "kc_mid", "kc_end",
                                            "duration_days", "t_base_c", "yield_t_ha")}
    out.update(price=np.full(n, c["price_php_kg"][0]), cost=np.full(n, c["cost_php_ha"][0]), sow_day=np.full(n, int(c["sow_day"][0])),
               ks_fail=np.full(n, 0.5), k_fail=np.full(n, 10))
    return out


def windows(arr, starts, length):
    """(length, R) slices of a 1-D daily array starting at each run's start index."""
    idx = starts[None, :] + np.arange(length)[:, None]
    return arr[idx]


def town_mc(daily, soil_row, ref_frac, c, crop, dr, years, en_years, water):
    """One crop x water scenario over all seasons for the drawn runs dr.
    Returns per-run arrays: fail rate (El Nino / other), median irrigation, mean income."""
    irrigated, max_irr = WATER[water]
    n = len(dr["sow_day"])
    f_e, f_v, f_r = stage_fractions(c)
    taw = np.array([awc_for_depth(soil_row, z) for z in dr["root_depth_m"]]) * dr["root_depth_m"]
    dur = np.round(dr["duration_days"]).astype(int)
    D = int(dur.max() * 2)
    dates = daily.index
    tmax, tmin = daily.T2M_MAX.values, daily.T2M_MIN.values
    P, et0 = daily.PRECTOTCORR.values, daily.ET0.values
    nov1 = {y: dates.get_loc(pd.Timestamp(f"{y}-11-01")) for y in years}
    usable = [y for y in years if nov1[y] + 45 + D <= len(dates)]
    # G_mat per run: duration x mean daily GDD from that run's sowing day, over the baseline
    gsum = np.zeros(n)
    for y in usable:
        st = nov1[y] + dr["sow_day"]
        gw = gdd_vec(windows(tmax, st, dur.max()), windows(tmin, st, dur.max()), dr["t_base_c"])
        gsum += np.where(np.arange(dur.max())[:, None] < dur[None, :], gw, 0).sum(0)
    g_mat = gsum / len(usable)
    prm = {"taw": taw, "p": np.full(n, c["p"][0]), "kc_ini": dr["kc_ini"], "kc_mid": dr["kc_mid"],
           "kc_end": dr["kc_end"], "t_base": dr["t_base_c"], "g_mat": g_mat,
           "f_e": np.full(n, f_e), "f_v": np.full(n, f_v), "f_r": np.full(n, f_r),
           "t_crit": np.full(n, c["t_crit_c"][0] if "t_crit_c" in c else np.nan),
           "irrigated": np.full(n, irrigated),
           "max_irr": np.full(n, np.inf if max_irr is None else max_irr), "ks_fail": dr["ks_fail"],
           "k_fail": dr["k_fail"]}
    fails, irrs, en = [], [], []
    ref = ref_frac.reindex(dates).values
    for y in usable:
        st = nov1[y] + dr["sow_day"]
        prm["s0"] = np.nan_to_num(ref[st], nan=0.5) * taw
        o = simulate_runs(windows(tmax, st, D), windows(tmin, st, D), windows(P, st, D),
                          windows(et0, st, D), prm)
        fails.append(o["failed"])
        irrs.append(o["irrigation_mm"])
        en.append(y in en_years)
    fails, irrs, en = np.array(fails), np.array(irrs), np.array(en)
    income = dr["yield_t_ha"] * 1000 * dr["price"] * (1 - fails)          # (seasons, runs)
    net = income - dr["cost"]                                                # cost is paid even if it fails
    return {"fail_en": fails[en].mean(0), "fail_other": fails[~en].mean(0),
            "irr_en": np.median(irrs[en], 0), "irr_other": np.median(irrs[~en], 0),
            "income_en": income[en].mean(0), "income_other": income[~en].mean(0),
            "net_en": net[en].mean(0), "net_other": net[~en].mean(0)}


def pct(a):
    return np.percentile(a, [10, 50, 90])


def risk_table(name, outcomes, daily, soil_row, ref_frac, crops, enso, n_runs, seed=7):
    d = daily[["T2M_MAX", "T2M_MIN", "PRECTOTCORR", "ET0"]].dropna()
    years = list(range(d.index.year.min(), d.index.year.max()))
    en_years = {int(s[:4]) for s in enso.loc[enso.tag_episode == "el_nino", "dry_season"]}
    rng = np.random.default_rng(seed)
    rows = []
    for crop, c in crops.items():
        dr = draw(c, crop, n_runs, rng)
        for water in WATER:
            o = outcomes[(outcomes.crop == crop) & (outcomes.water == water)]
            en = o.enso.eq("el_nino")
            row = {"muni": name, "crop": crop, "water": water}
            for lab, sub in (("all", o), ("en", o[en]), ("other", o[~en])):
                x, k = int(sub.failed.sum()), len(sub)
                lo, hi = wilson(x, k)
                row.update({f"fail_{lab}_x": x, f"fail_{lab}_n": k,
                            f"fail_{lab}_lo": round(lo, 3), f"fail_{lab}_hi": round(hi, 3)})
            row["stress_days_en_median"] = o[en].stress_days.median()
            row["irrigation_en_median"] = o[en].irrigation_mm.median()
            mc = town_mc(d, soil_row, ref_frac, c, crop, dr, years, en_years, water)
            for k, v in mc.items():
                p10, p50, p90 = pct(v)
                row.update({f"mc_{k}_p10": round(p10, 3), f"mc_{k}_p50": round(p50, 3),
                            f"mc_{k}_p90": round(p90, 3)})
            rows.append(row)
    return pd.DataFrame(rows)


def print_risk(name, t):
    print(f"\n{name}: failed seasons, El Nino (Wilson 95%) | Monte Carlo p10-p90 of the El Nino "
          "failure rate | irrigation and income in El Nino seasons (MC p50)")
    print("  crop          water       El Nino failed        MC rate     irrig mm   net PHP/ha (p10 / p50 / p90)")
    for r in t.itertuples():
        print(f"  {r.crop:12s}  {r.water:10s}  {r.fail_en_x}/{r.fail_en_n} "
              f"({r.fail_en_lo:4.0%}-{r.fail_en_hi:4.0%})   "
              f"{r.mc_fail_en_p10:4.0%}-{r.mc_fail_en_p90:4.0%}   {r.mc_irr_en_p50:7.0f}   "
              f"{r.mc_net_en_p10:10,.0f} /{r.mc_net_en_p50:9,.0f} /{r.mc_net_en_p90:9,.0f}")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("munis", nargs="+")
    ap.add_argument("--n", type=int, default=200)
    a = ap.parse_args(argv)
    soil = pd.read_csv(PROC / "soil.csv").set_index("muni")
    crops = load_crops()
    enso = pd.read_csv(PROC / "enso_dryseason.csv")
    for name in a.munis:
        daily = pd.read_csv(PROC / f"power_{name}.csv", index_col="date", parse_dates=True)
        ref = pd.read_csv(PROC / f"bucket_{name}.csv", index_col="date", parse_dates=True)
        out = pd.read_csv(PROC / f"outcomes_{name}.csv")
        t = risk_table(name, out, daily, soil.loc[name], ref.S_frac, crops, enso, a.n)
        t.to_csv(PROC / f"risk_{name}.csv", index=False)
        print_risk(name, t)
    print(f"\nN = {a.n} runs. Net = yield x price in seasons that did not fail, minus the PSA total "
          "cost per ha (paid even when the crop fails).")
    return 0


if __name__ == "__main__":
    sys.exit(main())