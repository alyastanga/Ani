"""Known-answer and property tests for zscores.py (spec F1-F4)."""

import numpy as np
import pandas as pd
import pytest
from scipy import stats

from pipeline.zscores import (build, loglogistic_pwm, loo_index, robust_z, spei_value,
                              spi_value)

RNG = np.random.default_rng(42)


def test_spi_of_gamma_sample_is_standard_normal():
    ref = stats.gamma.rvs(2.0, scale=50, size=400, random_state=RNG)
    z = np.array([spi_value(x, ref) for x in ref[:200]])
    assert abs(z.mean()) < 0.15 and abs(z.std() - 1) < 0.15


def test_spi_median_rain_is_near_zero():
    ref = stats.gamma.rvs(2.0, scale=50, size=500, random_state=RNG)
    assert spi_value(np.median(ref), ref) == pytest.approx(0, abs=0.1)


def test_spi_zero_rain_equals_phi_inverse_q():
    ref = np.r_[np.zeros(6), stats.gamma.rvs(1.5, scale=30, size=18, random_state=RNG)]
    q = 6 / 24
    assert spi_value(0.0, ref) == pytest.approx(stats.norm.ppf(q), abs=1e-9)


def test_spi_monotonic_in_rain():
    ref = stats.gamma.rvs(2.0, scale=50, size=30, random_state=RNG)
    xs = np.linspace(1, 300, 20)
    z = [spi_value(x, ref) for x in xs]
    assert all(b > a for a, b in zip(z, z[1:]))


def test_loglogistic_pwm_recovers_parameters():
    # fisk(c=beta, loc=gamma, scale=alpha) is the 3-parameter log-logistic
    alpha, beta, gam = 80.0, 4.0, -150.0
    x = stats.fisk.rvs(beta, loc=gam, scale=alpha, size=20000, random_state=RNG)
    a, b, g = loglogistic_pwm(x)
    assert a == pytest.approx(alpha, rel=0.1)
    assert b == pytest.approx(beta, rel=0.1)
    assert g == pytest.approx(gam, abs=10)


def test_spei_of_loglogistic_sample_is_standard_normal():
    ref = stats.fisk.rvs(4.0, loc=-150, scale=80, size=400, random_state=RNG)
    z = np.array([spei_value(x, ref) for x in ref[:200]])
    assert abs(z.mean()) < 0.15 and abs(z.std() - 1) < 0.15


def test_robust_z_guards_zero_mad():
    assert np.isnan(robust_z(1.0, np.ones(20)))


def test_leave_one_out_excludes_target():
    # a single extreme year must look MORE extreme when it is not in its own baseline
    idx = pd.date_range("2001-04-01", periods=25, freq="12MS")
    vals = np.r_[np.full(24, 10.0) + RNG.normal(0, 1, 24), 12.5]
    s = pd.Series(vals, index=idx)
    loo = loo_index(s, robust_z).iloc[-1]
    incl = robust_z(12.5, vals)
    assert loo > incl


def _daily(years=25, dry_year=None):
    d = pd.date_range("2001-01-01", f"{2000 + years}-12-31")
    doy = d.day_of_year.values
    rain = stats.gamma.rvs(0.6, scale=12, size=len(d), random_state=RNG) * (1 + np.sin(2 * np.pi * (doy - 120) / 365))
    gw = 0.7 + 0.15 * np.sin(2 * np.pi * (doy - 150) / 365) + RNG.normal(0, 0.03, len(d))
    df = pd.DataFrame({"PRECTOTCORR": rain, "ET0": 4 + RNG.normal(0, 0.3, len(d)),
                       "T2M_MAX": 32 + RNG.normal(0, 1, len(d)), "GWETROOT": gw}, index=d)
    if dry_year:
        sel = (df.index.year == dry_year) & (df.index.month <= 4)
        df.loc[sel, "PRECTOTCORR"] = 0
        df.loc[sel, "GWETROOT"] -= 0.2
    return df


def test_build_flags_a_planted_drought_and_sign_is_drier_higher():
    m = build(_daily(dry_year=2016))
    assert m.loc["2016-03", "D"].iloc[0] >= 1
    assert m.loc["2016-03", "label"].iloc[0] in ("bantay", "delikado")
    assert m.loc["2016-03", "dry_rank"].iloc[0] == 1


def test_build_monthly_indices_are_standardised():
    m = build(_daily())
    g = m.groupby(m.index.month)["spi1"]
    assert g.mean().abs().max() < 0.4
    assert (g.std() - 1).abs().max() < 0.4


def test_spei_falls_back_for_negative_skew():
    ref = -stats.gamma.rvs(2.0, scale=10, size=24, random_state=RNG) - 80   # left-skewed
    assert loglogistic_pwm(ref) is None
    lo, hi = spei_value(ref.min() - 5, ref), spei_value(ref.max() + 5, ref)
    assert lo < -1.5 and hi > 1.5


def test_robust_z_uses_sd_when_values_pinned():
    ref = np.r_[np.ones(15), 0.9, 0.95, 0.97, 0.85, 0.92]          # GWETROOT pinned at 1.0
    assert robust_z(0.8, ref) < 0
    assert -3.5 <= robust_z(0.0, ref) <= 3.5


def test_dry_season_uses_spei3_wet_season_spei1():
    m = build(_daily())
    jan, jul = m[m.index.month == 1], m[m.index.month == 7]
    assert (jan["spei_d_k"] == 3).all() and (jul["spei_d_k"] == 1).all()
    ok = jan.dropna(subset=["spei3"])
    assert np.allclose(ok["spei_d"], ok["spei3"])