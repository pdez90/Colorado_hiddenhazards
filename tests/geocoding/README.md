# Tests: geocoding and site-building stages

Covers `pipeline/tiger_geocode.py`, `run_geocode.py`, `geo_prep.py`, `build_sites.py`, `finalize.py`, `export.py`, `export_by_year.py`,
`validate_geocoding.py`, `validate_addresspoints.py`, `historical/{hist_parse,run_hist,geocode_hist}.py` and the R ports
`R/geocode_tiger.R`, `R/build_sites.R`, `R/fuzz.R`, `R/fix_direction_geocodes.R`.

```sh
pip install pytest                      # plus the pipeline's requirements.txt; R: testthat, sf, data.table, igraph, jsonlite
python3 -m pytest tests/geocoding       # everything: Python (incl. the real-TIGER test when work/tiger exists) and the R suite, ~15 s
python3 -m pytest tests/geocoding -m "not slow"   # without the real Denver TIGER index, ~7 s
Rscript tests/geocoding/run_r_tests.R   # the R suite on its own (after a pytest run: it reads tests/geocoding/.cache)
tests/geocoding/check_old_logic.sh 43bf273        # which tests fail on the pre-review geocoder at that git revision (dev aid)
```

## Fixture

`synthetic_tiger.py` writes a small ADDRFEAT-like shapefile around Denver's Ellsworth/Broadway baselines (13 named segments plus
filler so that six ZIPs qualify as Denver-grid ZIPs with a known half), with the `zip_city` / `zip_centroids` tables, into
`tests/geocoding/.cache/synthetic/` (gitignored) laid out like the repository; the pipeline's own `build()` indexes it. Streets:
Kalamath St (100-199 in 80223, 400-699 and 2100-2199 in 80204, 4000-4099 in 80211) and S Kalamath St (400-599, 80223), so 450 exists on
both; W 5th Ave (three vertices); E 24th Ave and 24th St (both hold 2350); Broadway / S Broadway; S Bannock St in Englewood's 80110.
`cases.py` lists the addresses that both ports geocode. The pytest run writes the Python results (`python_geocodes.json`,
`python_parse.json`, `python_fuzz.json`) to `.cache`, and the R tests compare against them.

## Test files

| file | what it checks |
|---|---|
| `test_parse.py` | `parse_addr` / `parse_name` / `ordfix`: units (`STE`, `#`, trailing unit number), `NO` as direction vs unit, `SO`/`NO`, 1/2 addresses, letters glued to the number (`1234A`, `123N MAIN`, `450S KALAMATH`), hyphenated ranges (`125-7`), OCR house numbers (`l234`, `12O5`), `I70`, ordinals, OCR street types |
| `test_interp_grid.py` | `interp`: fraction along cos-scaled length, 12 m left/right offset with hand-computed coordinates (north-, south- and westbound segments, multi-vertex), degenerate segment; side/parity choice (450 vs 451, one-sided range); `street_nearest` and its 300-number limit; `far()` via `max_km`; `grid_info` baselines, halves and rejection of inconsistent ZIPs |
| `test_geocode_synthetic.py` | the review rules: `_dirzip` by the printed ZIP's ranges or its half of the grid, `_dirtype` by street type, `_dirambig` → zip level, `grid_conflict` (prefixed address never on the wrong-side plain segment), `SO`/`NO`, glued direction letter (`SKALAMATH`, `450S`), fuzzy name recovering the direction, `_sufloose`, junk token dropped and never trimmed to a bare ordinal, trailing trim, blank ZIP → the town's neighbour ZIPs, ZIP → city → neighbour search order, fallbacks, determinism |
| `test_sites.py` | `cluster_sites` union-find with the across-the-street parity rule; `spread_m`; `name_match` (token_sort ≥ 88 or token_set ≥ 88 with ≥ 2 shared tokens); `nn`; `match_basis` precedence; `match_inventory` on synthetic records: name match ≤ 250 m, address match (ZIP, then street + city), cleanup boundary, proximity within tier radius (+ spread, capped at 250 m), no 250 m widening for approximate sites, radar precedence; `agg_site` keeps only hazardous firms' names; `geo_level` mapping |
| `test_pipeline_stages.py` | `geo_prep → run_geocode → build_sites → finalize → export → export_by_year → validate_geocoding` end to end on the synthetic fixture: ZIP recovered from the street field, geo keys, levels, site ids (parity), radar / match_basis / confidence, workbook sheets and formulas (confidence in column D), GeoJSON, listing CSVs, by-year files, coverage table |
| `test_validate.py` | `validate_addresspoints.classify`: found / not_found / undecidable (> 300 m disagreement), no preference for plain points, 20 km town filter, printed-direction filter; `validate_geocoding.hav` |
| `test_hist.py` | the audited pre-1960 entry patterns: `NEXT` cut (`"Copenhaver Geo C, wagon maker, Cooper Geo H, florist, 833 15th"` yields no street), `own_listing`, `is_person`, `ADDR` (`"125-7 S Weber"` → 125), `entries`, `clean_name`; `geocode_hist.hist_street` (renames, `2d` → `2ND`, building/block), `street_ok`, `street_level` codes |
| `test_real_tiger.py` (`slow`) | real `work/tiger/tl_2023_08031`: index built once into `.cache/real`; 30 committed Denver keys (direction printed, `range_interp`) re-geocoded: same code, exactly the 12 m offset from the committed pre-review point; real grid halves; the review's examples on real streets. Skipped when `work/tiger` is absent |
| `test_r_port.py` | runs the testthat suite (last) and requires 0 failures |
| `testthat/test-geocode_tiger.R` | R port: `parse_addr` on the same edge cases, index and grid info from the same fixture, `interp_line` offset, every case in `cases.py` gives the Python quality code and coordinates (1e-9°), `geocode_level` |
| `testthat/test-build_sites.R` | `R/fuzz.R` equals rapidfuzz on the pairs in `cases.py`; `name_match`, `nn`, `norm_street`, `match_basis`; `cluster_points` parity rule |
| `testthat/test-fix_direction.R` | `dir_of`, `conflict()` on synthetic Denver listings (baselines, 500 m tolerance, street level only, Denver only) |
| `testthat/test-real_tiger.R` | R port on the real Denver file: the same 30 keys identical to Python and 12 m from the committed points (runs when the slow Python test ran) |

