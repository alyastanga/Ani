"""Tests for soil_water.py (spec F5, F6)."""

import numpy as np
import pandas as pd
import pytest

from pipeline.soil_water import (awc_for_depth, balance_error, bucket_step, keep_flooded,
                                 load_crops, p_adjusted, paddy_step, refill_when_stressed,
                                 run_bucket, stress_coefficient, taw_mm)


# ---------------------------------------------------------------- F5 pieces

def test_ks_is_one_above_threshold_and_linear_below():
    # TAW 100, p 0.5 -> stress starts at S = 50
    assert stress_coefficient(80, 100, 0.5) == 1.0
    assert stress_coefficient(50, 100, 0.5) == 1.0
    assert stress_coefficient(25, 100, 0.5) == pytest.approx(0.5)
    assert stress_coefficient(0, 100, 0.5) == 0.0


def test_ks_uses_one_minus_p_not_p():
    # rice p = 0.2: stress starts at 80% of TAW (the plan.md bug started it at 20%)
    assert stress_coefficient(70, 100, 0.2) == pytest.approx(70 / 80)


def test_p_adjustment_and_bounds():
    assert p_adjusted(0.5, 5.0) == pytest.approx(0.5)
    assert p_adjusted(0.5, 7.0) == pytest.approx(0.42)
    assert p_adjusted(0.2, 10.0) == pytest.approx(0.1)        # clipped low
    assert p_adjusted(0.8, 0.0) == pytest.approx(0.8)         # clipped high


def test_drainage_is_booked_before_the_clamp():
    S, eta, dp, ks = bucket_step(S=90, P=30, I=0, ET0=5, Kc=1, taw=100, p=0.5)
    assert eta == pytest.approx(5) and dp == pytest.approx(15) and S == pytest.approx(100)


def test_soil_never_negative_and_eta_cut_to_what_is_there():
    S, eta, dp, ks = bucket_step(S=1, P=0, I=0, ET0=50, Kc=1, taw=10, p=0.5, dt=1)
    assert S == 0 and eta == pytest.approx(1) and dp == 0


# ---------------------------------------------------------------- known answer (spec F5 test)

def _euler(S0, lam_days, dt, taw=100, p=0.5):
    """Dry-down with P = I = 0 inside the stress zone. ET0 picked so ETc = 5 (p_adj = p)."""
    S = S0
    for _ in range(int(round(lam_days / dt))):
        S, *_ = bucket_step(S, 0, 0, ET0=5.0, Kc=1.0, taw=taw, p=p, dt=dt)
    return S


def test_euler_matches_exact_exponential_to_first_order():
    taw, p, S0, days = 100.0, 0.5, 40.0, 30
    lam = 5.0 / ((1 - p) * taw)                                # 0.1 per day
    exact = S0 * np.exp(-lam * days)
    e1 = abs(_euler(S0, days, 1.0) - exact) / exact
    e05 = abs(_euler(S0, days, 0.5) - exact) / exact
    assert _euler(S0, days, 1.0) == pytest.approx(S0 * (1 - lam) ** days)   # Euler closed form
    assert 1.8 < e1 / e05 < 2.2                                # first-order method


# ---------------------------------------------------------------- balance

def _weather(n=400, seed=1):
    rng = np.random.default_rng(seed)
    P = np.where(rng.random(n) < 0.3, rng.gamma(0.8, 20, n), 0.0)
    ET0 = rng.uniform(3, 6.5, n)
    return P, ET0


def test_balance_closes_rainfed_and_irrigated():
    P, ET0 = _weather()
    for irrigate in (False, True):
        res = run_bucket(P, ET0, Kc=1.1, taw=120, p=0.45, S0=60, irrigate=irrigate)
        assert abs(balance_error(60, P, res)) < 1e-9
        assert (res["S"] >= 0).all() and (res["S"] <= 120 + 1e-12).all()


def test_refill_rule_removes_stress():
    P, ET0 = _weather()
    res = run_bucket(P, ET0, Kc=1.1, taw=120, p=0.45, S0=120, irrigate=True)
    assert (res["Ks"] == 1).all() and res["I"].sum() > 0


def test_vectorised_runs_equal_separate_runs():
    P, ET0 = _weather(200)
    taws, ps = np.array([80.0, 120.0, 150.0]), np.array([0.3, 0.45, 0.6])
    many = run_bucket(P, ET0, Kc=1.0, taw=taws, p=ps)
    for i in range(3):
        one = run_bucket(P, ET0, Kc=1.0, taw=taws[i], p=ps[i])
        assert np.allclose(many["S"][:, i], one["S"])


# ---------------------------------------------------------------- F6 paddy

def _paddy_series(P, ET0, h0, SP=2.0, h_bund=100.0, taw=90.0, flood=False):
    h, S = np.array(h0), np.array(taw)
    tot = dict(P=0.0, I=0.0, ETa=0.0, DP=0.0, R=0.0)
    ks_ponded = []
    for t in range(len(P)):
        I = keep_flooded(h, 20.0, 50.0) if flood else 0.0
        was_ponded = h > 0
        h, S, eta, dp, r, ks = paddy_step(h, S, P[t], I, ET0[t], 1.05, taw, 0.2, SP, h_bund)
        if was_ponded:
            ks_ponded.append(float(ks))
        for k, v in zip(("P", "I", "ETa", "DP", "R"), (P[t], I, eta, dp, r)):
            tot[k] += float(v)
    return h, S, tot, ks_ponded


