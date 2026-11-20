# tests/stages — one suite per pipeline stage (review 4, 12–13 November 2026)

Each file checks one group of stages: row conservation between a stage's input and output, key uniqueness, references to the
previous stage, ranges and units, sums and shares, and results recomputed a second way from the committed files. They read only
committed files; tests that need `work/` or the restricted inputs (death records, person-level census and CenSoc files) skip
when those are absent, so more of them run on the analyst's machine than in CI.

```bash
python3 -m pytest tests/stages -p no:cacheprovider      # ~50 s; also part of tests/run_tests.sh
```

`stages.yml` declares every stage with its script, inputs and outputs; a test fails if a committed file under `data/results`,
`data/historical`, `data/by_year` or `app/data` is not the declared output of exactly one stage (or a declared copy).
`new_claims.yml` adds claims (same format as `tests/outputs/claims.yml`) for README, app and manuscript numbers that had none.

## Known defects (strict xfail)

A test marked `xfail(strict=True)` documents a defect: it fails against the current files and starts failing the suite the
moment the defect is fixed, at which point the marker is removed. Do not weaken these tests.

As of 20 November 2026 no strict xfail remains. The findings of review 4 (12–13 November) were closed in three rounds (13, 18 and
20 November); the last round kept regulatory records with unusable coordinates and matched point-less records by name within the
site's ZIP or town, took ZIP centroids from TIGER streets where the inventory median was unreliable, limited same-street parcel
matches to under 1,000 house numbers, joined same-point firm-locations sharing the first 12 letters of the name, dropped no-town
copies of a firm-location's listing (`data/historical/notown_copies_dropped.csv`), logged review rows that match no entry
(`data/historical/review_rows_unmatched.csv`), used the address printed in an 1870s entry's name, moved tract analyses to the
full-resolution `data/geo/co_tracts_2010.gpkg`, applied the 200-resident floor of the zoning tract paths across all three
censuses, retired the October address-point recheck and reran the R-vs-Python comparison. Two findings turned out not to be
defects and their tests were corrected: two 1990 firms are printed twice as separate entries, and the 1965 edition files
Commerce City firms under their Denver post office.
