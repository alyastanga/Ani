# Data record

One row per downloaded dataset. Raw files live in `pipeline/data/raw/` (gitignored) and in the team's shared Drive folder. How to download each one: [`docs/data_download_guide.md`](../../docs/data_download_guide.md).

| Dataset | Product / short name | Version | Variables | Area (points or polygons) | Dates | Downloaded on | By | Scale factor / no-data code | Notes |
|---|---|---|---|---|---|---|---|---|---|
| SMAP L4 soil moisture | SPL4SMGP | 008 | sm_rootzone, sm_surface, sm_rootzone_pctl | 3 points | 2016-01-01 – 2026-01-01 | 2026-11-15 | Sean | No no-data code found. sm_rootzone 0.126–0.546, sm_surface 0.028–0.544 | DOI 10.5067/T5RUATAQREF8. 3-hourly, 8 rows per day per point, 29,232 rows per town. One extra day (2026-01-01), so the pipeline trims it to 2025-12-31 and averages to daily. sm_rootzone_pctl is a percentile (0–100). Files: ani-smap-l4-SPL4SMGP-008-results.csv |
| MODIS NDVI | MOD13Q1 | 061 | NDVI, pixel_reliability | 9 paddy points (3 per town) | 2015-12-19 – 2025-12-19 (16-day composite start dates) | 2026-11-15 | Sean | Already scaled (0.0405–0.9829), no no-data code found | AppEEARS ID 13b3d05f-ad58-4437-a718-b2536582ee9e. 231 rows per point. pixel_reliability: 0 good (72%), 1 marginal (10.5%), 3 cloudy (17.5%); filter out 3. First composite starts before 2016, so the pipeline trims it. Points use about 200 m clearance (team note says 300 m); guimba_2, guimba_3 and bongabon_3 are nearer field edges. Files: ani-modis-MOD13Q1-061-results.csv |
| MODIS ET | MOD16A2GF (or MOD16A2) | 061 | ET_500m | 3-5 paddy points per town | 2016-01-01 – 2025-12-31 | | | | Optional. Not downloaded yet |
| SRTM elevation | SRTMGL1_NC | 003 | elevation | 3 polygons | 2000 | | | | |
| NASA POWER daily | POWER (AG community) | | T2M_MAX, T2M_MIN, PRECTOTCORR, RH2M, WS2M, ALLSKY_SFC_SW_DWN | 3 points | 2016-01-01 – 2025-12-31 | 2026-11-14 | Sean | −999 | Re-downloaded via POWER API. Points: Guimba 15.66, 120.77; Munoz 15.72, 120.90; Bongabon 15.64, 121.15. Files: power_<town>.csv |
| GPM IMERG | GPM_3IMERGDF (Final) | 07 | precipitation | 3 boxes (Giovanni) | 2016-01-01 – 2025-09-30 | 2026-11-14 | Groupmate B | −9999.9 | Giovanni returned data only up to 2025-09-30. Area average over about 2 IMERG cells per town. Files: gpm_<town>.csv |
| GRACE/GRACE-FO | JPL mascon CRI | RL06.x | water storage anomaly | global file | 2002 – | 2026-11-14 | Groupmate B | | Single file Tellus.nc (about 46 MB) |
| SoilGrids | SoilGrids 2.0 REST | 2.0 | clay, sand, silt, soc, phh2o, cec, bdod (0–30 cm) | 3 points | — | 2026-11-14 | Groupmate B | Scale factors are listed in each JSON | Files: soil_<town>.json |
| ONI | NOAA CPC oni.ascii.txt | | ONI anomaly | — | 1950 – | 2026-11-14 | Groupmate B | | File: oni.ascii.txt |
| Boundaries | HDX cod-ab-phl (admin 3) | | polygons | 3 municipalities | — | | | | |