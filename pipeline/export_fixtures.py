"""Phase 0: golden fixtures for the Dart ports (docs/PLAN.md, Phase 2 parity tests).

Usage:
    python pipeline/export_fixtures.py [--out app/assets/fixtures]
    # reads  pipeline/data/processed/ only (risk_, outcomes_, power_, monthly_, bucket_<muni>.csv,
    #        soil.csv, enso_dryseason.csv) and pipeline/data/raw/crops.csv
    # writes <out>/planner.json, field_machine.json, numeric.json

Output is deterministic: fixed iteration order, floats rounded to NDP places, no timestamps,
so a re-run on the same processed data is byte-identical.

  planner.json        cases = grid of profiles -> planner.plan() output (state, trace, blocked,
                      weights, cards with scores, Bakit reasons, confidence, flags, Hold
                      message and blocking guard). Input risk table and heat share come from
                      the town's risk_/outcomes_ CSVs, i.e. the bundle's `risk` block.
  field_machine.json  town x crop x 3 seasons: Params, sow date, starting soil water, then one
                      row per day of inputs (tmax, tmin, P, ET0) and the machine's state and
                      Mealy outputs after FieldMachine.tick(), until it returns to Fallow.
  numeric.json        et0 (Penman-Monteith), heat_index (RH at Tmax, NWS index, PAGASA band),
                      zscores (robust z, SPEI log-logistic with rank fallback, D) sample rows.
"""

import argparse
import hashlib
import json
import sys
from dataclasses import asdict
from pathlib import Path

import numpy as np
import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pipeline import planner as P                                        # noqa: E402
from pipeline import power_prep as PP                                    # noqa: E402
from pipeline import zscores as Z                                        # noqa: E402
from pipeline.fsm import WATER, FieldMachine, params_for                  # noqa: E402
from pipeline.soil_water import load_crops                               # noqa: E402

PROC = Path("pipeline/data/processed")
RAW = Path("pipeline/data/raw")
OUT = Path("app/assets/fixtures")
SCHEMA = 1
NDP = 8
TOWNS = ("guimba", "munoz", "bongabon")
ELEV_M = {"guimba": 107.63, "munoz": 107.63, "bongabon": 282.04}      # fallback: POWER header

# planner grid: (last two crops, wont, cold storage, priorities). Crossed with every town,
# every water level and both seasons modes (El Nino as tagged, and normal).
WATERS = ("rainfed", "limited_2", "limited_4", "full")
COMBOS = [
    (["rice", "rice"], [], False, ["risk", "water", "income"]),
    (["rice", "rice"], [], False, ["income", "risk", "pest"]),
    (["rice", "mungbean"], [], False, ["income", "soil", "risk"]),
    (["maize", "onion"], [], True, ["income", "risk", "water"]),
    (["rice", "rice"], ["onion"], False, ["water", "soil", "pest"]),
    (["sweet_potato", "rice"], ["rice", "maize"], True, ["pest", "income"]),
    ([], [], False, []),
    (["mungbean"], ["mungbean", "sweet_potato", "onion"], False, ["risk"]),
]
FM_SEASONS = (("el_nino", "rainfed"), ("neutral", "limited_2"), ("la_nina", "full"))
FM_COLS = ["tmax", "tmin", "p", "et0", "q", "d", "G", "S", "Ks", "kw", "ksev", "kh",
           "irr", "n_irr", "eta", "dp", "alerts"]


# ---------------------------------------------------------------- helpers

