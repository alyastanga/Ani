"""Known-answer tests for power_prep.py (write these before trusting real output)."""

import numpy as np
import pandas as pd
import pytest

from pipeline.power_prep import (check, et0_pm, extraterrestrial_ra, heat_index_c,
                                 pagasa_category, read_power_csv, rh_at_tmax, sat_vp)


def test_sat_vp_fao_table():
    # FAO-56 Annex 2, Table 2.3: e°(20 C) = 2.338 kPa
    assert sat_vp(20.0) == pytest.approx(2.338, abs=0.001)


def test_ra_fao_example_8():
    # FAO-56 Example 8: 20 S, 3 September (J = 246) -> Ra = 32.2 MJ m-2 day-1
    assert extraterrestrial_ra(-20.0, 246) == pytest.approx(32.2, abs=0.1)


def test_et0_fao_example_18():
    # FAO-56 Example 18: Uccle, 6 July (J = 187), 50 deg 48' N, 100 m.
    # Tmax 21.5, Tmin 12.3, ea 1.409 kPa, Rs 22.07 MJ, u2 2.078 m/s -> ET0 = 3.9 mm/day
    et0 = et0_pm(21.5, 12.3, 1.409, 22.07, 2.078, 50.80, 187, 100)
    assert et0 == pytest.approx(3.9, abs=0.1)


def test_et0_rises_with_wind_when_dry():
    a = et0_pm(33.0, 23.0, 2.0, 20.0, 1.0, 15.7, 100, 50)
    b = et0_pm(33.0, 23.0, 2.0, 20.0, 3.0, 15.7, 100, 50)
    assert b > a


def test_rh_at_tmax_saturated_and_dry():
    assert rh_at_tmax(30.0, 30.0) == pytest.approx(100.0)
    assert rh_at_tmax(35.0, 22.0) < rh_at_tmax(30.0, 22.0)


def test_heat_index_nws_chart():
    # NWS chart: 90 F, 60% RH -> 100 F (37.8 C), within 1 F
    hi_c = heat_index_c((90 - 32) * 5 / 9, 60)
    assert hi_c * 9 / 5 + 32 == pytest.approx(100, abs=1.0)


def test_heat_index_not_below_temp_when_humid():
    t = np.array([30.0, 33.0, 36.0])
    assert (heat_index_c(t, 60) >= t).all()


def test_pagasa_bins():
    cats = pagasa_category(pd.Series([26.9, 27, 33, 42, 52])).astype(str).tolist()
    assert cats == ["none", "caution", "extreme_caution", "danger", "extreme_danger"]


def _dav_csv(tmp_path, rows):
    head = ("-BEGIN HEADER-\nNASA/POWER Source Native Resolution Daily Data\n"
            "Location: Latitude  15.71   Longitude 120.9\n"
            "Elevation from MERRA-2: Average for 0.5 x 0.625 degree lat/lon region = 61.2 meters\n"
            "-END HEADER-\n")
    cols = "YEAR,MO,DY,T2M_MAX,T2M_MIN,T2MDEW,RH2M,WS2M,ALLSKY_SFC_SW_DWN,PRECTOTCORR,GWETROOT\n"
    p = tmp_path / "munoz.csv"
    p.write_text(head + cols + "\n".join(rows) + "\n")
    return p


def test_reads_dav_header_and_fill(tmp_path):
    p = _dav_csv(tmp_path, ["2024,4,1,36.1,24.0,21.0,62,1.8,22.5,0.0,0.41",
                            "2024,4,2,36.8,24.3,-999,60,1.9,23.0,0.0,0.40"])
    df, header = read_power_csv(p)
    assert header == {"elevation_m": 61.2, "lat": 15.71, "lon": 120.9}
    assert df.index[0] == pd.Timestamp("2024-04-01")
    assert np.isnan(df.loc["2024-04-02", "T2MDEW"])


def test_check_flags_long_gap(tmp_path):
    rows = [f"2024,4,{d},36,24,{-999 if 3 <= d <= 7 else 21},62,1.8,22,0,0.4" for d in range(1, 11)]
    df, _ = read_power_csv(_dav_csv(tmp_path, rows))
    probs = check(df, "munoz")
    assert any("T2MDEW: gap of 5 days" in p for p in probs)