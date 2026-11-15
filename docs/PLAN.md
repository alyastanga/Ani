# Ani — phased build plan (Flutter app on top of the existing pipeline)

## Context

**Source of truth:** `NASA Space Apps Challenge.docx` (Ani: EFSM-based decision support for El Niño dry-season crop selection in Guimba, Muñoz, Bongabon).

**Where we are.** The repo already contains the whole Python data pipeline the doc describes (Ch. 3–5): `pipeline/power_prep.py`, `enso.py`, `zscores.py`, `soil_water.py`, `fsm.py` (field machine), `planner.py` (planner machine), `uncertainty.py` (Wilson + Monte Carlo), `export_json.py`, with a pytest suite. What does **not** exist is the thing the doc's outputs are delivered through: the **offline mobile application** (Objective 5, Figures 2–4, IPO table). `pipeline/data/export/ani_<town>.json` is also not generated/committed yet.

**Decisions made with the user**
- App is built in **Flutter** (installed at `~/develop/flutter`).
- In-season weather comes from **NASA POWER when online**, cached on device; the app keeps working offline from cache + bundled JSON. No backend.

**Design input.** Figma Make file "Farmer Decision Assistant" (`hVFlRMi1DzR7e79YZYFsW1`) is a React/Tailwind prototype branded "Fieldwise" with placeholder content (Hudson Valley, tomatoes, °F, 7-day forecast). We take its **visual language and screen skeleton**, and the doc decides **content and behaviour**. Where they conflict, the doc wins.

| Figma screen | Becomes in Ani (doc reference) |
|---|---|
| Onboarding step 1: language (English / Filipino) | Same. Doc-quoted strings stay Filipino in both ("Huwag munang magtanim", "Bakit?", "Bantay", "Delikado", "Kumonsulta sa MAO") |
| Onboarding step 2: "Where is your farm?" (3 farm cards) | Town picker: Guimba, Science City of Muñoz, Bongabon |
| Dashboard (weather hero, heat advisory, crop overview, needs attention, insight banner) | **Start** (Fig. 2): El Niño season outlook, dryness banner Normal/Bantay/Delikado + "driest r of n years", heat-safety strip, tracked-crop summary, alerts list, CTA "What should I plant?" |
| Forecast (7-day, hourly) | **Season outlook**: El Niño tag + JAS value, monthly dryness-index chart, heat index + "Magtrabaho nang maaga". No 7-day/hourly forecast (not in the doc) |
| Crop library (6 crops, "% match", modal) | The 5 doc crops with duration, water need, family, and per-town risk by irrigation level. No "% match" |
| My farm (crop rows, stage timeline, add crop) | **Track planted crop** (Fig. 4): crop + planting date + method, stage timeline Prep→Estab→Veg→Repro→Mature→Harvest/Failed, alerts |
| Notification popover | In-season alerts: water now, heat at flowering, onion rot, failed, harvest ready |
| *(missing in Figma)* | **Recommendation flow** (Fig. 3): 5-answer questionnaire → 3 crop cards or Hold screen. Built in the same visual language (onboarding-choice + card styles) |

Design tokens to carry over (from Make `src/index.css`): cream `#f5efe3`, paper `#fffdf8`, olive `#4f5b2a`, olive-dark `#354019`, gold `#b8892d`, sand `#d8c9a8`, ink `#29301b`, muted `#797b69`, line `#dfd8c9`; font Asap Condensed (bundled as an asset, not fetched); bottom nav with 4 tabs on mobile.

## APIs needed

**The app calls exactly one API at runtime; it needs no key, no account and no backend.**

| API | Used by | When | Auth |
|---|---|---|---|
| **NASA POWER Daily Point API** — `GET https://power.larc.nasa.gov/api/temporal/daily/point?community=AG&latitude=..&longitude=..&start=YYYYMMDD&end=YYYYMMDD&format=JSON&parameters=T2M_MAX,T2M_MIN,T2MDEW,RH2M,WS2M,ALLSKY_SFC_SW_DWN,PRECTOTCORR,GWETROOT` | Flutter app (Phase 4–5) | When online: from planting date / last cached day to today, per town | None |
| ISRIC SoilGrids REST (`rest.isric.org/soilgrids/v2.0/properties/query`) | Pipeline only (`fetch_soilgrids.py`, already written) | Once, before release | None |
| NOAA CPC RONI table | Pipeline only (`oni.csv`, copied by hand; no API) | Once per season | None |
| PSA OpenSTAT / PalayStat | Pipeline only (already baked into `crops.csv`) | Manual | None |
| NASA AppEEARS (SMAP, MODIS) | Optional validation only, not in the app | Optional | Earthdata login |

