"""Step 4: daily root-zone water balance (spec F5) and paddy water layer (spec F6).

Usage:
    python pipeline/soil_water.py guimba munoz bongabon            # reference check run
    python pipeline/soil_water.py --crops guimba munoz bongabon    # every crop x dry season
    # reads  pipeline/data/processed/power_<muni>.csv   (power_prep.py: PRECTOTCORR, ET0, GWETROOT)
    #        pipeline/data/processed/soil.csv          (fetch_soilgrids.py: awc_mm_per_m_0_*)
    #        pipeline/data/raw/crops.csv               (root_depth_m, p, kc_*)
    #        pipeline/data/processed/enso_dryseason.csv (enso.py, --crops only)
    # writes pipeline/data/processed/bucket_<muni>.csv  (reference check run, see below)
    #        pipeline/data/processed/crop_seasons_<muni>.csv (--crops)

The functions are the physics only. Which Kc applies on a given day, and when a crop is
sown or harvested, is decided by the field machine M_F (fsm.py), which calls step().

Every step function accepts scalars or numpy arrays and broadcasts, so one call can
advance N Monte Carlo runs at once (e.g. TAW and p drawn per run, weather shared).

F5  FAO-56 bucket (Allen et al. 1998, Eqs. 82-85). S = water above wilting point (mm),
    0 <= S <= TAW; S = TAW is field capacity.
        TAW   = AWC [mm/m] * Zr [m]
        p_adj = clip(p + 0.04 (5 - ETc), 0.1, 0.8)
        Ks    = 1                       if S_m >= (1 - p_adj) TAW
                S_m / ((1 - p_adj) TAW) otherwise,   S_m = min(S + dt I, TAW)
                (irrigation is applied in the morning; rain is not, since its timing is unknown)
        ETa   = Ks Kc ET0
        S*    = S + dt (P + I - ETa)
        DP    = max(0, S* - TAW)        drainage below the roots, booked BEFORE the clamp
        S'    = clip(S*, 0, TAW)        if S* < 0 the shortfall is taken off ETa
    so the balance closes:  S0 + sum(P + I) - sum(ETa) - sum(DP) - S_end = 0.

F6  Paddy layer (rice). While ponded (h > 0) the soil is saturated (S = TAW), Ks = 1 and
    the pond takes the balance:
        h* = h + dt (P + I - Kc ET0 - SP)
        R  = max(0, h* - h_bund)        overflow runoff
        h' = clip(h*, 0, h_bund)        a negative h* is drawn from the soil
    SP (seepage + percolation) is booked as drainage. Without ponding the field is an
    F5 bucket, except that water above TAW is held by the bunds as new ponding.
    SP and h_bund have no default: they are site settings and must be passed in.

CHECK RUN (the CLI). A reference bucket per town: Kc = 1, Zr = 1.0 m on the 0-100 cm AWC,
p = 0.5, rainfed, 2001-2025. These are check settings, not crop parameters. The run must
close its water balance, and its monthly S/TAW anomalies are compared with GWETROOT's.
Both are driven by the same rain, so a high r shows the bucket behaves sensibly; it is
not independent skill. The independent test is H3 against SMAP.

CROP MODE (--crops). Every crop in crops.csv, every dry season 2001-02 .. 2024-25:
  - sown on sow_day (days after 1 Nov; 30 = 1 Dec), grown for duration_days;
  - Kc follows the FAO-56 four-stage curve (Fig. 25): Kc_ini over the initial stage,
    linear to Kc_mid over development, Kc_mid over mid-season, linear to Kc_end over the
    late stage. Stage lengths = FAO-56 Table 11 proportions scaled to duration_days;
  - TAW = AWC (SoilGrids layer reaching Zr) x Zr; p from crops.csv;
  - starting water S0 = the reference run's S/TAW on the sowing day x the crop's TAW,
    so each season starts from that year's real antecedent soil moisture;
  - two runs: rainfed (stress days, ET deficit) and irrigated with the refill rule
    (irrigation need in mm).
  Rice is run as an upland bucket here (no ponding, no percolation), so its irrigation
  figure is a LOWER BOUND; the paddy layer (F6) needs site SP and bund height.
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd

RAW = Path("pipeline/data/raw")
PROC = Path("pipeline/data/processed")


# ---------------------------------------------------------------- inputs

def load_crops(path=RAW / "crops.csv"):
    """crops.csv (long format) -> {crop: {param: (value, low, high)}}."""
    df = pd.read_csv(path)
    out = {}
    for r in df.itertuples():
        out.setdefault(r.crop, {})[r.param] = (float(r.value), float(r.low), float(r.high))
    return out


def awc_for_depth(soil_row, zr_m):
    """AWC (mm/m) of the shallowest SoilGrids layer that reaches the root depth.
    Falls back to the deepest available layer if the deeper one is missing."""
    cols = [(30, "awc_mm_per_m_0_30"), (60, "awc_mm_per_m_0_60"), (100, "awc_mm_per_m_0_100")]
    have = [(d, c) for d, c in cols if c in soil_row and pd.notna(soil_row[c])]
    if not have:
        raise ValueError("soil row has no AWC values")
    for d, c in have:
        if zr_m * 100 <= d:
            return float(soil_row[c])
    return float(soil_row[have[-1][1]])


def taw_mm(awc_mm_per_m, zr_m):
    return np.asarray(awc_mm_per_m, dtype=float) * np.asarray(zr_m, dtype=float)


# ---------------------------------------------------------------- F5

def p_adjusted(p, etc):
    """FAO-56 depletion fraction adjusted for evaporative demand, bounded 0.1-0.8."""
    return np.clip(np.asarray(p, dtype=float) + 0.04 * (5.0 - np.asarray(etc, dtype=float)), 0.1, 0.8)


def stress_coefficient(S, taw, p):
    """Ks: 1 above the readily available water, linear to 0 at wilting point."""
    S, taw, p = np.broadcast_arrays(*(np.asarray(x, dtype=float) for x in (S, taw, p)))
    thr = (1.0 - p) * taw
    with np.errstate(divide="ignore", invalid="ignore"):
        ks = np.where(S >= thr, 1.0, np.where(thr > 0, S / thr, 0.0))
    return np.clip(ks, 0.0, 1.0)


def bucket_step(S, P, I, ET0, Kc, taw, p, dt=1.0):
    """One Euler step of F5. Rates in mm/day, dt in days.
    Returns (S_new, ETa_mm, DP_mm, Ks) where the amounts are over the step."""
    etc = np.asarray(Kc, dtype=float) * np.asarray(ET0, dtype=float)
    # irrigation is applied at the start of the day, so it counts towards that day's Ks
    s_morning = np.minimum(np.asarray(S, float) + dt * np.asarray(I, float), taw)
    ks = stress_coefficient(s_morning, taw, p_adjusted(p, etc))
    eta = ks * etc * dt
    s_star = np.asarray(S, dtype=float) + dt * (np.asarray(P, float) + np.asarray(I, float)) - eta
    dp = np.maximum(0.0, s_star - taw)
    eta = eta + np.minimum(0.0, s_star)          # cannot use water that is not there
    s_new = np.clip(s_star, 0.0, taw)
    return s_new, eta, dp, ks


# ---------------------------------------------------------------- F6

def paddy_step(h, S, P, I, ET0, Kc, taw, p, SP, h_bund, dt=1.0):
    """One step of F6 for a bunded rice field.
    Returns (h_new, S_new, ETa_mm, DP_mm, R_mm, Ks)."""
    h = np.asarray(h, dtype=float)
    P, I = np.asarray(P, float), np.asarray(I, float)
    etc = np.asarray(Kc, float) * np.asarray(ET0, float)
    ponded = h > 0

    # ponded branch: soil saturated, pond takes the balance
    h_star = h + dt * (P + I - etc - SP)
    r_pond = np.maximum(0.0, h_star - h_bund)
    h_pond = np.clip(h_star, 0.0, h_bund)
    s_pond = np.clip(taw + np.minimum(0.0, h_star), 0.0, taw)     # deficit drawn from soil
    eta_pond = etc * dt + np.minimum(0.0, taw + np.minimum(0.0, h_star))
    dp_pond = np.broadcast_to(np.asarray(SP, float) * dt, h.shape).astype(float)

    # unponded branch: F5 bucket, but bunds hold water above TAW as ponding
    s_b, eta_b, excess, ks_b = bucket_step(S, P, I, ET0, Kc, taw, p, dt)
    h_b = np.minimum(excess, h_bund)
    r_b = excess - h_b

    h_new = np.where(ponded, h_pond, h_b)
    s_new = np.where(ponded, s_pond, s_b)
    eta = np.where(ponded, eta_pond, eta_b)
    dp = np.where(ponded, dp_pond, 0.0)
    r = np.where(ponded, r_pond, r_b)
    ks = np.where(ponded, 1.0, ks_b)
    return h_new, s_new, eta, dp, r, ks


# ---------------------------------------------------------------- irrigation rules

def refill_when_stressed(S, taw, p_adj):
    """Upland crop with a water source: refill to field capacity once Ks would drop below 1."""
    return np.where(S < (1.0 - p_adj) * taw, taw - S, 0.0)


def keep_flooded(h, h_min, h_target):
    """Continuous flooding: top the pond up to h_target when it falls below h_min."""
    return np.where(h < h_min, h_target - h, 0.0)


# ---------------------------------------------------------------- runner

def run_bucket(P, ET0, Kc, taw, p, S0=None, irrigate=False):
    """Daily F5 over a whole series. P, ET0: (days,). Kc: scalar, (days,) or (days, runs).
    taw, p: scalar or (runs,). Returns a dict of arrays shaped (days, ...)."""
    P, ET0 = np.asarray(P, float), np.asarray(ET0, float)
    n = len(P)
    Kc = np.asarray(Kc, float)
    if Kc.ndim == 0:
        Kc = np.full(n, float(Kc))
    shape = np.broadcast_shapes(np.shape(taw), np.shape(p), Kc.shape[1:])
    S = np.broadcast_to(np.asarray(taw if S0 is None else S0, float), shape).copy()
    keys = ("S", "ETa", "DP", "I", "Ks")
    out = {k: [] for k in keys}
    for t in range(n):
        etc = Kc[t] * ET0[t]
        I = refill_when_stressed(S, taw, p_adjusted(p, etc)) if irrigate else np.zeros_like(S)
        S, eta, dp, ks = bucket_step(S, P[t], I, ET0[t], Kc[t], taw, p)
        for k, v in zip(keys, (S, eta, dp, I, ks)):
            out[k].append(v)
    return {k: np.array(v) for k, v in out.items()}


def balance_error(S0, P, res):
    """S0 + sum(P + I) - sum(ETa) - sum(DP) - S_end; should be ~0 (mm)."""
    P = np.asarray(P, float)
    P_sum = P.sum() if res["S"].ndim == 1 else P.sum() * np.ones(res["S"].shape[1:])
    return S0 + P_sum + res["I"].sum(0) - res["ETa"].sum(0) - res["DP"].sum(0) - res["S"][-1]


# ---------------------------------------------------------------- crop mode

STAGES = ("fao_l_ini", "fao_l_dev", "fao_l_mid", "fao_l_late")


def stage_lengths(c, duration=None):
    """FAO-56 Table 11 proportions scaled to the crop's duration (days, floats)."""
    fao = np.array([c[k][0] for k in STAGES], dtype=float)
    d = c["duration_days"][0] if duration is None else duration
    return fao / fao.sum() * d


