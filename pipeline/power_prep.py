"""Step 0 checks + step 1 (F9 ET0, F10 heat index) for NASA POWER daily CSVs.

Usage:
    python pipeline/power_prep.py guimba=path/to/guimba.csv bongabon=... munoz=...
    # two downloads for one site? join them with +:  munoz=a.csv+b.csv
    # optional: --elev 60   (metres; overrides the elevation read from the file header)

Reads POWER Data Access Viewer CSVs (header block ending in -END HEADER-) or
plain CSVs with a date column. Writes pipeline/data/processed/power_<muni>.csv with
added columns ET0, ET0_HARG, RH_TMAX, HI, HI_CAT and prints a check report.

Formulas: Allen et al. (1998) FAO-56 Eqs. 6-39; heat index: Rothfusz (1990)
regression with NWS adjustments, Steadman simple form below 80 F.
"""

import argparse
import io
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

FILL = -999.0
NEEDED = ["T2M_MAX", "T2M_MIN", "T2MDEW", "RH2M", "WS2M", "ALLSKY_SFC_SW_DWN", "PRECTOTCORR"]
OPTIONAL = ["GWETROOT", "IMERG_PRECTOT"]  # IMERG = rain cross-check (2001+)

# Approximate town centres; replace with HDX centroids (also used for Ra).
LAT = {"guimba": 15.66, "bongabon": 15.63, "munoz": 15.71}


# ---------------------------------------------------------------- loading

def read_power_csv(path):
    """Return (DataFrame indexed by date, header dict)."""
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    header = {}
    if "-END HEADER-" in text:
        head, body = text.split("-END HEADER-", 1)
        m = re.search(r"=\s*([-\d.]+)\s*meters", head)
        if m:
            header["elevation_m"] = float(m.group(1))
        m = re.search(r"Latitude\s+([-\d.]+)\s+Longitude\s+([-\d.]+)", head)
        if m:
            header["lat"], header["lon"] = float(m.group(1)), float(m.group(2))
    else:
        body = text
    df = pd.read_csv(io.StringIO(body.strip()))
    df.columns = [c.strip().upper() for c in df.columns]
    if {"YEAR", "MO", "DY"} <= set(df.columns):
        idx = pd.to_datetime(dict(year=df.YEAR, month=df.MO, day=df.DY))
    elif {"YEAR", "DOY"} <= set(df.columns):
        idx = pd.to_datetime(df.YEAR.astype(str) + df.DOY.astype(int).astype(str).str.zfill(3), format="%Y%j")
    elif "DATE" in df.columns:
        idx = pd.to_datetime(df.DATE)
    else:
        raise ValueError(f"{path}: no YEAR/MO/DY, YEAR/DOY or date column")
    df.index = idx
    df.index.name = "date"
    df = df.drop(columns=[c for c in ["YEAR", "MO", "DY", "DOY", "DATE", "LAT", "LON"] if c in df.columns])
    df = df.replace(FILL, np.nan).sort_index()
    return df, header


def use_imerg_if_only_rain(df, name):
    """If the file has IMERG rain but no MERRA-2 rain, use IMERG as the rain
    column and trim to the IMERG record (2001 onward)."""
    if "PRECTOTCORR" in df.columns or "IMERG_PRECTOT" not in df.columns:
        return df
    first = df["IMERG_PRECTOT"].first_valid_index()
    df = df.loc[first:].copy()
    df["PRECTOTCORR"] = df["IMERG_PRECTOT"]
    print(f"{name}: rain source = IMERG (daily, UTC days), record trimmed to start {first.date()}")
    return df


def check(df, name):
    """Gate 3. Returns list of problems (empty = pass)."""
    problems = []
    missing = [c for c in NEEDED if c not in df.columns]
    if missing:
        hint = ""
        if "PRECTOTCORR" in missing and "IMERG_PRECTOT" in df.columns:
            hint = (" -> this file has IMERG rain only (starts 2001). Download again with the plain"
                    " 'Precipitation' box ticked and pass both files: muni=a.csv+b.csv")
        problems.append(f"missing columns {missing}; columns found: {list(df.columns)}{hint}")
        return problems
    full = pd.date_range(df.index.min(), df.index.max(), freq="D")
    if len(full) != len(df.index.unique()):
        problems.append(f"{len(full) - len(df.index.unique())} calendar days missing")
    if df.index.duplicated().any():
        problems.append("duplicate dates")
    bad = (df.T2M_MAX < df.T2M_MIN).sum()
    if bad:
        problems.append(f"{bad} days with Tmax < Tmin")
    for col, lo, hi in [("T2M_MAX", 10, 45), ("T2M_MIN", 5, 35), ("RH2M", 0, 100),
                        ("WS2M", 0, 30), ("PRECTOTCORR", 0, 500), ("ALLSKY_SFC_SW_DWN", 0, 40)]:
        out = (~df[col].dropna().between(lo, hi)).sum()
        if out:
            problems.append(f"{out} values of {col} outside [{lo}, {hi}]")
    # Gaps longer than 3 days are flagged, never filled (plan.md Gate 4).
    for col in NEEDED:
        run = df[col].isna().astype(int)
        longest = run.groupby((run == 0).cumsum()).sum().max()
        if longest > 3:
            problems.append(f"{col}: gap of {longest} days (flag, do not interpolate)")
    return problems