Notes on POWER for the app:
- Rainfall parameter name must match what the pipeline used (`PRECTOTCORR` column in `power_<town>.csv`; README allows `IMERG_PRECTOT`) — confirm in Phase 0 and record it in `meta`.
- POWER publishes with a lag of a few days and returns `-999` for missing values; the tracker advances only on real days and shows "waiting for data" for the rest.
- ET₀ and heat index are not POWER parameters we fetch; the app computes them on device (`et0.dart`, `heat_index.dart`) exactly as `power_prep.py` does.
- Everything else (risk tables, El Niño label, soil, crop parameters) ships inside `ani_<town>.json`, so recommendations work with no network at all.

## Repo layout after the work

```
pipeline/            (existing; small export additions in Phase 0)
app/                 (new Flutter project)
  assets/data/ani_{guimba,munoz,bongabon}.json
  assets/fixtures/   golden cases generated by the pipeline for parity tests
  lib/core/          pure Dart ports: planner, field machine, alert machine, et0, heat index, dryness
  lib/data/          bundle loader, POWER client, local store
  lib/features/      onboarding, home, recommend, outlook, library, farm
  lib/theme/, lib/l10n/
  test/              parity + unit + widget tests
```

## Phase 0 — Pipeline contract (Python, small)

Goal: the JSON is everything the phone needs, and Python can produce test fixtures for Dart.

1. Run the pipeline end to end (README steps 1–9) and confirm `python -m pytest pipeline/tests` passes; generate `pipeline/data/export/ani_<town>.json`.
2. Extend `pipeline/export_json.py` `build()` (bump `SCHEMA` to 2) with what live in-season features need but v1 lacks:
   - `dryness.reference`: per calendar month, the baseline arrays needed to score a new month on device — 3-month (Nov–Apr) / 1-month `P − ET0` balances and monthly mean `GWETROOT` per year (reuse `zscores.monthly`, `accumulate`). ~25 values × 12 × 2 per town.
   - `tracker.s0_frac_by_doy`: median starting soil-water fraction by sowing day from `bucket_<town>.csv`, for seasons with no observed start value.
   - `meta.point` already present; add POWER parameter list so the app's request matches `power_prep.py`.
3. New `pipeline/export_fixtures.py`: writes golden cases to `app/assets/fixtures/`:
   - planner: a grid of profiles (3 towns × 4 water levels × several priority/last-crop/wont/cold-storage combos) → `planner.plan()` output (cards, scores, Bakit reasons, confidence, Hold guard).
   - field machine: for each town × crop, 2–3 seasons of daily inputs + `FieldMachine.tick()` state/outputs per day (from `fsm.run_season`).
   - ET0 / heat index / robust z / SPEI / D: sample rows from `power_prep` and `zscores`.
4. Add tests in `pipeline/tests/test_export_json.py` for the new blocks; keep the existing "same cards from JSON as from CSV" test green.

Done when: three JSON files + fixtures exist and are committed; pytest green.

## Phase 1 — Flutter foundation

1. `flutter create app` (Android + iOS; package `ani`). Dependencies kept minimal: `shared_preferences` (or `hive`) for local state, `http` for POWER, `flutter_local_notifications`, `fl_chart` for the dryness chart, `flutter_localizations`/`intl`.
2. `lib/theme/`: colour tokens, Asap Condensed, shared widgets ported from the Make styles — card, eyebrow label, pill/badge, progress bar, choice tile (onboarding-choice), primary button, bottom nav (Home, Outlook, Crops, My farm).
3. `lib/data/bundle.dart`: typed models for the JSON (`meta`, `enso`, `dryness`, `crops`, `risk`, `planner`, `tracker`, `heat`) loaded from assets by town.
4. `lib/l10n/`: English + Filipino ARB files; crop names from `planner.NAME` (Palay, Sibuyas, Munggo, Mais, Kamote).
5. Onboarding (language → town) persisted locally; app shell with 4 tabs and empty screens.

Done when: app launches offline (iOS simulator, or Flutter web as the accepted interim target), onboarding works, town JSON loads.

_Status: met via Flutter web, as the user chose on 2026-11-15 (iOS simulator launch deferred: Xcode 26.6 needs the iOS 26.5 platform, which is not installed). Onboarding, persistence and town JSON loading were verified in the browser; `flutter analyze` and 54 tests pass._

## Phase 2 — Core logic in Dart (no UI)

Pure Dart, each a line-for-line port of tested Python, verified against Phase 0 fixtures.

