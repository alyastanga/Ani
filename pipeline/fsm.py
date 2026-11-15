"""Step 6: field machine M_F (spec 5.4), simulated over every dry season.

Usage:
    python pipeline/fsm.py guimba munoz bongabon
    # reads  pipeline/data/processed/power_<muni>.csv   (T2M_MAX, T2M_MIN, PRECTOTCORR, ET0)
    #        pipeline/data/processed/soil.csv, bucket_<muni>.csv, enso_dryseason.csv
    #        pipeline/data/raw/crops.csv
    # writes pipeline/data/processed/outcomes_<muni>.csv  (one outcome record o per crop x season x water)
    #        pipeline/data/processed/traces_<muni>.csv    (every transition, for "Bakit?")

M_F = (Q, q0, V, v0, Sigma, Lambda, delta). One instance = one crop on one field.

  Q      Fallow, Prep, Estab, Veg, Repro, Mature, Harvest, Failed          (q0 = Fallow)
  V      crop c, days in state d, GDD G (F7), soil water S (F5), Ks,
         kappa_w (stress days in sensitive stages), kappa_sev (consecutive days with
         Ks < KS_FAIL in a sensitive stage), kappa_h (days Tmax >= T_crit in Repro),
         cumulative irrigation, ETa, drainage
  Sigma  daily tick x = (Tmax, Tmin, P, ET0), events sow(c), confirm_harvest
  Lambda Moore: stage, harvest window.  Mealy: water_stress, water_fail, heat_risk,
         rot_risk, harvest_ready, and the outcome record o at the end of a season

Step order on each tick (fixed, so the Python and app versions agree):
  1. G += GDD(x); d += 1
  2. Kc from the stage (FAO-56 curve in thermal time)
  3. one F5 step of S (irrigation first if the water source allows); Ks
  4. risk guards update counters and emit Mealy alerts (never change the stage)
  5. transition guards, lowest priority number wins:
       1  Estab..Mature  kappa_sev >= K_FAIL          -> Failed    water_fail
       3  Prep           d >= D_PREP                  -> Estab
       4  Estab          G >= f_e G_mat               -> Veg
       5  Veg            G >= f_v G_mat               -> Repro
       6  Repro          G >= f_r G_mat               -> Mature
       7  Mature         G >= G_mat and (confirm or simulating) -> Harvest  harvest_ready
       8  Harvest        tick                         -> Fallow    o
       9  Failed         tick                         -> Fallow    o (failed)
      10  any            otherwise                    -> same
     (guard 2, Fallow -> Prep, is the sow event.)
  Guard 1 outranks 3-7 and guard 10 is the complement of the rest: exactly one fires.

Parameters (crops.csv unless noted):
  f_e, f_v, f_r   cumulative FAO-56 Table 11 stage proportions (ini, +dev, +mid)
  G_mat           duration_days x the site's mean daily GDD from the sowing day, averaged
                  over the baseline years, so a normal year reproduces the guide duration (F8)
  T_base          t_base_c;  T_up: none (no published cap opened yet)
  T_crit          t_crit_c where present (rice only); other crops: no heat guard yet

WATER SCENARIOS (the farmer's answer to "how many times can you irrigate this dry season?"):
  rainfed 0, limited_2 at most 2, limited_4 at most 4, full as needed. Each irrigation
  refills the root zone to field capacity once stress begins (refill rule, soil_water.py).

DESIGN CHOICES (stated, swept in the Monte Carlo, not published values):
  D_PREP = 0       the sow date is the day the crop is in the ground
  KS_FAIL = 0.5    severe stress: Ks below 0.5
  K_FAIL = 10      failure after 10 consecutive severe-stress days in Veg or Repro
  SENSITIVE = Veg, Repro
  Rot risk: onion in Estab with 3-day rain >= that town's 98th percentile of 3-day rain.
  N balance (F12) is 0 until N_fix and grain N are added to crops.csv.
"""

import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

if __package__ in (None, ""):                      # run as `python pipeline/fsm.py`
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pipeline.soil_water import (awc_for_depth, bucket_step, load_crops, p_adjusted,  # noqa: E402
                                 refill_when_stressed, taw_mm)

RAW = Path("pipeline/data/raw")
PROC = Path("pipeline/data/processed")

