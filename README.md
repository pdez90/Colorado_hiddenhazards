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
| `run_all.sh` | Runs the pipeline end to end (`./run_all.sh`), or from saved OCR (`./run_all.sh parse`) |
| `app/` | R Shiny app (`shiny::runApp("app")`) and its prepared data |
| `data/by_year/` | **One geocoded CSV per directory edition** (25 editions, 68,368 listings) |
| `data/results/` | Site workbook (`CO_hazardous_sites_1961-2002.xlsx`), all sites (`.geojson`), all listings, listings that could not be street-located, geocoding validation |
| `data/historical/` | Pre-1960 layer: hazardous-trade listings (`CO_pre1960_hazardous_listings.csv`) and firm-locations (`CO_pre1960_hazardous_sites.csv`) from the Colorado State Business Directory, 1871–1956; GNIS place gazetteer |
| `data/ocr/` | Saved Tesseract output for every page (lets anyone rerun everything after OCR without the scans) |

## Method in brief

1. **Directories.** 25 editions of the Colorado Directory of Manufacturers (1961–2002) were OCR'd (Tesseract 5.3.4, word boxes)
   and parsed with format-specific parsers (`pipeline/volumes.py` maps each volume to its year and format).
   Columns are rebuilt from word positions. OCR digit confusions (C→0, e/€/@→8, S/$→9) are corrected using field context.
2. **Industry.** Printed SIC codes (1965, 1967–1993) or NAICS codes (1999, 2002). The 1961, 1962 and 1966 editions print only product
   descriptions; codes are inferred with a nearest-neighbour classifier trained on description–code pairs from the other editions,
   plus keyword rules for smelters, refineries, plating, wood preserving, etc. (`industry_code_source` records which).
3. **Hazardous sectors.** Frickel & Elliott's seven: SIC 28 chemicals, 29 petroleum refining, 30 rubber & plastics, 33 primary metals,
   34 fabricated metals, 35 industrial machinery, 37 transportation equipment (NAICS 325, 324, 326, 331, 332, 333, 336).
   An *extended* set adds wood preserving, tanning, electronic components and circuit boards, batteries, photographic chemicals and ore milling.
4. **Linking.** Listings are linked across editions into establishments (fuzzy name within ZIP or city).
5. **Geocoding (fully reproducible, offline).** `pipeline/tiger_geocode.py` interpolates house numbers on US Census TIGER/Line 2023
   ADDRFEAT address ranges, tolerating OCR errors (street-type and direction misreads, trailing junk, fuzzy street names ≥86 similarity,
   neighbouring ZIPs within 12 km). Results are deterministic given the inputs. Listings within 30 m form one **site**.
6. **Inventory matching.** Each site is compared with EPA's Facility Registry Service (Colorado state file), EPA TRI, and CDPHE
   Hazardous Materials & Waste Management Division layers. A site is "known" if a record lies within 75 m (cleanup programs),
   100 m (TRI) or 40 m (RCRA handlers, other permits), shares the firm's name within 250 m, has the same address, or lies inside a
   cleanup site boundary. **"Not on any list"** = none of these.

## Key results (reproduced run, after the October 2026 geocoding fixes)

* 68,368 listings → 33,473 establishments; **4,458 hazardous-sector sites** located at street level.
* **1,842 (41%) are on no current federal or state inventory** (1,168 of them high confidence); 711 (16%) are on a cleanup or
  contamination list; 333 report to TRI; 1,069 are known only as RCRA hazardous-waste handlers; 503 have only other EPA permits or
  solid-waste records.
* 1,497 sites hosted two or more hazardous-sector firms over time.
* Census tracts containing a potentially unknown site have higher EnviroScreen scores (median percentile 61.2 vs 42.1 for other tracts),
  more low-income residents (23.8% vs 18.8%) and lower educational attainment (5.8% vs 4.5% without a high-school diploma); all p < 0.001.
  The difference in people of color is small (28.1% vs 26.3%, p = 0.02). Tracts with unknown sites look like tracts with only known sites,
  consistent with Frickel & Elliott's finding that relic sites are widespread rather than concentrated where regulators look.

## How good is the geocoding?

Three independent checks (October 2026).

**1. Against Colorado's statewide address points** (`pipeline/validate_addresspoints.py`,
`data/results/geocoding_validation_addresspoints.csv`). The State's public address-point layer places addresses on rooftops or parcels
and does not come from TIGER address ranges. For a random sample of 1,000 sites we looked up the same house number and street in the
stated town and measured the distance to our point:

| geocode level | sampled | compared | median | 90th pct | within 100 m | within 250 m | over 1 km |
|---|---|---|---|---|---|---|---|
| address | 654 | 427 | 49 m | 182 m | 78% | 93% | 0.9% |
| address_approx | 331 | 131 | 87 m | 597 m | 54% | 78% | 9.2% |

About a third of address-level listings have no matching address point today (the building is gone, the street was renumbered or
renamed, or the house number was misread); those could not be checked.

**2. Against EPA Facility Registry coordinates** for identical addresses (`pipeline/validate_geocoding.py`,
`data/results/geocoding_validation.md`): address level n = 1,845, median 48 m, 88% within 250 m, 2.7% over 1 km
(FRS coordinates carry their own error).

**3. Against the scans.** For 25 randomly chosen sites we compared the parsed address with the printed page: 23 matched, one house
number was misread by OCR (2915 for 3915 Tennyson, about 1.3 km off), and one could not be located on the crop. Expect roughly
4% of house numbers to carry an OCR digit error; most other OCR noise (street-type letters, suite numbers) does not move the point.

