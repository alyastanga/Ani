"""Step 9: per-town JSON bundled in the app (spec Appendix B).

Usage:
    python pipeline/export_json.py guimba munoz bongabon
    # reads  processed/: power_, monthly_, bucket_, risk_, outcomes_<muni>.csv, soil.csv,
    #        enso_dryseason.csv;  raw/crops.csv
    # writes pipeline/data/export/ani_<muni>.json

One file per town holds everything the app needs offline:

  meta      schema version, generation date, town point, baseline, sources
  enso      coming dry season and its tag (JAS rule), with the past seasons (episode rule)
  dryness   latest D, label (Normal / Bantay / Delikado) and a plain rank sentence, plus the
            monthly series for the El Nino page. Rank wording follows the sign of D:
            "driest r of n" when D >= 0, "wettest r of n" when D < 0.
            reference (schema 2): per calendar month "1".."12" the baseline the phone needs to
            score a new month on device: {years, bal1, bal3, gwet} aligned by year, where bal1 =
            1-month P - ET0 (mm), bal3 = 3-month accumulated P - ET0 ending in that month (the
            Nov-Apr season accumulation), gwet = monthly mean GWETROOT. null = month incomplete.
  crops     names, family, legume, small-market flag, duration, sowing window
  risk      per water scenario x crop: the card numbers (failed X/n with Wilson range, Monte
            Carlo failure, irrigation, net income p10/p50/p90, heat share)
  planner   the constants M_P uses (thresholds, beta, ranked share, criteria)
  tracker   per crop: the M_F parameters for this town (TAW, p, Kc, T_base, G_mat, stage
            fractions, T_crit, rot P98, failure thresholds), so the phone runs the same machine.
            s0_frac_by_doy (schema 2, sits beside the crop keys): 366 values, index = calendar
            day-of-year - 1 (leap-year numbering, Feb 29 = index 59), median bucket S_frac over
            the baseline: the starting soil-water fraction for seasons with no observed start.
  meta.power (schema 2) the NASA POWER daily-point request the app must make (parameters,
            community, endpoint). Rain is the PRECTOTCORR column of power_<town>.csv (MERRA-2
            corrected rain), as used by power_prep.py / zscores.py; IMERG_PRECTOT is only an
            optional cross-check (used as PRECTOTCORR only if a file has no PRECTOTCORR).
  heat      PAGASA heat-index categories for the safety channel

Values are rounded for size; the planner gives the same cards from this file as from the CSVs
(test_export_json.py).
"""

import json
import sys
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pipeline import planner as P                                        # noqa: E402
from pipeline.fsm import K_FAIL, KS_FAIL, WATER, params_for              # noqa: E402
from pipeline.soil_water import load_crops                               # noqa: E402
from pipeline.zscores import accumulate, monthly as zmonthly             # noqa: E402

PROC = Path("pipeline/data/processed")
OUT = Path("pipeline/data/export")
SCHEMA = 2
RISK_COLS = ["fail_en_x", "fail_en_n", "fail_en_lo", "fail_en_hi",
             "fail_other_x", "fail_other_n", "fail_other_lo", "fail_other_hi",
             "mc_fail_en_p10", "mc_fail_en_p50", "mc_fail_en_p90",
             "mc_fail_other_p10", "mc_fail_other_p50", "mc_fail_other_p90",
             "mc_irr_en_p50", "mc_irr_other_p50",
             "mc_net_en_p10", "mc_net_en_p50", "mc_net_en_p90",
             "mc_net_other_p10", "mc_net_other_p50", "mc_net_other_p90"]
PAGASA = [{"from": 27, "to": 32, "label": "caution"}, {"from": 33, "to": 41, "label": "extreme caution"},
          {"from": 42, "to": 51, "label": "danger"}, {"from": 52, "to": None, "label": "extreme danger"}]


def num(v, nd=3):
    if v is None or (isinstance(v, float) and np.isnan(v)):
        return None
    return round(float(v), nd) if not float(v).is_integer() else int(v)


