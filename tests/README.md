# Tests

Automated checks of the pipeline and of what it publishes. Run everything with

```bash
tests/run_tests.sh            # all suites (the Shiny smoke test takes 2-4 minutes)
tests/run_tests.sh --fast     # skip tests marked `slow`
tests/run_tests.sh --python   # or --r for one language only; `-- -k name` passes options to pytest
```

The runner reports pass/fail and run time per suite and exits non-zero if any suite fails.
Run each Python suite in its own `pytest` process (`pytest tests/digitization`, not `pytest tests`):
every suite has a `conftest.py` with the same module name, and the digitization suite changes
directory into a scratch workspace while it runs.
Python dependencies: `pip install -r requirements-test.txt` (plus `playwright` and
`playwright install chromium` for the smoke test). R: `testthat` and the packages the R code uses
(`data.table`, `sf`, `jsonlite`, `Matrix`, `sandwich`, `lmtest`, `spdep`, `fixest`, `RANN`).
CI (`.github/workflows/tests.yml`) runs the Python suites with `-m "not slow"` and the R suite on
every push and pull request; tests that need `work/` inputs skip themselves when those are absent.

| Suite | What it covers |
|---|---|
| `tests/digitization` | parsing / OCR digitization (pytest) |
| `tests/geocoding` | the TIGER geocoder (pytest) |
| `tests/outputs` | the committed outputs and the text that describes them, including the manuscript's tables (pytest; this document) |
| `tests/r` | the R re-implementation (testthat) |

## tests/outputs

All of these read only files that are in the repository (`app/data`, `data/results`,
`data/by_year`, `data/full_inventory`, `data/historical`); none need the network.

### `test_consistency.py` — the published files agree with each other (~7 s)

* **Copies.** Every `.csv`/`.geojson`/`.md` under `app/data` that also exists under
  `data/results/**` (same name, or `rezoning_`/`sanborn1903_`/`ownership_`/`conditions_` prefix →
  the matching results folder) is byte-identical; the 20 m land-use `.tif` rasters are binary and are
  compared by size only; `app/data/by_year/*.csv` equals `data/by_year/*.csv`, whose 13 files hold the
  same 44,808 listings as `data/results/CO_directory_listings_1961-2002.csv`.
* **Sites.** `app/data/sites.csv` (3,657 hazardous sites: 3,487 F&E + 170 extended-sector only),
  `data/results/CO_historical_industrial_sites.geojson` (7,973 located sites, hazardous or not) and the
  three site sheets of `CO_hazardous_sites_1961-2002.xlsx` agree on ids, coordinates, years,
  `hazard_years`, status, confidence and the fe/ext flags; the workbook's coverage sheet matches the
  listings; `data/full_inventory` (the all-25-edition run, with its own site numbering) is internally
  consistent.
* **Listings ↔ sites.** `site_years` ids ⊆ sites and equal the hazardous (site, year) pairs of the
  listings; `site_firms` ids ⊆ sites, every (site, estab) pair is in the listings with the same
  first/last year and edition count, and the hazardous firms are exactly the hazardous listing pairs;
  `first_year`/`last_year` equal the listing min/max; `hazard_years` ⊆ listing years (and equal the
  years of hazardous listings); no site has `fe_hazard = ext_hazard = FALSE`; `n_hazard_establishments`
  matches `site_firms`; every GEOID is 11 digits or blank.
* **Tract panel.** 1,249 tracts × 9 censuses; no measure where `pop < 200`; `p_*` in [0, 100];
  population ≥ 0; Denver County sums: 2010 = 600,158 (±0.5 %), 1940/1950/1980/1990/2000/2020 within
  1 % of the published county totals (322,412 / 415,786 / 492,365 / 467,610 / 554,636 / 715,522),
  1960 and 1970 within 5 % (area-weighted from their own tracts onto the 2010 footprint, which includes
  land annexed after 1960; panel 509,770 vs 493,887 and 507,373 vs 514,678).
* **Rezoning.** `by_dir` cells sum to the 288 changes; `by_holc` = `by_holc_period` sums and is
  recomputed from `changes.csv`; Fisher's exact p recomputed from `changes.csv` equals `test.csv`
  (±1e-3, overall and per period); `placed` sums to 288; the geojson has one feature per placed change.
* **Ownership / housing.** Group tables sum to the "all" row (rental units, buildings, units);
  owner-location rows sum to 100 ± 0.2; size/type shares sum to 100; `by_holc` sums to "All of Denver";
  concentration equals linking stage S4; eviction terciles' tracts sum to the 143 tracts with 50+ rental
  units and their filing rate = filings / renter households; no published CSV/GeoJSON has an owner-name
  or mailing-address column; if `work/property/top_owners_private.csv` is present, none of its names
  occurs in any published file (skipped otherwise).
