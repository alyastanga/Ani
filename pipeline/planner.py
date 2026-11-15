"""Step 8: planner M_P (spec 5.5): a farmer profile -> top 3 crop cards, or Hold.

Usage:
    python pipeline/planner.py --muni guimba --water limited_2 --last rice rice \\
        --priorities risk income water [--wont onion] [--cold-storage] [--json]
    python pipeline/planner.py --demo              # a few example farmers per town
    # reads  pipeline/data/processed/risk_<muni>.csv      (uncertainty.py)
    #        pipeline/data/processed/outcomes_<muni>.csv  (fsm.py; heat share for g5)
    #        pipeline/data/processed/enso_dryseason.csv   (enso.py; e = tag_jas of the coming season)

M_P states: Idle -> Filter -> Rank -> Advise, or Filter -> Hold when no crop passes.

PROFILE (the farmer's five answers)
  muni          guimba | munoz | bongabon
  water w       rainfed | limited_2 | limited_4 | full   ("how many times can you irrigate?")
  last          last two crops, most recent first (pest-break criterion)
  wont          crops the farmer will not plant
  cold_storage  yes / no
  priorities    up to 3, ranked, from: income, risk, water, soil, pest

GUARDS (hard; a crop that fails one is removed)
  g1 season   crop is grown in the dry season (all five are)
  g2 water    failure rate at w <= THETA_F (El Nino seasons in El Nino mode, other seasons
              otherwise): the best-estimate X/n shown on the card, from risk_<muni>.csv
  g3 storage  onion without cold storage stays, with a price-risk flag (soft)
  g4 farmer   crop not in wont
  g5 heat     share of seasons with >= 1 heat day at flowering < THETA_H (outcomes_<muni>.csv)
  g6 profit   median net income (Monte Carlo p50) > 0: never recommend an expected loss
  No crop left -> Hold, naming the guard that removed the most crops.

CRITERIA (F14, min-max scaled across the remaining crops; equal values -> 1)
  income  net income p50 (PHP/ha)                      benefit
  risk    failure rate p50                             cost
  water   irrigation need p50 (mm)                     cost
  soil    1 for a legume (adds N), else 0              benefit  (N balance not yet modelled)
  pest    1 if its family differs from both last crops, 0.5 if from one, 0 if neither   benefit
  Labour is NOT a criterion: no labour data (delimitation).

WEIGHTS (F15). Ranked k <= 3 criteria share 0.8 by rank-order centroid (n = k); the others
share 0.2 equally. El Nino mode: water and risk x BETA, then renormalise.
SCORE (F16) U = sum_j w_j x~_j. TOPSIS on the same matrix is reported as a cross-check.
"BAKIT?" = the two criteria with the largest w_j (x~_j - mean over the other candidates):
what sets this crop apart, not what every candidate shares.

CONFIDENCE  Low if the El Nino Wilson interval or the Monte Carlo failure range (p10-p90) is
>= 0.5 wide, or net p10 < 0; Medium if either range is >= 0.3; else High.

DESIGN CHOICES (stated, swept later): THETA_F = 0.5, THETA_H = 0.5, BETA = 1.5, the 0.8 split,
the pest rule (a different botanical family breaks pest and disease cycles).
"""

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd

PROC = Path("pipeline/data/processed")
THETA_F, THETA_H, BETA, RANKED_SHARE = 0.5, 0.5, 1.5, 0.8
CRITERIA = ("income", "risk", "water", "soil", "pest")
BENEFIT = {"income": True, "risk": False, "water": False, "soil": True, "pest": True}
DRY_SEASON_CROPS = {"rice", "onion", "mungbean", "maize", "sweet_potato"}
FAMILY = {"rice": "Poaceae", "maize": "Poaceae", "onion": "Amaryllidaceae",
          "mungbean": "Fabaceae", "sweet_potato": "Convolvulaceae"}
LEGUME = {"mungbean"}
SMALL_MARKET = {"mungbean", "sweet_potato"}
NAME = {"rice": "Palay", "onion": "Sibuyas", "mungbean": "Munggo", "maize": "Mais",
        "sweet_potato": "Kamote"}
WATER_LABEL = {"rainfed": "walang patubig", "limited_2": "mga 2 patubig",
               "limited_4": "mga 4 na patubig", "full": "patubig kung kailangan"}


@dataclass
class Profile:
    muni: str
    water: str
    last: list = field(default_factory=list)
    wont: set = field(default_factory=set)
    cold_storage: bool = False
    priorities: list = field(default_factory=list)
    single: bool = False