def kc_curve(lengths, kc_ini, kc_mid, kc_end):
    """Daily Kc for day 0..round(sum(lengths))-1, FAO-56 Fig. 25 (linear in dev and late)."""
    l1, l2, l3, l4 = lengths
    t = np.arange(int(round(sum(lengths)))) + 0.5                # middle of each day
    b1, b2, b3 = l1, l1 + l2, l1 + l2 + l3
    kc = np.where(t < b1, kc_ini,
         np.where(t < b2, kc_ini + (t - b1) / l2 * (kc_mid - kc_ini),
         np.where(t < b3, kc_mid,
                  kc_mid + (t - b3) / l4 * (kc_end - kc_mid))))
    return kc


def stage_of_day(lengths):
    """0 ini, 1 dev, 2 mid, 3 late for each day of the season."""
    t = np.arange(int(round(sum(lengths)))) + 0.5
    return np.searchsorted(np.cumsum(lengths)[:-1], t, side="right")


def crop_season(P, ET0, c, taw, s0_frac, irrigate):
    """One season of one crop. P, ET0: arrays from the sowing day, length >= duration."""
    L = stage_lengths(c)
    kc = kc_curve(L, c["kc_ini"][0], c["kc_mid"][0], c["kc_end"][0])
    n = len(kc)
    res = run_bucket(P[:n], ET0[:n], kc, taw, c["p"][0], S0=s0_frac * taw, irrigate=irrigate)
    etc = kc * ET0[:n]
    stage = stage_of_day(L)
    return {
        "stressed_days": int((res["Ks"] < 1).sum()),
        "mid_stressed_days": int(((res["Ks"] < 1) & (stage == 2)).sum()),
        "severe_days": int((res["Ks"] < 0.5).sum()),
        "et_deficit": float(1 - res["ETa"].sum() / etc.sum()),
        "irrigation_mm": float(res["I"].sum()),
        "etc_mm": float(etc.sum()),
        "rain_mm": float(np.sum(P[:n])),
    }


