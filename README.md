# Colorado Hidden Hazards

Historical hazardous industrial sites in Colorado, 1961–2002, identified from the *Colorado Directory of Manufacturers*
(plus a pre-1960 layer of hazardous trades from the *Colorado State Business Directory*, 1871–1956),
following Scott Frickel and James R. Elliott, *Sites Unseen: Uncovering Hidden Hazards in American Cities* (Russell Sage, 2018),
compared with today's federal and state inventories, and explored in an R Shiny app alongside EPA TRI facilities,
cleanup sites (including brownfields), schools, health facilities and CDPHE EnviroScreen 2.0.

## Inventory scope (October 2026)

The 1961–2002 *Directory of Colorado Manufacturers* is used through its **13 complete editions** only — 1965, 1966, 1967, 1968, 1970,
1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992. The other twelve (1961, 1962, 1971, 1976, 1979, 1982, 1984, 1985, 1986, 1993, 1999,
2002) reached the project as partial scans that stop part-way through the geographic section and are set aside until CU Boulder
Libraries supplies the missing pages. The switch is `config/editions.json` (`mode: "complete"`), applied once, in `pipeline/build_sites.py`
and `R/build_sites.R`, so that every downstream product — sites, firm histories, `data/by_year/`, corridors, the census panels, the
redlining comparisons and the health models — inherits it. The all-editions files are kept in `data/full_inventory/`; `R/edition_coverage.R`
and `R/benchmarks.R` read those so the Data and Benchmarks tabs still document every edition. Where an analysis needs "firms of the
decade" for 2000, 2010 or 2020 it uses the last complete decade, 1983–1992. To restore the full inventory set `mode` to `"all"` and rerun
from `build_sites`.

## What is in the repository

| Path | Contents |
|---|---|
| `pipeline/` | Python pipeline: page extraction, Tesseract OCR, format-specific parsers, SIC/NAICS coding, cross-year linking, offline TIGER/Line geocoder, inventory matching, exports |
| `R/` | **R re-implementation** of the geocoder, site building and inventory matching, exposures and health models, checked against the Python results (see `R/README.md`) |
| `run_all.sh` | Runs the pipeline end to end (`./run_all.sh`), or from saved OCR (`./run_all.sh parse`) |
| `app/` | R Shiny app (`shiny::runApp("app")`) and its prepared data |
| `data/by_year/` | **One geocoded CSV per directory edition**: the 13 complete editions (41,987 listings) used throughout; all 25 editions, partial ones included, are in `data/full_inventory/` |
| `data/geocoder/` | ZIP centroids and ZIP–town table used by the geocoder, and every address key with its geocode (for checking the R geocoder) |
| `data/results/` | Site workbook (`CO_hazardous_sites_1961-2002.xlsx`), all sites (`.geojson`), all listings, listings that could not be street-located, geocoding validation |
| `data/historical/` | Pre-1960 layer: hazardous-trade listings (`CO_pre1960_hazardous_listings.csv`) and firm-locations (`CO_pre1960_hazardous_sites.csv`) from the Colorado State Business Directory, 1871–1956; GNIS place gazetteer |
| `data/ocr/` | Saved Tesseract output for every page (lets anyone rerun everything after OCR without the scans) |

## Method in brief

1. **Directories.** 25 editions of the Colorado Directory of Manufacturers (1961–2002) were OCR'd (Tesseract 5.3.4, word boxes)
   and parsed with format-specific parsers (`pipeline/volumes.py` maps each volume to its year and format).
   Columns are rebuilt from word positions: for each page the column cuts are chosen among the detected cuts and forced two- or
   three-column splits by whichever leaves the fewest over-long lines (the October 2026 review found 10–30% of 1966–1977 pages read
   as one column, with neighbouring columns' text interleaved), and lines are clustered on the printed line pitch rather than word
   height (the low-resolution 1992 scan had merged adjacent lines). A street-and-phone line inside a record starts a new record, and
   a size or "S.PROP" line without a founding year counts as a record boundary. OCR digit confusions (C→0, e/€/@→8, B→8 in codes and
   ZIPs; S/$→5, E→1, G→0 in house numbers) are corrected using field context; a five-digit token becomes a Colorado ZIP only when the
   result is a Colorado ZIP and the token is not the house number;
   a ZIP code that the parser left at the end of the street ("1546 GLENARM PL 0202") is moved back to the ZIP field.
2. **Industry.** Printed SIC codes (1965, 1967–1993) or NAICS codes (1999, 2002). The 1961, 1962 and 1966 editions print only product
   descriptions; codes are inferred with a nearest-neighbour classifier trained on description–code pairs from the other editions,
   plus keyword rules for smelters, refineries, plating, wood preserving, etc. (`industry_code_source` records which).
   Two checks guard against OCR errors in codes (`pipeline/consolidate.py`): a printed code whose printed description belongs to a
   code one digit away in another industry is corrected ("2911 MEAT PACKING PLANTS" → 2011; 795 codes, logged in `sic_ocr_fix`), and a
   hazardous code is removed when it cannot belong to the firm – software houses filed under computer equipment, or a code bled in
   from the neighbouring entry that contradicts the firm's own name or description (a bakery with "paving mixtures", a bottler
   predicted as a soap maker; 382 listings, logged in `sic_dropped`).
3. **Hazardous sectors.** Frickel & Elliott's seven: SIC 28 chemicals, 29 petroleum refining, 30 rubber & plastics, 33 primary metals,
   34 fabricated metals, 35 industrial machinery, 37 transportation equipment (NAICS 325, 324, 326, 331, 332, 333, 336).
   An *extended* set adds wood preserving, tanning, electronic components and circuit boards, batteries, photographic chemicals and ore milling.
4. **Linking.** Listings are linked across editions into establishments (token-sorted fuzzy name ≥ 92 within ZIP or city, or ≥ 80 at the
   same street address; 68,368 listings → 40,942 establishments, largest 27 listings).
5. **Geocoding (fully reproducible, offline).** `pipeline/tiger_geocode.py` interpolates house numbers on US Census TIGER/Line 2023
   ADDRFEAT address ranges, tolerating OCR errors (street-type and direction misreads, unit numbers, trailing junk, fuzzy street names
   ≥ 86 similarity that keep the street's own numbers, neighbouring ZIPs within 12 km). Any loosened match is `address_approx`, never
   `address`; so is an address printed without a direction when the same number exists on a directional version of the street in
   the same town or a neighbouring ZIP ("4300 LIPAN" in Denver could be 4300 N or 4300 S Lipan). In Denver-grid towns that choice is
   settled by the printed street type, then by the printed ZIP's own address ranges or its half of the grid (`_dirzip`, `_dirtype`,
   derived from TIGER); an address that neither settles (`_dirambig`) keeps its street coordinate for inspection but counts as
   unplaced (ZIP level). A prefixed address is never placed on the unprefixed street on the wrong side of the Ellsworth/Broadway
   baselines; "SO"/"NO" and a direction letter glued to the street name are read as directions. Each point is offset 12 m from the
   street centreline toward the side whose range held the number. Results are deterministic given the inputs. Listings within 30 m
   form one **site**, except that numbered addresses on opposite sides of the same street are not joined directly.
6. **Inventory matching.** Each site is compared with EPA's Facility Registry Service (Colorado state file), EPA TRI, and CDPHE
   Hazardous Materials & Waste Management Division layers. A site is "known" if a record lies within 75 m (cleanup programs),
   100 m (TRI) or 40 m (RCRA handlers, other permits), shares the firm's name within 250 m, has the same address, or lies inside a
   cleanup site boundary; every site's radius grows by the spread of its member points (to at most 250 m). A name match needs two
   shared informative words or a near-identical whole name, against the site's hazardous firms. **"Not on any list"** = none of these:
   not on the searched EPA and CDPHE HMWMD lists (state petroleum-tank and release registers are reported separately). Each site also
   records its `match_basis`: same entity (name or address), inside a cleanup boundary, or a nearby record only. The October 2026 review
   found that most "known" sites rest on a nearby record only (often an unrelated small-quantity waste notifier within 40 m), so the
   "on no inventory" share is near the low end of what reasonable rules give; `R/known_hidden_sensitivity.R` reports the counts and
   the tract comparison under six rules, from radii doubled to strict (same firm or cleanup boundary only).

## Key results (the 13 complete editions, as published in `data/` and the app)

*Note (29 October 2026): the inventory below (listings, establishments, sites and their inventory matches) is from the run of 29 October with the revised parsing, geocoding and matching rules (see the method notes above). Results further down that use the sites (EJ panel, HOLC industry ratios, Sanborn persistence, health and mortality models, corridors, site fate) are from the R chain of 28 October, which ran on the earlier inventory, and are refreshed by the next run of the R chain.*

* 44,808 listings in the 13 complete editions (1965–1992) → 24,079 establishments; **3,482 hazardous-sector sites** located at street level.
* **1,285 (37%) are on no current federal or state inventory** (920 of them high confidence); 645 (19%) are on a cleanup or contamination
  list; 286 report to TRI; 886 are known only as RCRA hazardous-waste handlers; 380 have only other EPA permits or solid-waste records.
* 1,287 sites hosted two or more hazardous-sector firms over time.
* **How much "hidden" depends on the matching rule** (`R/known_hidden_sensitivity.R`; `data/results/known_hidden/summary.md`).
  1,168 of the 2,197 known sites (53%) are known only because a differently named record lies within the tier's radius: for 48% of
  them the nearest such record is an RCRA hazardous-waste handler and for 36% another EPA permit, and 82% lie 10–40 m away.
  Counting only the same firm (by name or address) or a cleanup boundary, 2,453 sites (70%) are on no inventory; counting proximity
  only within 25 m, 1,793 (51%); counting proximity only to cleanup and TRI records, 2,110 (61%); with every radius doubled,
  738 (21%). The published 37% sits toward the low end of that range. The tract comparison does not depend on the rule: under each of the six
  rules, 2020 tracts that hold a hidden site have higher EnviroScreen 2.0 percentiles (medians 61–63 vs 42 in tracts with no
  hazardous-sector site), more low-income residents (24.5–25.0% vs 18.2%) and more adults without a high-school diploma (5.7–5.9% vs
  4.4%), all p < 1e-5, but similar shares of people of color (27–28% vs 26%, p = 0.03–0.08); and they do not differ from tracts
  with only known sites on any of the four measures (all p ≥ 0.37).

