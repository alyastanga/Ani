"""Tests for uncertainty.py: Wilson interval and parity of the vectorised field machine."""

import numpy as np
import pandas as pd
import pytest

from pipeline.fsm import Params, run_season
from pipeline.uncertainty import simulate_runs, wilson


def test_wilson_known_values():
    lo, hi = wilson(5, 7)
    assert lo == pytest.approx(0.359, abs=0.002) and hi == pytest.approx(0.918, abs=0.002)
    assert wilson(0, 9)[0] == 0 and wilson(9, 9)[1] == 1
    assert np.isnan(wilson(0, 0)[0])


def _cases():
    rng = np.random.default_rng(3)
    out = []
    for k in range(12):
        n = 260
        w = pd.DataFrame({"T2M_MAX": rng.uniform(28, 37, n), "T2M_MIN": rng.uniform(18, 26, n),
                          "PRECTOTCORR": np.where(rng.random(n) < 0.15, rng.gamma(0.8, 15, n), 0.0),
                          "ET0": rng.uniform(3, 7, n)},
                         index=pd.date_range("2010-12-01", periods=n, name="date"))
        prm = Params(crop="maize", taw=float(rng.uniform(40, 180)), p=float(rng.uniform(0.2, 0.6)),
                     kc_ini=0.3, kc_mid=1.2, kc_end=0.5, t_base=10.0,
                     g_mat=float(rng.uniform(1500, 2100)), f_e=0.16, f_v=0.44, f_r=0.76,
                     t_crit=35.0 if k % 2 else None, irrigated=k % 3 > 0,
                     max_irr=[None, 2, 4][k % 3] if k % 3 else None,
                     ks_fail=float(rng.uniform(0.4, 0.6)), k_fail=int(rng.integers(8, 13)))
        out.append((w, prm, float(rng.uniform(0.1, 1.0))))
    return out


def test_vectorised_machine_matches_field_machine_run_for_run():
    cases = _cases()
    D = 260
    stack = lambda col: np.column_stack([w[col].values[:D] for w, _, _ in cases])
    get = lambda attr, fill=np.nan: np.array([fill if getattr(p, attr) is None else getattr(p, attr)
                                              for _, p, _ in cases], dtype=float)
    prm = {k: get(k) for k in ("taw", "p", "kc_ini", "kc_mid", "kc_end", "t_base", "g_mat",
                               "f_e", "f_v", "f_r", "ks_fail", "k_fail")}
    prm["t_crit"] = get("t_crit")
    prm["irrigated"] = np.array([p.irrigated for _, p, _ in cases])
    prm["max_irr"] = get("max_irr", np.inf)
    prm["s0"] = np.array([s * p.taw for _, p, s in cases])
    v = simulate_runs(stack("T2M_MAX"), stack("T2M_MIN"), stack("PRECTOTCORR"), stack("ET0"), prm)
    for i, (w, p, s) in enumerate(cases):
        o, _, _ = run_season(p, w, s)
        assert v["failed"][i] == o["failed"], i
        assert v["stress_days"][i] == o["stress_days"], i
        assert v["heat_days"][i] == o["heat_days"], i
        assert v["irrigation_mm"][i] == pytest.approx(o["irrigation_mm"], abs=0.06), i
        hd = o["harvest_day"]
        assert (np.isnan(v["harvest_day"][i]) and hd is None) or v["harvest_day"][i] == hd, i