def crop_runs(name, daily, soil_row, ref_frac, crops, enso=None):
    """All crops x dry seasons for one town -> DataFrame (one row per crop, season, water)."""
    d = daily[["PRECTOTCORR", "ET0"]].dropna()
    rows = []
    for crop, c in crops.items():
        zr = c["root_depth_m"][0]
        taw = float(taw_mm(awc_for_depth(soil_row, zr), zr))
        dur = int(round(c["duration_days"][0]))
        for y in range(d.index.year.min(), d.index.year.max() + 1):
            sow = pd.Timestamp(f"{y}-11-01") + pd.Timedelta(days=int(c["sow_day"][0]))
            win = d[sow: sow + pd.Timedelta(days=dur - 1)]
            if len(win) < dur or sow not in ref_frac.index:
                continue
            for irrigate in (False, True):
                r = crop_season(win.PRECTOTCORR.values, win.ET0.values, c, taw,
                                float(ref_frac.loc[sow]), irrigate)
                rows.append({"muni": name, "crop": crop, "dry_season": f"{y}-{str(y + 1)[-2:]}",
                             "sow": sow.date(), "water": "irrigated" if irrigate else "rainfed",
                             "taw_mm": round(taw, 1), **r})
    out = pd.DataFrame(rows)
    if enso is not None and len(out):
        out = out.merge(enso[["dry_season", "tag_episode"]], on="dry_season", how="left")
        out = out.rename(columns={"tag_episode": "enso"})
    return out