## Earlier results: all 25 editions (run of 17 October 2026, before partial editions were set aside; kept for reference)

* 68,368 listings → 40,942 establishments; **4,312 hazardous-sector sites** located at street level.
* **1,331 (31%) are on no current federal or state inventory** (936 of them high confidence); 860 (20%) are on a cleanup or
  contamination list; 389 report to TRI; 1,238 are known only as RCRA hazardous-waste handlers; 494 have only other EPA permits or
  solid-waste records.
* 1,642 sites hosted two or more hazardous-sector firms over time.
* Census tracts containing a potentially unknown site have higher EnviroScreen scores (median percentile 61.8 vs 43.5 for other tracts),
  more low-income residents (24.7% vs 19.1%) and lower educational attainment (5.8% vs 4.5% without a high-school diploma); all p < 0.001.
  The difference in people of color is small and not significant (27.8% vs 26.4%, p = 0.06). Tracts with unknown sites have the same
  EnviroScreen scores as tracts with only known sites (61.8 vs 60.4, p = 0.57), consistent with Frickel & Elliott's finding that relic
  sites are widespread rather than concentrated where regulators look.

## Accuracy review (17 October 2026)

An independent code review and a re-check of every stage changed the following. Each fix is in the code, so `run_all.sh` reproduces it.

| Problem found | Effect before the fix | Fix |
|---|---|---|
| Street-type mismatch (ST vs AVE) accepted as an exact address | some points on the wrong street | now `address_approx` |
| Suite/unit numbers read as part of the street; fuzzy street matches could change the street number ("W 38TH" ↔ "W 36TH") | wrong street | units stripped; fuzzy matches must keep the street's digits |
| Interpolation along a segment in raw degrees | small along-street shifts | distances scaled by cos(latitude) |
| A site at an approximate location called "not on any list" after a 40–100 m search | hidden count inflated | approximate sites searched over 250 m; radius grows with the site's spread |
| One-digit OCR errors in printed SIC codes ("2911 MEAT PACKING") | non-hazardous firms flagged (and the reverse) | 795 codes corrected |
| Codes bled in from neighbouring entries; software houses filed under computers | bakeries, bottlers, printers, software firms flagged hazardous | 382 listings' hazardous codes removed |
| Cross-edition linking chained unrelated firms (one "firm" had 4,776 listings) | firm histories and site persistence wrong | stricter name matching; largest firm now 27 listings |
| Name matching to inventories used a random 12 of a site's names | results varied between runs at 167 busy addresses | all names, fixed order |
| ZIP codes left in the street field | 419 listings without a ZIP, many unplaced | ZIP recovered |
| An address printed without its direction placed on the plain street when a directional street also holds that number (Denver's 4300 LIPAN → 4300 N Lipan, but the firm was at 4300 S Lipan, 15 km away) | about 1 in 25 "exact" points on the wrong side of town | flagged `dirambig`, counted as approximate (medium confidence) |
| Pre-1960: a trade word from the next listing in an interleaved line ("Goldhammer S, phys, 312 17th. GOODRICH RUBBER CO") | physicians, grocers etc. listed as hazardous trades; addresses of neighbours | 350 entries dropped, 732 streets corrected |

Net effect since the previously published run: hazardous-sector sites 4,458 → 4,312, sites on no list 1,842 → 1,331, and high-confidence hidden sites 1,168 → 936. A random check of 50 "not on any list" sites
against the directory text still found about 1 in 10 with a doubtful industry code (a bookbinder coded as metal stamping, a jeweller
whose 1984 code was misread as tires): treat each site as a lead to check, not a finding. Town headings are sometimes wrong in the
1961, 1962 and 1965 editions (e.g. Boulder pages filed under Allenspark); those listings fail the geocoder's 15 km town check and stay
off the map rather than being misplaced.

## How good is the geocoding?

Three independent checks (October 2026).

**1. Against Colorado's statewide address points** (`pipeline/validate_addresspoints.py`,
`data/results/geocoding_validation_addresspoints.csv`). The State's public address-point layer places addresses on rooftops or parcels
and does not come from TIGER address ranges. For a random sample of 1,000 sites we looked up the same house number and street in the
stated town and measured the distance to our point:

| geocode level | sampled | compared | median | 90th pct | within 100 m | within 250 m | over 1 km |
|---|---|---|---|---|---|---|---|
| address | 679 | 455 | 49 m | 171 m | 79% | 94% | 0.9% |
| address_approx | 299 | 119 | 103 m | 946 m | 50% | 75% | 10.1% |

(19 sampled sites fell back to a ZIP centroid under the corrected geocoder and are no longer mapped.)

**Re-check on the final data** (17 October 2026, fresh random sample of 300 address-level and 100 approximate sites, queried from
a browser in 20 batched requests; `data/results/geocoding_validation_addresspoints_recheck.csv`): address level n = 131 compared,
median 67 m, 88% within 250 m, 3.8% (5 sites) over 1 km; approximate n = 32, median 97 m, 75% within 250 m, 12.5% over 1 km.
All five address-level misses were Denver addresses printed without a direction ("4440 YATES", "4300 LIPAN", "4200 FOX") that the
geocoder had put on the north side of town while the State's address points only know the south-side address, 14–16 km away.
That is the `dirambig` rule above: those points are now approximate, and 119 hidden sites moved from high to medium confidence.
Addresses that do not exist today anywhere in the stated town (129 of the 167 unmatched address-level sites) cannot be checked.

(Run on 17 October 2026 before the last data fixes, which moved few points; the State's service is not reachable from every network, so
`validate_addresspoints.py` leaves the saved results in place when it cannot connect.) About a third of address-level listings have no matching address point today (the building is gone, the street was renumbered or
renamed, or the house number was misread); those could not be checked.

**2. Against EPA Facility Registry coordinates** for identical addresses (`pipeline/validate_geocoding.py`,
`data/results/geocoding_validation.md`, rerun on the final data): address level n = 1,841, median 48 m, 88% within 250 m, 2.7% over 1 km
(FRS coordinates carry their own error).

**3. Against the scans.** For 25 randomly chosen sites we compared the parsed address with the printed page: 23 matched, one house
number was misread by OCR (2915 for 3915 Tennyson, about 1.3 km off), and one could not be located on the crop. Expect roughly
4% of house numbers to carry an OCR digit error; most other OCR noise (street-type letters, suite numbers) does not move the point.

**What the vetting changed.** The first check exposed a geocoder bug: an address on a south-side street ("1934 S Broadway") could match
the north-side street of the same name ("Broadway") in the same ZIP, moving it up to 14 km. The geocoder now requires the prefix
direction to match, falls back to a direction-free match only as `address_approx`, and rejects matches more than 15 km from the stated
city. 113 sites moved by more than 1 km. Address-level points over 1 km from the address point fell from 4.7% to 0.9% and from 3.6% to
2.7% against FRS.

**How to read it.** `address` points are good to about a city block (median ~50 m, 94% within 250 m), with roughly 1–3% badly wrong,
mostly because of misread house numbers. `address_approx` points are right to the street or neighbourhood but about 1 in 10 are more
than 1 km off; check them before field work. Listings placed only at a ZIP or city centroid are in the edition CSVs but not on the map.
Coverage varies by edition: 22–76% of listings geocode at address level (`data/results/geocoding_coverage_by_year.csv`).

**Pre-1960 layer.** Most entries (about 90%) are placed only at the town centre and are drawn as clusters. Street-level placement uses
today's numbering, which applies to Denver after the 1887 renumbering, but later street renamings are not handled and these points have
not been checked against historical maps (e.g. Sanborn atlases); treat them as approximate. Vetting this layer removed 2,205 entries
that were workers listed at their home addresses ("Cain Patrick, stoker, Denver Gas Co, 2422 Champa"), not works. It also stopped
placing 1,846 office listings at their downtown office addresses.

## Do hidden hazards matter for health? (first analysis, October 2026)

`pipeline/health/build_exposures.py` and `pipeline/health/health_models.py`; full results in `data/results/health_models.csv`.

*Input not fetched by script:* the EnviroScreen 2.0 block-group layer (`work/health/enviroscreen_v2_blockgroups.geojson`) was downloaded by hand from CDPHE's EnviroScreen download page as a shapefile and converted to GeoJSON, which is why its fields carry shapefile-truncated names (`Prcnt_lw_` = percent low income, `Prc___` = percent people of color, `Pr_____` = percent less than high school, `Prcnt_ln_` = percent linguistically isolated, `Pp__64` = population over 64); `run_all.sh` and `R/run_all.R` skip the health step when it is absent.

**Data.** Outcomes come from CDPHE Colorado EnviroScreen 2.0. Its block-group layer repeats the tract value for every health indicator,
so outcomes vary only between tracts: the analysis uses 1,248–1,428 tracts with at least 500 residents (depending on the outcome). Asthma hospitalization, low birth weight and life
expectancy come from administrative records; the heart disease, cancer, diabetes and mental health indices are modelled estimates.
Exposure is a kernel density of sites (σ = 500 m) at each block-group centroid, averaged to the tract, log-transformed and expressed
per standard deviation.

**Models.** Nested, each fit by OLS and as a spatial error model (queen contiguity):
M1 SES and demographics (low income, people of color, < high school, linguistic isolation, age 65+, under 5, log density) →
M2 + hazards regulators track (EnviroScreen proximity to hazardous-waste, NPL and RMP facilities; TRI and cleanup-site density) →
M3 + historical hazardous-sector sites that are on some inventory → M4 + hidden historical sites (on no inventory).
Placebo: non-hazardous manufacturers from the same directories (same source, same geocoding, no hazardous process).

Coefficients for 1 SD more exposure, spatial error models (standard errors in parentheses; * p<0.05, ** p<0.01; the table is
`data/results/health_models.md`, built from `health_models.csv`):

