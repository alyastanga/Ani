"""ENSO tag for each Nov-Apr dry season (spec F13).

Usage:
    python pipeline/enso.py
    # reads  pipeline/data/raw/oni.csv              (year, DJF ... NDJ; NOAA CPC RONI table)
    # writes pipeline/data/processed/enso_dryseason.csv

Input: NOAA CPC Relative Oceanic Nino Index (RONI), 3-month running seasons, copied from
https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso/roni/ (base 1991-2020).

Two tags per dry season DS(y+1) = Nov y .. Apr y+1:

  tag_jas      F13 forecast rule: JAS of year y >= +0.5 -> El Nino, <= -0.5 -> La Nina.
               Known before planting, so this is what the app uses for the COMING season.
  tag_episode  NOAA episode rule: the season OND of year y lies inside a run of >= 5
               consecutive overlapping seasons at >= +0.5 (El Nino) or <= -0.5 (La Nina).
               Uses the full record, so this labels PAST seasons for the drought checks and
               the "X of Y El Nino years" counts.

The two disagree when an event starts late (after JAS), e.g. 2006-07 and 2018-19.
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd

RAW = Path("pipeline/data/raw")
PROC = Path("pipeline/data/processed")
SEASONS = ["DJF", "JFM", "FMA", "MAM", "AMJ", "MJJ", "JJA", "JAS", "ASO", "SON", "OND", "NDJ"]
THRESH, RUN = 0.5, 5


def load(path=RAW / "oni.csv"):
    df = pd.read_csv(path).set_index("year")[SEASONS]
    s = df.stack(future_stack=True)                          # (year, season) in time order
    s.index = pd.MultiIndex.from_tuples(s.index, names=["year", "season"])
    return s


def episodes(s, thresh=THRESH, run=RUN):
    """+1 / -1 / 0 per season: inside a run of >= run consecutive seasons past +/- thresh."""
    out = pd.Series(0, index=s.index)
    for sign in (1, -1):
        hit = (sign * s >= thresh).fillna(False).to_numpy()
        i = 0
        while i < len(hit):
            if hit[i]:
                j = i
                while j < len(hit) and hit[j]:
                    j += 1
                if j - i >= run:
                    out.iloc[i:j] = sign
                i = j
            else:
                i += 1
    return out


def label(v):
    return {1: "el_nino", -1: "la_nina", 0: "neutral"}[int(v)]


def tag_dry_seasons(s):
    ep = episodes(s)
    rows = []
    for y in sorted(set(s.index.get_level_values("year"))):
        jas, ond = s.get((y, "JAS")), s.get((y, "OND"))
        if pd.isna(jas):
            continue
        rows.append({
            "dry_season": f"{y}-{str(y + 1)[-2:]}",
            "harvest_year": y + 1,
            "jas": jas,
            "ond": ond,
            "tag_jas": label(np.sign(jas) * (abs(jas) >= THRESH)),
            "tag_episode": label(ep.get((y, "OND"), 0)) if not pd.isna(ond) else "pending",
        })
    return pd.DataFrame(rows)


def main(argv=None):
    s = load()
    t = tag_dry_seasons(s)
    PROC.mkdir(parents=True, exist_ok=True)
    t.to_csv(PROC / "enso_dryseason.csv", index=False)
    print(t.to_string(index=False))
    for col in ("tag_jas", "tag_episode"):
        ds = t[(t[col] == "el_nino") & t.harvest_year.between(2001, 2025)].dry_season.tolist()
        print(f"\n{col}: {len(ds)} El Nino dry seasons in the 2001-2025 baseline: {', '.join(ds)}")
    diff = t[(t.tag_jas != t.tag_episode) & (t.tag_episode != "pending")]
    if len(diff):
        print("\ndisagree (late or early events):", ", ".join(diff.dry_season))
    return 0


if __name__ == "__main__":
    sys.exit(main())