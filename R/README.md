# Reproducing the analysis in R

The R scripts in this folder re-implement the spatial and statistical core of the pipeline so that it can be checked and
reused without Python. Each one was run against the Python pipeline on the same inputs (17 October 2026); `pipeline/check_r_vs_python.py`
writes the comparison to `data/results/r_vs_python.md`.

| Step | R | Python original | Check |
|---|---|---|---|
| Address geocoding (TIGER/Line 2023 address ranges, offline) | `geocode_tiger.R` | `pipeline/tiger_geocode.py` | `compare_with_python.R`: same match type and the same point (max difference 0.0 m) for all 36,615 address keys |
| String similarity (rapidfuzz `ratio`, `token_set_ratio`, `token_sort_ratio`) | `fuzz.R` | rapidfuzz | identical scores on 500 name pairs |
| Sites (30 m clusters) and inventory matching ("Not on any list") | `build_sites.R` | `pipeline/build_sites.py`, `finalize.py` | 9,848 identical sites; all 4,312 hazardous sites get the same status and confidence |
| Exposures (kernel density at block groups → tracts) | `build_exposures.R` | `pipeline/health/build_exposures.py` | equal to 2e-10 at all 4,058 block groups |
| Tract models (OLS HC3, spatial error ML) | `health_models.R` | `pipeline/health/health_models.py` | coefficients, SEs, λ and LR tests equal to 1e-6 (AIC differs by a constant 4: spreg and spatialreg count parameters differently) |
| Block-group mortality (negative binomial, county FE, tract-clustered SE) | `mortality_bg.R` | `pipeline/health/mortality_bg.py` | rate ratios equal to 1e-5, CI limits to 4e-4 (small-sample factor of the clustered SE); needs the restricted death counts |

`Rscript R/run_all.R` runs all of it. Packages: `sf`, `data.table`, `igraph`, `spdep`, `spatialreg`, `sandwich`, `lmtest`, `MASS`.

## What stays in Python, and why

OCR of the scanned directories (Tesseract), the edition-specific parsers, SIC assignment (including the description→code classifier
and the OCR-error corrections) and linking listings across editions into firms are Python only. They are long, text-heavy and
already deterministic given the saved OCR output in `data/ocr/`. Their results are handed to R as two plain CSV files:

* `work/inv/records_linked.csv` – one row per directory listing: year, name, normalised street/city/ZIP, geocoding key, firm ID,
  SIC codes and their source, hazardous-sector flags (written by `pipeline/link.py`).
* `work/inv/reg.csv` – the federal and state inventories (EPA FRS, TRI, CDPHE layers) with coordinates and cleanup-site
  boundaries (written by `pipeline/build_reg.py`).

The published listings (`data/by_year/`, `data/results/CO_directory_listings_1961-2002.csv`) carry the same fields.

## Geocoding on its own

```r
source("R/geocode_tiger.R")
fetch_tiger_addrfeat("work/tiger", 2023)                       # 64 county files from census.gov, once
g <- tiger_geocoder("work/tiger", "data/geocoder/zip_city.csv", "data/geocoder/zip_centroids.csv")  # ~20 min first time, then cached
geocode_one(g, "1805 S BANNOCK ST", "DENVER", "80223")
geocode_many(g, data.frame(street = ..., city = ..., zip = ...))
```

`geo_quality` says how each address was placed (`range_interp` = exact street and range; suffixes `_cityzips`, `_nearzips`,
`_trim`, `_dirloose`, `_sufloose`, `fuzzy_` mark looser matches, which become `geo_level = address_approx`; `zip_centroid` and
`city_centroid` are fallbacks not used for sites).