| Outcome | Hidden sites, M4 (per SD) | Known historical, M4 | Placebo (non-hazardous mfrs), M4+placebo | ΔAIC M3→M4 | LR p (M4 vs M3) |
|---|---|---|---|---|---|
| Asthma hospitalization rate (log) | -0.025 (0.037) | 0.104 (0.048)* | 0.007 (0.041) | 1.6 | 0.505 |
| Low birth weight (%) | 0.029 (0.150) | 0.065 (0.194) | -0.041 (0.166) | 2.0 | 0.845 |
| Life expectancy (years) | 0.080 (0.138) | -0.436 (0.179)* | -0.414 (0.155)** | 1.7 | 0.564 |
| Heart disease (index) | 0.601 (0.871) | -1.509 (1.090) | 2.285 (0.995)* | 1.5 | 0.49 |
| Cancer (index) | -0.232 (0.832) | 0.092 (1.050) | -0.190 (0.946) | 1.9 | 0.781 |
| Diabetes (index) | 0.718 (0.796) | -0.257 (0.990) | 1.614 (0.917) | 1.1 | 0.368 |
| Poor mental health (%) | -0.187 (0.081)* | 0.171 (0.103) | -0.043 (0.090) | -3.4 | 0.0202 |

**Reading.** Unadjusted, tracts with more hidden sites have more asthma hospitalizations, lower life expectancy and more heart disease
and diabetes. Most of that goes away with SES and demographics, and the rest goes away once regulated hazards (above all
cleanup-site density) are in the model: hidden sites add explanatory power for one of the seven outcomes, poor mental health, and
there with a protective sign (−0.19 points per SD, LR p = 0.02), which is what chance would produce across 7 outcomes × 5 nested
tests; for the other six the likelihood-ratio p is 0.37 or more. The
placebo is as strong as or stronger than the hidden sites (life expectancy, heart disease). So at the tract level, with these outcomes,
the association is with industrial land use generally, not specifically with unregulated hazardous sites. This does not show hidden
hazards are harmless: tract averages and modelled outcomes are blunt, and many cleanup sites are themselves former hidden sites
(cleanup listing is partly an outcome of the same history).

### Block-group mortality (Colorado death records, 2015–2019)

`pipeline/health/mortality_bg.py`. Natural-cause and all-cause deaths from Colorado death records, aggregated to 2010 block groups,
with person-years as the offset (the record-level file and block-group counts are restricted and are not in this repository).
Negative binomial models with county fixed effects and tract-clustered standard errors; covariates are SES, age structure (% 65+,
its square, % under 5), density and PM2.5. Rate ratios per 1 SD of log site density (95% CI):

Block groups: 3439, natural-cause deaths 2015-2019: 158,758

*This table is from the run on all 25 editions (17 October 2026); it is refreshed by `python3 pipeline/health/mortality_bg.py`, which
needs the restricted death counts, and stands as is until that rerun.*

| Outcome | Model | Hidden sites RR per SD | Known historical | Placebo (non-hazardous) | Cleanup sites | AIC |
|---|---|---|---|---|---|---|
| natural-cause | M1 SES+age+PM2.5 |  |  |  |  | 30739.0 |
| natural-cause | M2 +regulated |  |  |  | 1.027 (0.993–1.062) | 30736.1 |
| natural-cause | M3 +known historical |  | 1.045 (0.999–1.092) |  | 1.006 (0.968–1.045) | 30732.1 |
| natural-cause | M4 +hidden | 1.004 (0.967–1.042) | 1.042 (0.993–1.094) |  | 1.005 (0.967–1.046) | 30734.1 |
| natural-cause | M4 hidden high-confidence only | 1.007 (0.974–1.042) | 1.040 (0.990–1.092) |  | 1.005 (0.967–1.045) | 30733.9 |
| natural-cause | Placebo: M2 +non-hazardous mfrs |  |  | 1.067 (1.029–1.106)* | 0.996 (0.959–1.035) | 30718.5 |
| natural-cause | M4 +placebo | 0.990 (0.953–1.029) | 1.027 (0.977–1.079) | 1.064 (1.023–1.106)* | 0.990 (0.950–1.031) | 30720.8 |
| all-cause | M1 SES+age+PM2.5 |  |  |  |  | 31421.9 |
| all-cause | M2 +regulated |  |  |  | 1.034 (1.001–1.067)* | 31414.3 |
| all-cause | M3 +known historical |  | 1.051 (1.008–1.095)* |  | 1.010 (0.974–1.047) | 31408.1 |
| all-cause | M4 +hidden | 1.005 (0.970–1.041) | 1.047 (1.001–1.097)* |  | 1.009 (0.973–1.047) | 31410.0 |
| all-cause | M4 hidden high-confidence only | 1.008 (0.976–1.041) | 1.045 (0.998–1.095) |  | 1.009 (0.973–1.046) | 31409.7 |
| all-cause | Placebo: M2 +non-hazardous mfrs |  |  | 1.068 (1.032–1.105)* | 1.002 (0.967–1.039) | 31394.6 |
| all-cause | M4 +placebo | 0.991 (0.956–1.028) | 1.032 (0.985–1.082) | 1.063 (1.024–1.103)* | 0.994 (0.956–1.032) | 31396.1 |

Hidden sites are not associated with mortality (rate ratio 1.00 per SD, 95% CI 0.97–1.04); the non-hazardous-manufacturer placebo is
(about 7% per SD, significant), and known historical sites sit in between (about 4–5%). The same pattern as the
tract analysis: mortality is higher around historical industry generally, and these data cannot attribute it to the hidden hazardous
sites specifically. Age adjustment is limited to block-group age shares (the death file has no age), so residual age confounding is
possible.

**What could detect an effect if there is one:** outcomes that vary below the tract (geocoded birth records, hospital discharges or
blood-lead tests from CDPHE under a data agreement); outcomes specific to the pathways these sites create (childhood blood lead,
soil and indoor-air vapor intrusion, specific cancers from the Colorado Central Cancer Registry); and within-neighbourhood designs
(distance to the nearest site among residents of the same tract) that hold industrial land use constant.

## Industrial corridors and the origins of environmental inequality (R, October 2026)

`R/corridors.R` (runs from the repository's own data; outputs in `data/results/corridors/`):

* **Formation and persistence.** 500 m grid cells with any located manufacturer in the 13 complete editions 1965–1992, classed as persistent (listed from the
  1960s to the 1990s in ≥ 60% of the editions between), emerging (first listed 1980 or later), former (none after 1980) or intermittent;
  "persistent, sector turnover" when the dominant two-digit sector changed at least twice. Pre-1960 street-level firms extend a cell's
  history where they exist (Denver 1891+). Denver metro (25 km of downtown): 1,453 cells, of which 290 persistent (231 with sector
  turnover), 633 emerging, 242 former (`corridors_summary.md`).
* **Clustering.** Ellison–Glaeser γ per sector and edition on 1 km cells, measured against the distribution of *all* located manufacturers
  that year (so it asks whether a sector is more concentrated than manufacturing in general), with a random-relabelling p-value.
  Printing (significant in every edition), petroleum products and machinery (about half) cluster beyond general manufacturing; chemicals, primary
  metals and transportation equipment do not, statewide or in the metro. γ is on the Ellison–Glaeser scale with equal plant weights.
* **Succession.** Transition counts of a cell's dominant sector between successive editions (`sector_transitions.csv`) and from first to
  last listing (`sector_first_to_last.csv`). Machinery ↔ fabricated metals and food ↔ printing are the common exchanges.
* **Do old industrial areas attract new industry?** Entries (first listing) per cell and edition against the cell's stock and its
  neighbours' stock in the previous edition and distance to downtown: pooled Poisson elasticity 0.99 for own stock, 0.30 for
  neighbours; within-cell (demeaned) 0.12 per log-unit (`entry_models.csv`). The standard errors are iid Poisson on repeated
  observations of the same cells, so read these as descriptive. Persistence of location, not an explanation of it (no rail, river or zoning
  controls yet).
* **Present-day legacy.** Tract spatial error models: a tract's cumulative manufacturing history (firm-years in the complete editions 1965–1992, hazardous-sector
  firm-years, or hidden sites) predicts today's EnviroScreen score, low income and people of color (all p < 0.01 except hidden sites
  for people of color). Associations, with density as the only control.