STATES = ("Fallow", "Prep", "Estab", "Veg", "Repro", "Mature", "Harvest", "Failed")
GROWING = ("Estab", "Veg", "Repro", "Mature")
SENSITIVE = ("Veg", "Repro")
D_PREP, KS_FAIL, K_FAIL = 0, 0.5, 10
# Water scenarios = the farmer's answer to "How many times can you irrigate this dry season?"
# Each irrigation refills the root zone to field capacity once stress begins.
WATER = {"rainfed": (False, 0), "limited_2": (True, 2), "limited_4": (True, 4), "full": (True, None)}


# ---------------------------------------------------------------- F7

def gdd(tmax, tmin, t_base, t_up=None):
    """Daily growing degree days (McMaster & Wilhelm style, with optional upper cap)."""
    hi = tmax if t_up is None else min(tmax, t_up)
    return max(0.0, (hi + max(tmin, t_base)) / 2.0 - t_base)


def stage_fractions(c):
    L = np.array([c[k][0] for k in ("fao_l_ini", "fao_l_dev", "fao_l_mid", "fao_l_late")], float)
    cum = np.cumsum(L) / L.sum()
    return cum[0], cum[1], cum[2]                     # f_e, f_v, f_r


def g_mat_for_site(daily, c, years):
    """Mean GDD accumulated over duration_days from the sowing day, across baseline years."""
    tb, dur, sow = c["t_base_c"][0], int(round(c["duration_days"][0])), int(c["sow_day"][0])
    totals = []
    for y in years:
        start = pd.Timestamp(f"{y}-11-01") + pd.Timedelta(days=sow)
        w = daily.loc[start: start + pd.Timedelta(days=dur - 1)]
        if len(w) == dur:
            totals.append(sum(gdd(a, b, tb) for a, b in zip(w.T2M_MAX, w.T2M_MIN)))
    return float(np.mean(totals))


# ---------------------------------------------------------------- the machine

@dataclass
class Params:
    crop: str
    taw: float
    p: float
    kc_ini: float
    kc_mid: float
    kc_end: float
    t_base: float
    g_mat: float
    f_e: float
    f_v: float
    f_r: float
    t_crit: float = None
    t_up: float = None
    irrigated: bool = False
    max_irr: int = None            # cap on irrigation events per season (None = as needed)
    rot_p98: float = None
    d_prep: int = D_PREP
    ks_fail: float = KS_FAIL
    k_fail: int = K_FAIL


