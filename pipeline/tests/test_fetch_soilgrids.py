"""Tests for fetch_soilgrids.py on a SoilGrids-shaped JSON fixture."""

import pytest

import json

import pandas as pd

from pipeline.fetch_soilgrids import (TOWNS, candidates, check, is_valid, km_between, main,
                                      nearest_valid, parse, summarise, weighted)

DEPTHS = [(0, 5), (5, 15), (15, 30), (30, 60), (60, 100)]


def _doc(fc, wp, clay=450, sand=200, missing=False, lat=15.71, lon=120.9):
    def layer(name, vals):
        return {"name": name, "depths": [
            {"range": {"top_depth": t, "bottom_depth": b, "unit_depth": "cm"},
             "label": f"{t}-{b}cm", "values": {"mean": None if missing else v}}
            for (t, b), v in zip(DEPTHS, vals)]}
    return {"type": "Feature", "geometry": {"type": "Point", "coordinates": [lon, lat]},
            "properties": {"layers": [layer("wv0033", fc), layer("wv1500", wp),
                                      layer("clay", [clay] * 5), layer("sand", [sand] * 5)]}}


def test_uniform_profile():
    layers = parse(_doc([400] * 5, [250] * 5))
    row = summarise("munoz", 15.71, 120.9, layers)
    assert row["theta_fc_0_60"] == 0.4 and row["theta_wp_0_60"] == 0.25
    assert row["awc_mm_per_m_0_60"] == 150.0          # 400 - 250 mm/m
    assert row["clay_pct_0_30"] == 45.0
    assert check(row) == []


def test_thickness_weighting():
    # 0-30 cm: layers 5, 10, 15 cm thick with values 100, 200, 300
    layers = parse(_doc([100, 200, 300, 400, 500], [0] * 5))
    assert weighted(layers, "wv0033", 30) == pytest.approx((100 * 5 + 200 * 10 + 300 * 15) / 30)


def test_missing_pixel_is_flagged():
    row = summarise("munoz", 15.71, 120.9, parse(_doc([400] * 5, [250] * 5, missing=True)))
    assert row["awc_mm_per_m_0_60"] is None
    assert any("missing values" in p for p in check(row))


def test_implausible_awc_is_flagged():
    row = summarise("x", 0, 0, parse(_doc([300] * 5, [290] * 5)))   # AWC 10 mm/m
    assert any("outside the plausible" in p for p in check(row))


def test_km_between_one_degree_latitude():
    assert km_between(15.0, 121.0, 16.0, 121.0) == pytest.approx(111.2, abs=0.2)


def test_candidates_start_at_centre_and_grow():
    c = candidates(15.66, 120.77)
    assert c[0][0] == 0 and (c[0][1], c[0][2]) == (15.66, 120.77)
    assert all(a[0] <= b[0] for a, b in zip(c, c[1:])) and c[-1][0] <= 5.0


def _fake_fetcher(null_within_km, town):
    """Built-up centre: pixels closer than null_within_km return nulls."""
    calls = []
    def f(lat, lon):
        calls.append((lat, lon))
        d = km_between(town[0], town[1], lat, lon)
        return _doc([400] * 5, [250] * 5, missing=d < null_within_km, lat=lat, lon=lon)
    f.calls = calls
    return f


def test_nearest_valid_skips_built_up_pixels():
    town = TOWNS["Guimba"]
    f = _fake_fetcher(0.5, town)
    hits = nearest_valid(*town, fetcher=f, wait=0, log=lambda *_: None)
    assert len(hits) == 1 and 0.5 <= hits[0][0] < 0.9
    assert is_valid(hits[0][3])


def test_main_replaces_offsite_file(tmp_path):
    # an old file 45 km away (the degrees-minutes mix-up) must not be used
    (tmp_path / "SOIL_Guimba.json").write_text(json.dumps(_doc([400] * 5, [250] * 5, lat=15.39, lon=120.46)))
    for label in ("Munoz", "Bongabon"):
        la, lo = TOWNS[label]
        (tmp_path / f"SOIL_{label}.json").write_text(json.dumps(_doc([400] * 5, [250] * 5, lat=la + 0.01, lon=lo)))
    f = _fake_fetcher(0.5, TOWNS["Guimba"])
    assert main(["--dir", str(tmp_path), "--out", str(tmp_path / "out")], fetcher=f, wait=0) == 0
    assert not list(tmp_path.glob("*.offsite.json"))
    lon, lat = json.loads((tmp_path / "SOIL_Guimba.json").read_text())["geometry"]["coordinates"][:2]
    assert km_between(*TOWNS["Guimba"], lat, lon) < 1.0                    # overwritten with the in-town pixel
    soil = pd.read_csv(tmp_path / "out" / "soil.csv").set_index("muni")
    assert soil.loc["guimba", "km_from_town"] < 1.0
    assert soil.loc["munoz", "km_from_town"] == pytest.approx(1.11, abs=0.05)   # saved in-town file reused
    assert len(f.calls) < 40                                                 # only Guimba was searched


def test_average_of_n_pixels_reports_range(tmp_path):
    town = TOWNS["Bongabon"]
    i = {"k": 0}
    def f(lat, lon):
        i["k"] += 1
        return _doc([380 + i["k"]] * 5, [250] * 5, lat=lat, lon=lon)
    assert main(["--dir", str(tmp_path), "--out", str(tmp_path / "o"), "--n", "3"], fetcher=f, wait=0) == 0
    soil = pd.read_csv(tmp_path / "o" / "soil.csv").set_index("muni")
    assert (soil["n_pixels"] == 3).all()
    assert (soil["awc_0_60_max"] > soil["awc_0_60_min"]).all()