def rank_text(d, rank, n):
    """Plain rank sentence. dry_rank counts from the driest, so a wet month flips."""
    if d is None or rank is None or n is None:
        return None
    r, n = int(rank), int(n)
    return f"pinakatuyo: ika-{r} sa {n} na taon" if d >= 0 else f"pinakabasa: ika-{n - r + 1} sa {n} na taon"


POWER = {"endpoint": "https://power.larc.nasa.gov/api/temporal/daily/point", "community": "AG",
         "time_standard": "UTC", "format": "JSON", "fill_value": -999,
         "parameters": ["T2M_MAX", "T2M_MIN", "T2MDEW", "RH2M", "WS2M", "ALLSKY_SFC_SW_DWN",
                        "PRECTOTCORR", "GWETROOT"],
         "rain_parameter": "PRECTOTCORR",
         "notes": "AG community gives solar in MJ/m2/day (not kWh). ET0 and heat index are computed on "
                  "device as in power_prep.py. Rain is PRECTOTCORR; IMERG_PRECTOT is not requested."}


def dryness_reference(daily):
    """Per calendar month: years + 1-month / 3-month P-ET0 balances + mean GWETROOT (null if incomplete)."""
    m = zmonthly(daily)
    m["bal3"] = accumulate(m["wb_mm"], 3)
    if "gwetroot" not in m:
        m["gwetroot"] = np.nan
    out = {}
    for mm in range(1, 13):
        g = m[m.index.month == mm]
        g = g[g.wb_mm.notna() | g.gwetroot.notna()]
        out[str(mm)] = {"years": [int(i.year) for i in g.index],
                        "bal1": [num(v, 2) for v in g.wb_mm], "bal3": [num(v, 2) for v in g.bal3],
                        "gwet": [num(v, 5) for v in g.gwetroot]}
    return out


def s0_frac_by_doy(ref):
    """Median bucket S_frac by calendar day of year (366 entries, leap-year numbering)."""
    if ref is None:
        return []
    f = ref["S_frac"].dropna()
    med = f.groupby(f.index.month * 100 + f.index.day).median()
    return [num(med.get(d.month * 100 + d.day), 2) for d in pd.date_range("2000-01-01", "2000-12-31")]


