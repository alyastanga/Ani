"""Tests for export_fixtures.py: golden cases for the Dart ports."""

import json

import numpy as np
import pandas as pd
import pytest

from pipeline import export_fixtures as X
from pipeline import planner as P
from pipeline import power_prep as PP
from pipeline import zscores as Z
from pipeline.fsm import FieldMachine, Params

NAMES = ("planner.json", "field_machine.json", "numeric.json")


@pytest.fixture(scope="module")
def fx(tmp_path_factory):
    out = tmp_path_factory.mktemp("fx")
    assert X.main(["--out", str(out)]) == 0
    return out


def _load(d, name):
    return json.loads((d / name).read_text(encoding="utf-8"))


def test_deterministic_byte_identical(fx, tmp_path):
    assert X.main(["--out", str(tmp_path)]) == 0
    for n in NAMES:
        assert (fx / n).read_bytes() == (tmp_path / n).read_bytes()


def test_headers_and_size(fx):
    total = 0
    for n in NAMES:
        doc = _load(fx, n)
        h = doc["header"]
        assert h["schema"] == X.SCHEMA and h["generated_from"]["sources"]
        total += (fx / n).stat().st_size
    assert total < 5_000_000


def test_planner_grid_coverage(fx):
    doc = _load(fx, "planner.json")
    cases = doc["cases"]
    assert len(cases) == 3 * 4 * len(X.COMBOS) * 2
    assert len({c["id"] for c in cases}) == len(cases)
    assert {c["profile"]["muni"] for c in cases} == set(X.TOWNS)
    assert {c["profile"]["water"] for c in cases} == set(X.WATERS)
    states = {c["expect"]["state"] for c in cases}
    assert states == {"Advise", "Hold"}
    for c in cases:
        e = c["expect"]
        assert {"state", "trace", "blocked"} <= set(e)
        if e["state"] == "Hold":
            assert e["blocking_guard"] in e["blocked"] and e["message"]["title"]
        else:
            assert 1 <= len(e["cards"]) <= 3 and "weights" in e
            for card in e["cards"]:
                assert {"crop", "score", "why", "confidence", "flags", "risk_text"} <= set(card)


def test_planner_fixtures_replay_to_same_cards(fx):
    doc = _load(fx, "planner.json")
    for c in doc["cases"][::7]:
        pr = c["profile"]
        risk, hs = P.load_town(pr["muni"])
        prof = P.Profile(pr["muni"], pr["water"], list(pr["last"]), set(pr["wont"]),
                         pr["cold_storage"], list(pr["priorities"]))
        res = P.plan(prof, risk, hs, c["el_nino"])
        assert res["state"] == c["expect"]["state"]
        if res["state"] == "Hold":
            assert res["blocking_guard"] == c["expect"]["blocking_guard"]
            continue
        assert [k["crop"] for k in res["cards"]] == [k["crop"] for k in c["expect"]["cards"]]
        assert [k["why"] for k in res["cards"]] == [k["why"] for k in c["expect"]["cards"]]
        assert [k["score"] for k in res["cards"]] == pytest.approx(
            [k["score"] for k in c["expect"]["cards"]], abs=1e-6)


def test_field_machine_cases_replay(fx):
    doc = _load(fx, "field_machine.json")
    cases = doc["cases"]
    assert len(cases) == len(X.TOWNS) * 5 * 3
    assert {(c["muni"], c["crop"]) for c in cases} == {(m, k) for m in X.TOWNS for k in
                                                       ("rice", "onion", "mungbean", "maize", "sweet_potato")}
    assert any(c["outcome"]["failed"] for c in cases) and any(not c["outcome"]["failed"] for c in cases)
    cols = doc["cases"][0]["columns"]
    assert cols == X.FM_COLS
    for c in cases[::6]:
        m = FieldMachine(Params(**c["params"]))
        m.sow(c["s0_frac"] * c["params"]["taw"])
        for row in c["days"]:
            out = m.tick(*row[:4])
            assert m.q == row[4] and out == row[-1]
            assert m.G == pytest.approx(row[6], abs=1e-6) and m.S == pytest.approx(row[7], abs=1e-6)
        assert c["days"][-1][4] == "Fallow" and c["days"][-1][-1] == ["outcome"]


def test_numeric_sections_and_values(fx):
    doc = _load(fx, "numeric.json")
    assert {"et0", "heat_index", "zscores", "robust_z_edge"} <= set(doc)
    assert {e["muni"] for e in doc["et0"]} == set(X.TOWNS)
    for e in doc["et0"]:                                   # matches the processed CSV to its rounding
        assert e["expect"]["et0_rounded"] == pytest.approx(e["expect"]["et0_csv"], abs=1e-9)
        i = e["in"]
        v = PP.et0_pm(i["tmax"], i["tmin"], PP.sat_vp(i["tdew"]), i["rs"], i["u2"], i["lat"], i["doy"], i["elev"])
        assert float(v) == pytest.approx(e["expect"]["et0"], abs=1e-6)
    cats = {h["expect"]["category"] for h in doc["heat_index"]}
    assert cats == {"none", "caution", "extreme_caution", "danger", "extreme_danger"}
    for h in doc["heat_index"]:
        if h["muni"] != "synthetic":
            assert h["expect"]["hi_rounded"] == pytest.approx(h["expect"]["hi_csv"], abs=1e-9)
    zs = doc["zscores"]
    assert any(z["spei"]["fallback"] for z in zs)
    assert {z["month"][5:] for z in zs} >= {f"{m:02d}" for m in range(1, 13)}
    for z in zs:
        if z["spei"]["x"] is not None:
            assert Z.spei_value(z["spei"]["x"], z["spei"]["ref"]) == pytest.approx(z["spei"]["expect"], abs=1e-6)
        if z["robust_z"]["x"] is not None and z["robust_z"]["expect"] is not None:
            assert Z.robust_z(z["robust_z"]["x"], z["robust_z"]["ref"]) == pytest.approx(
                z["robust_z"]["expect"], abs=1e-6)
        csv_d = z["D"]["csv"].get("D")
        if z["D"]["expect"] is not None and csv_d is not None:   # monthly CSV is rounded to 3 dp
            assert z["D"]["expect"] == pytest.approx(csv_d, abs=2e-3)
    for e in doc["robust_z_edge"]:
        exp = e["expect"]
        got = Z.robust_z(e["x"], e["ref"])
        assert (exp is None and np.isnan(got)) or got == pytest.approx(exp, abs=1e-6)
