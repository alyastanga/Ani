# Ani

Ani is an offline-first Android/iOS app (Flutter) that gives smallholder farmers in Nueva Ecija (Guimba, Science City of Muñoz, Bongabon) advice on what to plant in an El Niño dry season, in Filipino and English. It answers five questions (town, last two crops, irrigations available, crops you won't plant, priorities) and shows up to three suggested crops, or a "Huwag munang magtanim" (Hold) message when no crop is safe. A planted crop can then be tracked stage by stage with water and heat alerts.

**Ani is advisory only.** It is a decision aid, not a guarantee. Estimates come from past weather and a simple field model, and local conditions differ. Always confirm with the Municipal Agriculture Office (MAO) before committing seed, labour or money.

## How the data flows

```
NASA POWER weather + NOAA RONI + SoilGrids + crops.csv
        |  pipeline/ (Python)
        v
pipeline/data/export/ani_<town>.json   (one bundle per town, schema 2)
        |  copied to
        v
app/assets/data/ani_guimba.json, ani_munoz.json, ani_bongabon.json
        |  app/lib/data/bundle.dart (typed loader)
        v
app/lib/core/  planner, field machine, dryness, ET0, alerts (Dart ports)
        v
app/lib/features/  questionnaire -> result / Hold, outlook, crops, My farm
```

- **pipeline/**: Python. Prepares daily weather (ET0, heat index), ENSO state, soil water, crop failure risk and income ranges, then `export_json.py` writes one JSON bundle per town. `planner.py` is the reference recommender (guards, TOPSIS ranking). Full steps and data sources: `pipeline/README.md`.
- **app/assets/data/**: the three bundles shipped inside the app, so every recommendation works with no network. `app/assets/fixtures/` holds Python-generated expected values (planner, numeric, field machine, demo seasons) that the Dart tests compare against.
- **app/lib/core/**: pure Dart ports of the Python logic. **app/lib/data/**: bundle loading, local storage, the optional live NASA POWER top-up for the Outlook (`power_client.dart`, `live_outlook.dart`) and local notifications. **app/lib/features/**: screens.
- Parity between Dart and Python is the main correctness gate: change the logic in one place and the fixture tests will say if the other drifted.

## Run things

Pipeline tests (Python 3.11+, from the repo root):

```bash
python -m venv .venv && source .venv/bin/activate
pip install pandas numpy scipy requests matplotlib pytest
python -m pytest pipeline/tests
```

Reference recommendation from the command line (should match the app):

```bash
python pipeline/planner.py --muni guimba --water limited_2 --last rice rice --priorities risk water income
```

App (Flutter SDK, Dart ^3.13):

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run            # on an emulator, simulator or connected phone
```

Release APK:

```bash
cd app && flutter build apk --release
# output: app/build/app/outputs/flutter-apk/app-release.apk
```

A walkthrough for presenting the app is in `docs/DEMO.md`.

## Limits

- Advisory only; not agronomic or financial advice, and no substitute for the MAO.
- Three towns only. The coming-season state (El Niño) and the data come from the bundles built at the last pipeline run.
- Income, water and failure-risk figures are estimates from 2001-2025 history and may be far from what a given farm sees (see the ranges on each card).
- Season replay in the app is a demo of past seasons; its alerts are not live and are never saved.