# ---------------------------------------------------------------- F15

def roc(n):
    """Rank-order-centroid weights for n ranks (Barron & Barrett 1996)."""
    return np.array([sum(1.0 / i for i in range(k, n + 1)) / n for k in range(1, n + 1)])


def weights(priorities, el_nino):
    pr = [p for p in priorities if p in CRITERIA][:3]
    w = {c: 0.0 for c in CRITERIA}
    if pr:
        for c, r in zip(pr, roc(len(pr))):
            w[c] = RANKED_SHARE * r
        rest = [c for c in CRITERIA if c not in pr]
        for c in rest:
            w[c] = (1 - RANKED_SHARE) / len(rest)
    else:
        w = {c: 1 / len(CRITERIA) for c in CRITERIA}
    if el_nino:
        w["water"] *= BETA
        w["risk"] *= BETA
    s = sum(w.values())
    return {c: v / s for c, v in w.items()}


# ---------------------------------------------------------------- criteria

def pest_score(crop, last):
    fam = FAMILY[crop]
    last = [x for x in last[:2] if x in FAMILY]
    if not last:
        return 1.0
    differs = sum(FAMILY[x] != fam for x in last)
    return differs / len(last)


def scale(raw):
    """F14: min-max per criterion; cost criteria reversed; equal values -> 1."""
    out = raw.copy().astype(float)
    for c in CRITERIA:
        lo, hi = raw[c].min(), raw[c].max()
        x = (raw[c] - lo) / (hi - lo) if hi > lo else pd.Series(1.0, index=raw.index)
        out[c] = x if BENEFIT[c] else (1 - x if hi > lo else x)
    return out


def topsis(raw, w):
    """TOPSIS closeness on the same criteria (cross-check only)."""
    X = raw[list(CRITERIA)].astype(float).values
    norm = np.sqrt((X ** 2).sum(0))
    norm[norm == 0] = 1
    V = X / norm * np.array([w[c] for c in CRITERIA])
    best = np.where([BENEFIT[c] for c in CRITERIA], V.max(0), V.min(0))
    worst = np.where([BENEFIT[c] for c in CRITERIA], V.min(0), V.max(0))
    dp, dm = np.linalg.norm(V - best, axis=1), np.linalg.norm(V - worst, axis=1)
    tot = dp + dm
    return pd.Series(np.divide(dm, tot, out=np.ones_like(tot), where=tot > 0), index=raw.index)


def confidence(r, mode):
    wil = r[f"fail_{mode}_hi"] - r[f"fail_{mode}_lo"]
    mc = r[f"mc_fail_{mode}_p90"] - r[f"mc_fail_{mode}_p10"]
    if wil >= 0.5 or mc >= 0.5 or r[f"mc_net_{mode}_p10"] < 0:
        return "low"
    if wil >= 0.3 or mc >= 0.3:
        return "medium"
    return "high"


# ---------------------------------------------------------------- M_P

def plan(profile, risk, heat_share, el_nino, top=3):
    """Run M_P. risk: risk_<muni>.csv rows for this town. heat_share: {(crop, water): share}.
    Returns a dict with state Advise or Hold, the trace, and the cards."""
    trace = ["Idle", "Filter"]
    mode = "en" if el_nino else "other"
    rows = risk[risk.water == profile.water].set_index("crop")
    blocked = {"g1 season": [], "g2 water": [], "g4 farmer": [], "g5 heat": [], "g6 profit": []}
    keep = []
    for crop in sorted(rows.index):
        r = rows.loc[crop]
        if crop not in DRY_SEASON_CROPS:
            blocked["g1 season"].append(crop)
        elif crop in profile.wont:
            blocked["g4 farmer"].append(crop)
        elif r[f"fail_{mode}_x"] / max(r[f"fail_{mode}_n"], 1) > THETA_F:
            blocked["g2 water"].append(crop)
        elif heat_share.get((crop, profile.water), 0.0) >= THETA_H:
            blocked["g5 heat"].append(crop)
        elif r[f"mc_net_{mode}_p50"] <= 0:
            blocked["g6 profit"].append(crop)
        else:
            keep.append(crop)
    if not keep:
        guard = max(blocked, key=lambda g: (len(blocked[g]), g))
        trace.append("Hold")
        return {"state": "Hold", "trace": trace, "blocked": blocked, "blocking_guard": guard,
                "message": hold_message(guard, profile)}
    trace += ["Rank", "Advise"]
    w = weights(profile.priorities, el_nino)
    raw = pd.DataFrame({
        "income": [rows.loc[c, f"mc_net_{mode}_p50"] for c in keep],
        "risk": [rows.loc[c, f"mc_fail_{mode}_p50"] for c in keep],
        "water": [rows.loc[c, f"mc_irr_{mode}_p50"] for c in keep],
        "soil": [1.0 if c in LEGUME else 0.0 for c in keep],
        "pest": [pest_score(c, profile.last) for c in keep]}, index=keep)
    x = scale(raw)
    score = sum(w[c] * x[c] for c in CRITERIA)
    order = sorted(keep, key=lambda c: (-round(score[c], 9), c))           # deterministic ties
    tp = topsis(raw, w)
    tp_order = sorted(keep, key=lambda c: (-round(tp[c], 9), c))
    edge = x - x.mean()                                   # what sets each crop apart
    profile.single = len(keep) == 1
    cards = [card(c, rows.loc[c], raw.loc[c], edge.loc[c], w, score[c], mode, profile)
             for c in order[:top]]
    return {"state": "Advise", "trace": trace, "blocked": blocked, "weights": w,
            "el_nino": el_nino, "cards": cards, "topsis_top": tp_order[0],
            "topsis_agrees": tp_order[0] == order[0]}