`R/ej_panel.R` — the "how did it develop" design of Marlow, Frickel & Elliott (2020): a tract panel for the Denver core (Denver County
plus the inner parts of Adams, Arapahoe and Jefferson), matched to the censuses with a complete directory edition in the same year
(1970, 1980, 1990), with active-site density (within-tract change), legacy-site density (sites listed earlier but no longer active) and
the reverse model (composition at t → net change in active establishments by t+1). It needs census extracts that are not redistributed here: the Longitudinal Tract Data Base
(Brown University, free) in 2010 tract boundaries, and optionally NHGIS 1940–1960 tract tables and boundaries (areal-interpolated to
2010 tracts as counts, then percentages) and Brown's 1880 enumeration districts for a cross-section against the 1879–1885 directories.
`R/fetch_census.R` downloads them through the NHGIS API (`ipumsr`): standardized-to-2010 tract time series 1970–2020 for
Colorado (population, race, Hispanic origin, nativity, poverty), the 2010 tract boundaries, and the 1940–1960 Denver tract tables
and boundaries; it writes `work/census/denver_tract_panel.csv`, which `ej_panel.R` reads. You need an NHGIS account and an API key
(https://account.ipums.org/api_keys) in the environment variable `IPUMS_API_KEY`; the key is never stored.
**Results (Denver core: the 147 tracts in 2010 boundaries within 10 km of downtown; censuses 1970, 1980 and 1990, the three with a
complete directory edition in the same year; 437 tract-years; `data/results/ej_panel_models.csv`, `ej_panel_reverse.csv`).**
Census years from NHGIS (1970–1980 area-weighted from their own tracts onto 2010 tracts); "active" = hazardous-sector establishments
listed in the matched directory, "legacy" = sites listed in earlier directories but no longer active at the first panel year. Hybrid
model with tract-clustered SE; coefficients are percentage points (log points for home value) per log-unit of establishment density.
The reverse model regresses the net change in a tract's active hazardous establishments by the next census on its composition
(tract density, population, distance and year controlled; tract-clustered SE; 290 tract-years).

| Outcome | Within-tract change in active density | Between-tract active density | Legacy density (1970) | Reverse: composition → net change in establishments |
|---|---|---|---|---|
| % Hispanic | −0.8 (SE 1.2, p = 0.53) | **+17.6 (3.9, p < 0.001)** | −1.6 (n.s.) | **+0.052 (0.014, p = 0.0001)** |
| % Black | −0.6 (n.s.) | +1.8 (n.s.) | −2.6 (n.s.) | +0.007 (0.004, p = 0.10) |
| % White | −3.6 (n.s.) | **−10.4 (3.5, p = 0.003)** | +1.5 (n.s.) | −0.005 (n.s.) |
| % foreign born | +0.8 (n.s.) | +0.1 (n.s.) | +0.9 (0.5, p = 0.08) | **−0.128 (0.054, p = 0.019)** |
| % in poverty | +1.4 (n.s.) | **+5.8 (1.6, p < 0.001)** | +2.0 (n.s.) | **+0.087 (0.035, p = 0.013)** |
| log home value | −0.06 (n.s.) | **−0.22 (0.04, p < 0.001)** | 0.00 (n.s.) | **−1.6 (0.77, p = 0.04)** |

Reading: within a tract, a rise or fall in hazardous-establishment density between 1970 and 1990 was not followed by a change in
Hispanic share, poverty or any other outcome in the same decade — nothing is significant within tracts. The association is between
places: tracts with dense industry had larger Hispanic shares, smaller White shares, more poverty and lower home values, and the
same places still differ in 2000, 2010 and 2020. Black share is not associated with industry at the tract scale (Denver's Black
neighbourhoods, Five Points and Whittier, were shaped by covenants rather than by the industrial Platte corridor). In the reverse
direction, tracts with higher Hispanic and poverty shares and lower home values gained hazardous establishments by the next census,
and tracts with more immigrants lost them. With three censuses the reverse models are indicative; an association between places in
both directions is consistent with industry and disadvantaged residents each drawing the other to cheap land rather than with either
causing the other. The next step is to extend the panel back to 1940–1960 against the business directories.

`R/fetch_ipums_fullcount.R` takes the period before tracts (1880–1940) from the IPUMS USA 100% census files, Colorado only, and
aggregates them to enumeration districts (population, Black, foreign born by region, Hispanic, labourers); the ED boundaries to map
them come from Brown University's Urban Transition HGIS (1880 for Denver; 1900–1940 street-and-ED reference files), which is free
but asks for an e-mail and acceptance of its conditions of use. Denver is IPUMS `CITY` 1710 (the City and County of Denver exists only
from 1902; in 1880 and 1900 Denver is Arapahoe County, `COUNTYICP` 50, whose EDs 1–17 are the city). City totals 1880–1940 and the
dissimilarity index across EDs (`app/data/denver_city_1880_1940.csv`): Black residents were 2.4–2.8% of Denver throughout, but their
segregation across enumeration districts rose from 0.41 (1880) to 0.51 (1900), 0.65 (1920) and 0.82 (1940); the foreign-born share fell
from 24% to 8% while its dissimilarity stayed at 0.13–0.26; the Hispanic share (IPUMS HISPAN) was under 1.5% until 1930 and 4.6% in 1940.

### Denver 1880: who lived next to the hazardous trades? (`R/denver_1880.R`)

Brown University's Urban Transition HGIS geocoded the full 1880 census of Denver to buildings and drew the 17 enumeration districts and
the 1880 street grid. `R/denver_1880.R` places the 108 hazardous-trade firms of the 1878–1885 business directories (smelters, foundries,
powder agents, gas works, assay offices…) on that grid by their printed house numbers — the same pre-1887 numbering Brown used, so this
does not depend on today's streets — and measures every resident's distance to the nearest one. 69 firms are placed (60 at the building
or within a few house numbers). Results (`data/results/denver_1880/`, aggregates only; Brown's files stay in `work/census/brown/` under
their conditions of use):

| band | residents | % foreign born | % German | % Black | % Chinese | % laborers (employed adults) | mean SEI (employed adults) |
|---|---|---|---|---|---|---|---|
| < 100 m | 10,726 | 27.1 | 5.3 | 2.9 | 1.6 | 10.8 | 31.8 |
| 100–250 m | 8,985 | 23.7 | 4.4 | 4.6 | 0.4 | 11.3 | 31.3 |
| 250–500 m | 6,199 | 24.1 | 4.1 | 1.5 | 0.0 | 10.9 | 31.8 |
| > 500 m | 8,476 | 23.9 | 3.3 | 1.8 | 0.0 | 18.9 | 28.3 |

Person-level models (odds ratio per log-metre of distance, building-clustered SE; < 1 = lived closer): foreign born 0.945 (p = 0.03),
Black 0.883 (p = 0.03), Chinese 0.33 (p < 1e-10), German-born 0.87 (p = 0.0002), Irish 1.02 (n.s.); employed adults' SEI fell by 1.0 per
log-metre (p = 0.002), and unskilled laborers (Duncan SEI 8) were more common farther out (OR 1.20), in the cheap land beyond the
built-up core. In 1880 the hazardous trades were concentrated in the lower-downtown districts (ED 10 alone holds 22 of the 60 firms placed at a building or house number) where the foreign-born and Black shares were highest; the `laborer`
pattern is the opposite of what the later tract panel shows for poverty, a reminder that "far from industry" meant the undeveloped
fringe in a 35,000-person city. `occlabelB` in Brown's microdata is an undocumented occupation-string id; SEI (`seiusB`, 0 = no
occupation) is the documented measure and is used for both the laborer flag and the SEI results.

`R/fetch_census.R` also fetches foreign born and poverty for 1990–2020 (1990 STF3, 2000 SF3, ACS 2008–12 and 2016–20 tract
tables, area-weighted onto 2010 tracts where needed), which the standardized NHGIS series lack; re-run it to fill those years.

### Enumeration districts 1880–1940, reconstructed (`R/grf_eds.R`, `pipeline/historical/grf_eds.py`, `R/denver_eds_analysis.R`)

No public source has boundaries for the enumeration districts of 1880–1940 (IPUMS gives each person's ED number but no address;
NHGIS starts at tracts). Brown's Geographic Reference Files for Denver list every person of the 1900–1940 censuses with the
household's street, house number and ED. The districts are reconstructed from them: every distinct address is geocoded with the
project's offline TIGER geocoder (the post-1887 numbering still applies; Holladay → Market etc. translated), street-level results
kept; stray geocodes dropped (farther from the ED's person-weighted median centre than max(400 m, 2.5× the median), or fewer than
30% of the ten nearest neighbours in the same ED); the Voronoi tessellation of the remaining addresses dissolved by ED and clipped to
the concave hull of all addresses, each ED keeping its main body and freed ground going to the nearest ED, so the districts are
space-filling like tracts. 1880 is tessellated the same way from Brown's geocoded buildings. IPUMS full-count totals are joined by ED
number (1900–1930: `ENUMDIST mod 100000`; 1940: SD-ED-suffix → "225", "250A"). Polygons: `data/results/denver_eds/denver_eds_<year>.geojson`
(this project's derived product; the address files stay in `work/`); geocoding log `ed_geocoding.csv`. `R/denver_eds_analysis.R`
places the hazardous trades of the preceding decade in the districts and writes `ed_year_groups.csv` (EDs with vs without a firm,
dissimilarity), `ed_distance_models.csv` (composition vs log distance to the nearest firm, population-weighted, HC1) and the app layers.
Boundaries are approximate (a block or so at the edges). The Python and R versions implement the same steps; R's Voronoi/concave hull
come from sf (GEOS ≥ 3.11).

**All fields (IPUMS extract with 43 variables, 64 measures per district; `ed_year_groups.csv`, `ed_distance_models.csv`).** The
housing market reads the hazard exactly as expected: owner-occupancy rises 11.5 (1900) to 21.0 (1940) points per log-metre from the
nearest firm in every census 1900–1940 (pooled +18.9, p < 1e-100), mean SEI of employed residents rises 2.3–5.2 points, and
non-relatives in the household (boarders, lodgers, servants) fall by 3.8–16.1 points; districts with a firm had 13–28% owner households
against 30–47% elsewhere, and in 1940 a median rent of $17 against $52. Recent immigrants (arrived within ten years) concentrate near
industry 1900–1930; illiteracy is higher there; and in 1940, 80% of residents of the firm districts had moved house since 1935 against
72% elsewhere (−7.5 points per log-metre, p < 1e-14) — the industrial districts were the city's high-turnover rental belt. Employment
in the hazardous industries themselves shows no gradient (7–11% of workers everywhere), so the people living next to the plants were not, for the most part,
their workforce.

`R/county_panel_1880_1940.R` gives the statewide counterpart: the full count by county on each census's county boundaries (NHGIS
extract F in `fetch_census.R`), with the pre-1960 trades of the decade by county.

### Redlining and racial covenants (`R/holc_covenants.R`)