def test_paddy_balance_closes():
    P, ET0 = _weather(300, seed=3)
    for flood in (False, True):
        h, S, t, _ = _paddy_series(P, ET0, h0=50.0, flood=flood)
        err = 50.0 + 90.0 + t["P"] + t["I"] - t["ETa"] - t["DP"] - t["R"] - float(h) - float(S)
        assert abs(err) < 1e-9


def test_ponded_rice_is_unstressed_and_overflow_runs_off():
    h, S, eta, dp, r, ks = paddy_step(h=90, S=90, P=40, I=0, ET0=5, Kc=1.0, taw=90, p=0.2,
                                      SP=2, h_bund=100)
    assert ks == 1.0 and r == pytest.approx(23) and h == 100 and dp == 2


def test_pond_dries_then_soil_takes_over():
    P, ET0 = np.zeros(60), np.full(60, 5.0)
    h, S, t, ks_ponded = _paddy_series(P, ET0, h0=30.0)
    assert float(h) == 0 and float(S) < 90 and all(k == 1 for k in ks_ponded)


def test_continuous_flooding_keeps_pond():
    P, ET0 = np.zeros(60), np.full(60, 5.0)
    h, S, t, _ = _paddy_series(P, ET0, h0=50.0, flood=True)
    assert float(h) > 0 and float(S) == 90


# ---------------------------------------------------------------- inputs

def test_awc_layer_choice():
    row = pd.Series({"awc_mm_per_m_0_30": 150.0, "awc_mm_per_m_0_60": 140.0,
                     "awc_mm_per_m_0_100": np.nan})
    assert awc_for_depth(row, 0.3) == 150.0
    assert awc_for_depth(row, 0.45) == 140.0
    assert awc_for_depth(row, 1.35) == 140.0                  # 0-100 missing -> deepest available
    assert taw_mm(140.0, 0.45) == pytest.approx(63.0)


def test_load_crops(tmp_path):
    f = tmp_path / "crops.csv"
    f.write_text("crop,param,value,low,high,unit,source,status\n"
                 "rice,p,0.2,0.2,0.2,fraction,FAO-56,verified\n"
                 "rice,root_depth_m,0.75,0.5,1.0,m,FAO-56,verified\n")
    c = load_crops(f)
    assert c["rice"]["root_depth_m"] == (0.75, 0.5, 1.0)


# ---------------------------------------------------------------- crop mode

from pipeline.soil_water import crop_season, kc_curve, stage_lengths, stage_of_day  # noqa: E402


def _crop(duration=100.0, stages=(20, 30, 30, 20), p=0.5):
    c = {"duration_days": (duration,) * 3, "kc_ini": (0.4,) * 3, "kc_mid": (1.05,) * 3,
         "kc_end": (0.5,) * 3, "p": (p,) * 3, "root_depth_m": (0.8,) * 3}
    for k, v in zip(("fao_l_ini", "fao_l_dev", "fao_l_mid", "fao_l_late"), stages):
        c[k] = (float(v),) * 3
    return c


def test_stage_lengths_scale_fao_proportions():
    L = stage_lengths(_crop(65.0, (20, 30, 30, 20)))
    assert L.sum() == pytest.approx(65) and L[1] / L[0] == pytest.approx(1.5)


def test_kc_curve_follows_fao_shape():
    kc = kc_curve([20, 30, 30, 20], 0.4, 1.05, 0.5)
    assert len(kc) == 100
    assert kc[:20].tolist() == [0.4] * 20                       # initial: flat
    assert np.all(np.diff(kc[20:50]) > 0)                       # development: rising
    assert np.allclose(kc[50:80], 1.05)                         # mid: flat
    assert np.all(np.diff(kc[80:]) < 0) and kc[-1] > 0.5        # late: falling to Kc_end
    assert stage_of_day([20, 30, 30, 20])[[0, 25, 60, 95]].tolist() == [0, 1, 2, 3]


def test_crop_season_rainfed_vs_irrigated():
    n = 100
    P, ET0 = np.zeros(n), np.full(n, 5.0)
    rf = crop_season(P, ET0, _crop(), taw=100.0, s0_frac=1.0, irrigate=False)
    ir = crop_season(P, ET0, _crop(), taw=100.0, s0_frac=1.0, irrigate=True)
    assert rf["stressed_days"] > 0 and rf["et_deficit"] > 0 and rf["irrigation_mm"] == 0
    assert ir["stressed_days"] == 0 and ir["et_deficit"] == pytest.approx(0)
    assert ir["irrigation_mm"] == pytest.approx(ir["etc_mm"] - 0, rel=0.5)   # roughly ETc minus stored water


def test_wetter_start_means_less_stress():
    P, ET0 = np.zeros(100), np.full(100, 5.0)
    dry = crop_season(P, ET0, _crop(), 100.0, 0.2, False)
    wet = crop_season(P, ET0, _crop(), 100.0, 1.0, False)
    assert wet["stressed_days"] < dry["stressed_days"]