| Dart module | Ported from | Doc |
|---|---|---|
| `core/planner.dart` — `roc`, `weights`, `pestScore`, `scale`, `topsis`, `confidence`, `plan`, `card`, `reason`, `holdMessage` | `pipeline/planner.py` | Guards g1–g6, Eq. 4.18–4.20, confidence label |
| `core/field_machine.dart` — `Params`, `FieldMachine.sow/tick/kc/outcome`, `gdd`, `bucketStep`, `pAdjusted`, `refillWhenStressed` | `pipeline/fsm.py`, `pipeline/soil_water.py` | Eq. 4.8–4.15, transition table priorities 1–10 |
| `core/alert_machine.dart` — Normal/Bantay/Delikado with hysteresis (up at 1 / 2, down after 2 dekads below 1.5 / 0.5) | thresholds in `export_json.py` `dryness.thresholds` | Alert Machine |
| `core/et0.dart` — FAO-56 Penman–Monteith; `core/heat_index.dart` — RH at Tmax from dew point, NWS regression, PAGASA bands | `pipeline/power_prep.py` | Eq. 4.1–4.2 |
| `core/dryness.dart` — robust z of GWETROOT, SPEI (log-logistic PWM with rank fallback), D, rank sentence | `pipeline/zscores.py` | Eq. 4.3, 4.5, 4.6 |

Tests in `app/test/` load the fixtures and assert equality (numeric tolerance 1e-6; identical card order, reasons and guard names). Determinism and totality of each machine are asserted as in `test_fsm.py`.

Done when: `flutter test` green; planner in Dart gives the same cards as Python for every fixture profile.

_Status: met on 2026-11-15. All six `lib/core` modules are pure Dart (no Flutter imports). Planner matches all 192 fixture profiles, field machine all 45 seasons day by day, ET0/heat index/dryness every `numeric.json` row within 1e-6; `flutter analyze` clean, 717 tests pass. Alert machine has no Python counterpart (only the stateless `zscores.label`); its edge-case choices are documented in `alert_machine.dart`. Export precision was then raised (stage fractions and `g_mat` at 6 dp; reference GWETROOT at 5 dp, balances at 2 dp), so bundle-driven replays match the fixtures exactly and on-device D is within 0.0055 of `dryness.monthly`._

## Phase 3 — Start screen + Recommendation flow (the core demo)

1. **Home / Start** (Fig. 2): El Niño outlook card ("Inaasahan ang El Niño ngayong tag-araw", JAS +2.2), dryness banner with label and rank sentence, heat-safety strip, CTA to the planner, tracked-crop summary (empty state until Phase 4).
2. **Questionnaire** (5 answers, one per step, choice-tile style): town (prefilled); last two crops; water source + irrigations (0 / about 2 / about 4 / as needed); crops they won't plant + cold storage; top-3 priorities ranked from income, risk, water, soil, pest.
3. **Result**: up to three crop cards — "X sa Y taon" failure with Wilson range, water needed (mm), net income p10–p90, "Bakit?" (two reasons), confidence High/Medium/Low, onion price-risk warning (g3), MAO referral on Low.
4. **Hold screen**: "Huwag munang magtanim", the guard that removed the most crops, mulch/rest-soil tip, "Kumonsulta sa MAO".
5. Profile saved locally so the recommendation can be reopened and reused in Phase 4.

Done when: the doc's Chapter 5 results reproduce in the app (rainfed Guimba/Muñoz → Hold; ~2 irrigations → Munggo; ~4 → Kamote/Mais/Munggo; as needed → all five incl. Sibuyas).

_Status: met on 2026-11-15. `test/features/recommend_chapter5_test.dart` drives the questionnaire answers through the planner for Guimba and Muñoz under several priority orders and reproduces every Chapter 5 result. Bongabon rainfed gives Munggo with Low confidence, so it shows the MAO referral. Home and the questionnaire render on Flutter web; 809 tests pass. The heat strip lists PAGASA bands and "Magtrabaho nang maaga" but shows no current heat index, because the bundle has none; the live value comes in Phase 5 from POWER. "Bakit?" reasons are the planner's Filipino sentences in both locales._

## Phase 4 — Track planted crop + alerts

