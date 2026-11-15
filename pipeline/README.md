# Ani: data pipeline

Ani recommends dry-season crops for El Niño years in Guimba, Science City of Muñoz and Bongabon (Nueva Ecija). This pipeline turns NASA and Philippine data into one JSON file per town for the app.

Method, formulas and limits: see the **Ani spec doc**. Run every command below from the **project root** (the folder that contains `pipeline/`).

---

## 1. Setup

```bash
python -m venv .venv
source .venv/bin/activate              # fish: source .venv/bin/activate.fish
pip install pandas numpy scipy requests matplotlib pytest
python -m pytest pipeline/tests        # all tests should pass
```

Python 3.11 or newer.

---

## 2. Get the raw data (once)

Everything goes in `pipeline/data/raw/`.

| File | What | How to get it |
| --- | --- | --- |
| `POWER_<town>.csv` (×3) | Daily weather, 2001–2025 | NASA POWER Data Access Viewer, see below |
| `oni.csv` | El Niño index (RONI) | NOAA CPC table, see below |
| `crops.csv` | Crop parameters with sources | Already in the repo (do not edit without a source) |
| `SOIL_<Town>.json` (×3) | Soil water retention | Downloaded automatically in step 4 |

### NASA POWER (weather)

<https://power.larc.nasa.gov/data-access-viewer/>

1. **Community:** Agroclimatology. **Temporal average:** Daily. **Point** (not regional).
2. **Coordinates**, one download per town:

   | Town | Latitude | Longitude |
   | --- | --- | --- |
   | Guimba | 15.6623 | 120.7657 |
   | Muñoz | 15.7153 | 120.9039 |
   | Bongabon | 15.6321 | 121.1459 |

3. **Dates:** 01/01/2001 to 12/31/2025.
4. **Parameters:** `T2M_MAX`, `T2M_MIN`, `T2MDEW`, `RH2M`, `WS2M`, `ALLSKY_SFC_SW_DWN`, `IMERG_PRECTOT` (or `PRECTOTCORR`), `GWETROOT`.
5. **Format:** CSV. Save as `pipeline/data/raw/POWER_guimba.csv`, `POWER_munoz.csv` and `POWER_bongabon.csv`.

If one town comes in two files (too many parameters at once), keep both; step 1 joins them.

### NOAA RONI (El Niño index)

<https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/enso/roni/>

Copy the table rows from 2000 to the latest year into `pipeline/data/raw/oni.csv` with this header:

```
year,DJF,JFM,FMA,MAM,AMJ,MJJ,JJA,JAS,ASO,SON,OND,NDJ
2000,-1.5,-1.3,-1.0,-0.8,-0.7,-0.6,-0.5,-0.4,-0.4,-0.5,-0.8,-0.8
...
```

Leave empty cells for months not yet published. NOAA revises the last two months, so refresh this file before each season (it is published by about the 5th of each month).

---

## 3. Run the pipeline (in this order)

Each step reads the previous step's output from `pipeline/data/processed/` and prints a check.

| # | Command | Writes | Check that |
| --- | --- | --- | --- |
| 1 | `python pipeline/power_prep.py guimba=pipeline/data/raw/POWER_guimba.csv munoz=pipeline/data/raw/POWER_munoz.csv bongabon=pipeline/data/raw/POWER_bongabon.csv` | `power_<town>.csv` (ET₀, heat index) | ET₀ r vs Hargreaves ≈ 0.85–0.91 |
| 2 | `python pipeline/enso.py` | `enso_dryseason.csv` | 9 El Niño dry seasons (episode rule); coming season tagged |
| 3 | `python pipeline/zscores.py guimba munoz bongabon` | `monthly_<town>.csv` (SPI, SPEI, D) | El Niño seasons drier than La Niña |
| 4 | `python pipeline/fetch_soilgrids.py` | `raw/SOIL_<Town>.json`, `soil.csv` | Pixel within 5 km; AWC 40–250 mm/m |
| 5a | `python pipeline/soil_water.py guimba munoz bongabon` | `bucket_<town>.csv` (reference run) | Water balance error ≈ 0 |
| 5b | `python pipeline/soil_water.py --crops guimba munoz bongabon` | `crop_seasons_<town>.csv` | El Niño seasons need more irrigation |
| 6 | `python pipeline/fsm.py guimba munoz bongabon` | `outcomes_<town>.csv`, `traces_<town>.csv` | Harvest day within ±7 d of guide |
| 7 | `python pipeline/uncertainty.py guimba munoz bongabon` | `risk_<town>.csv` (Wilson, Monte Carlo, net income) | Takes ~25 s; `--n 50` for a quick run |
| 8 | `python pipeline/planner.py --demo` | (prints cards) | Rainfed Guimba/Muñoz → Hold; 2 irrigations → Munggo |
| 9 | `python pipeline/export_json.py guimba munoz bongabon` | `pipeline/data/export/ani_<town>.json` | ~19 KB per town |

Steps 4 and 5a only need re-running if the soil or weather changes. Step 5a must run before 5b and 6 (they start each season from its soil moisture).

### When to re-run what

| You changed | Re-run from step |
| --- | --- |
| POWER files | 1 |
| `oni.csv` | 2, then 3, 6, 7, 9 |
| `crops.csv` (Kc, roots, duration, stages, sowing) | 5b |
| `crops.csv` (yield, price, cost only) | 7 |
| Planner settings (`planner.py`) | 8, 9 |

### Try one farmer

```bash
python pipeline/planner.py --muni guimba --water limited_2 --last rice rice \
    --priorities risk income water            # add --cold-storage, --wont onion, --json
```

`--water` is the farmer's answer to "how many times can you irrigate this dry season?": `rainfed` (0), `limited_2`, `limited_4`, `full` (as needed). Priorities, up to 3 in order: `income risk water soil pest`.

---

## 4. Folder layout

```
pipeline/
  data/raw/          POWER_*.csv, oni.csv, crops.csv, SOIL_*.json      (inputs)
  data/processed/    every intermediate CSV                             (generated)
  data/export/       ani_<town>.json                                    (for the app)
  data/psa/          PSA yield and price series behind crops.csv
  tests/             pytest suite
notebooks/           Jupyter scripts (cells split by # %%): ani_water_checks.py, ani_montecarlo.py
docs/                team notes
```

Notebooks read from `../pipeline/data/processed`, so run them from `notebooks/`.

---

## 5. Optional: validation data (H1, H3)

Not needed for the app; only for checking the model against independent satellite data. Use **AppEEARS → Point Sample** (not Area), with the three town points:

- **SMAP** `SPL4SMGP`, layer `sm_rootzone`, 2015-03-31 to 2025-12-31 → `pipeline/data/raw/smap/` (H3; Muñoz alone is enough).
- **MODIS** `MOD13Q1.061`, `_250m_16_days_NDVI` + `_pixel_reliability`, 1 paddy point per town, 2015–2025 → `pipeline/data/raw/modis/` (H1).

---

## 6. Troubleshooting

| Problem | Fix |
| --- | --- |
| `ModuleNotFoundError: No module named 'pipeline'` | Run from the project root, or use `python -m pipeline.fsm …` |
| `SyntaxError` near the end of a file | The file was pasted twice into an existing file; replace it whole |
| `FileNotFoundError …/processed/…` | A previous step was skipped; follow the order above |
| Notebook can't find files | Set `DATA = Path("../pipeline/data/processed")`, or the full path |
| SoilGrids is slow | Normal: it waits ~12 s between requests (ISRIC rate limit) |
| `.fish` activate error in zsh/bash | Use `source .venv/bin/activate` |