"""Soil water-holding capacity per municipality from ISRIC SoilGrids 2.0.

For each town the script finds the NEAREST SoilGrids pixel to the town centre that
has data (town centres are built up and return nulls), searching outward on a
~280 m grid up to MAX_KM. Optionally it averages the N nearest valid pixels.

Usage:
    python pipeline/fetch_soilgrids.py                # reuse saved in-town files, fetch the rest
    python pipeline/fetch_soilgrids.py --refetch      # search again for every town
    python pipeline/fetch_soilgrids.py --n 5          # average the 5 nearest valid pixels (slower)

Files:
    pipeline/data/raw/SOIL_<Town>.json        nearest valid pixel (input/cache; replaced if it is
                                              more than MAX_KM from town or has no data)
    pipeline/data/processed/soil.csv          output

Town centres: PhilAtlas municipal centres (Guimba 15.6623, 120.7657; Bongabon
15.6321, 121.1459) and Wikipedia (Science City of Munoz 15.7153, 120.9039).

Units (SoilGrids FAQ): wv0033 and wv1500 are mapped in 10^-3 cm3/cm3, which is also
mm of water per metre of soil:
    theta_fc = wv0033 / 1000          (field capacity, 33 kPa)
    theta_wp = wv1500 / 1000          (wilting point, 1500 kPa)
    AWC [mm/m] = wv0033 - wv1500      (available water per metre of roots)
Crop bucket (spec F5): TAW [mm] = AWC_0_to_Zr [mm/m] * Zr [m].
clay and sand are mapped in g/kg (divide by 10 for %).

ISRIC asks API users to keep to about 5 requests per minute, so the search waits
between calls; a town whose centre is built up can take a few minutes.

Citation: Poggio et al. (2021) SOIL 7:217-240. Data: ISRIC, CC-BY 4.0.
"""

import argparse
import json
import math
import sys
import time
from pathlib import Path

import pandas as pd

API = "https://rest.isric.org/soilgrids/v2.0/properties/query"
PROPS = ["wv0033", "wv1500", "clay", "sand"]
DEPTHS = ["0-5cm", "5-15cm", "15-30cm", "30-60cm", "60-100cm"]

TOWNS = {                      # file label: (lat, lon) of the municipal centre
    "Guimba": (15.6623, 120.7657),
    "Munoz": (15.7153, 120.9039),
    "Bongabon": (15.6321, 121.1459),
}
STEP_DEG = 0.0025              # ~280 m search grid
MAX_KM = 5.0                   # give up beyond this; also the "still in town" test for saved files
WAIT_S = 12.5                  # ~5 requests per minute
RAW = Path("pipeline/data/raw")
OUT = Path("pipeline/data/processed")


# ---------------------------------------------------------------- geometry