def card(crop, r, raw, edge, w, score, mode, profile):
    n_x, n = int(r[f"fail_{mode}_x"]), int(r[f"fail_{mode}_n"])
    years = "El Niño na taon" if mode == "en" else "taon"
    contrib = sorted(((w[c] * edge[c], c) for c in CRITERIA), reverse=True)
    why = [reason(c, crop, raw, profile) for v, c in contrib[:2] if v > 1e-9]
    if not why and profile.single:                        # the only crop left
        why = [f"Tanging pananim na kaya ang tag-araw na ito sa {WATER_LABEL[profile.water]}",
               reason("risk", crop, raw, profile)]
    elif not why:                                         # no criterion sets it apart
        why = ["Halos kapantay ng ibang pagpipilian"]
    flags = []
    if crop in SMALL_MARKET:
        flags.append("Maliit ang lokal na pamilihan: kumonsulta sa MAO")
    if crop == "onion" and not profile.cold_storage:
        flags.append("Walang cold storage: mataas ang panganib sa presyo")
    conf = confidence(r, mode)
    if conf == "low":
        flags.append("Mababang katiyakan: kumonsulta sa MAO")
    return {"crop": crop, "name": NAME[crop], "score": round(float(score), 3),
            "risk_text": f"Nasira sa {n_x} sa {n} na {years} "
                         f"({r[f'fail_{mode}_lo']:.0%}–{r[f'fail_{mode}_hi']:.0%})",
            "failed": n_x, "seasons": n, "fail_lo": r[f"fail_{mode}_lo"], "fail_hi": r[f"fail_{mode}_hi"],
            "water_mm": round(float(raw["water"])),
            "net_php_ha": {"p10": round(float(r[f"mc_net_{mode}_p10"]), -2),
                           "p50": round(float(r[f"mc_net_{mode}_p50"]), -2),
                           "p90": round(float(r[f"mc_net_{mode}_p90"]), -2)},
            "confidence": conf, "why": why, "flags": flags,
            "trace": [f"g1 season: pass", f"g2 water: fail rate {r[f'mc_fail_{mode}_p50']:.0%} <= {THETA_F:.0%}",
                      "g4 farmer: pass", "g5 heat: pass"]}


def reason(criterion, crop, raw, profile):
    if criterion == "income":
        return f"Kita: mga ₱{raw['income'] / 1000:,.0f}k bawat ektarya (gitnang tantiya)"
    if criterion == "risk":
        return "Mababa ang tsansang masira ngayong tag-araw" if raw["risk"] < 0.2 else \
            f"Tsansang masira: {raw['risk']:.0%}"
    if criterion == "water":
        return f"Kaunting tubig: mga {raw['water']:.0f} mm sa buong panahon"
    if criterion == "soil":
        return "Nagdadagdag ng nitrogen sa lupa (legume)"
    if criterion == "pest":
        return "Iba ang pamilya sa huling tanim: pumuputol sa siklo ng peste"
    return criterion


def hold_message(guard, profile):
    why = {"g2 water": f"Masyadong mataas ang tsansang masira sa {WATER_LABEL[profile.water]} ngayong El Niño",
           "g4 farmer": "Wala nang natirang pananim matapos alisin ang ayaw ninyong itanim",
           "g5 heat": "Masyadong mainit sa panahon ng pamumulaklak",
           "g6 profit": "Walang pananim na inaasahang kikita ngayong tag-araw sa inyong patubig",
           "g1 season": "Walang pananim na angkop sa tag-araw"}[guard]
    return {"title": "Huwag munang magtanim", "reason": why,
            "tip": "Takpan ng dayami (mulch) o iwanang pahinga ang lupa; ihanda ang patubig para sa susunod",
            "refer": "Kumonsulta sa MAO"}