def print_crop_summary(name, out):
    print(f"\n{name}: {out.dry_season.nunique()} dry seasons, sown "
          f"{out.sow.iloc[0]:%d %b} each year (median over seasons; El Nino = NOAA episode rule)")
    print("  crop          TAW   rainfed: stressed days   ET deficit    irrigated: water mm")
    print("                mm      all  El Nino  others    all  El Nino      all  El Nino  others")
    for crop, g in out.groupby("crop", sort=False):
        rf, ir = g[g.water == "rainfed"], g[g.water == "irrigated"]
        en = rf.enso == "el_nino" if "enso" in rf else pd.Series(False, index=rf.index)
        ien = ir.enso == "el_nino" if "enso" in ir else pd.Series(False, index=ir.index)
        print(f"  {crop:12s} {g.taw_mm.iloc[0]:4.0f}   {rf.stressed_days.median():5.0f} "
              f"{rf[en].stressed_days.median():7.0f} {rf[~en].stressed_days.median():7.0f}   "
              f"{rf.et_deficit.median():4.0%} {rf[en].et_deficit.median():7.0%}   "
              f"{ir.irrigation_mm.median():6.0f} {ir[ien].irrigation_mm.median():7.0f} "
              f"{ir[~ien].irrigation_mm.median():7.0f}")


