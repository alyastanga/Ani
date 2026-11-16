# Ani

**Crop planning and drought alerts for Nueva Ecija farmers during El Niño dry seasons.**

**Live web demo:** https://alyastanga.github.io/Ani/

Ani is an offline-first mobile app (Flutter, for Android and iOS, with a web build) built for the **NASA Space Apps Challenge**. It helps smallholder farmers in three towns of Nueva Ecija, Philippines (**Guimba**, **Science City of Muñoz** and **Bongabon**) decide what to plant in a dry season hit by El Niño. Once a crop is planted, the app tracks it and warns the farmer about water and heat problems. It works in **Filipino and English**.

> **Ani is advisory only.** It helps with a decision but guarantees nothing. Its estimates come from past weather and a simple field model, and conditions on a given farm can differ. Always check with the Municipal Agriculture Office (MAO) before you commit seed, labour or money.

---

## The problem

El Niño brings drier, hotter dry seasons to Central Luzon. A farmer who plants the wrong crop for the water they have can lose the whole season. Weather and climate data exist (NASA satellites, NOAA's El Niño index, global soil maps), but they don't reach the farmer in a form that answers one question: *what should I plant this season, given my town and my water?*

## What Ani does

- **Recommends a crop in five questions.** The farmer answers: which town, the last two crops, how many irrigations they can give, any crops they won't plant, and what matters most to them (low risk, saving water, income, soil, pests). Ani then shows up to **three crop cards**. If no crop is safe, it shows a **"Huwag munang magtanim"** (Hold: don't plant yet) screen with the reason and what to do instead.
- **Explains each suggestion.** Every card shows how often the crop failed in past El Niño years ("Failed in 0 of 9 El Niño years"), how much water it needs, an expected income range in PHP, and warnings such as "No cold storage: high price risk".
- **Shows the season outlook.** It gives the El Niño state, a monthly dryness index (Normal / Bantay / Delikado) and heat-safety advice ("Magtrabaho nang maaga", work early).
- **Tracks a planted crop.** The app follows the crop stage by stage (Prep → Establishment → Vegetative → Reproductive → Mature → Harvest) and alerts the farmer when to irrigate, when heat stress threatens flowering, about onion rot risk, a likely failure, or harvest time.
- **Includes a crop library.** It covers the five crops the model knows, Palay (rice), Sibuyas (onion), Munggo (mung bean), Mais (corn) and Kamote (sweet potato), with duration, water need and risk per town and irrigation level.
- **Works offline.** All recommendation data ships inside the app. When the phone is online, it can also fetch recent NASA POWER weather for the outlook and the tracker.
- **Has a season replay demo.** It replays past seasons so you can see the tracker and its alerts without waiting a real season.

## Research paper

Ani is the working system behind the paper **"Ani: An Extended Finite State Machine-Based Decision Support System for El Niño Dry-Season Crop Selection in Nueva Ecija"**, submitted to the NASA Space Apps Challenge, **Field Shift: Adapting Farms with NASA Data** (November 2026).

**Read the paper:** [`docs/paper/PAPER.md`](docs/paper/PAPER.md) (Markdown, with figures and equations), or download the original [Word file](docs/Ani_NASA_Space_Apps_Challenge.docx).

**Why it was built.** Farmers choose their dry-season crop before they know how dry the season will be. They rely on fixed calendars and general El Niño advisories, which don't say what a drought means for a given crop on a farm with a given water supply. Free NASA, soil and market data are never turned into local advice. In November 2026 the July–September value of NOAA's Relative Oceanic Niño Index was +2.2, the highest since 2000 and above the +1.7 that preceded the 2015–2016 drought, so the signal for the coming dry season is strong.

**Objectives.**

1. Build a town-level dryness index and El Niño outlook that ranks the current season against 25 years of each town's own record.
2. Simulate daily soil water, growth stage, water stress, failure and irrigation need for rice, onion, mungbean, maize and sweet potato in every dry season from 2001 to 2025, under four levels of irrigation access.
3. Design a deterministic, deadlock-free planner, modelled as an extended finite state machine (EFSM), that removes unsuitable crops, ranks the rest by the farmer's priorities and explains each recommendation.
4. Quantify uncertainty with Wilson confidence intervals and a Monte Carlo simulation, and report the failure risk and net-income range on every recommendation.
5. Provide in-season alerts on dryness, crop water stress, heat at flowering, harvest timing and heat safety through an offline mobile app.

