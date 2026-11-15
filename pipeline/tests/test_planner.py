"""Tests for planner.py: the planner machine M_P (spec 5.5)."""

import numpy as np
import pandas as pd
import pytest

from pipeline.planner import (CRITERIA, Profile, pest_score, plan, roc, scale, weights)


def _risk():
    """Small risk table: 5 crops x 2 water levels, El Nino columns only matter."""
    rows = []
    spec = {  # crop: (fail_rate_limited, fail_rate_full, net_p50, irr_mm)
        "rice": (1.0, 0.0, 58_000, 520), "onion": (1.0, 0.0, 700_000, 470),
        "mungbean": (0.0, 0.0, 18_000, 100), "maize": (0.55, 0.0, 37_000, 300),
        "sweet_potato": (0.1, 0.0, 85_000, 330)}
    for crop, (fl, ff, net, irr) in spec.items():
        for water, f in (("limited_2", fl), ("full", ff)):
            r = {"crop": crop, "water": water}
            for m in ("en", "other", "all"):
                r.update({f"fail_{m}_x": round(f * 9), f"fail_{m}_n": 9,
                          f"fail_{m}_lo": max(0, f - 0.2), f"fail_{m}_hi": min(1, f + 0.2)})
            for m in ("en", "other"):
                r.update({f"mc_fail_{m}_p10": f, f"mc_fail_{m}_p50": f, f"mc_fail_{m}_p90": f,
                          f"mc_net_{m}_p10": net * 0.6 if f < 0.5 else -50_000,
                          f"mc_net_{m}_p50": net if f < 0.5 else -50_000,
                          f"mc_net_{m}_p90": net * 1.4, f"mc_irr_{m}_p50": irr})
            rows.append(r)
    return pd.DataFrame(rows)


RISK = _risk()


def test_roc_weights():
    assert np.allclose(roc(3), [0.611, 0.278, 0.111], atol=0.001)
    assert roc(1)[0] == 1.0 and roc(3).sum() == pytest.approx(1)


def test_weights_sum_to_one_and_el_nino_boosts_water_and_risk():
    w0 = weights(["income", "risk", "water"], el_nino=False)
    w1 = weights(["income", "risk", "water"], el_nino=True)
    assert sum(w0.values()) == pytest.approx(1) and sum(w1.values()) == pytest.approx(1)
    assert w0["income"] == pytest.approx(0.8 * 0.611, abs=0.001)
    assert w1["water"] > w0["water"] and w1["income"] < w0["income"]
    assert all(v > 0 for v in w0.values())               # unranked criteria never drop to zero


def test_pest_score():
    assert pest_score("mungbean", ["rice", "rice"]) == 1.0
    assert pest_score("maize", ["rice", "rice"]) == 0.0          # same family (grasses)
    assert pest_score("maize", ["rice", "mungbean"]) == 0.5
    assert pest_score("onion", []) == 1.0


def test_scaling_reverses_cost_criteria():
    raw = pd.DataFrame({"income": [10, 30], "risk": [0.1, 0.5], "water": [100, 300],
                        "soil": [1, 0], "pest": [1, 1]}, index=["a", "b"])
    x = scale(raw)
    assert x.loc["b", "income"] == 1 and x.loc["a", "risk"] == 1 and x.loc["a", "water"] == 1
    assert (x["pest"] == 1).all()                         # equal values -> 1


def test_water_guard_removes_high_failure_crops():
    p = Profile("guimba", "limited_2", ["rice", "rice"], set(), False, ["income"])
    res = plan(p, RISK, {}, el_nino=True)
    names = [c["crop"] for c in res["cards"]]
    assert set(res["blocked"]["g2 water"]) == {"rice", "onion", "maize"}
    assert "rice" not in names and "onion" not in names
    assert res["state"] == "Advise" and res["trace"] == ["Idle", "Filter", "Rank", "Advise"]


def test_priorities_change_the_ranking():
    base = dict(muni="guimba", water="full", last=["rice", "rice"], wont=set(), cold_storage=True)
    income = plan(Profile(**base, priorities=["income", "risk", "water"]), RISK, {}, True)
    water = plan(Profile(**base, priorities=["water", "soil", "risk"]), RISK, {}, True)
    assert income["cards"][0]["crop"] == "onion"
    assert water["cards"][0]["crop"] == "mungbean"


def test_hold_when_nothing_passes_and_names_the_guard():
    p = Profile("guimba", "limited_2", [], {"mungbean", "sweet_potato"}, False, ["risk"])
    res = plan(p, RISK, {}, el_nino=True)
    assert res["state"] == "Hold" and res["trace"][-1] == "Hold"
    assert res["blocking_guard"] == "g2 water"
    assert res["message"]["title"] == "Huwag munang magtanim"


def test_heat_guard():
    p = Profile("guimba", "full", [], set(), True, ["income"])
    res = plan(p, RISK, {("onion", "full"): 0.8}, el_nino=True)
    assert "onion" in res["blocked"]["g5 heat"]


def test_flags_and_determinism():
    p = Profile("guimba", "full", ["rice", "rice"], set(), False, ["income", "risk", "water"])
    a, b = plan(p, RISK, {}, True), plan(p, RISK, {}, True)
    assert a == b
    onion = next(c for c in a["cards"] if c["crop"] == "onion")
    assert any("cold storage" in f for f in onion["flags"])
    p2 = Profile("guimba", "limited_2", [], set(), False, ["water"])
    mung = next(c for c in plan(p2, RISK, {}, True)["cards"] if c["crop"] == "mungbean")
    assert any("MAO" in f for f in mung["flags"])


def test_profit_guard_removes_expected_losses():
    risk = RISK.copy()
    m = (risk.crop == "maize") & (risk.water == "full")
    risk.loc[m, "mc_net_en_p50"] = -5_000
    res = plan(Profile("guimba", "full", [], set(), True, ["income"]), risk, {}, True)
    assert "maize" in res["blocked"]["g6 profit"]


def test_single_candidate_explains_why_it_survived():
    p = Profile("guimba", "limited_2", [], {"sweet_potato"}, False, ["risk"])
    res = plan(p, RISK, {}, True)
    assert [c["crop"] for c in res["cards"]] == ["mungbean"]
    assert res["cards"][0]["why"][0].startswith("Tanging pananim")