# ---------------------------------------------------------------- check run (CLI)

REF = {"Kc": 1.0, "zr_m": 1.0, "p": 0.5}     # check settings, see module docstring


def check_town(name, daily, soil_row):
    awc = awc_for_depth(soil_row, REF["zr_m"])
    taw = float(taw_mm(awc, REF["zr_m"]))
    d = daily[["PRECTOTCORR", "ET0"]].dropna()
    res = run_bucket(d.PRECTOTCORR.values, d.ET0.values, REF["Kc"], taw, REF["p"], S0=taw)
    out = pd.DataFrame({"P": d.PRECTOTCORR.values, "ET0": d.ET0.values, "S": res["S"],
                        "S_frac": res["S"] / taw, "ETa": res["ETa"], "DP": res["DP"],
                        "Ks": res["Ks"]}, index=d.index)
    err = float(balance_error(taw, d.PRECTOTCORR.values, res))

    print(f"\n{name}: AWC {awc} mm/m, TAW {taw:.0f} mm (Zr {REF['zr_m']} m, Kc {REF['Kc']}, p {REF['p']})")
    print(f"  water balance error over {len(d)} days: {err:.2e} mm")
    m = out.resample("ME").agg({"P": "sum", "ET0": "sum", "ETa": "sum", "DP": "sum",
                                "S_frac": "mean", "Ks": lambda k: (k < 1).mean()})
    clim = m.groupby(m.index.month).mean()
    print("  month  P mm  ET0 mm  ETa mm  DP mm  S/TAW  stressed days")
    for mo, r in clim.iterrows():
        print(f"  {mo:>5} {r.P:5.0f} {r.ET0:7.0f} {r.ETa:7.0f} {r.DP:6.0f}  {r.S_frac:5.2f}  {r.Ks:5.0%}")
    if "GWETROOT" in daily:
        g = daily["GWETROOT"].resample("ME").mean()
        both = pd.concat([m.S_frac, g], axis=1, keys=["S", "G"]).dropna()
        anom = both.groupby(both.index.month).transform(lambda x: x - x.mean())
        r = anom.S.corr(anom.G)
        print(f"  monthly anomaly r(S/TAW, GWETROOT) = {r:.2f} "
              "(same rain drives both: a sanity check, not skill)")
    return out, err


def main(argv=None):
    names = list(argv if argv is not None else sys.argv[1:])
    crop_mode = "--crops" in names
    names = [n for n in names if n != "--crops"]
    if not names:
        print(__doc__)
        return 1
    soil = pd.read_csv(PROC / "soil.csv").set_index("muni")
    if crop_mode:
        crops = load_crops()
        ef = PROC / "enso_dryseason.csv"
        enso = pd.read_csv(ef) if ef.exists() else None
        for name in names:
            daily = pd.read_csv(PROC / f"power_{name}.csv", index_col="date", parse_dates=True)
            bf = PROC / f"bucket_{name}.csv"
            if bf.exists():
                ref = pd.read_csv(bf, index_col="date", parse_dates=True)
            else:
                ref, _ = check_town(name, daily, soil.loc[name])
            out = crop_runs(name, daily, soil.loc[name], ref.S_frac, crops, enso)
            out.to_csv(PROC / f"crop_seasons_{name}.csv", index=False)
            print_crop_summary(name, out)
        print("\nrice irrigation is a lower bound (upland bucket, no ponding/percolation)")
        return 0
    worst = 0.0
    for name in names:
        daily = pd.read_csv(PROC / f"power_{name}.csv", index_col="date", parse_dates=True)
        out, err = check_town(name, daily, soil.loc[name])
        out.to_csv(PROC / f"bucket_{name}.csv")
        worst = max(worst, abs(err))
    print(f"\nworst balance error {worst:.2e} mm -> {'PASS' if worst < 1e-6 else 'CHECK'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())