**Three state machines.** The system implements a *field machine* for the growing season, a *planner* that ranks crops from the farmer's answers, and an *alert machine* for the dryness banner.

**Who it is for.** Farmers get advice that matches their own water access and priorities. Municipal Agriculture Offices and the Department of Agriculture get a tool that shows the reasons and uncertainty behind each recommendation. The National Irrigation Administration and local governments can see how much irrigation each crop needs in an El Niño season.

### Scope

| | |
| --- | --- |
| **Towns** | Guimba (15.6623° N, 120.7657° E), Science City of Muñoz (15.7153° N, 120.9039° E), Bongabon (15.6321° N, 121.1459° E), one point each |
| **Season** | Dry season, November to April; baseline 2001–2025 |
| **Crops** | Rice, red onion, mungbean, yellow maize, sweet potato (sown 1 December ±15 days) |
| **Irrigation levels** | None, about two, about four, as needed |
| **Uncertainty** | Wilson confidence intervals; Monte Carlo with 200 runs |

### Delimitations

- Only drought and heat linked to El Niño are modelled. Flood, typhoon, erosion, pests and disease are not.
- Results describe one point per town, not individual fields or barangays. Guimba and Muñoz share one NASA POWER weather cell for temperature.
- Only five crops, and crop-level advice only: varieties are not compared. Peanut, sorghum and watermelon were left out for lack of local data.
- Labour is not a criterion, except inside the PSA production cost.
- Irrigation is only the number of times a farmer can irrigate. Canal schedules, pump capacity and water cost are not modelled. Rice is modelled as an upland crop, so its water need is a lower bound.
- Yields and prices are provincial averages, and costs are regional or national averages from different years. Net income ignores partial yield loss short of crop failure.
- Crop failure is defined as ten or more consecutive days of severe water stress, a calibration choice and not a published threshold. Heat damage at flowering is evaluated for rice only.
- No field trials. Validation uses satellite data, published crop durations and agricultural statistics.

### Proponents

- Sean Anikin Coquia
- Peter Dela Cruz
- Hanz Laurence Mapua
- Kurt Laurence Raneses
- Aaron Angelo Ragudos
- Jerick Anthony Remo

## How it works

```
NASA POWER weather + NOAA RONI + ISRIC SoilGrids + crops.csv (PSA yields & prices)
        |  pipeline/ (Python)
        v
pipeline/data/export/ani_<town>.json   (one bundle per town)
        |  copied to
        v
app/assets/data/ani_guimba.json, ani_munoz.json, ani_bongabon.json
        |  app/lib/data/bundle.dart (typed loader)
        v
app/lib/core/  planner, field machine, dryness, ET0, alerts (Dart ports)
        v
app/lib/features/  questionnaire -> result / Hold, outlook, crops, My farm
```

1. **Weather and climate.** The pipeline reads 2001–2025 daily weather from NASA POWER for each town. It computes reference evapotranspiration (ET₀) and heat index, and tags each dry season as El Niño, neutral or La Niña using NOAA's RONI index.
2. **Dryness.** It computes SPI/SPEI-style drought indices per month.
3. **Soil water.** A daily soil water balance uses soil water-holding capacity from ISRIC SoilGrids.
4. **Field state machine.** It simulates every crop in every past season, at every irrigation level, through its growth stages, and records whether the crop reached harvest or failed.
5. **Risk and income.** It estimates failure rates with Wilson confidence intervals and builds net-income ranges with Monte Carlo sampling over yield, price and cost.
6. **Planner.** It applies safety guards (failure risk too high for the water supply, crop rotation, cold storage for onion), then ranks the remaining crops with **TOPSIS** using the farmer's priorities.
7. **The app** ships the results as JSON and runs the same planner, field machine and alert logic in Dart on the phone. Fixture tests check that the Dart results match the Python reference.

## Data sources