@dataclass
class FieldMachine:
    """M_F for one crop on one field. Call sow(), then tick() once per day."""
    prm: Params
    q: str = "Fallow"
    d: int = 0
    G: float = 0.0
    S: float = 0.0
    Ks: float = 1.0
    kw: int = 0
    ksev: int = 0
    ksev_max: int = 0
    kh: int = 0
    irr: float = 0.0
    n_irr: int = 0
    eta: float = 0.0
    dp: float = 0.0
    rain: float = 0.0
    day: int = 0
    rain3: list = field(default_factory=list)
    trace: list = field(default_factory=list)
    reason: str = ""
    harvest_day: int = None

    # -- events
    def sow(self, s0):
        assert self.q == "Fallow", "sow only from Fallow"
        self._go("Prep", "g2 sow")
        self.S = float(s0)

    # -- Kc in thermal time (FAO-56 Fig. 25 shape)
    def kc(self):
        p, g = self.prm, self.G / self.prm.g_mat
        if self.q in ("Prep", "Estab"):
            return p.kc_ini
        if self.q == "Veg":
            return p.kc_ini + (g - p.f_e) / (p.f_v - p.f_e) * (p.kc_mid - p.kc_ini)
        if self.q == "Repro":
            return p.kc_mid
        if self.q == "Mature":
            return p.kc_mid + min(1.0, (g - p.f_r) / (1 - p.f_r)) * (p.kc_end - p.kc_mid)
        return 0.0

    def _go(self, to, guard):
        self.trace.append((self.day, self.q, to, guard))
        self.q, self.d = to, 0

    # -- one daily tick; returns the list of Mealy outputs emitted
    def tick(self, tmax, tmin, P, et0, confirm_harvest=False, simulating=True):
        out = []
        p = self.prm
        if self.q in ("Fallow",):
            self.day += 1
            return out
        # 1. thermal time and days in state
        if self.q not in ("Harvest", "Failed"):
            self.G += gdd(tmax, tmin, p.t_base, p.t_up)
        self.d += 1
        # 2-3. water
        if self.q not in ("Harvest", "Failed"):
            kc = self.kc()
            I = 0.0
            if p.irrigated and (p.max_irr is None or self.n_irr < p.max_irr):
                I = float(refill_when_stressed(self.S, p.taw, p_adjusted(p.p, kc * et0)))
                self.n_irr += I > 0
            S, eta, dp, ks = bucket_step(self.S, P, I, et0, kc, p.taw, p.p)
            self.S, self.Ks = float(S), float(ks)
            self.irr += I
            self.eta += float(eta)
            self.dp += float(dp)
            self.rain += P
            # 4. risk guards (counters + Mealy alerts, no stage change)
            if self.q in SENSITIVE and self.Ks < 1:
                self.kw += 1
                out.append("water_stress")
            if self.q in SENSITIVE and self.Ks < p.ks_fail:
                self.ksev += 1
                self.ksev_max = max(self.ksev_max, self.ksev)
            else:
                self.ksev = 0
            if self.q == "Repro" and p.t_crit is not None and tmax >= p.t_crit:
                self.kh += 1
                out.append("heat_risk")
            self.rain3 = (self.rain3 + [P])[-3:]
            if (p.crop == "onion" and self.q == "Estab" and p.rot_p98 is not None
                    and len(self.rain3) == 3 and sum(self.rain3) >= p.rot_p98):
                out.append("rot_risk")
        # 5. transition guards by priority
        g = self.G
        if self.q in GROWING and self.ksev >= p.k_fail:                        # 1
            self.reason = f"{self.ksev} days with Ks < {p.ks_fail} in {self.q}"
            self._go("Failed", "g1 kappa_sev >= K_fail")
            out.append("water_fail")
        elif self.q == "Prep" and self.d >= p.d_prep:                          # 3
            self._go("Estab", "g3 d >= d_prep")
        elif self.q == "Estab" and g >= p.f_e * p.g_mat:                       # 4
            self._go("Veg", "g4 G >= f_e G_mat")
        elif self.q == "Veg" and g >= p.f_v * p.g_mat:                         # 5
            self._go("Repro", "g5 G >= f_v G_mat")
        elif self.q == "Repro" and g >= p.f_r * p.g_mat:                       # 6
            self._go("Mature", "g6 G >= f_r G_mat")
        elif self.q == "Mature" and g >= p.g_mat and (confirm_harvest or simulating):  # 7
            self.harvest_day = self.day
            self._go("Harvest", "g7 G >= G_mat")
            out.append("harvest_ready")
        elif self.q in ("Harvest", "Failed"):                                  # 8, 9
            self._go("Fallow", "g8 tick" if self.q == "Harvest" else "g9 tick")
            out.append("outcome")
        # 10: otherwise stay
        self.day += 1
        return out

    def outcome(self):
        failed = any(t[2] == "Failed" for t in self.trace)
        if failed:
            main = "water: " + self.reason
        elif self.kh:
            main = f"heat: {self.kh} days at flowering >= {self.prm.t_crit} C"
        elif self.kw:
            main = f"water: {self.kw} stressed days in Veg/Repro"
        else:
            main = "none"
        return {"failed": failed, "stressed": self.kw > 0, "stress_days": self.kw,
                "severe_run_max": self.ksev_max, "heat_days": self.kh,
                "irrigation_mm": round(self.irr, 1), "irrigations": self.n_irr, "eta_mm": round(self.eta, 1),
                "drainage_mm": round(self.dp, 1), "rain_mm": round(self.rain, 1),
                "harvest_day": self.harvest_day, "n_balance": 0.0, "main_reason": main}


# ---------------------------------------------------------------- simulation over seasons

def params_for(crop, c, soil_row, daily, years, irrigated, rot_p98, max_irr=None):
    zr = c["root_depth_m"][0]
    f_e, f_v, f_r = stage_fractions(c)
    return Params(crop=crop, taw=float(taw_mm(awc_for_depth(soil_row, zr), zr)), p=c["p"][0],
                  kc_ini=c["kc_ini"][0], kc_mid=c["kc_mid"][0], kc_end=c["kc_end"][0],
                  t_base=c["t_base_c"][0], g_mat=g_mat_for_site(daily, c, years),
                  f_e=f_e, f_v=f_v, f_r=f_r,
                  t_crit=c["t_crit_c"][0] if "t_crit_c" in c else None,
                  irrigated=irrigated, max_irr=max_irr, rot_p98=rot_p98)


