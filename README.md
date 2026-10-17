# Colorado Hidden Hazards

Historical hazardous industrial sites in Colorado, 1961–2002, identified from the *Colorado Directory of Manufacturers*
(plus a pre-1960 layer of hazardous trades from the *Colorado State Business Directory*, 1871–1956),
following Scott Frickel and James R. Elliott, *Sites Unseen: Uncovering Hidden Hazards in American Cities* (Russell Sage, 2018),
compared with today's federal and state inventories, and explored in an R Shiny app alongside EPA TRI facilities,
cleanup sites (including brownfields), schools, health facilities and CDPHE EnviroScreen 2.0.

## What is in the repository

| Path | Contents |
|---|---|
| `pipeline/` | Python pipeline: page extraction, Tesseract OCR, format-specific parsers, SIC/NAICS coding, cross-year linking, offline TIGER/Line geocoder, inventory matching, exports |
| `R/` | **R re-implementation** of the geocoder, site building and inventory matching, exposures and health models, checked against the Python results (see `R/README.md`) |
| `run_all.sh` | Runs the pipeline end to end (`./run_all.sh`), or from saved OCR (`./run_all.sh parse`) |
| `app/` | R Shiny app (`shiny::runApp("app")`) and its prepared data |
| `data/by_year/` | **One geocoded CSV per directory edition** (25 editions, 68,368 listings) |
| `data/geocoder/` | ZIP centroids and ZIP–town table used by the geocoder, and every address key with its geocode (for checking the R geocoder) |
| `data/results/` | Site workbook (`CO_hazardous_sites_1961-2002.xlsx`), all sites (`.geojson`), all listings, listings that could not be street-located, geocoding validation |
| `data/historical/` | Pre-1960 layer: hazardous-trade listings (`CO_pre1960_hazardous_listings.csv`) and firm-locations (`CO_pre1960_hazardous_sites.csv`) from the Colorado State Business Directory, 1871–1956; GNIS place gazetteer |
| `data/ocr/` | Saved Tesseract output for every page (lets anyone rerun everything after OCR without the scans) |

## Method in brief

1. **Directories.** 25 editions of the Colorado Directory of Manufacturers (1961–2002) were OCR'd (Tesseract 5.3.4, word boxes)
   and parsed with format-specific parsers (`pipeline/volumes.py` maps each volume to its year and format).
   Columns are rebuilt from word positions. OCR digit confusions (C→0, e/€/@→8, S/$→9, B→8) are corrected using field context;
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
   the same town or a neighbouring ZIP ("4300 LIPAN" in Denver could be 4300 N or 4300 S Lipan; `range_interp_dirambig`, 8% of
   address keys). Results are deterministic given the inputs. Listings within 30 m form one **site**.
6. **Inventory matching.** Each site is compared with EPA's Facility Registry Service (Colorado state file), EPA TRI, and CDPHE
   Hazardous Materials & Waste Management Division layers. A site is "known" if a record lies within 75 m (cleanup programs),
   100 m (TRI) or 40 m (RCRA handlers, other permits), shares the firm's name within 250 m, has the same address, or lies inside a
   cleanup site boundary. Sites placed only approximately are searched over 250 m, and every site's radius grows by the spread of its
   member points. **"Not on any list"** = none of these.

## Key results (reproduced run, 17 October 2026, after the accuracy review below)

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

Coefficients for 1 SD more exposure, spatial error models (standard errors in parentheses; * p<0.05, ** p<0.01):

| Outcome | Hidden sites, M4 (per SD) | Known historical, M4 | Placebo (non-hazardous mfrs), M4+placebo | ΔAIC M3→M4 | LR p (M4 vs M3) |
|---|---|---|---|---|---|
| Asthma hospitalization rate (log) | 0.003 (0.040) | 0.076 (0.050) | 0.025 (0.041) | 2.0 | 0.934 |
| Low birth weight (%) | 0.068 (0.159) | 0.044 (0.203) | -0.053 (0.165) | 1.8 | 0.671 |
| Life expectancy (years) | 0.056 (0.147) | -0.435 (0.186)* | -0.379 (0.154)* | 1.9 | 0.702 |
| Heart disease (index) | 0.588 (0.925) | -1.092 (1.127) | 2.541 (1.003)* | 1.6 | 0.525 |
| Cancer (index) | 0.059 (0.884) | 0.178 (1.086) | 0.152 (0.952) | 1.9 | 0.947 |
| Diabetes (index) | 0.866 (0.846) | 0.083 (1.021) | 1.080 (0.926) | 0.9 | 0.306 |
| Poor mental health (%) | -0.145 (0.086) | 0.093 (0.107) | -0.023 (0.090) | -0.9 | 0.0896 |

**Reading.** Unadjusted, tracts with more hidden sites have more asthma hospitalizations, lower life expectancy and more heart disease
and diabetes. Most of that goes away with SES and demographics, and the rest goes away once regulated hazards (above all
cleanup-site density) are in the model: hidden sites add no explanatory power for any outcome (likelihood-ratio p ≥ 0.09). The
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
to 0.0 m on all 36,615 address keys, model coefficients equal to 1e-6).

Network inputs change over time (FRS, TRI, CDPHE layers are live); the published results used downloads of 16 October 2026.
OCR output can differ slightly across Tesseract versions, which is why the OCR output is saved in `data/ocr/`.

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
  listing, extended back to the pre-1960 directories where a precursor is found), filtered by years listed (1871–2002), sector, status and confidence;
  each site's popup lists **every firm at the address**: years listed, what the directory says it made, year established, employment
  class, hazardous-sector firms shaded (all of it downloadable in Data & downloads);
  a **radium & uranium** layer (yellow);
  a **pre-1960 layer** (brown; firms placed only at a town centre share one marker per town whose popup lists them all, black ring = firm or address still listed after 1960);
  layers for EPA TRI facilities, schools, hospitals, clinics, residential care, brownfields, voluntary cleanup, Superfund, RCRA corrective
  action and land-use controls; census tracts shaded by any EnviroScreen indicator.
* **Trends** – sites per edition by sector and by status; share on no inventory; **phases of Colorado manufacturing** (share of all
  listed firms by industry, every edition); how long firms stayed listed, hazardous vs other; pre-1960 hazardous-trade firms per edition.
* **Neighborhoods** – distributions of EnviroScreen and socioeconomic indicators for tracts with vs. without hazardous sites,
  with potentially unknown sites vs. all others, unknown vs. known-only, and TRI vs. non-TRI tracts; medians, population-weighted means,
  Wilcoxon tests.
* **Nearby schools & health care** – schools and health facilities within a chosen distance of potentially unknown sites.
* **Data & downloads** – per-edition geocoded CSVs, filtered sites, firms at the filtered sites, pre-1960 firms, geocoding validation.

To deploy (e.g. shinyapps.io), copy `data/by_year/` into `app/data/by_year/` so the app folder is self-contained.

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