* **Highways, Sanborn.** `km_open_at_decade_end` is non-decreasing except where `km_removed > 0` and
  obeys end = previous + opened − removed; HOLC table km/km² recomputes; no block `streets` label starts
  with `/`; the exposure table recomputes from the blocks GeoJSON.
* **App packaging.** `app/manifest.json` lists no missing file and every file `app.R` reads; the
  committed `.gitignore` ignores nothing the manifest lists (checked with a throw-away git dir so local
  `.git/info/exclude` plays no part); every `dd("…")` and `rd_opt("…")` literal in `app.R` exists under
  `app/data` (except the one `file.exists()`-guarded read).

**Known inconsistencies** would be kept as `xfail(strict=True)` tests, so that they are documented and the marker must be removed
when the data are fixed; there are none at present (the tract-panel zeros once recorded here were fixed in the panel).

`test_manifest_checksums_match_the_files` fails whenever `app/manifest.json` is older than the files it lists: regenerate it
(`rsconnect::writeManifest("app")`, or update the md5 checksums) before pushing, since Posit Connect deploys what the manifest describes.

### `test_claims.py` + `claims.yml` — the numbers in the text are what the data say (~3 s)

`claims.yml` is a registry of 200+ claims. Each has `file` (README.md, app/app.R or a
`data/results/*/summary.md`), `text` (an exact substring that must be present in that file), `check`
(a Python expression over the data files, using `load(path)`, `listings()`, `sites()`, `fe_sites()`,
`fisher_exact_p()`, `mh_conditional_or()` …) and `expect` (the quoted number(s)). The test fails if the
text is gone **or** the data no longer give the quoted value, so a rerun that changes a number is caught
until the text is updated. Tolerance defaults to half a unit of the last printed decimal; `tol`
overrides it; the decimals are taken as the number is WRITTEN in claims.yml, so write `1.10`, not `1.1`, for a number printed with two. A claim with `stale: reason` is a known out-of-date statement (strict xfail); after the 31 October audit rerun
none is marked stale.

To add a claim: copy the sentence or table row verbatim into `text`, write a `check` that recomputes it
from the committed data (not from the file the text was generated from, where possible), run
`pytest tests/outputs/test_claims.py -k <id>`.

### `test_paper_tables.py` + `paper/make_tables.py` — the manuscript's tables are what the data say (~1 s)

`paper/make_tables.py` rebuilds all 23 tables of the manuscript from the committed result files (`python3 paper/make_tables.py`
writes them to `paper/tables_generated.md`, each with a comment naming its source files). The test imports the same builders and
asserts that every generated data row appears verbatim in `paper/Before_and_After_the_Map_manuscript.md`, the Markdown export of the
manuscript Doc that is committed next to the .docx. A rerun that moves a table cell fails the test until the Doc is updated and
re-exported; a Doc edit that changes a number fails it until the data agree. Prose numbers in the manuscript are not yet covered (add
them to `claims.yml` with `file: paper/Before_and_After_the_Map_manuscript.md`).

### `test_si_blocks.py` + `paper/si/make_si.py` — the Supplementary Information is what the data say (~1 s)

`paper/si/make_si.py` builds every paragraph and table of the SI from the committed result files into `paper/si/si_blocks.json`
(hard-coded figures are checked against their source inside the script; unchanged prose is reused from `paper/si/si_prose_base.json`),
and `node paper/si/build_si.js` (npm package `docx`) renders it as `paper/Before_and_After_the_Map_SI.docx`. The test rebuilds the
blocks in a temporary copy and asserts they equal the committed `si_blocks.json`, so a rerun that moves an SI number fails until both
files are rebuilt.

### `test_app_smoke.py` — the Shiny app runs (slow, ~2.5 min)

Starts `Rscript -e 'shiny::runApp("app", port=8790, launch.browser=FALSE)'` with `LANG=C.UTF-8`,
waits for "Listening", opens every tab (nav links by `data-value`, dropdown items included) with
Playwright/chromium and asserts: no `.shiny-output-error`; every plotly widget has at least one trace
and the listed plot ids are present on their tabs; the main map has ≥ 30 overlay groups including
"Zone changes" and "Sanborn 1903–04 sheet images"; the four start-up-populated selects (`hw_ev_cmp`,
`cx_var`, `cx_pol`, `bm_year`) have > 1 option within 5 s of opening their tabs; no new JavaScript
errors or missing app assets beyond the known DT dependency issues listed in the file. The app's PID is
found with `ps` and killed in a separate call at the end. Set `APP_SMOKE_PORT` to use another port.