def solar_units_ok(rs):
    """AG community gives MJ/m2/day (tropics ~10-25). RE gives kWh (~3-7)."""
    return rs.median() > 8


# ---------------------------------------------------------------- FAO-56

def sat_vp(t):
    """FAO-56 Eq. 11, kPa."""
    return 0.6108 * np.exp(17.27 * t / (t + 237.3))


def extraterrestrial_ra(lat_deg, doy):
    """FAO-56 Eqs. 21-25, MJ m-2 day-1."""
    phi = np.radians(lat_deg)
    dr = 1 + 0.033 * np.cos(2 * np.pi * doy / 365)
    delta = 0.409 * np.sin(2 * np.pi * doy / 365 - 1.39)
    ws = np.arccos(np.clip(-np.tan(phi) * np.tan(delta), -1, 1))
    return 24 * 60 / np.pi * 0.0820 * dr * (ws * np.sin(phi) * np.sin(delta)
                                             + np.cos(phi) * np.cos(delta) * np.sin(ws))


def et0_pm(tmax, tmin, ea, rs, u2, lat_deg, doy, elev_m):
    """FAO-56 Penman-Monteith daily ET0 (Eq. 6), mm/day. G = 0 for daily steps."""
    tmean = (tmax + tmin) / 2
    p = 101.3 * ((293 - 0.0065 * elev_m) / 293) ** 5.26          # Eq. 7
    gamma = 0.000665 * p                                          # Eq. 8
    es = (sat_vp(tmax) + sat_vp(tmin)) / 2                        # Eq. 12
    delta = 4098 * sat_vp(tmean) / (tmean + 237.3) ** 2           # Eq. 13
    ra = extraterrestrial_ra(lat_deg, doy)
    rso = (0.75 + 2e-5 * elev_m) * ra                             # Eq. 37
    rns = 0.77 * rs                                               # Eq. 38
    ratio = np.clip(rs / rso, 0.25, 1.0)
    sigma = 4.903e-9
    rnl = sigma * ((tmax + 273.16) ** 4 + (tmin + 273.16) ** 4) / 2 \
        * (0.34 - 0.14 * np.sqrt(ea)) * (1.35 * ratio - 0.35)     # Eq. 39
    rn = rns - rnl                                                # Eq. 40
    num = 0.408 * delta * rn + gamma * 900 / (tmean + 273) * u2 * (es - ea)
    return num / (delta + gamma * (1 + 0.34 * u2))


def et0_hargreaves(tmax, tmin, lat_deg, doy):
    """FAO-56 Eq. 52, cross-check only."""
    ra = extraterrestrial_ra(lat_deg, doy)
    return 0.0023 * ((tmax + tmin) / 2 + 17.8) * np.sqrt(np.maximum(tmax - tmin, 0)) * 0.408 * ra


# ---------------------------------------------------------------- heat index

def rh_at_tmax(tmax, tdew):
    """F10: RH at the time of Tmax from dew point, %."""
    return np.clip(100 * sat_vp(tdew) / sat_vp(tmax), 0, 100)


def heat_index_c(t_c, rh):
    """NWS heat index (Rothfusz 1990 + adjustments), input/output deg C."""
    t = np.asarray(t_c, float) * 9 / 5 + 32
    r = np.asarray(rh, float)
    simple = 0.5 * (t + 61.0 + (t - 68.0) * 1.2 + r * 0.094)
    full = (-42.379 + 2.04901523 * t + 10.14333127 * r - 0.22475541 * t * r
            - 0.00683783 * t ** 2 - 0.05481717 * r ** 2 + 0.00122874 * t ** 2 * r
            + 0.00085282 * t * r ** 2 - 0.00000199 * t ** 2 * r ** 2)
    adj_low = np.where((r < 13) & (t >= 80) & (t <= 112),
                       -((13 - r) / 4) * np.sqrt(np.maximum(17 - np.abs(t - 95), 0) / 17), 0)
    adj_high = np.where((r > 85) & (t >= 80) & (t <= 87), ((r - 85) / 10) * ((87 - t) / 5), 0)
    full = full + adj_low + adj_high
    use_full = (simple + t) / 2 >= 80
    hi_f = np.where(use_full, full, simple)
    return (hi_f - 32) * 5 / 9