**What the vetting changed.** The first check exposed a geocoder bug: an address on a south-side street ("1934 S Broadway") could match
the north-side street of the same name ("Broadway") in the same ZIP, moving it up to 14 km. The geocoder now requires the prefix
direction to match, falls back to a direction-free match only as `address_approx`, and rejects matches more than 15 km from the stated
city. 113 sites moved by more than 1 km. Address-level points over 1 km from the address point fell from 4.7% to 0.9% and from 3.6% to
2.7% against FRS.

**How to read it.** `address` points are good to about a city block (median ~50 m, 93% within 250 m), with roughly 1–3% badly wrong,
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
| Asthma hospitalization rate (log) | 0.025 (0.041) | 0.054 (0.049) | 0.038 (0.045) | 1.7 | 0.544 |
| Low birth weight (%) | 0.075 (0.163) | 0.033 (0.198) | -0.063 (0.179) | 1.8 | 0.643 |
| Life expectancy (years) | -0.140 (0.152) | -0.264 (0.182) | -0.391 (0.167)* | 1.1 | 0.358 |
| Heart disease (index) | 1.067 (0.964) | -1.454 (1.119) | 2.989 (1.086)** | 0.7 | 0.269 |
| Cancer (index) | 0.008 (0.918) | 0.160 (1.076) | -0.116 (1.030) | 2.0 | 0.993 |
| Diabetes (index) | 1.214 (0.885) | -0.367 (1.017) | 1.377 (1.003) | 0.1 | 0.17 |
| Poor mental health (%) | -0.154 (0.088) | 0.080 (0.106) | 0.009 (0.097) | -1.0 | 0.0801 |

**Reading.** Unadjusted, tracts with more hidden sites have more asthma hospitalizations, lower life expectancy and more heart disease
and diabetes. Most of that goes away with SES and demographics, and the rest goes away once regulated hazards (above all
cleanup-site density) are in the model: hidden sites add no explanatory power for any outcome (likelihood-ratio p ≥ 0.08). The
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
| natural-cause | M2 +regulated |  |  |  | 1.027 (0.993–1.062) | 30736.0 |
| natural-cause | M3 +known historical |  | 1.022 (0.979–1.066) |  | 1.017 (0.979–1.056) | 30736.6 |
| natural-cause | M4 +hidden | 1.033 (0.993–1.074) | 1.004 (0.958–1.051) |  | 1.010 (0.971–1.051) | 30734.5 |
| natural-cause | M4 hidden high-confidence only | 1.013 (0.976–1.051) | 1.014 (0.968–1.062) |  | 1.014 (0.976–1.054) | 30737.9 |
| natural-cause | Placebo: M2 +non-hazardous mfrs |  |  | 1.070 (1.029–1.111)* | 0.994 (0.956–1.033) | 30719.7 |
| natural-cause | M4 +placebo | 1.012 (0.971–1.055) | 0.993 (0.948–1.040) | 1.066 (1.022–1.112)* | 0.993 (0.953–1.035) | 30723.1 |
| all-cause | M1 SES+age+PM2.5 |  |  |  |  | 31421.8 |
| all-cause | M2 +regulated |  |  |  | 1.034 (1.001–1.067)* | 31414.2 |
| all-cause | M3 +known historical |  | 1.030 (0.989–1.073) |  | 1.019 (0.984–1.056) | 31413.3 |
| all-cause | M4 +hidden | 1.031 (0.994–1.070) | 1.012 (0.969–1.057) |  | 1.013 (0.977–1.051) | 31411.1 |
| all-cause | M4 hidden high-confidence only | 1.013 (0.978–1.050) | 1.022 (0.978–1.069) |  | 1.017 (0.981–1.054) | 31414.4 |
| all-cause | Placebo: M2 +non-hazardous mfrs |  |  | 1.069 (1.031–1.108)* | 1.000 (0.965–1.037) | 31396.7 |
| all-cause | M4 +placebo | 1.012 (0.973–1.053) | 1.002 (0.959–1.047) | 1.063 (1.021–1.106)* | 0.997 (0.959–1.036) | 31399.9 |

Hidden sites raise mortality by about 3% per SD, with confidence intervals that include no effect; the non-hazardous-manufacturer
placebo is larger (about 7% per SD) and significant, and including it shrinks the hidden-site estimate to 1%. The same pattern as the
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

Result: 8,386 hazardous-trade listings → 7,495 firm-locations; 928 at a street address; 399 link to the 1961–2002 directory,
giving 249 later sites a documented pre-1960 hazardous precursor.
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
  listing, extended back to the pre-1960 directories where a precursor is found), filtered by years listed (1877–2002), sector, status and confidence;
  a **pre-1960 layer** (brown; firms placed only at a town centre share one marker per town whose popup lists them all, black ring = firm or address still listed after 1960);
  layers for EPA TRI facilities, schools, hospitals, clinics, residential care, brownfields, voluntary cleanup, Superfund, RCRA corrective
  action and land-use controls; census tracts shaded by any EnviroScreen indicator.
* **Trends** – sites per edition by sector and by status; share on no inventory; pre-1960 hazardous-trade firms per business-directory edition.
* **Neighborhoods** – distributions of EnviroScreen and socioeconomic indicators for tracts with vs. without hazardous sites,
  with potentially unknown sites vs. all others, unknown vs. known-only, and TRI vs. non-TRI tracts; medians, population-weighted means,
  Wilcoxon tests.
* **Nearby schools & health care** – schools and health facilities within a chosen distance of potentially unknown sites.
* **Data & downloads** – per-edition geocoded CSVs, filtered sites, pre-1960 firms, geocoding validation.

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