def clean(v, nd=NDP):
    """JSON-safe, rounded, sorted copy (sets -> sorted lists, numpy -> python, NaN -> None)."""
    if isinstance(v, dict):
        return {str(k): clean(x, nd) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [clean(x, nd) for x in v]
    if isinstance(v, (set, frozenset)):
        return sorted(clean(x, nd) for x in v)
    if isinstance(v, (bool, np.bool_)):
        return bool(v)
    if isinstance(v, (int, np.integer)):
        return int(v)
    if isinstance(v, (float, np.floating)):
        if not np.isfinite(v):
            return None
        r = round(float(v), nd)
        return int(r) if r.is_integer() and abs(r) < 1e15 else r
    if isinstance(v, pd.Timestamp):
        return v.strftime("%Y-%m-%d")
    return v


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()[:16]


def header(kind, sources, extra=None):
    h = {"schema": SCHEMA, "kind": kind, "ndp": NDP,
         "generated_from": {"script": "pipeline/export_fixtures.py",
                            "sources": {str(p): sha(p) for p in sorted(sources, key=str)}}}
    h.update(extra or {})
    return h


def dump(doc, path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n",
                          encoding="utf-8")


# ---------------------------------------------------------------- planner

def planner_fixtures():
    el_nino_now, season = P.coming_season_el_nino()
    modes = [bool(el_nino_now), not bool(el_nino_now)]
    cases, towns = [], {}
    for muni in TOWNS:
        risk, hs = P.load_town(muni)
        towns[muni] = hs
        for water in WATERS:
            for last, wont, cold, prio in COMBOS:
                for en in modes:
                    prof = P.Profile(muni=muni, water=water, last=list(last), wont=set(wont),
                                     cold_storage=cold, priorities=list(prio))
                    res = P.plan(prof, risk, hs, en)
                    cases.append({
                        "id": f"{muni}|{water}|{'+'.join(last) or '-'}|{'+'.join(sorted(wont)) or '-'}"
                              f"|{'cold' if cold else 'nocold'}|{'>'.join(prio) or '-'}"
                              f"|{'en' if en else 'normal'}",
                        "profile": {"muni": muni, "water": water, "last": list(last),
                                    "wont": sorted(wont), "cold_storage": cold,
                                    "priorities": list(prio)},
                        "el_nino": en, "expect": clean(res)})
    src = [PROC / f"{k}_{m}.csv" for m in TOWNS for k in ("risk", "outcomes")] + [PROC / "enso_dryseason.csv"]
    hdr = header("planner", src, {
        "coming_season": season, "coming_season_el_nino": bool(el_nino_now),
        "constants": {"theta_f": P.THETA_F, "theta_h": P.THETA_H, "beta": P.BETA,
                      "ranked_share": P.RANKED_SHARE, "top": 3},
        "note": "heat_share is {crop|water: share of seasons with >=1 heat day at flowering}; "
                "risk rows are the town's risk_<muni>.csv (= bundle `risk` block)."})
    heat = {m: {f"{c}|{w}": round(float(v), NDP) for (c, w), v in sorted(towns[m].items())} for m in TOWNS}
    return {"header": hdr, "heat_share": heat, "cases": cases}


# ---------------------------------------------------------------- field machine

def pick_seasons(out):
    """3 deterministic (dry_season, enso tag, water) picks per crop: last El Nino, last neutral,
    last La Nina season on record (falls back to the last remaining season)."""
    picks = []
    seasons = sorted(out.dry_season.unique())
    used = set()
    for tag, water in FM_SEASONS:
        cand = sorted(out[out.enso == tag].dry_season.unique())
        cand = [s for s in cand if s not in used] or [s for s in seasons if s not in used]
        s = cand[-1]
        used.add(s)
        picks.append((s, tag, water))
    return picks


def field_machine_fixtures():
    soil = pd.read_csv(PROC / "soil.csv").set_index("muni")
    crops = load_crops()
    cases = []
    for muni in TOWNS:
        daily = pd.read_csv(PROC / f"power_{muni}.csv", index_col="date", parse_dates=True)
        ref = pd.read_csv(PROC / f"bucket_{muni}.csv", index_col="date", parse_dates=True)
        outc = pd.read_csv(PROC / f"outcomes_{muni}.csv")
        d = daily[["T2M_MAX", "T2M_MIN", "PRECTOTCORR", "ET0"]].dropna()
        years = list(range(d.index.year.min(), d.index.year.max()))
        rot = float(d.PRECTOTCORR.rolling(3).sum().quantile(0.98))
        for crop, c in crops.items():
            dur = int(round(c["duration_days"][0]))
            oc = outc[outc.crop == crop]
            for ds, tag, water in pick_seasons(oc):
                y = int(ds[:4])
                irrigated, max_irr = WATER[water]
                prm = params_for(crop, c, soil.loc[muni], d, years, irrigated, rot, max_irr)
                sow = pd.Timestamp(f"{y}-11-01") + pd.Timedelta(days=int(c["sow_day"][0]))
                w = d.loc[sow: sow + pd.Timedelta(days=2 * dur)]
                s0 = float(ref.loc[sow, "S_frac"])
                m = FieldMachine(prm)
                m.sow(s0 * prm.taw)
                rows = []
                for r in w.itertuples():
                    n_tr = len(m.trace)
                    out = m.tick(r.T2M_MAX, r.T2M_MIN, r.PRECTOTCORR, r.ET0)
                    rows.append([r.T2M_MAX, r.T2M_MIN, r.PRECTOTCORR, r.ET0, m.q, m.d, m.G, m.S, m.Ks,
                                 m.kw, m.ksev, m.kh, m.irr, m.n_irr, m.eta, m.dp, out])
                    if m.q == "Fallow":
                        break
                o = m.outcome()
                o["matured"] = m.harvest_day is not None or o["failed"]
                cases.append({
                    "id": f"{muni}|{crop}|{ds}|{water}", "muni": muni, "crop": crop, "dry_season": ds,
                    "enso": tag, "water": water, "sow": sow.strftime("%Y-%m-%d"),
                    "s0_frac": s0, "params": asdict(prm),
                    "columns": FM_COLS, "days": rows,
                    "transitions": [list(t) for t in m.trace],
                    "outcome": o})
    src = ([PROC / f"{k}_{m}.csv" for m in TOWNS for k in ("power", "bucket", "outcomes")]
           + [PROC / "soil.csv", RAW / "crops.csv"])
    hdr = header("field_machine", src, {
        "tick": "FieldMachine.tick(tmax, tmin, p, et0) with simulating=True, confirm_harvest=False; "
                "each day row = inputs then state AFTER the tick; `alerts` = Mealy outputs of that tick.",
        "state_fields": "q state, d days in state, G GDD, S soil water mm, Ks, kw stress days, "
                        "ksev consecutive severe days, kh heat days, irr mm, n_irr, eta mm, dp mm"})
    return {"header": hdr, "cases": cases}


# ---------------------------------------------------------------- numeric (ET0, heat, z, SPEI, D)

def town_site(muni):
    f = RAW / f"POWER_{muni.capitalize()}.csv"
    elev = ELEV_M[muni]
    if f.exists():
        elev = PP.read_power_csv(f)[1].get("elevation_m", elev)
    return PP.LAT[muni], float(elev)


def band(hi):
    return str(PP.pagasa_category(np.array([round(hi, 1)]))[0])


def spaced(index, n):
    """n deterministic, evenly spaced positions in 0..len-1."""
    return sorted({int(round(i)) for i in np.linspace(0, len(index) - 1, n)})


def et0_and_heat():
    et0, heat = [], []
    for muni in TOWNS:
        daily = pd.read_csv(PROC / f"power_{muni}.csv", index_col="date", parse_dates=True)
        d = daily.dropna(subset=["T2M_MAX", "T2M_MIN", "T2MDEW", "ALLSKY_SFC_SW_DWN", "WS2M"])
        lat, elev = town_site(muni)
        hot = d.HI.nlargest(4).index                                    # extreme-heat rows
        dry = d.RH_TMAX.nsmallest(3).index                              # low-RH adjustment region
        wet = d.RH_TMAX.nlargest(3).index                               # high-RH adjustment region
        pick = sorted(set(d.index[spaced(d.index, 24)]) | set(hot) | set(dry) | set(wet))
        for t in pick:
            r = d.loc[t]
            doy = int(t.day_of_year)
            ea = float(PP.sat_vp(r.T2MDEW))
            val = float(PP.et0_pm(r.T2M_MAX, r.T2M_MIN, ea, r.ALLSKY_SFC_SW_DWN, r.WS2M, lat, doy, elev))
            et0.append({"muni": muni, "date": t,
                        "in": {"tmax": r.T2M_MAX, "tmin": r.T2M_MIN, "tdew": r.T2MDEW,
                               "rs": r.ALLSKY_SFC_SW_DWN, "u2": r.WS2M, "lat": lat, "doy": doy,
                               "elev": elev},
                        "ea": ea, "ra": float(PP.extraterrestrial_ra(lat, doy)),
                        "expect": {"et0": val, "et0_rounded": round(val, 2), "et0_csv": r.ET0,
                                   "et0_harg": float(PP.et0_hargreaves(r.T2M_MAX, r.T2M_MIN, lat, doy))}})
            rh = float(PP.rh_at_tmax(r.T2M_MAX, r.T2MDEW))
            hi = float(PP.heat_index_c(r.T2M_MAX, round(rh, 1)))
            heat.append({"muni": muni, "date": t, "in": {"tmax": r.T2M_MAX, "tdew": r.T2MDEW},
                         "expect": {"rh_tmax": rh, "rh_tmax_rounded": round(rh, 1),
                                    "hi": hi, "hi_rounded": round(hi, 1),
                                    "hi_csv": r.HI, "category": band(hi)}})
    # synthetic rows that hit every branch of the NWS regression and every PAGASA edge
    for i, (t, rh) in enumerate([(25, 60), (26.5, 50), (30, 40), (32, 12), (36, 10), (40, 12), (30, 90),
                                 (28, 88), (27, 86), (33, 50), (35, 70), (38, 55), (41, 60), (44, 60),
                                 (47, 70), (50, 80), (52, 80), (20, 50), (45, 5)]):
        hi = float(PP.heat_index_c(t, rh))
        heat.append({"muni": "synthetic", "date": None, "in": {"tmax": t, "rh": rh},
                     "expect": {"hi": hi, "hi_rounded": round(hi, 1),
                                "category": band(hi)}})
    return et0, heat


def zscore_rows():
    rows = []
    for muni in TOWNS:
        daily = pd.read_csv(PROC / f"power_{muni}.csv", index_col="date", parse_dates=True)
        mon = pd.read_csv(PROC / f"monthly_{muni}.csv", index_col="month", parse_dates=True)
        m = Z.monthly(daily)
        series = {"wb1": m["wb_mm"], "wb3": Z.accumulate(m["wb_mm"], 3), "gwet": m["gwetroot"]}
        years = sorted(set(m.index.year))
        sel_years = [years[4], years[15], years[-2]]
        fall = []                                           # rows that use the rank fallback
        for t in m.index:
            s = series["wb3"]
            sub = s[s.index.month == t.month]
            if pd.notna(s[t]) and Z.loglogistic_pwm(sub.drop(t).dropna().values) is None:
                fall.append(t)
        pick = sorted({t for t in m.index if t.year in sel_years} | set(fall[:4]) | set(fall[-2:]))
        for t in pick:
            dry = t.month in Z.DRY_SEASON
            k = 3 if dry else 1
            wb = series["wb3"] if dry else series["wb1"]
            row = {"muni": muni, "month": t.strftime("%Y-%m"), "dry_season": dry, "k": k}

            def ref_of(s):
                x = s[t]
                ref = s[s.index.month == t.month].drop(t).dropna().values
                return (None if pd.isna(x) else float(x)), [float(v) for v in ref]

            x, ref = ref_of(wb)
            row["spei"] = {"x": x, "ref": ref,
                           "expect": None if x is None else Z.spei_value(x, ref),
                           "fallback": bool(len(ref) >= 10 and Z.loglogistic_pwm(np.array(ref)) is None)}
            xs, refs = ref_of(series["gwet"])
            row["robust_z"] = {"x": xs, "ref": refs,
                               "expect": None if xs is None else Z.robust_z(xs, refs)}
            spei = row["spei"]["expect"]
            z = row["robust_z"]["expect"]
            if spei is None or (isinstance(spei, float) and np.isnan(spei)):
                D = None
            elif z is None or np.isnan(z):
                D = -spei                                    # fall back to the climate term (F4)
            else:
                D = 0.5 * (-spei - z)
            row["D"] = {"spei": spei, "z_sm": z, "expect": D,
                        "label": None if D is None else Z.label(D),
                        "csv": {k_: (None if pd.isna(mon.loc[t, k_]) else mon.loc[t, k_])
                                for k_ in ("D", "label", "dry_rank", "dry_n") if k_ in mon}}
            rows.append(row)
    # robust_z edge cases: normal, pinned (MAD = 0 -> SD), constant (-> NaN), clip, short ref
    edge = [([0.40, 0.45, 0.50, 0.55, 0.60, 0.52, 0.47, 0.58, 0.43, 0.49, 0.51, 0.56], 0.9),
            ([1.0] * 10 + [0.98, 0.97], 0.5), ([1.0] * 12, 0.9),
            ([0.40, 0.45, 0.50, 0.55, 0.60, 0.52, 0.47, 0.58, 0.43, 0.49, 0.51, 0.56], 5.0),
            ([0.1, 0.2, 0.3], 0.2)]
    zedge = [{"x": x, "ref": ref, "expect": Z.robust_z(x, ref)} for ref, x in edge]
    return rows, zedge


def numeric_fixtures():
    et0, heat = et0_and_heat()
    zrows, zedge = zscore_rows()
    src = ([PROC / f"{k}_{m}.csv" for m in TOWNS for k in ("power", "monthly")])
    hdr = header("numeric", src, {
        "et0": "FAO-56 Penman-Monteith (power_prep.et0_pm), G = 0; ea = sat_vp(tdew); rs MJ/m2/day; "
               "lat from power_prep.LAT, elev from the POWER header; csv value is rounded to 2 dp.",
        "heat_index": "RH at Tmax from dew point (power_prep.rh_at_tmax), NWS heat index in deg C "
                      "from the 1-dp RH; PAGASA bands none<27, caution<33, extreme_caution<42, "
                      "danger<52, extreme_danger.",
        "zscores": "spei/robust_z use leave-one-year-out `ref` for the same calendar month; "
                   "D = 0.5 (-spei - z_sm), -spei if z_sm undefined; label normal/bantay/delikado."})
    return {"header": hdr, "et0": et0, "heat_index": heat, "zscores": zrows, "robust_z_edge": zedge}


# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args(argv)
    out = Path(a.out)
    docs = {"planner.json": planner_fixtures(), "field_machine.json": field_machine_fixtures(),
            "numeric.json": numeric_fixtures()}
    for name, doc in docs.items():
        dump(clean(doc), out / name)
        p = out / name
        n = len(doc.get("cases", [])) or sum(len(doc[k]) for k in ("et0", "heat_index", "zscores"))
        print(f"{p} ({p.stat().st_size / 1024:.0f} KB, {n} cases)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