## Import-safety changes made to the pipeline (behaviour unchanged)

The stage scripts were plain top-level scripts; their bodies now sit in `main()` under `if __name__ == '__main__':` and the rules they
apply are module-level functions: `build_sites.py` (`geo_level`, `placed_loose`, `cluster_sites`, `spread_m`, `agg_site`, `nn`,
`name_match`, `match_basis`, `match_inventory`, `radar_status`), `geo_prep.py` (`zip_from_street`, `city_for`, `kind`),
`run_geocode.py` (`geocode_keys`), `finalize.py` (`confidence`), `validate_addresspoints.py` (`classify`),
`validate_geocoding.py` (`hav`), `historical/run_hist.py` (`NEXT`, `own_listing`, `is_person`, `clean_name`),
`historical/geocode_hist.py` (`hist_street`, `street_level`, `street_ok`). `build_sites.py` imports `consolidate.norm_street` lazily
(`consolidate` → `sic_predict` unpickles `work/inv/sic_clf.pkl` at import time; `conftest.py` stands in for `sic_predict` when that
file is absent). `R/build_sites.R` has its pure functions first and the run under `if (!exists("TESTING") && !nzchar(Sys.getenv("AUDIT_TESTING")))`
(the clustering loop is now `cluster_points()`); `R/fix_direction_geocodes.R` has the same guard around its package installs and its run.

## Bugs found by the tests and fixed (Python and R port alike)

* `123N MAIN` / `450S KALAMATH`: a direction letter glued to the house number was dropped (and `S` turned into a `5` by the OCR step),
  so 40 committed keys lost their direction (`1731S WADSWORTH BLVD` → zip centroid). Now read as the direction.
* `125-7 S WEBER`: hyphenated ranges parsed to no number; now the first number.
* `400 NO 5TH ST`: `NO` was taken as a unit marker because `5TH` starts with a digit, contrary to the comment; the lookahead now
  excludes ordinals (`NO 5`, `NO 21` are still units).
* `450 KALAMATH, DENVER 80223` (real TIGER): 80223 straddles Ellsworth, so plain Kalamath St has segments in the ZIP that do not hold
  450; the strict pass returned their nearest end (`street_nearest`, north side) before the plain/directional resolution could move the
  point to 450 S Kalamath St. `street_nearest` on a plain street now goes through `resolve()` as well (31 committed Denver keys change).
* `run_hist.NEXT`: the audit's "spelled-out given name" pattern also cut at the tail of a firm's own name (`... & Refining Co, smelters,
  1721 Holladay`), losing the smelter's address; legal-form words are excluded from the given-name position.
* `geocode_hist.RENAME`: `SANTA` → `SANTA FE` doubled an already complete `SANTA FE`.

Observed but not changed (outside this suite's files): `R/fix_direction_geocodes.R`'s `rebuild()` is not idempotent on quoted CSV
fields — each run doubles the `""` escapes inside `hazard_firms` (see `app/data/sites.csv` S00239, S04608 after a second run); and
`data/geocoder/geocode_keys_with_python_results.csv` holds the pre-review Python results, so `R/compare_with_python.R` will report the
12 m offset and the direction changes until it is regenerated (`pipeline/export_geocoder_keys.py`).