def build(muni, daily, monthly, soil_row, ref, risk, outcomes, enso, crops, soil_all):
    # enso
    e = enso.dropna(subset=["jas"])
    coming = e.iloc[-1]
    enso_block = {"coming_season": coming.dry_season, "tag": coming.tag_jas, "jas": num(coming.jas, 2),
                  "rule": "JAS RONI >= +0.5 (forecast); past seasons by NOAA episode rule",
                  "past": [{"season": r.dry_season, "tag": r.tag_episode} for r in enso.itertuples()
                           if r.tag_episode != "pending"]}
    # dryness
    m = monthly.dropna(subset=["D"])
    last = m.iloc[-1]
    dry = {"latest": {"month": last.name.strftime("%Y-%m"), "D": num(last.D, 2), "label": last.label,
                      "rank": rank_text(last.D, last.get("dry_rank"), last.get("dry_n"))},
           "thresholds": {"bantay": 1.0, "delikado": 2.0, "down_bantay": 1.5, "down_normal": 0.5,
                          "calm_dekads": 2},
           "monthly": [[i.strftime("%Y-%m"), num(r.D, 2)] for i, r in m.iterrows()],
           "reference": dryness_reference(daily)}
    # crops and tracker
    d = daily[["T2M_MAX", "T2M_MIN", "PRECTOTCORR", "ET0"]].dropna()
    years = list(range(d.index.year.min(), d.index.year.max()))
    rot = float(d.PRECTOTCORR.rolling(3).sum().quantile(0.98))
    crop_block, tracker = {}, {}
    for crop, c in crops.items():
        crop_block[crop] = {"name": P.NAME[crop], "family": P.FAMILY[crop], "legume": crop in P.LEGUME,
                            "small_market": crop in P.SMALL_MARKET,
                            "duration_days": num(c["duration_days"][0]),
                            "sow_window_days_after_nov1": [int(c["sow_day"][1]), int(c["sow_day"][2])]}
        prm = params_for(crop, c, soil_row, d, years, False, rot)
        tracker[crop] = {k: num(getattr(prm, k), 3) for k in
                         ("taw", "p", "kc_ini", "kc_mid", "kc_end", "t_base", "t_crit", "rot_p98")}
        # stage boundaries need more digits: 3 dp moves a stage transition by a day (schema 2)
        tracker[crop].update({k: num(getattr(prm, k), 6) for k in ("g_mat", "f_e", "f_v", "f_r")})
        tracker[crop].update(ks_fail=KS_FAIL, k_fail=K_FAIL, d_prep=0,
                             sensitive=["Veg", "Repro"], t_up=None)
    # risk (+ heat share for g5)
    hs = outcomes.assign(h=outcomes.heat_days >= 1).groupby(["crop", "water"]).h.mean()
    risk_block = {}
    for w in [w for w in WATER if w in set(risk.water)]:
        risk_block[w] = {}
        for r in risk[risk.water == w].itertuples():
            row = {k: num(getattr(r, k)) for k in RISK_COLS}
            row["heat_share"] = num(hs.get((r.crop, w), 0.0))
            risk_block[w][r.crop] = row
    return {
        "meta": {"schema": SCHEMA, "generated": date.today().isoformat(), "muni": muni,
                 "point": {"lat": num(soil_row.town_lat, 4), "lon": num(soil_row.town_lon, 4)},
                 "power": POWER,
                 "baseline": f"{d.index.year.min()}-{d.index.year.max()}",
                 "water_scenarios": {"rainfed": 0, "limited_2": 2, "limited_4": 4, "full": None},
                 "sources": ["NASA POWER", "ISRIC SoilGrids 2.0", "NOAA CPC RONI", "FAO-56",
                             "PSA OpenSTAT", "PSA costs and returns"]},
        "enso": enso_block, "dryness": dry, "crops": crop_block, "risk": risk_block,
        "planner": {"theta_f": P.THETA_F, "theta_h": P.THETA_H, "beta": P.BETA,
                    "ranked_share": P.RANKED_SHARE, "criteria": list(P.CRITERIA),
                    "benefit": P.BENEFIT, "water_label": P.WATER_LABEL},
        "tracker": {**tracker, "s0_frac_by_doy": s0_frac_by_doy(ref)}, "heat": {"index_categories_c": PAGASA}}


def risk_frame(doc):
    """Rebuild the planner's risk table from an exported file (used by the app logic and tests)."""
    rows = [{"crop": c, "water": w, **v} for w, crops in doc["risk"].items() for c, v in crops.items()]
    df = pd.DataFrame(rows)
    hs = {(r.crop, r.water): r.heat_share or 0.0 for r in df.itertuples()}
    return df, hs


def main(argv=None):
    names = list(argv if argv is not None else sys.argv[1:])
    if not names:
        print(__doc__)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    soil = pd.read_csv(PROC / "soil.csv").set_index("muni")
    crops = load_crops()
    enso = pd.read_csv(PROC / "enso_dryseason.csv")
    for muni in names:
        daily = pd.read_csv(PROC / f"power_{muni}.csv", index_col="date", parse_dates=True)
        monthly = pd.read_csv(PROC / f"monthly_{muni}.csv", index_col="month", parse_dates=True)
        ref = pd.read_csv(PROC / f"bucket_{muni}.csv", index_col="date", parse_dates=True)
        risk = pd.read_csv(PROC / f"risk_{muni}.csv")
        outc = pd.read_csv(PROC / f"outcomes_{muni}.csv")
        doc = build(muni, daily, monthly, soil.loc[muni], ref, risk, outc, enso, crops, soil)
        path = OUT / f"ani_{muni}.json"
        path.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")))
        L = doc["dryness"]["latest"]
        print(f"{muni}: {path} ({path.stat().st_size / 1024:.0f} KB) | {doc['enso']['coming_season']} "
              f"{doc['enso']['tag']} | latest {L['month']} D {L['D']} {L['label']} ({L['rank']}) | "
              f"{len(doc['risk'])} water x {len(doc['crops'])} crops")
    return 0


if __name__ == "__main__":
    sys.exit(main())