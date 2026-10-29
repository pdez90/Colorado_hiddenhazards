# Tests for the R analysis scripts

    LANG=C.UTF-8 Rscript -e 'testthat::test_dir("tests/r")'

Runs in a few seconds (no data, no network). Needs the packages the scripts already use: testthat, data.table, sf, spdep, sandwich, lmtest, RANN.

## How the scripts are tested without running them

The scripts in `R/` run top to bottom against data in `work/` and `app/data/`. The tests never execute them. `helpers.R` provides
`source_functions(path)`, which parses a script and evaluates only its top-level `name <- function(...)` assignments and simple
constants (`X <- "..."`, `X <- c(...)`, `X <- list(...)` built from literals), into a fresh environment. A test then calls the functions on
small synthetic `data.table`s and `sf` objects, setting any script-level inputs a function reads (e.g. `ip`, `RO`, `PC`, `ZJ`) in that
environment first. `script_env("name.R")` memoises one environment per script for the run.

Where a reviewed rule lived in inline data-processing code, it was moved into a small function in the script (behaviour unchanged) so
it could be called in isolation: `fill_hisp_1940`, `change_periods`, `drop_small_classes`, `change_model` (holc_covenants);
`dedupe_changes`, `sure_changes` (rezoning_denver); `parcel_type`, `is_condo_master`, `other_door` (ownership_denver);
`order_building_parcels`, `nonres_addresses` (housing_conditions_denver); `carriageway_weights`, `route_of` (highways_denver);
`nza_cat`, `city_cat` (zoning_over_time); `streets_label`, `exposure_of` (loc_sanborn_1903); `pct_within_500` (mlp_residential_history);
`gisjoin_county`, `has_edition` (benchmarks); `county_region` (statewide); `queen_listw` (corridors, health_models); `add_shares` (ej_panel).

## Files

| file | covers |
|---|---|
| `test-parse.R` | every `R/*.R` and `app/app.R` parses; the functions the tests rely on exist |
| `test-fetch_census.R` | `interp()` medians (0 = suppressed, owner/renter-unit weights, `MIN_U`), `grouped_median()`, `num()`, `gj()` |
| `test-grf_eds.R` | `ipums_ed()` 1940 SD-ED-suffix labels (A-G), unknown-suffix and label-collision stops, 1900-1930 labels, county rule |
| `test-holc_covenants.R` | change periods (p_hisp/p_pov from 1970), 1940 Hispanic fill (pop40 >= 200), classes < 5 tracts dropped but the A reference class (4 tracts) kept, HC1 + classical SEs |
| `test-rezoning_denver.R` | `parse_doc()` on four synthetic ordinances (Board letter cut, OCR change phrases, `t.o`, `e` -> C, R-2/B-4, `R--0`, reprint fallback), `fuzzy_zone`, `new_code`, dedupe rules (`same()` wildcard, boundary text, 300 m, passing mentions), `legal_name` directional words, two-word subdivision rule, self-crossing street filter, `sure_changes` |
| `test-ownership_denver.R` | parcel types (mixed use needs homes, hotels excluded), condo master drop, `unit_differs`, duplex other-door rule, name/address normalisation |
| `test-housing_conditions.R` | address key keeps N/S and ST/CT, `compat()` partial matches, building-owner tie-break, non-residential address flag |
| `test-site_fate.R` | `pick()` rules 1-4 and no-parcel case, `addr_parts` (letter suffix, no number), `broad()` |
| `test-highways_denver.R` | carriageway weights w = 1 - f/2 on two opposite one-way lines 30 m apart plus a single line (km of road = 2, not 3), pairing conditions, NBER route-name fallback |
| `test-zoning.R` | 2023 categories, `locate()` nearest polygon within 50 m and unmatched counts, `pct_tab`; 'Commercial (housing not allowed)' in the over-time categories |
| `test-loc_sanborn.R` | `st_base`, block street labels without stray '/', `dmin()` edge distances and the 30 m across-street rule, exposure ladder, block outlines |
| `test-mlp_censoc.R` | exposure-window share with `na.rm`, kernels, percentiles, CenSoc file reader, hazardous IND1950 codes |
| `test-spatial_models.R` | `eg()` seeded permutations, `queen_listw` snap (2 m / 2e-5 deg), `z()`, `add_shares()` universes |
| `test-benchmarks_statewide.R` | GISJOIN county code (G0801010 -> 101), edition-within-2-years rule (1900 excluded), Denver/Arapahoe region rule, `REG`, `share_in`, `lq` |

Each test for a previously reviewed fix asserts the corrected value (e.g. a population-weighted or zero-including median, an address
key without N/S, county code 010 for Pueblo) would fail.