def run_season(prm, w, s0_frac, max_factor=2.0):
    """Run M_F from the sowing day until it returns to Fallow (or max_factor x duration)."""
    m = FieldMachine(prm)
    m.sow(s0_frac * prm.taw)
    alerts = []
    for i, r in enumerate(w.itertuples()):
        out = m.tick(r.T2M_MAX, r.T2M_MIN, r.PRECTOTCORR, r.ET0)
        alerts += [(i, a) for a in out]
        if m.q == "Fallow":
            break
    o = m.outcome()
    o["matured"] = m.harvest_day is not None or o["failed"]
    return o, m.trace, alerts


def simulate_town(name, daily, soil_row, ref_frac, crops, enso=None):
    d = daily[["T2M_MAX", "T2M_MIN", "PRECTOTCORR", "ET0"]].dropna()
    years = list(range(d.index.year.min(), d.index.year.max()))
    rot_p98 = float(d.PRECTOTCORR.rolling(3).sum().quantile(0.98))
    tag = {} if enso is None else dict(zip(enso.dry_season, enso.tag_episode))
    rows, traces = [], []
    for crop, c in crops.items():
        dur = int(round(c["duration_days"][0]))
        for water, (irrigated, max_irr) in WATER.items():
            prm = params_for(crop, c, soil_row, d, years, irrigated, rot_p98, max_irr)
            for y in years:
                sow = pd.Timestamp(f"{y}-11-01") + pd.Timedelta(days=int(c["sow_day"][0]))
                w = d.loc[sow: sow + pd.Timedelta(days=int(2 * dur))]
                if len(w) < 2 * dur or sow not in ref_frac.index:
                    continue
                o, tr, al = run_season(prm, w, float(ref_frac.loc[sow]))
                ds = f"{y}-{str(y + 1)[-2:]}"
                rows.append({"muni": name, "crop": crop, "dry_season": ds, "sow": sow.date(),
                             "water": water,
                             "enso": tag.get(ds, ""), "g_mat": round(prm.g_mat, 1),
                             "guide_days": dur, **o,
                             "alerts": ";".join(sorted({a for _, a in al} - {"outcome"}))})
                traces += [{"muni": name, "crop": crop, "dry_season": ds,
                            "water": water,
                            "day": t[0], "from": t[1], "to": t[2], "guard": t[3]} for t in tr]
    return pd.DataFrame(rows), pd.DataFrame(traces)


def print_summary(name, out):
    print(f"\n{name}: {out.dry_season.nunique()} dry seasons x {out.crop.nunique()} crops x "
          f"{out.water.nunique()} water scenarios")
    print("  crop          water      failed (El Nino / other)  stress days (EN / other)  "
          "irrigations  heat days  harvest day vs guide")
    for (crop, water), g in out.groupby(["crop", "water"], sort=False):
        en = g.enso.eq("el_nino")
        f = lambda s: f"{int(s.sum())}/{len(s)}"
        hd = g.harvest_day.dropna()
        print(f"  {crop:12s}  {water:9s}  {f(g[en].failed):>6s} / {f(g[~en].failed):<7s}           "
              f"{g[en].stress_days.median():6.0f} / {g[~en].stress_days.median():<6.0f}       "
              f"{g.irrigations.median():5.0f}      {g.heat_days.median():5.0f}      {hd.median():5.0f} vs {g.guide_days.iloc[0]}"
              f" (MAE {np.abs(hd - g.guide_days.iloc[0]).mean():.1f} d)")


def main(argv=None):
    names = list(argv if argv is not None else sys.argv[1:])
    if not names:
        print(__doc__)
        return 1
    soil = pd.read_csv(PROC / "soil.csv").set_index("muni")
    crops = load_crops()
    ef = PROC / "enso_dryseason.csv"
    enso = pd.read_csv(ef) if ef.exists() else None
    for name in names:
        daily = pd.read_csv(PROC / f"power_{name}.csv", index_col="date", parse_dates=True)
        ref = pd.read_csv(PROC / f"bucket_{name}.csv", index_col="date", parse_dates=True)
        out, tr = simulate_town(name, daily, soil.loc[name], ref.S_frac, crops, enso)
        out.to_csv(PROC / f"outcomes_{name}.csv", index=False)
        tr.to_csv(PROC / f"traces_{name}.csv", index=False)
        print_summary(name, out)
    print("\nfailed = Ks < 0.5 for 10 days in a row in Veg/Repro (design choice, swept later). "
          "Heat days: rice only (T_crit 35 C).\nwater: rainfed = 0 irrigations; limited_2 / "
          "limited_4 = at most 2 / 4 refills; full = refill whenever stress starts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())