# ---------------------------------------------------------------- data

def load_town(muni):
    risk = pd.read_csv(PROC / f"risk_{muni}.csv")
    out = pd.read_csv(PROC / f"outcomes_{muni}.csv")
    hs = (out.assign(h=out.heat_days >= 1).groupby(["crop", "water"]).h.mean()).to_dict()
    return risk, hs


def coming_season_el_nino():
    e = pd.read_csv(PROC / "enso_dryseason.csv")
    last = e.dropna(subset=["jas"]).iloc[-1]
    return last.tag_jas == "el_nino", last.dry_season


def peso(v):
    return ("−" if v < 0 else "") + f"₱{abs(v):,.0f}"


def print_plan(p, res):
    print(f"\n{p.muni} | {p.water} | last {p.last} | wont {sorted(p.wont)} | cold storage "
          f"{'yes' if p.cold_storage else 'no'} | priorities {p.priorities}")
    print("  trace:", " -> ".join(res["trace"]),
          "| removed:", {g: v for g, v in res["blocked"].items() if v})
    if res["state"] == "Hold":
        m = res["message"]
        print(f"  HOLD ({res['blocking_guard']}): {m['title']}. {m['reason']}. {m['tip']}. {m['refer']}.")
        return
    w = res["weights"]
    print("  weights:", ", ".join(f"{c} {w[c]:.2f}" for c in CRITERIA),
          f"| TOPSIS top = {res['topsis_top']} ({'agrees' if res['topsis_agrees'] else 'DIFFERS'})")
    for i, c in enumerate(res["cards"], 1):
        net = c["net_php_ha"]
        print(f"  {i}. {c['name']} ({c['crop']})  score {c['score']:.2f}  [{c['confidence']}]")
        print(f"     {c['risk_text']} | tubig ~{c['water_mm']} mm | kita {peso(net['p50'])} "
              f"({peso(net['p10'])} – {peso(net['p90'])})")
        for y in c["why"]:
            print(f"     Bakit? {y}")
        for f in c["flags"]:
            print(f"     ! {f}")


DEMO = [
    dict(water="rainfed", last=["rice", "rice"], priorities=["risk", "water", "income"]),
    dict(water="limited_2", last=["rice", "rice"], priorities=["risk", "income", "water"]),
    dict(water="limited_2", last=["rice", "rice"], priorities=["income", "risk", "pest"]),
    dict(water="limited_4", last=["rice", "mungbean"], priorities=["income", "soil", "risk"]),
    dict(water="full", last=["rice", "rice"], priorities=["income", "risk", "water"]),
    dict(water="full", last=["rice", "rice"], priorities=["income", "risk", "water"], cold_storage=True),
]


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--muni")
    ap.add_argument("--water", choices=["rainfed", "limited_2", "limited_4", "full"])
    ap.add_argument("--last", nargs="*", default=[])
    ap.add_argument("--wont", nargs="*", default=[])
    ap.add_argument("--cold-storage", action="store_true")
    ap.add_argument("--priorities", nargs="*", default=[])
    ap.add_argument("--neutral", action="store_true", help="ignore the El Nino tag (normal mode)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--demo", action="store_true")
    a = ap.parse_args(argv)
    el_nino, season = coming_season_el_nino()
    el_nino = el_nino and not a.neutral
    print(f"coming dry season {season}: {'EL NINO mode' if el_nino else 'normal mode'}")
    if a.demo:
        for muni in ("guimba", "munoz", "bongabon"):
            risk, hs = load_town(muni)
            for d in DEMO:
                p = Profile(muni=muni, wont=set(), **{k: v for k, v in d.items()})
                print_plan(p, plan(p, risk, hs, el_nino))
        return 0
    if not (a.muni and a.water):
        ap.error("--muni and --water are required (or use --demo)")
    p = Profile(a.muni, a.water, a.last, set(a.wont), a.cold_storage, a.priorities)
    risk, hs = load_town(a.muni)
    res = plan(p, risk, hs, el_nino)
    if a.json:
        print(json.dumps(res, ensure_ascii=False, indent=1, default=float))
    else:
        print_plan(p, res)
    return 0


if __name__ == "__main__":
    sys.exit(main())