def km_between(lat1, lon1, lat2, lon2):
    """Great-circle distance (haversine), km."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def candidates(lat, lon, step=STEP_DEG, max_km=MAX_KM):
    """Grid points around (lat, lon), nearest first, within max_km."""
    n = int(max_km / (step * 111)) + 1
    pts = []
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            la, lo = round(lat + i * step, 5), round(lon + j * step, 5)
            d = km_between(lat, lon, la, lo)
            if d <= max_km:
                pts.append((d, la, lo))
    return sorted(pts)


# ---------------------------------------------------------------- SoilGrids

def fetch(lat, lon):
    import requests
    params = [("lat", lat), ("lon", lon), ("value", "mean")]
    params += [("property", p) for p in PROPS] + [("depth", d) for d in DEPTHS]
    r = requests.get(API, params=params, timeout=60)
    if r.status_code == 429:                       # rate limited: wait and retry once
        time.sleep(60)
        r = requests.get(API, params=params, timeout=60)
    r.raise_for_status()
    return r.json()


def parse(doc):
    """SoilGrids JSON -> one row per depth layer (top, bottom, one column per property)."""
    rows = []
    for layer in doc["properties"]["layers"]:
        for d in layer["depths"]:
            rows.append({
                "prop": layer["name"],
                "top": d["range"]["top_depth"],
                "bottom": d["range"]["bottom_depth"],
                "value": d["values"].get("mean"),
            })
    df = pd.DataFrame(rows)
    df["value"] = pd.to_numeric(df["value"], errors="coerce")   # null -> NaN
    wide = df.pivot(index=["top", "bottom"], columns="prop", values="value").reset_index()
    wide.columns.name = None
    return wide


def is_valid(doc):
    layers = parse(doc)
    return all(c in layers for c in ("wv0033", "wv1500")) and \
        layers[["wv0033", "wv1500"]].notna().all().all()


def nearest_valid(lat, lon, n=1, fetcher=fetch, wait=WAIT_S, log=print):
    """Return up to n (distance_km, lat, lon, doc) with data, nearest first."""
    found = []
    for k, (d, la, lo) in enumerate(candidates(lat, lon)):
        if k:
            time.sleep(wait)
        doc = fetcher(la, lo)
        ok = is_valid(doc)
        log(f"    try {la:.4f}, {lo:.4f} ({d:.2f} km): {'data' if ok else 'no data'}")
        if ok:
            found.append((d, la, lo, doc))
            if len(found) >= n:
                break
    return found


# ---------------------------------------------------------------- summaries

def weighted(layers, col, to_cm):
    """Thickness-weighted mean of col from 0 to to_cm. None if a needed layer is missing."""
    if col not in layers:
        return None
    total, depth = 0.0, 0.0
    for _, r in layers.sort_values("top").iterrows():
        top, bot = r["top"], min(r["bottom"], to_cm)
        if top >= to_cm:
            break
        v = r[col]
        if pd.isna(v):
            return None
        total += v * (bot - top)
        depth += bot - top
    return total / depth if depth >= to_cm - 1e-9 else None


def summarise(name, lat, lon, layers):
    row = {"muni": name, "lat": lat, "lon": lon}
    for to in (30, 60, 100):
        fc, wp = weighted(layers, "wv0033", to), weighted(layers, "wv1500", to)
        row[f"theta_fc_0_{to}"] = None if fc is None else round(fc / 1000, 3)
        row[f"theta_wp_0_{to}"] = None if wp is None else round(wp / 1000, 3)
        row[f"awc_mm_per_m_0_{to}"] = None if fc is None or wp is None else round(fc - wp, 1)
    for p in ("clay", "sand"):
        v = weighted(layers, p, 30)
        row[f"{p}_pct_0_30"] = None if v is None else round(v / 10, 1)
    return row


def check(row):
    problems = []
    awc = row["awc_mm_per_m_0_60"]
    if awc is None:
        problems.append("missing values at 0-60 cm")
    elif not 40 <= awc <= 250:
        problems.append(f"AWC {awc} mm/m outside the plausible 40-250 mm/m for mineral soils")
    if row["theta_fc_0_60"] is not None and row["theta_wp_0_60"] is not None \
            and row["theta_fc_0_60"] <= row["theta_wp_0_60"]:
        problems.append("field capacity <= wilting point")
    if row["awc_mm_per_m_0_100"] is None and awc is not None:
        problems.append("no 60-100 cm layer: deep-rooted crops will use the 0-60 cm value")
    return problems


def combine(name, town_lat, town_lon, hits):
    """Mean of the summaries of the valid pixels; AWC min/max kept as a range for Monte Carlo."""
    rows = [summarise(name, la, lo, parse(doc)) for _, la, lo, doc in hits]
    df = pd.DataFrame(rows)
    out = df.drop(columns=["muni"]).mean(numeric_only=True).round(3).to_dict()
    out = {"muni": name, **out}
    out["lat"], out["lon"] = hits[0][1], hits[0][2]           # nearest pixel's position
    out["town_lat"], out["town_lon"] = town_lat, town_lon
    out["km_from_town"] = round(hits[0][0], 2)
    out["n_pixels"] = len(hits)
    if len(hits) > 1:
        out["awc_0_60_min"] = df["awc_mm_per_m_0_60"].min()
        out["awc_0_60_max"] = df["awc_mm_per_m_0_60"].max()
    return out


# ---------------------------------------------------------------- main

def main(argv=None, fetcher=fetch, wait=WAIT_S):
    ap = argparse.ArgumentParser()
    ap.add_argument("--refetch", action="store_true")
    ap.add_argument("--n", type=int, default=1, help="average the n nearest valid pixels")
    ap.add_argument("--dir", default=str(RAW))
    ap.add_argument("--out", default=str(OUT))
    a = ap.parse_args(argv)
    data, out = Path(a.dir), Path(a.out)
    data.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)

    rows = []
    for label, (tlat, tlon) in TOWNS.items():
        name = label.lower()
        path = data / f"SOIL_{label}.json"
        print(f"\n{name}: town centre {tlat}, {tlon}")
        hits = []
        if path.exists() and not a.refetch and a.n == 1:
            doc = json.loads(path.read_text())
            lon, lat = doc["geometry"]["coordinates"][:2]
            d = km_between(tlat, tlon, lat, lon)
            if d <= MAX_KM and is_valid(doc):
                print(f"  using saved {path.name} ({lat:.4f}, {lon:.4f}, {d:.2f} km from centre)")
                hits = [(d, lat, lon, doc)]
            else:
                print(f"  saved {path.name} is {d:.1f} km from town or has no data -> searching again")
        if not hits:
            hits = nearest_valid(tlat, tlon, n=a.n, fetcher=fetcher, wait=wait)
            if not hits:
                print(f"  CHECK: no SoilGrids data within {MAX_KM} km")
                continue
            path.write_text(json.dumps(hits[0][3]))
            print(f"  nearest valid pixel {hits[0][1]:.4f}, {hits[0][2]:.4f} "
                  f"({hits[0][0]:.2f} km) saved to {path.name}")
        row = combine(name, tlat, tlon, hits)
        rng = f" (range {row['awc_0_60_min']}-{row['awc_0_60_max']})" if row["n_pixels"] > 1 else ""
        print(f"  AWC 0-30 / 0-60 / 0-100 cm: {row['awc_mm_per_m_0_30']} / "
              f"{row['awc_mm_per_m_0_60']}{rng} / {row['awc_mm_per_m_0_100']} mm/m | "
              f"FC {row['theta_fc_0_60']} WP {row['theta_wp_0_60']} | "
              f"clay {row['clay_pct_0_30']}% sand {row['sand_pct_0_30']}% | {row['n_pixels']} pixel(s)")
        for p in check(row):
            print(f"  CHECK: {p}")
        rows.append(row)

    pd.DataFrame(rows).to_csv(out / "soil.csv", index=False)
    print(f"\nwrote {out / 'soil.csv'}")
    print("TAW for a crop = awc_mm_per_m (0 to its root depth) x root depth in m  (spec F5)")
    return 0


if __name__ == "__main__":
    sys.exit(main())