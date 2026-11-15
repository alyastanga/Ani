"""Phase 4 demo mode: past seasons the app replays through its tracker (docs/PLAN.md, Phase 4.6).

Usage:
    python pipeline/export_demo.py [--out app/assets/fixtures]
    # reads  pipeline/data/processed/power_<muni>.csv, bucket_<muni>.csv, soil.csv
    #        pipeline/data/raw/crops.csv
    # writes <out>/demo_seasons.json

No single season shows all five in-season alerts (heat at flowering is rice-only, onion rot is
onion-only), so the demo is a small set of real seasons that together show every alert:

  guimba   rice   2023-24 full       heat at flowering (rice, Tmax >= 35 C in Repro), harvest ready
  munoz    onion  2004-05 rainfed    onion rot (3-day rain >= p98 in Estab), water now, failed
  bongabon onion  2011-12 limited_4  onion rot, water now (stress after the 4 refills), harvest ready

Each season carries the POWER daily values as stored in power_<muni>.csv (ET0 already computed
by power_prep.py), the starting soil-water fraction run_season used (bucket S_frac on the sow day)
and the Python machine's expected state per day (simulating=True), so the Dart replay can be
checked against it. Days run past the Python Fallow day by EXTRA days so an unconfirmed live
replay can keep ticking in Mature. Deterministic: same data -> byte-identical output.
"""

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pipeline.export_fixtures import NDP, PROC, RAW, clean, header      # noqa: E402
from pipeline.fsm import WATER, FieldMachine, params_for                  # noqa: E402
from pipeline.soil_water import load_crops                               # noqa: E402

OUT = Path("app/assets/fixtures")
EXTRA = 14
# (muni, crop, dry season, water, enso tag, alerts the app should show)
DEMO = [
    ("guimba", "rice", "2023-24", "full", "el_nino", ["heatAtFlowering", "harvestReady"]),
    ("munoz", "onion", "2004-05", "rainfed", "", ["onionRot", "waterNow", "failed"]),
    ("bongabon", "onion", "2011-12", "limited_4", "", ["onionRot", "waterNow", "harvestReady"]),
]
RAW_COLS = ["T2M_MAX", "T2M_MIN", "T2MDEW", "RH2M", "WS2M", "ALLSKY_SFC_SW_DWN", "PRECTOTCORR",
            "GWETROOT", "ET0"]


def demo_seasons():
    soil = pd.read_csv(PROC / "soil.csv").set_index("muni")
    crops = load_crops()
    enso_f = PROC / "enso_dryseason.csv"
    enso = pd.read_csv(enso_f) if enso_f.exists() else None
    tags = {} if enso is None else dict(zip(enso.dry_season, enso.tag_episode))
    seasons = []
    for muni, crop, ds, water, tag, shows in DEMO:
        daily = pd.read_csv(PROC / f"power_{muni}.csv", index_col="date", parse_dates=True)
        ref = pd.read_csv(PROC / f"bucket_{muni}.csv", index_col="date", parse_dates=True)
        d = daily[["T2M_MAX", "T2M_MIN", "PRECTOTCORR", "ET0"]].dropna()
        years = list(range(d.index.year.min(), d.index.year.max()))
        rot = float(d.PRECTOTCORR.rolling(3).sum().quantile(0.98))
        c = crops[crop]
        dur = int(round(c["duration_days"][0]))
        irrigated, max_irr = WATER[water]
        prm = params_for(crop, c, soil.loc[muni], d, years, irrigated, rot, max_irr)
        y = int(ds[:4])
        sow = pd.Timestamp(f"{y}-11-01") + pd.Timedelta(days=int(c["sow_day"][0]))
        w = d.loc[sow: sow + pd.Timedelta(days=2 * dur)]
        s0 = float(ref.loc[sow, "S_frac"])
        m = FieldMachine(prm)
        m.sow(s0 * prm.taw)
        q, alerts = [], {}
        for i, r in enumerate(w.itertuples()):
            out = m.tick(r.T2M_MAX, r.T2M_MIN, r.PRECTOTCORR, r.ET0)
            q.append(m.q)
            if out:
                alerts[str(i)] = out
            if m.q == "Fallow":
                break
        n = min(len(q) + EXTRA, len(w))
        rows = daily.loc[w.index[:n], RAW_COLS]
        days = [[ix.strftime("%Y%m%d"), *[None if pd.isna(v) else v for v in r]]
                for ix, r in zip(rows.index, rows.itertuples(index=False))]
        o = m.outcome()
        seasons.append({
            "id": f"{muni}|{crop}|{ds}|{water}", "muni": muni, "crop": crop, "dry_season": ds,
            "enso": tags.get(ds, tag), "water": water, "sow": sow.strftime("%Y-%m-%d"),
            "s0_frac": s0, "shows": shows,
            "columns": ["date", *RAW_COLS], "days": days,
            "expect": {"q": q, "alerts": alerts, "transitions": [list(t) for t in m.trace],
                       "failed": o["failed"], "harvest_day": o["harvest_day"]}})
    return seasons


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args(argv)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    src = ([PROC / f"{k}_{m}.csv" for m in ("guimba", "munoz", "bongabon") for k in ("power", "bucket")]
           + [PROC / "soil.csv", RAW / "crops.csv"])
    doc = {"header": header("demo_seasons", src, {
        "note": "Past seasons replayed in the app's demo mode (clearly labelled as a replay). "
                "days = POWER daily values as in power_<muni>.csv (ET0 from power_prep.py); "
                "expect = fsm.FieldMachine with simulating=True, state after each tick."}),
        "seasons": demo_seasons()}
    doc["header"]["generated_from"]["script"] = "pipeline/export_demo.py"
    path = out / "demo_seasons.json"
    path.write_text(json.dumps(clean(doc, NDP), ensure_ascii=False, separators=(",", ":")) + "\n",
                    encoding="utf-8")
    print(f"wrote {path} ({path.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
