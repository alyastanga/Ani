"""Tests for fsm.py: the field machine M_F (spec 5.4)."""

import numpy as np
import pandas as pd
import pytest

from pipeline.fsm import STATES, FieldMachine, Params, g_mat_for_site, gdd, run_season


def _prm(**kw):
    base = dict(crop="maize", taw=150.0, p=0.55, kc_ini=0.3, kc_mid=1.2, kc_end=0.475,
                t_base=10.0, g_mat=1650.0, f_e=0.16, f_v=0.44, f_r=0.76)
    base.update(kw)
    return Params(**base)


def _weather(n=220, tmax=33.0, tmin=23.0, P=0.0, et0=5.0):
    idx = pd.date_range("2010-12-01", periods=n, name="date")
    return pd.DataFrame({"T2M_MAX": tmax, "T2M_MIN": tmin, "PRECTOTCORR": P, "ET0": et0}, index=idx)


# ---------------------------------------------------------------- F7

def test_gdd():
    assert gdd(33, 23, 10) == pytest.approx(18)
    assert gdd(12, 5, 10) == pytest.approx(1)          # Tmin raised to T_base
    assert gdd(8, 2, 10) == 0
    assert gdd(40, 25, 10, t_up=34) == pytest.approx(19.5)


def test_g_mat_reproduces_guide_duration_in_a_normal_year():
    w = _weather(400)                                   # GDD 18/day, every year the same
    c = {"t_base_c": (10.0,), "duration_days": (110.0,), "sow_day": (30,)}
    daily = pd.concat([w.set_index(pd.date_range(f"{y}-11-01", periods=400, name="date"))
                       for y in (2003,)])
    assert g_mat_for_site(daily, c, [2003]) == pytest.approx(110 * 18)


# ---------------------------------------------------------------- stages, determinism, totality

def test_normal_season_runs_all_stages_in_order_and_harvests_on_time():
    prm = _prm(g_mat=110 * 18, irrigated=True)
    o, trace, alerts = run_season(prm, _weather(), s0_frac=1.0)
    path = [t[2] for t in trace]
    assert path == ["Prep", "Estab", "Veg", "Repro", "Mature", "Harvest", "Fallow"]
    assert abs(o["harvest_day"] - 110) <= 1 and not o["failed"]


def test_hot_season_matures_earlier():
    prm = _prm(g_mat=110 * 18, irrigated=True)
    hot, _, _ = run_season(prm, _weather(tmax=36, tmin=25), 1.0)      # 20.5 GDD/day
    assert hot["harvest_day"] < 100


def test_deterministic():
    prm = _prm(g_mat=1980)
    a = run_season(prm, _weather(P=2.0), 0.6)
    b = run_season(prm, _weather(P=2.0), 0.6)
    assert a[0] == b[0] and a[1] == b[1]


def test_total_and_single_transition_per_tick():
    rng = np.random.default_rng(0)
    m = FieldMachine(_prm(g_mat=900))
    m.sow(80)
    for _ in range(400):
        before = len(m.trace)
        m.tick(rng.uniform(20, 40), rng.uniform(15, 27), rng.gamma(0.5, 10), rng.uniform(2, 7))
        assert len(m.trace) - before <= 1 and m.q in STATES
        if m.q == "Fallow":
            break
    assert m.q == "Fallow"


# ---------------------------------------------------------------- guards

def test_rainfed_drought_fails_and_irrigated_does_not():
    dry = _weather(P=0.0, et0=6.0)
    rf, trace, alerts = run_season(_prm(g_mat=1980, irrigated=False), dry, 0.3)
    ir, _, _ = run_season(_prm(g_mat=1980, irrigated=True), dry, 0.3)
    assert rf["failed"] and "Failed" in [t[2] for t in trace] and rf["main_reason"].startswith("water")
    assert any(a == "water_fail" for _, a in alerts)
    assert not ir["failed"] and ir["stress_days"] == 0 and ir["irrigation_mm"] > 0


def test_failure_guard_outranks_stage_progress():
    # severe stress already counted on the day G reaches the next stage: Failed wins
    m = FieldMachine(_prm(g_mat=100, f_e=0.1, f_v=0.5, f_r=0.9, k_fail=1, taw=10, irrigated=False))
    m.sow(0.0)
    m.tick(33, 23, 0, 6)                     # Prep -> Estab
    m.tick(33, 23, 0, 6)                     # Estab -> Veg
    m.tick(33, 23, 0, 6)                     # in Veg, Ks = 0 -> ksev 1 >= k_fail -> Failed
    assert m.q == "Failed"


def test_heat_days_counted_only_in_repro_for_crops_with_t_crit():
    prm = _prm(crop="rice", g_mat=110 * 18, t_crit=35.0, irrigated=True)
    w = _weather(tmax=33)
    w.iloc[5:15, w.columns.get_loc("T2M_MAX")] = 36.0          # early season: Estab/Veg
    w.iloc[60:70, w.columns.get_loc("T2M_MAX")] = 36.0         # inside Repro (day ~48-84)
    o, _, alerts = run_season(prm, w, 1.0)
    assert o["heat_days"] == 10 and o["main_reason"].startswith("heat")
    no_tcrit, _, _ = run_season(_prm(g_mat=110 * 18, irrigated=True), w, 1.0)
    assert no_tcrit["heat_days"] == 0


def test_onion_rot_alert():
    prm = _prm(crop="onion", g_mat=110 * 18, f_e=0.1, rot_p98=60.0, irrigated=True)
    w = _weather()
    w.iloc[2:5, w.columns.get_loc("PRECTOTCORR")] = 25.0       # 75 mm in 3 days while in Estab
    _, _, alerts = run_season(prm, w, 1.0)
    assert any(a == "rot_risk" for _, a in alerts)


def test_water_balance_closes_inside_the_machine():
    prm = _prm(g_mat=1980, irrigated=True)
    w = _weather(P=3.0)
    m = FieldMachine(prm)
    m.sow(90.0)
    for r in w.itertuples():
        m.tick(r.T2M_MAX, r.T2M_MIN, r.PRECTOTCORR, r.ET0)
        if m.q in ("Harvest", "Failed", "Fallow"):
            break
    assert 90.0 + m.rain + m.irr - m.eta - m.dp - m.S == pytest.approx(0, abs=1e-9)


def test_limited_irrigation_caps_events_and_sits_between_rainfed_and_full():
    dry = _weather(P=0.0, et0=6.0)
    res = {k: run_season(_prm(g_mat=1980, irrigated=k > 0, max_irr=None if k == 99 else k), dry, 0.5)[0]
           for k in (0, 2, 4, 99)}
    assert res[2]["irrigations"] == 2 and res[4]["irrigations"] == 4
    assert res[0]["irrigation_mm"] < res[2]["irrigation_mm"] < res[4]["irrigation_mm"] < res[99]["irrigation_mm"]
    assert res[99]["stress_days"] == 0 and res[0]["stress_days"] >= res[4]["stress_days"]