1. **My farm**: add planting (crop, planting date, method; irrigation level defaults from the profile), list row with stage + progress, expandable detail with stage timeline and expected harvest window.
2. `lib/data/power_client.dart`: NASA POWER daily point API for the town coordinates, same parameters as the pipeline; cache per town/day locally; tolerate POWER's multi-day lag (unfilled recent days marked "waiting for data", machine advances only on real data).
3. **Tracker service**: on app open (and after a sync) replay `FieldMachine.tick` from planting date over cached days; persist machine state; emit alerts — water now, heat at flowering, onion rot, failed, harvest ready; "confirm harvest" action fires transition 7.
4. Outcome record on Harvest/Failed is stored and feeds the "last two crops" answer next season.
5. Alerts list (bell) + local notifications for new alerts.
6. Demo mode: replay a past season from a bundled fixture so judges can see a full season without waiting (clearly labelled as a replay).

Done when: a logged planting advances day by day from real POWER data, survives app restart offline, and the replay shows every alert type.

_Status: met on Flutter web on 2026-11-15. POWER client + per-town day cache (`power_client.dart`, `weather_cache.dart`), farm store, `tracker_service.dart` (replay via `core/season_replay.dart`, alert dedupe, confirm harvest = transition 7, outcome records feeding "last two crops"), My farm / add planting / detail timeline, alerts bell + list, local notifications behind `AlertNotifier` (no-op on web), and a demo replay of three bundled seasons (`assets/fixtures/demo_seasons.json` from `pipeline/export_demo.py`) that together show all five alert types. A browser check synced a real planting from NASA POWER ("4 days waiting for data"). `flutter analyze` clean, 909 tests pass. Not verified: Android/iOS builds and real notification delivery (no Android SDK; iOS 26.5 platform missing). Known gaps: a backdated planting's first alerts appear in the list but don't fire a notification; Filipino strings need a native-speaker check._

## Phase 5 — Season outlook, crop library, heat safety

1. **Outlook tab**: El Niño tag + past-season labels, monthly dryness-index chart with El Niño seasons marked, live dekadal D from synced POWER data through `dryness.dart` + `alert_machine.dart` (falls back to bundled `dryness.latest` offline).
2. **Heat safety**: daily heat index and PAGASA category; "Magtrabaho nang maaga" on danger days. Shown as people-safety advice only, never used in crop decisions (doc requirement).
3. **Crop library**: five crops with duration, sowing window, family, water need and a failed-X-of-9 table by irrigation level for the selected town; detail sheet in the Make modal style.
4. "About / limits" page stating the delimitations (one point per town, advisory only, rice water need is a lower bound, no field trials) and data sources.

_Status: met on 2026-11-15 (widget-tested only; not run in a browser or on a device). Outlook tab with live dekadal D from POWER (trailing-window scoring is our own choice; the pipeline scores whole months) and bundled fallback, monthly chart with El Niño seasons, heat safety card + Home strip (people-safety only), crop library with failed-X-of-N table and detail sheet, About / limits page from Settings. `flutter analyze` clean, 930 tests pass. Water-need levels per crop in the library are hand-assigned (bundle has none) and need review; Filipino strings need a native-speaker check._

## Phase 6 — Hardening and submission

1. Widget tests for questionnaire, cards, Hold, tracker; airplane-mode run-through of every screen.
2. Visual pass against the Figma Make screens (spacing, colours, type) on a small Android phone size.
3. App icon/name "Ani", release APK build, short README at repo root (currently just `# Ani`) covering pipeline → JSON → app.
4. Demo script: Guimba rainfed (Hold) → Guimba 2 irrigations (Munggo) → Bongabon as-needed (Sibuyas with warning) → track a planting via replay.

_Status: mostly met on 2026-11-15. Offline widget tests for every screen (`offline_screens_test.dart`), overflow fixes at 360x640 / text scale 1.3 (en + fil), root README, `docs/DEMO.md`, app name "Ani" and generated icon are in; `flutter analyze` clean, 932 tests pass. Not done: release APK (no Android SDK on this machine, `flutter build apk --release` fails), and the visual pass was not compared against the Figma frames (tokens only)._

## Suggested order if time is short

Phase 0 → 1 → 2 (planner only) → 3 is the minimum submission that demonstrates Objectives 1–4. Phase 4 delivers Objective 5; Phase 5 and 6 are polish.

## Verification

- `python -m pytest pipeline/tests` after Phase 0.
- `cd app && flutter analyze && flutter test` — parity tests against Python fixtures are the main correctness gate.
- Run on the iOS Simulator / Android emulator; walk the four demo profiles and compare cards with `python pipeline/planner.py --muni … --water … --json`.
- Offline check: disable network, cold-start, complete a recommendation and open a tracked crop.

## Open items to confirm during the build (not blocking)

- Planting "method" (doc Fig. 4) currently only affects onion (duration counted from transplanting); treated as informational for other crops.
- The Figma file has no questionnaire/result/Hold screens; these are designed in code from the existing styles unless new frames are added.
