"""Tests for enso.py (spec F13)."""

import pandas as pd

from pipeline.enso import SEASONS, episodes, load, tag_dry_seasons


def _series(rows):
    df = pd.DataFrame(rows, columns=["year"] + SEASONS).set_index("year")
    s = df.stack(future_stack=True)
    s.index = pd.MultiIndex.from_tuples(s.index, names=["year", "season"])
    return s


def test_episode_needs_five_consecutive_seasons():
    four = [0, 0, 0, 0, 0, 0, 0, 0, 0.6, 0.6, 0.6, 0.6]       # only 4 -> not an episode
    five = [0, 0, 0, 0, 0, 0, 0, 0.6, 0.6, 0.6, 0.6, 0.6]      # 5 -> episode
    assert (episodes(_series([[2000] + four])) == 0).all()
    assert episodes(_series([[2000] + five])).loc[(2000, "OND")] == 1


def test_episode_runs_across_the_year_boundary():
    s = _series([[2000] + [0] * 9 + [0.7, 0.8, 0.9], [2001] + [0.8, 0.6] + [0] * 10])
    assert episodes(s).loc[(2000, "SON")] == 1 and episodes(s).loc[(2001, "JFM")] == 1


def test_jas_and_episode_tags_on_the_real_table():
    t = tag_dry_seasons(load()).set_index("dry_season")
    assert t.loc["2015-16", "tag_jas"] == "el_nino" and t.loc["2015-16", "tag_episode"] == "el_nino"
    assert t.loc["2018-19", "tag_jas"] == "neutral" and t.loc["2018-19", "tag_episode"] == "el_nino"
    assert t.loc["2010-11", "tag_episode"] == "la_nina"
    assert t.loc["2026-27", "tag_episode"] == "pending"           # OND 2026 not out yet