| Source | Used for | Where |
| --- | --- | --- |
| [NASA POWER](https://power.larc.nasa.gov/) daily point data | Weather history (pipeline) and live in-season top-up (app, optional) | Pipeline and app |
| [NOAA CPC RONI](https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso/roni/) | El Niño / La Niña state per season | Pipeline |
| [ISRIC SoilGrids](https://soilgrids.org/) | Soil water retention | Pipeline |
| PSA OpenSTAT / PalayStat | Crop yields and farm-gate prices (`crops.csv`) | Pipeline |
| NASA AppEEARS (SMAP, MODIS) | Optional model validation only | Notebooks |

The app calls only one API at runtime, NASA POWER. It needs no key, no account and no backend.

## Tech stack

- **App:** Flutter / Dart (SDK ^3.13), `shared_preferences`, `http`, `flutter_local_notifications`, `fl_chart`, `intl`, Flutter localizations (English and Filipino)
- **Pipeline:** Python 3.11+, pandas, numpy, scipy, requests, matplotlib, pytest
- **Hosting:** GitHub Pages for the web demo (`gh-pages` branch)

## Repository layout

```
app/                 Flutter app
  assets/data/       ani_<town>.json bundles shipped with the app
  assets/fixtures/   Python-generated expected values for parity tests
  lib/core/          planner, field machine, alert machine, ET0, heat index, dryness
  lib/data/          bundle loader, NASA POWER client, local storage, notifications
  lib/features/      onboarding, home, recommend, outlook, library, farm, alerts, about
  lib/l10n/          English and Filipino strings
  lib/theme/         colours, fonts and shared widgets
  test/              unit, parity and widget tests
pipeline/            Python data pipeline (see pipeline/README.md)
notebooks/           exploration, Monte Carlo and figure notebooks
docs/
  paper/PAPER.md     the research paper (Markdown) with its images
  Ani_NASA_Space_Apps_Challenge.docx   the research paper (Word original)
  PLAN.md            build plan and design decisions
  DEMO.md            five-minute demo script
```

## Getting started

### Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install) with Dart ^3.13, to run the app
- Python 3.11 or newer, to run or test the pipeline

### Run the app

```bash
cd app
flutter pub get
flutter run            # on an emulator, simulator, connected phone or Chrome
```

### Test the app

```bash
cd app
flutter analyze
flutter test
```

### Build a release APK

```bash
cd app && flutter build apk --release
# output: app/build/app/outputs/flutter-apk/app-release.apk
```

### Build the web version (GitHub Pages)

The site is served from the `gh-pages` branch under `/Ani/`, so build with that base path:

```bash
cd app && flutter build web --release --base-href /Ani/
# output: app/build/web/  (publish its contents to the gh-pages branch)
```

### Run the pipeline

```bash
python -m venv .venv && source .venv/bin/activate
pip install pandas numpy scipy requests matplotlib pytest
python -m pytest pipeline/tests
```

Get a reference recommendation from the command line. It should match the app:

```bash
python pipeline/planner.py --muni guimba --water limited_2 --last rice rice --priorities risk water income
```

To rebuild the data bundles from raw data, follow the steps in [`pipeline/README.md`](pipeline/README.md).

## Demo

Try it at **https://alyastanga.github.io/Ani/**, or follow the five-minute script in [`docs/DEMO.md`](docs/DEMO.md). It covers:

1. Guimba, rain only → **Hold** (no crop is safe)
2. Guimba, about 2 irrigations → **Munggo**
3. Bongabon, irrigate as needed → Munggo, Kamote, **Sibuyas** with a cold-storage warning
4. Season replay of a past planting with its stage changes and alerts

## Limits

- Advisory only. Ani is not agronomic or financial advice and does not replace the MAO.
- It covers three towns and five crops only. The El Niño state for the coming season, and all other data, come from the bundles built at the last pipeline run.
- Income, water and failure-risk figures are estimates from 2001–2025 history and may be far from what a given farm sees (see the ranges on each card).
- The model covers only El Niño drought and heat, with one point per town and no field trials. See the paper's delimitations above.
- Season replay shows past seasons only. Its alerts are not live and are never saved.