def pagasa_category(hi_c):
    bins = [-np.inf, 27, 33, 42, 52, np.inf]
    labels = ["none", "caution", "extreme_caution", "danger", "extreme_danger"]
    return pd.cut(hi_c, bins=bins, labels=labels, right=False)


# ---------------------------------------------------------------- pipeline

def process(df, lat, elev):
    out = df.copy()
    doy = out.index.day_of_year.values
    ea = sat_vp(out.T2MDEW)                                       # FAO-56 Eq. 14
    out["ET0"] = et0_pm(out.T2M_MAX, out.T2M_MIN, ea, out.ALLSKY_SFC_SW_DWN,
                        out.WS2M, lat, doy, elev).round(2)
    out["ET0_HARG"] = et0_hargreaves(out.T2M_MAX, out.T2M_MIN, lat, doy).round(2)
    out["RH_TMAX"] = rh_at_tmax(out.T2M_MAX, out.T2MDEW).round(1)
    out["HI"] = np.round(heat_index_c(out.T2M_MAX, out.RH_TMAX), 1)
    out["HI_CAT"] = pagasa_category(out.HI)
    return out


def report(name, out):
    print(f"\n== {name} ==  {out.index.min().date()} to {out.index.max().date()}, {len(out)} days")
    ok = out[["ET0", "ET0_HARG"]].dropna()
    r = ok.ET0.corr(ok.ET0_HARG)
    by_m = ok.groupby(ok.index.month).mean()
    bias = ((by_m.ET0 - by_m.ET0_HARG) / by_m.ET0_HARG * 100).round(1)
    print(f"ET0 PM mean {ok.ET0.mean():.2f} mm/day | r vs Hargreaves {r:.2f} "
          f"(gate >= 0.8) | worst monthly bias {bias.abs().max():.1f}% (gate <= 15%)")
    apr24 = out.loc["2024-04"] if "2024-04" in out.index.strftime("%Y-%m") else None
    if apr24 is not None:
        n = (apr24.HI >= 42).sum()
        print(f"April 2024: max HI {apr24.HI.max():.1f} C, {n} day(s) at PAGASA danger (>= 42 C)")
    if "IMERG_PRECTOT" in out and not out.PRECTOTCORR.equals(out.IMERG_PRECTOT):
        both = out[["PRECTOTCORR", "IMERG_PRECTOT"]].dropna().resample("ME").sum(min_count=20).dropna()
        if len(both) > 12:
            r = both.PRECTOTCORR.corr(both.IMERG_PRECTOT)
            ratio = both.IMERG_PRECTOT.sum() / both.PRECTOTCORR.sum()
            print(f"Rain cross-check (monthly, {both.index.min():%Y}-{both.index.max():%Y}): "
                  f"r(MERRA-2, IMERG) = {r:.2f}, IMERG/MERRA-2 total = {ratio:.2f}")
    if "GWETROOT" in out:
        print(f"GWETROOT range {out.GWETROOT.min():.2f}-{out.GWETROOT.max():.2f} (unitless 0-1)")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", help="muni=path.csv")
    ap.add_argument("--elev", type=float, default=None)
    ap.add_argument("--out", default="pipeline/data/processed")
    a = ap.parse_args(argv)

    outdir = Path(a.out)
    outdir.mkdir(parents=True, exist_ok=True)
    frames, failed = {}, False
    for item in a.files:
        name, paths = item.split("=", 1)
        df, header = None, {}
        for path in paths.split("+"):
            part, h = read_power_csv(path)
            header = {**h, **header}
            df = part if df is None else df.combine_first(part)
        df = use_imerg_if_only_rain(df, name)
        probs = check(df, name)
        if not solar_units_ok(df["ALLSKY_SFC_SW_DWN"].dropna()):
            probs.append("ALLSKY_SFC_SW_DWN looks like kWh/m2/day: re-download with the AG community")
        if probs:
            print(f"\n{name}: CHECKS FAILED\n  - " + "\n  - ".join(probs))
            if any("missing columns" in p or "kWh" in p for p in probs):
                failed = True
                continue
        lat = header.get("lat", LAT.get(name, 15.7))
        elev = a.elev if a.elev is not None else header.get("elevation_m", 50.0)
        print(f"{name}: lat {lat}, elevation {elev} m"
              + ("" if "elevation_m" in header or a.elev else " (default; pass --elev)"))
        out = process(df, lat, elev)
        out.to_csv(outdir / f"power_{name}.csv")
        frames[name] = out
        report(name, out)

    names = list(frames)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a_, b_ = frames[names[i]][NEEDED], frames[names[j]][NEEDED]
            if a_.equals(b_):
                print(f"\nNOTE: {names[i]} and {names[j]} share one POWER grid cell (identical weather).")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())