Xu (2022, *Housing Policy Debate*) compared HOLC's post-hoc Residential Security Map of Chicago with the FHA's implemented
mortgage-risk map; no FHA map survives for Denver, so here the 1938 HOLC grades (Mapping Inequality, CC-BY-NC, with the
appraisers' area-description forms and the crosswalk to 2010 tracts) are read against what preceded them — the reconstructed
1930/1940 districts and the firms of 1921–40 — and what followed (the 1940–2020 tract panel), together with the 730 located racial
covenants of 1931–35 from Denver Public Library's Mapping Prejudice pilot (public domain; `data/covenants/`). Results
(`data/results/holc/`): no A or B area held a hazardous firm in 1921–40; 4 of 16 D areas did (and 5 of 20 C areas), and 8 D-area
descriptions cite industry, railroads, smoke or odours. In 1930 the future D areas were already 8.3% Black (vs 0.5–1.1% elsewhere),
1.6% Hispanic and 7.2% laborers; by 1940 their Hispanic share was 9.9% (0.5–0.7% elsewhere). Afterwards the D tracts went to 37%
Hispanic in 1970 and 57% in 2000. In the change models (`holc_tract_models.csv`; A = reference, 1940 baseline, 1940 % Black and
1931–40 firms controlled; the Hispanic-share models start in 1970, the first census that identifies Hispanic residents comparably),
the D tracts' Hispanic share rose 3.6 points more than the A tracts' 1970–80 (SE 3.1, HC1 p = 0.25) and 14.0 points more 1980–2010
(7.7, p = 0.075; Conley 2 km p = 0.18); poverty rose 4.4 points more in D than in A tracts 1970–80 (2.1, p = 0.037; Conley p = 0.007)
and 11.0 points 1980–2010 (3.8, p = 0.005; Conley p = 0.024); log home value fell 0.54 more 1940–80 (0.17, p = 0.003;
Conley p = 0.001). Black share did not differ by grade once the 1940 baseline is controlled. Classes with fewer than five tracts are
dropped from these models (the A reference class, four tracts, is kept), so the estimates are fragile; the D estimates for poverty
1980–2010 and 1970–2010 and for home value 1940–80 and 1940–2010 hold under classical, HC1 and Conley errors, the Hispanic-share
estimates do not reach p < 0.05 under HC1 or Conley errors.
27 of the covenant deeds also bar business or manufacturing use. HOLC also outlined ungraded "Industrial" and "Commercial"
zones, and that is where the pre-1938 industry sat: 64% of the street-level hazardous trades listed before the map were in
Commercial zones and 14% in Industrial ones, 15% in D areas and none in A or B (`holc_facility_shares.csv`). Classing the 1930
districts by the HOLC class that covers them (`ed_holc_classes.csv`): the D districts, 7.3% Black in 1930, held 2.4 hazardous
firms per 10,000 residents before the map and 45 hazardous-sector sites per 10,000 in 1965–92, against 5.6 per 10,000 in A–C —
the post-war industrial growth went into the redlined and industrial districts. The app's Redlining tab shows the 1930
districts by class, covenants, composition and firms before/after the map, and the share of each era's facilities by HOLC class.

**Did the map create or reinforce the pattern?** Following Aaronson, Hartley & Mazumder (2021), `R/holc_covenants.R` also tracks the
D-minus-C gap census by census from 1900 (reconstructed districts area-weighted into the fixed HOLC polygons; no harmonisation needed)
to 2020 (2010 tracts), both for all C vs all D areas and within a boundary band (district centroids within 400 m, tract centroids within
800 m, of both a C and a D area), with population-weighted HC1 standard errors (`holc_boundary.csv`, `holc_gaps.csv`); and hazardous
firms per km² of each grade in six periods from 1891 to 2002 (`holc_industry_periods.csv`). At the C–D boundaries the Black-share gap
was nil in 1900–1920, 4 points by 1930 and 6 by 1940 — before the map — then 10–18 points in 1950–1970 before converging after 1980;
the Hispanic gap opens only in 1940 and after. Hazardous firms per km² per directory edition in D areas against C areas
(`holc_industry_periods.csv`): 6.4× in 1906–20 (but on 13 firms in D against 3 in C), 1.7× in 1921–37 (8 against 9 firms) and 2.1×
in 1938–56 (37 against 27), then 13.6× in 1965–80 (286 against 49) and 16.8× in 1981–92 (228 against 28); the pre-1938 ratios rest on a
handful of street-level listings. Reading: the appraisers ratified a divergence already under way, which then accelerated. Railways and the 1925 zoning
ordinance are not controlled, and Fishback, Rose, Snowden & Storrs (2024) show that FHA practice, not the HOLC map, governed lending,
so the post-1938 acceleration cannot be attributed to the map alone. Two controls address this: the distance of each unit to the
nearest rail line (TIGER rails; `gap_rail`), and the share of each unit zoned industrial under Denver's first zoning ordinance
(`gap_zone`, `b_zone`), from `R/zoning_1925.R`. Robustness outputs: `holc_boundary.csv` also carries Conley (2 km) standard errors
(`se_conley2km`, needs the `fixest` package) and the gap with the strict zoning layer (`gap_zone_strict`); `holc_boundary_bandwidth.csv`
repeats the D–C gaps with narrow/standard/wide bands (districts 200/400/800 m, tracts 400/800/1600 m); `holc_trend_test.csv` regresses the
census-by-census D–C gap on time with a post-1938 level shift and slope change (weighted by 1/SE², thirteen points, indicative only);
`holc_tract_models.csv` carries Conley SEs and the strict-zoning estimates for the change models.

### The 1925 zoning ordinance (`R/zoning_1925.R`)
Denver zoned in February 1925, thirteen years before the HOLC map. The Denver Public Library's scan of the *Building Zone Map* as revised
to January 1929 (CG4314 .D4 G44 1929) is a monochrome hatched map; a texture classifier run on the 11,849 × 12,000-pixel scan labels
32-pixel cells as Industrial A ("/" hatch with no lot lines), Industrial B ("\" hatch) or Commercial (dense cross-hatch), with the
result drawn over the scan in `data/raw/zoning_1929/zone_classification_overlay.jpg` and the cells in `zone_cells_1929.csv`. The
script georeferences the scan from 16 candidate control points (street intersections and park corners read off the scan), 13 of which
resolve to TIGER road intersections with `tigris` (affine fit in UTM 13N, RMSE 25 m; `data/results/zoning_1929/gcp_fit.csv`) and writes the zoned districts (`zoning_1929.geojson`) and the
industrially and commercially zoned share of every HOLC area, enumeration district and 2010 tract (`zoning_shares_*.csv`), which
`holc_covenants.R` then uses as a control in the boundary gaps and the change models. Residence E (apartments) and Industrial A share a
hatch and are separated only by the absence of lot lines, so a few platted Industrial A blocks and the unplatted land north-east of
the 1929 city are the least certain cells; `zone_cells_1929.csv` flags them (`uncertain`), and a strict share that drops them is carried
through the analyses as a sensitivity check. The library's 1944 revision of the same map (revised to 1 April 1944) was registered to the 1929 scan by a ten-point
affine fit (`affine_1944_to_1929_px.csv`, RMSE ≈ 32 m) and compared cell by cell (`pipeline/zoning/classify_zoning_1944.py`, then
`Rscript R/zoning_1944.R`): one random forest trained on the 1929 labels is applied to both scans resampled to a common frame; clusters
where the two years disagree (226) are candidates, every one of a block or more (118) was inspected on side-by-side binarised crops, and
only visibly redrawn districts were accepted (`changes_1944_review.csv`, 9 accepted, 8 distinct areas). `zone_cells_1944.csv` is the
1929 layer with those changes applied. Result: no industrial district added 1929–44; 0.47 km² of Industrial A (2%) redrawn as
commercial, business or apartment districts; D land zoned industrial 16.2% → 15.9% on the land both sheets cover. Changes smaller than
a block and the hand-coloured amendments on the 1944 copy are not included.

### Zoning today (`R/zoning_2023.R`)
Denver-metro zoning of 3 October 2023 compiled by Carrie Makarewicz (University of Colorado Denver) for the National Zoning Atlas
(place `ALL_DenverMSA_10.3.23.*` in `work/zoning_2023/`). The site shows it on its maps, grouped into six categories, with the author's permission, but does not offer it for download; request the layer through the form on the project's StoryMap, https://storymaps.arcgis.com/stories/adb86c7ab2624e95a84566fecb8a6f6d. The script tabulates the 1929 districts, the hazardous
sites and the 147 study tracts by 2023 zoning category (industrial without housing, Denver's I-MX industrial mixed use, other mixed use
with housing, residential, commercial, other) into `data/results/zoning_2023/`.

### Zoning, 1929 to today (`R/fetch_zoning_city.R`, `R/zoning_over_time.R`)
Every Denver zoning map available in digital form, on one geography and one set of categories: 1929 and 1944 (above), the 2023
National Zoning Atlas layer, and the city's official zoning map today (`Rscript R/fetch_zoning_city.R` downloads it from Denver's open
data, layer CCD_Zoning/27, into `work/zoning_city/`; each district carries the year of the ordinance that last zoned it). The 1956
ordinance's map and later citywide maps before 2010 are not digitised (Denver Public Library holds them in print). `Rscript
R/zoning_over_time.R` writes to `data/results/zoning_over_time/`: industrial land by year and by HOLC grade on the 202 km² of Denver
County covered by both historical sheets (14.0% → 13.8% → 10.6% → 10.4%; D land 16.3% → 12.2%); what the 1929 industrial land is zoned
today and the year of its last zoning ordinance (an upper bound on when it left industrial zoning, since earlier rezonings are not
recorded); the share of sites in industrial districts each year; tracts industrial in 1929 and/or today with their 1970–2020
composition; and dissolved category polygons for the site's maps.

### Land use 1937–1997 (`R/landuse_1937_1997.R`)
The USGS historical land-use maps of the northern Front Range (Drummond, Stier & Diffendorfer 2019, https://doi.org/10.5066/P995RGC9;
public domain): 1 m rasters for 1937, 1957, 1977 and 1997, interpreted by hand from aerial photographs. Download the
"1937to1997_north_front_range_tifs.zip" set (the "extended" set has only 8 broad classes, without industry) and unzip it into
`work/usgs_landuse/north/`. The script groups the 37–46 classes into eight (industrial, waste and extraction, transportation, commercial,
single-family, multifamily, institutional, open land), aggregates to 10 m (cached in `work/usgs_landuse/`), and writes to
`data/results/landuse/`: land by year, by HOLC grade, against the 1929 zoning, the share of sites on industrial land, land under the sites
1977→1997, tract industrial-use shares and the composition of tracts by industrial path, plus 20 m category rasters for the site's maps.
The rasters end at latitude 39.62, so a sliver of far-south Denver is unmapped; shares are computed on mapped land only.

### Freeways (`R/fetch_highways.R`, `R/highways_denver.R`)
`Rscript R/fetch_highways.R` downloads the NBER highway data (interstate opening dates by route, county and milepost from the FHWA PR-511
reports; corridors; the 1947 plan), TIGER 2023 primary roads, and OpenHistoricalMap's dated road alignments around Denver (Overpass API) into
`work/highways/`. `Rscript R/highways_denver.R` writes to `data/results/highways/`: dated alignments for the maps, freeway km opened and removed by decade and km in service at each decade's end (segments taken down or replaced drop out),
an NBER-versus-OpenHistoricalMap check for Denver County's interstates, freeway length and nearby land by HOLC grade, freeway length by
1929 zoning, and the composition of tracts crossed by freeways built 1950–1979. It also lines up each tract that a 1950–1979 freeway opened within 250 m of on
its own opening year and traces its population-weighted gap (Hispanic, Black, white, owner-occupied, poverty) from tracts with no freeway
within 1 km, decade by decade from two censuses before to four after (`highways_event_study.csv`, with all such tracts and with those
no farther from downtown than the median freeway tract as comparisons; tract groups in `highways_tract_groups.csv`).

### Block-level mortality (`R/mortality_block.R`)
Run on the machine that holds the Colorado death records (default folder `~/Downloads/CO_HIA`: `co_deaths_official.csv`,
`block_noyr.gpkg`), which are read in place and never copied into the project. Natural-cause and all-cause deaths 2015–2019 per 2010
block; negative binomial with county fixed effects, an offset for person-years and tract-clustered errors; block age structure (2010 SF1
P12, fetched once from NHGIS with `IPUMS_API_KEY`), density and PM2.5, tract poverty, ethnicity, race and tenure, EnviroScreen indicators;
kernel densities of hidden, known historical and pre-1960 sites, TRI, cleanup and a non-hazardous placebo. Writes rate ratios only to
`data/results/health/`.

### Former sites before and after they were rebuilt (`R/mortality_redevelopment.R`)
Same restricted inputs as the block models, read in place. Block-year panel 2000–2019 for the Denver study area (yearly block population
and PM2.5 from `block_noyr.gpkg`; years whose deaths match the 2010 blocks for under 90% are dropped). A site counts as rebuilt from the
year its parcel's current structure was built (`R/site_fate.R`), when that is after its last directory listing. Kernel (500 m, 2 km) of
sites still standing, by group (hidden, known, pre-1960), in a Poisson model with block and year fixed effects, a population offset and
PM2.5; plus an event study around the first rebuild within 400 m. Writes rate ratios only to `data/results/health/`. Needs `fixest`.

### 1940 residents and their age at death (`R/censoc_denver_1940.R`)
Links Denver's 1940 census (IPUMS full count, `R/fetch_ipums_fullcount.R`) to Social Security death records through CenSoc's HISTID
(CenSoc-Numident: men and women, deaths 1988–2005; CenSoc-DMF: men, deaths 1975 on; free from https://dataverse.harvard.edu/dataverse/censoc,
unzipped into `work/censoc/`). Each person gets their 1940 street address from Brown's GRF (geocoded by `R/grf_eds.R`) and, there: the
1938 HOLC grade, the 1929 zoning district, industrial and commercial land within 250 m in 1937 (USGS), the hazardous trades listed to 1940
(kernel and within 500 m), and the 1965–92 hidden and known sites. OLS of age at death with birth-year fixed effects, CenSoc weights,
1940 person and household controls, errors clustered by ED, and a version with ED fixed effects. Writes aggregates only to
`data/results/censoc/`; the linked person file stays in `work/censoc/`. The app's "Lifespan of 1940 residents" tab (under Historical change) reads copies of
`censoc_models.csv`, `censoc_groups.csv` and `censoc_linkage.csv` in `app/data/`.

### CenSoc follow-ups (`R/censoc_extensions.R`, `R/censoc_enlistment.R`, `R/mlp_residential_history.R`)
All three run after `R/censoc_denver_1940.R`, which also saves every 1940 resident with their address exposures to
`work/censoc/denver_1940_residents.rds`. `R/censoc_extensions.R`: results by age in 1940, stayers and leavers (CenSoc-Numident place of
death, `censoc_numident_geography_supplement_v1.csv`), own and household head's 1940 industry, groups, who links to a death record, Gompertz
hazard ratios (`gompertztrunc`), and highways and displacement (1940 addresses in a later freeway's path, 75-500 m from one, on residential
land cleared by 1977, or near a major road already open in 1940). `R/censoc_enlistment.R`: height, weight, body-mass index and schooling at
WWII Army enlistment (CenSoc Enlistment-Census-1940). `R/mlp_residential_history.R`: 1910-1930 Denver addresses of 1940 residents through
the IPUMS MLP links (`Rscript R/fetch_ipums_mlp.R` writes them to `work/mlp/` through the IPUMS API, using the MLP key HIK in a
Colorado 1910-1940 full-count extract; the national crosswalk files also work), persistence and cumulative and childhood exposure. Because the surviving directory years list very different numbers of Denver sites per decade (`mlp_exposure_windows.csv`), exposure at each address is also expressed as a percentile among all geocoded Denver residents in that census, and the cumulative measures are averaged over the censuses observed (and repeated on the windows listing 20+ sites). All write aggregates only to
`data/results/censoc/`.

### Contamination, emissions, urban renewal, lead and health (`R/fetch_context_layers.R`, `R/context_layers.R`)
`Rscript R/fetch_context_layers.R` downloads public layers to `work/context/`: Colorado petroleum releases (1986-) and regulated tank
facilities (Division of Oil & Public Safety, data.colorado.gov), EPA TRI basic data files for Colorado (1987-), EPA AQS annual means for
Denver-metro monitors (1980-), Renewing Inequality urban-renewal projects (University of Richmond, CC BY-NC), EPA Superfund operable-unit
boundaries, CDPHE's modelled childhood lead-risk decile by tract, CDC PLACES tract estimates (2024 release) and NCHS life expectancy
(USALEEP, 2010-15). `Rscript R/context_layers.R` matches releases and tank facilities to every historical site (50 m) and TRI facilities
(100 m), summarises TRI releases by year and HOLC grade and AQS means by pollutant, counts sites inside urban-renewal projects and Superfund
units, compares tract health by industrial history, and builds Sanborn map links (Library of Congress, 1887-1904). Outputs go to
`data/results/context/` and the app's "Contamination & health" tab (Explore more) and main-map layers, including the georeferenced 1933
aerial survey (Denver Public Library; City and County of Denver tile service). It also maps the Library of Congress Sanborn volume extents for Denver
(1887-1951) and writes a Sanborn digitising worklist (`data/results/context/sanborn_worklist.csv`: sites now residential, schools or parks,
with the 1903-04, 1929-30 and 1950-51 volume covering each address), shows the Vasquez Boulevard/I-70 residential soil results by
neighbourhood (`data/raw/vbi70/`, transcribed from the 2003 Record of Decision), and builds urban-renewal case studies (area-weighted census
composition 1940-1990 inside each project, plus the sites and petroleum releases inside).

### What became of the sites (`R/site_fate.R`)
Every geocoded Denver site (1965–92 manufacturers' directory, hazardous sectors; street-level pre-1960 hazardous trades) is matched to
the assessor parcel within 40 m whose situs address matches the directory address (same number and street; else same street and side,
nearest number; else same street; else the nearest parcel, the rule being recorded in `parcel_match` and the agreement rate in
`site_fate_parcel_match.csv`), through Denver's open-data parcel service (property class, current and pre-2010 zone district,
dwelling units, year built), cached in `work/site_fate/parcels_by_point.csv`. Outputs in `data/results/site_fate/` and `app/data/`:
current use by series and by decade of last listing, the share still zoned industrial, the share rebuilt since the last listing, and the
residential/school/park conversions with no cleanup record (`site_fate_sensitive.csv`).

### Benchmarks against the national series (`R/benchmarks.R`)

No public national dataset locates individual factories (the Census Bureau's Longitudinal Business Database does, but only inside a
Research Data Center), so the directories are checked against county totals. (1) County Business Patterns establishment counts
1975–2002 by county and 2-digit SIC / NAICS, from the raw county files redistributed by Eckert, Fort, Schott & Yang (2021, NBER WP
26632; 1975–85 National Archives, 1986+ Census Bureau): the Directory of Colorado Manufacturers covers 30–100% of CBP manufacturing
establishments depending on the edition (median ratio in Denver 0.77), with county counts correlating at r = 0.85 (log) and the
hazardous sectors at r = 0.88 (`cbp_vs_directory_state.csv`, `cbp_vs_directory_county.csv`). The edition-to-edition swings are the
publisher's coverage, not industrial change — read the Trends tab against this. (2) NHGIS county manufacturing tables 1880–1940
(fetched through the NHGIS API) against the business directory's hazardous trades by county (`nhgis_mfg_vs_directory.csv`). (3) The
Atack–Bateman–Weiss Census of Manufactures samples for 1870 and 1880 (Vanderbilt; also at ICPSR), tabulated for Colorado if present —
samples of surviving schedules with county and industry but no addresses. The app's Benchmarks tab shows all three.

`R/app_census_layers.R` turns all of this — the NHGIS tract panel with firm counts per decade, the panel models, the corridor cells,
the 1880 ED aggregates and placed firms, and the IPUMS city series — into the app's `app/data/` files (aggregates only).

## Reproduce

```bash
pip install -r requirements.txt          # plus Tesseract 5.3.x for OCR
python pipeline/fetch_inputs.py          # TIGER, EPA FRS + TRI, CDPHE layers, EnviroScreen, schools, health facilities -> work/
# A) from the scans: put the DCM PDFs (original file names) in work/pdf/, then
./run_all.sh
# B) from the saved OCR output (no scans needed):
mkdir -p work && tar xzf data/ocr/dcm_ocr_output.tar.gz -C work
./run_all.sh parse
```

In R: `Rscript R/run_all.R` reruns geocoding, site building and inventory matching, exposures and the health models from the
Python hand-off files (see `R/README.md`; comparisons in `data/results/r_vs_python.md`: identical sites and statuses, geocodes identical
to 0.0 m on all 36,615 address keys, model coefficients equal to 1e-6; that comparison was last run on all 25 editions, before the switch to the complete editions).

The census chain (NHGIS/IPUMS keys in `~/.Renviron`) runs in this order, because each step reads the previous one's output:
`Rscript R/fetch_census.R` (NHGIS extracts, tract panel 1940-2020) → `Rscript R/fetch_ipums_fullcount.R` and `Rscript R/grf_eds.R 1900 1910 1920 1930 1940`
(Denver districts) → `Rscript R/denver_eds_analysis.R` → `Rscript R/county_panel_1880_1940.R` → `Rscript R/ej_panel.R` → `Rscript R/fetch_hmda.R` →
`Rscript R/app_census_layers.R` (writes `app/data/tract_panel.csv`) → `Rscript R/known_hidden_sensitivity.R` (known vs hidden under six matching rules) → `Rscript R/holc_covenants.R` (reads it; stops if it is stale) →
`Rscript R/zoning_1925.R` (1929 zoning shares; then `Rscript R/holc_covenants.R` again for the zoning-adjusted gaps) → `Rscript R/zoning_1944.R` → `Rscript R/denver_tracts_1950_2020.R` → `Rscript R/site_fate.R` → `Rscript R/zoning_2023.R` → `Rscript R/fetch_zoning_city.R` → `Rscript R/zoning_over_time.R` → `Rscript R/landuse_1937_1997.R` → `Rscript R/fetch_highways.R` → `Rscript R/highways_denver.R` → `Rscript R/mortality_block.R` (restricted data; analyst's machine) → `Rscript R/mortality_redevelopment.R` (same) → `Rscript R/censoc_denver_1940.R` (after downloading CenSoc) → `Rscript R/censoc_extensions.R` → `Rscript R/censoc_enlistment.R` → `Rscript R/fetch_ipums_mlp.R` → `Rscript R/mlp_residential_history.R` → `Rscript R/fetch_context_layers.R` → `Rscript R/context_layers.R` →
`Rscript R/benchmarks.R` (CBP, NHGIS county manufacturing and the Atack samples; needs network and the NHGIS key) →
`Rscript R/edition_coverage.R` (per-edition pages, listings, hazardous firms and completeness for both directory series → app/data/edition_coverage.csv;
twelve of the 25 manufacturers' directory editions are partial scans that stop part-way through the geographic section — complete: 1965–68, 1970, 1973–74, 1977, 1980, 1983, 1988, 1990, 1992 — flagged on the Trends and Data tabs; the complete editions are the ones that match CBP best).

Network inputs change over time (FRS, TRI, CDPHE layers are live); the published results used downloads of 16 October 2026.
OCR output can differ slightly across Tesseract versions, which is why the OCR output is saved in `data/ocr/`.

## Tests

```bash
pip install -r requirements-test.txt     # pandas, geopandas, rapidfuzz, pytest, pyyaml, openpyxl (+ playwright for the app test)
tests/run_tests.sh                        # all suites; --fast skips the Shiny app smoke test
```

`tests/digitization` and `tests/geocoding` (pytest) cover the parser and the TIGER geocoder, `tests/r` (testthat) the
R re-implementation, and `tests/outputs` the published files: `test_consistency.py` checks that `app/data`,
`data/results`, the site workbook, the listings and the tract panel agree with each other, `test_claims.py` checks every
number quoted in this README, in the app's text and in the `data/results/*/summary.md` files against the data
(`tests/outputs/claims.yml` is the registry; a rerun that changes a number fails the test until the text is updated),
and `test_app_smoke.py` starts the app and opens every tab in a headless browser. `.github/workflows/tests.yml` runs the
Python and R suites on every push. Details and the list of known inconsistencies in `tests/README.md`.

## Before 1960: Colorado State Business Directory, 1871–1956

The manufacturers' directory starts in 1961, but Colorado's smelters, foundries, assay offices and gas works go back to the 1870s.
`pipeline/historical/` reads the searchable text of the CU Boulder scans of the *Colorado State Business Directory*
(34 editions: 1871 Rocky Mountain Directory, 1875, 1877, 1878, 1879, 1880, 1881, 1882, 1883, 1884, 1885, 1887, 1888, 1891, 1892, 1910, 1911, 1912, 1913, 1914, 1915, 1916, 1917, 1920, 1927, 1929, 1932, 1933, 1935, 1939, 1941, 1943, 1950, 1956) and:

1. **Finds the town** for every entry from town headings ("ALPINE.", "Delta Business Directory.", "DENVER CONT'D"), page running
   heads ("DEN", "LEA") and, failing that, a town named in the entry, all matched to the USGS GNIS gazetteer.
2. **Keeps hazardous historical trades** with a keyword vocabulary mapped to Frickel & Elliott sectors: smelting/reduction/sampling works,
   foundries, iron and steel works, machine and boiler shops, tinners and sheet-metal works, chemical, paint, soap, powder and fertilizer works,
   oil refineries, rubber works, carriage/wagon/car shops; plus extended trades (assay offices, stamp and ore mills, gas works, tanneries,
   tie-treating/creosote plants, coke ovens). The 1950 edition uses numeric business codes, which are mapped directly. Individuals listed
   by occupation in city-directory sections ("lab., Globe smelter, r. 123 …") are dropped.
3. **Places entries** at a street address only where today's numbering applies – Denver from 1891 (after the 1887 renumbering) and larger
   cities from 1910 – and only on an exact TIGER address-range match, translating old street names (Holladay → Market). Everything else sits
   at the GNIS town point (`precision = town`).
4. **Links firms** across editions (fuzzy names within a town) and to the 1961–2002 directory, by name in the same city or by a street
   address within 40 m of a later hazardous site.

Result: 8,203 hazardous-trade listings → 7,305 firm-locations; 805 at a street address; 356 link to the 1961–2002 directory,
giving 222 later sites a documented pre-1960 hazardous precursor.

**Radium and uranium.** Colorado's carnotite ores made it the world's main radium source in 1910–1922; Denver refined it, and spas sold
"radium water" and radium cave baths as cures. `pipeline/app_radium.py` collects every radium, uranium and vanadium firm in both
directories (names, products and SIC 1094; detection instruments excluded) into `app/data/radium_firms.csv`: 53 firm-places from the
business directories (Colorado Radium Products Co, Radium Ores Co, National Radium Co, Minerals Recovery Co, Hot Springs Hotel &
Radium Cave Baths in Idaho Springs, Placerville Radium Springs, the Vanadium Corporation of America mills…) and 31 from the
manufacturers' directory (uranium mills at Rifle, Durango, Naturita, Maybell and Telluride, Cotter Corp at Cañon City, S.W.
Shattuck Chemical at 1805 S Bannock – now the Shattuck Superfund site). Most are placed at the town only; names come from
uncorrected OCR. The map shows them as a yellow layer.
**Caveats:** the text layers are uncorrected OCR with columns interleaved, so names can be garbled (`name_quality`), some entries are
missed, and counts are not comparable between editions or with the manufacturers' directory. 1871, 1875 and the user-supplied 1877
volumes are read from the Internet Archive / Google Books copies, which carry text layers; the CU 1885 and 1920 scans have no text
layer and were OCR'd with Tesseract (`pipeline/historical/ocr_volume.sh`; 300 dpi for 1885, 220 dpi for the 1,548-page 1920 volume).
All 52 CU Boulder volumes are now in hand; the 1950s beyond 1956 are not in that collection.

## The Shiny app

```r
source("app/install_packages.R")
shiny::runApp("app")
```

* **Map** – historical hazardous sites coloured by current regulatory status or by **persistence** (years between first and last hazardous
  listing, extended back to the pre-1960 directories where a precursor is found), filtered by years listed (1871–1992), sector, status and confidence;
  each site's popup lists **every firm at the address**: years listed, what the directory says it made, year established, employment
  class, hazardous-sector firms shaded (all of it downloadable in Data & downloads);
  a **radium & uranium** layer (yellow);
  a **pre-1960 layer** (brown; firms placed only at a town centre share one marker per town whose popup lists them all, black ring = firm or address still listed after 1960);
  layers for EPA TRI facilities, schools, hospitals, clinics, residential care, brownfields, voluntary cleanup, Superfund, RCRA corrective
  action and land-use controls; census tracts shaded by any EnviroScreen indicator; the 1933 aerial survey, Sanborn volume extents and the
  1903–04 sheet images and blocks, zone-map changes 1925–1956, petroleum releases, urban-renewal projects, Superfund operable units, the
  zoning maps of 1929, 1944, 2023 and today, and the USGS land-use maps of 1937–1997.
  An **industrial corridors** layer draws every 500 m cell with a manufacturer in the complete editions 1965–1992, coloured by persistence class
  (persistent, sector turnover, intermittent, former, emerging), sized by peak firms, with the pre-1960 trades in the cell in the popup.
* **Trends** – both directory series on one timeline; sites per edition by sector and by status; share on no inventory; pre-1960
  hazardous-trade firms per edition; **clustering** in the Denver metro (Ellison–Glaeser γ by sector and edition, filled points significant).
* **Historical change** (menu):
  * **Denver 1880–2020** – the reconstructed enumeration districts of every census 1880–1940 and the 147 study tracts (2010 boundaries)
    1950–2020, shaded by composition, firms or distance to the nearest firm, with the hazardous trades of the decade; units with vs without
    a firm; the distance models; dissimilarity 1880–1940; the 1880 building-level results; population-weighted composition of tracts with an
    active hazardous firm, legacy-only and never, by census 1940–2020; the hybrid panel models and the reverse ("who predicts where industry
    goes") model for the Denver core. The underlying `app/data/tract_panel.csv` holds all 1,249 Colorado tracts (2010 boundaries; Denver only
    before 1960, the big metros from 1960, the whole state from 1990); the app shows and downloads the 147 study tracts.
  * **What became of the sites** – Denver sites on today's assessor parcels, and zoning 1929 → 1944 → 2023 → today.
  * **Before zoning: 1903** – housing next to industry on the 1903–04 Sanborn sheets, and the zone-map changes of 1925–1956.
  * **Land use & freeways** – the USGS land-use maps, freeways by decade and HOLC grade, the freeway event study, urban-renewal case studies.
  * **Lifespan of 1940 residents** – CenSoc age at death and WWII enlistment by 1940 address (aggregates only).
  * **Redlining & covenants** – the 1938 HOLC map with each area's appraisal form in the popup, the 1931–35 racial covenants (orange
    where the deed also bars manufacturing), the firms of 1871–1956 and the 1930 districts; areas by grade; 1900–2020 trajectories by grade;
    the D–C boundary gaps; the change-by-grade models; HMDA lending today; the 1925 ordinance and its 1944 revision by grade.
* **Colorado trends** – the statewide counterpart: counties 1880–1940, regional shares 1965–1992, tract associations 1990–2020, the legacy
  models, the other graded cities, **phases of Colorado manufacturing** (share of all listed firms by industry), how long firms stayed
  listed, statewide clustering and **succession** (the most common changes of a cell's dominant sector).
* **Explore more** (menu): **Contamination & health** (petroleum releases, TRI, air quality, urban renewal, Superfund soils, health by
  industrial history, the hedonic model), **Who owns rental housing**, **Neighborhoods** (distributions of EnviroScreen and socioeconomic
  indicators for tracts with vs. without hazardous sites, with potentially unknown sites vs. all others, unknown vs. known-only, and TRI vs.
  non-TRI tracts; medians, population-weighted means, Wilcoxon tests) and **Nearby schools & health care** (schools and health facilities
  within a chosen distance of potentially unknown sites).
* **Methods & downloads** (menu): **Benchmarks** (the directories against CBP, NHGIS and the Atack–Bateman–Weiss samples), **About the
  data** (what each layer is and where it comes from, including what an environmental covenant / land-use control means) and **Data &
  downloads** (per-edition geocoded CSVs, filtered sites, firms at the filtered sites, pre-1960 firms, corridor cells, Denver 1880–1940
  districts and firms, the zoning, redlining and site-fate files, the study-area tract panel, edition coverage, geocoding validation).

`app/data/by_year/` is a committed copy of `data/by_year/` (the 13 complete editions), so the app folder is self-contained for deployment
(Posit Connect Cloud deploys from GitHub: anything `.gitignore`d never reaches the server; `app/manifest.json` lists every file).

## Sources

* Colorado Directory of Manufacturers, 1961–2002 (scans from CU Boulder Libraries via interlibrary loan; not redistributed here).
* US EPA Facility Registry Service, state combined file for Colorado; EPA TRI facility table (Envirofacts).
* CDPHE Hazardous Materials & Waste Management Division layers, Colorado EnviroScreen 2.0 (census tracts), CDPHE Health Facilities,
  CDE school locations — via geodata.colorado.gov.
* Colorado State Business Directory (Gazetteer Publishing / J.A. Blake), 1871–1956: CU Boulder Libraries digital collections, linked from
  History Colorado's business-directory guide (https://www.historycolorado.org/business-directories).
* USGS Geographic Names Information System (domestic and historical populated places).
* US Census Bureau TIGER/Line 2023 ADDRFEAT.
* Frickel, S. & Elliott, J. R. (2018). *Sites Unseen: Uncovering Hidden Hazards in American Cities.* Russell Sage Foundation.

A site that appears on no inventory is a lead for records review or soil testing, not evidence of contamination.

## Home prices near historical sites (hedonic model)

```
Rscript R/fetch_denver_property.R   # Denver Assessor sales, parcels and residential characteristics (public) into work/property/
Rscript R/hedonic_denver.R          # data/results/hedonic/ and app/data/hedonic_models.csv
```

Arm's-length residential sales in the City and County of Denver since 2015 are located at their parcels and compared with otherwise similar homes in the same market neighbourhood and year. Distance bands to the nearest hidden site (1965–92 hazardous-sector manufacturer on no current inventory), known site (on a current inventory) and pre-1960 hazardous trade; controls for floor area, basement, bedrooms, baths, stories, lot, age and property type, and in later models for present-day hazards (petroleum releases, TRI facilities, Superfund units, freeways, industrial zoning). The property records stay in work/property/; only model results are written.

## Who owns rental housing

```
Rscript R/fetch_denver_property.R   # now also writes work/property/owners.csv (owner name and mailing address; public records)
Rscript R/fetch_landlord_data.R     # CO business registry (work/registry/), ZCTA points and ACS income (data/raw/acs/), Eviction Lab tracts (work/evictionlab/)
Rscript R/fetch_denver_311.R        # 311 requests to Community Planning & Development and Public Health & Environment, 2016 on (work/denver311/)
Rscript R/ownership_denver.R        # data/results/ownership/ and app/data/ownership_*.csv
Rscript R/housing_conditions_denver.R   # data/results/housing_conditions/ and app/data/conditions_*.csv
```

Owners are linked in five stages, and concentration is reported at each (`linking_stages.csv`, after Hangen & O'Brien 2025, *Housing Studies*): exact names and addresses; cleaned names and normalised addresses (companies by name, people and trusts by name and address); near-identical names (3-gram cosine similarity of 0.85 or more for name and address within a ZIP, and for the names alone; never across different numbers, including digits inside words, generational suffixes or middle initials); names sharing a mailing address (owner families; not at addresses used by more than 5 individuals or 40 names, nor PO boxes used by more than 5, unless the address was checked by hand and listed, as a hash, in `data/raw/ownership/audited_addresses.csv`); and, if the Colorado business registry was downloaded, companies sharing a principal address or a named registered agent (registered-agent firms and agents or addresses serving many entities are never links; chains joining more than 30 families are undone). `owner_location.csv` places owners by their mailing ZIP (on the property, Denver, metro, Colorado, another state) with the distance and the income and white share of the owner's and the property's ZIP areas (after Preis 2024; Hochstenbach 2022). `R/housing_conditions_denver.R` links 311 requests about conditions inside homes and about the outside of properties to buildings, models them on the owner's portfolio size with tract fixed effects (after An et al. 2024, *JAPA*) and compares Eviction Lab tract filing rates, averaged over the latest five years in which nearly every Denver tract has a count and which the Lab judged complete for Denver County (computed from the files; 2012-2016 with the current ones), with the share of rentals held by large owners.

Residential parcels in the City and County of Denver (houses, condominium units, rowhouses, duplexes and triplexes, apartment and senior apartment buildings, and mixed-use buildings with homes; condominium master parcels without an owner name are dropped), grouped into owners by normalised name and, more broadly, into owner families by shared mailing address. Units not occupied by their owner count as rentals (owner-occupied: the owner's mailing address is the property, with the same unit number for condominiums and rowhouses, or another door of the same duplex or triplex). Outputs are aggregates only: owners and units by owner size, concentration (top 10/100 owners, top 1%), owner types, and shares held by large landlords, companies and out-of-state owners by tract, 1938 HOLC grade and distance to historical sites. The largest owners, with names, are written only to work/property/top_owners_private.csv for checking and are not published.

## Changes to the zone map, 1925–1956 (Denver ordinances)

```
Rscript R/fetch_denver_ordinances.R      # 560 zoning-related ordinances of 1923-1956 from the City's scanned archive (Municode MuniDocs): text layer -> data/raw/ordinances/text/
Rscript R/fetch_denver_property.R        # now also work/property/legal.csv (parcels' lot, block and subdivision)
Rscript R/rezoning_denver.R              # data/results/rezoning/ and app/data/rezoning_*
```

Every "changed from <district> to <district>" in an ordinance amending the 1925 zone map, and every newly annexed area "classified as" a district, read from the archive's OCR (district words matched allowing two wrong letters; page headers dropped; the papers attached after the ordinance itself, such as the Board of Adjustment's letter, owners' petitions and the newspaper reprint, ignored; repeats within an ordinance kept once, but separate areas changed the same way kept apart). Each change is placed from the subdivision and block it names, matched to today's parcel legal descriptions (the whole subdivision name, or at least two words of it), or from the crossings of the streets its boundary follows (TIGER; "48th Avenue" and "West 48th Avenue" are one street, not a crossing), and flagged where the two disagree by more than 1 km, in which case the named block is used. The "sure" comparisons keep changes placed by a named block, or by street crossings that a named subdivision confirms. At each place: the 1938 HOLC grade, the 1929 zoning district, the 1940 or 1950 census tract, and hazardous trades already listed within 400 m. `changes.csv` has one row per change with a link to the ordinance; `by_holc*.csv`, `test.csv` and `summary.md` compare the direction of change across HOLC grades.

## Before zoning: the 1903–04 Sanborn maps (Library of Congress)

```
Rscript R/fetch_loc_sanborn.R            # catalogue + title/index/key pages of the seven 1887-1904 volumes (public domain)
Rscript R/fetch_loc_sanborn.R sheets     # the 152 sheets in data/raw/sanborn_loc/sheets_to_fetch.csv, into work/sanborn_loc/
Rscript R/loc_sanborn_1903.R             # places the sheets on today's map and measures housing next to industry
```

The 152 sheets of the 1903–04 atlas covering the north side (volume 2: Lower Downtown, the Platte valley, Five Points, Ironton, Cole, Elyria, Swansea) and Auraria, West Denver and the South Platte corridor (volume 1) were transcribed block by block into `data/raw/sanborn_loc/readings/1903_batch_*.json`: street crossings in sheet pixels, and for each block the dwellings, flats, shanties and stores and every industrial or workshop establishment with its trade and drawn equipment, plus dwellings facing industry across a street. Street crossings read off each volume's key map (`key_v1.json`, `key_v2.json`) form a 1903 gazetteer for streets that have since disappeared or been renamed. Each sheet is placed by a similarity transform fitted by RANSAC to TIGER street crossings and the gazetteer, held to the atlas scale (50 ft to the inch); sheets with no street crossings (rail yards, the Grant smelter, the packing houses) remain unplaced. A sheet placed on only two crossings is kept only if its blocks also land beside the streets that bound them (75%+ of block-street pairs within 120 m, on streets shown to survive under the same name; `sheets.csv` reports the check for every sheet). Block outlines come from the crossings of each block's bounding streets (a 50 m circle where the corners cannot be found), and plants drawn on unplatted ground are placed from their outlines on the sheet (`1903_outside_xy.json`), so distances to industry run edge to edge, with 'across the street' as its own category. Outputs: `data/results/sanborn_1903/` and the app layers `sanborn_1903_sheets.geojson` (outlines, image corners and links to the Library of Congress images, which the app lays on the map), `sanborn_1903_blocks.geojson` (block outlines) and `sanborn_1903_plants.geojson`.
