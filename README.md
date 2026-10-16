# Colorado Hidden Hazards

Historical hazardous industrial sites in Colorado, 1961–2002, identified from the *Colorado Directory of Manufacturers*
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

## Key results (reproduced run)

* 68,368 listings → 33,473 establishments; **4,510 hazardous-sector sites** located at street level.
* **1,889 (42%) are on no current federal or state inventory**; 717 (16%) are on a cleanup or contamination list; 332 report to TRI;
  1,064 are known only as RCRA hazardous-waste handlers; 508 have only other EPA permits or solid-waste records.
* 1,485 sites hosted two or more hazardous-sector firms over time.
* Census tracts containing a potentially unknown site have higher EnviroScreen scores (median percentile 59.7 vs 43.1 for other tracts),
  more low-income residents (23.6% vs 19.1%) and lower educational attainment; differences in people of color are small and not significant.
  Tracts with unknown sites look like tracts with only known sites (no significant differences), consistent with Frickel & Elliott's
  finding that relic sites are widespread rather than concentrated where regulators look.

## How good is the geocoding?

`pipeline/validate_geocoding.py` compares our coordinates with independent EPA FRS coordinates for identical addresses
(`data/results/geocoding_validation.md`):

| geocode level | n | median distance | within 100 m | within 250 m | over 1 km |
|---|---|---|---|---|---|
| address (range interpolation) | 1,927 | 50 m | 69% | 86% | 3.6% |
| address_approx (OCR-corrected, neighbouring ZIP, nearest segment) | 57 | 206 m | 33% | 56% | 8.8% |

FRS coordinates carry their own error, so these distances partly overstate ours. Coverage varies by edition: 22–76% of listings
geocode at address level (`data/results/geocoding_coverage_by_year.csv`); 1961–1965 have no ZIP codes, and 1971, 1985, 1992 and 2002
volumes are partial. Errors that remain: OCR'd house numbers, streets renumbered or renamed since the 1960s, PO-box-only listings
(placed at ZIP centroids and kept off the map). Treat `address_approx` and low-confidence sites as leads to verify.

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

## The Shiny app

```r
source("app/install_packages.R")
shiny::runApp("app")
```

* **Map** – historical hazardous sites coloured by current regulatory status, filtered by years listed, sector, status and confidence;
  layers for EPA TRI facilities, schools, hospitals, clinics, residential care, brownfields, voluntary cleanup, Superfund, RCRA corrective
  action and land-use controls; census tracts shaded by any EnviroScreen indicator.
* **Trends** – sites per edition by sector and by status; share on no inventory.
* **Neighborhoods** – distributions of EnviroScreen and socioeconomic indicators for tracts with vs. without hazardous sites,
  with potentially unknown sites vs. all others, unknown vs. known-only, and TRI vs. non-TRI tracts; medians, population-weighted means,
  Wilcoxon tests.
* **Nearby schools & health care** – schools and health facilities within a chosen distance of potentially unknown sites.
* **Data & downloads** – per-edition geocoded CSVs, filtered sites, geocoding validation.

To deploy (e.g. shinyapps.io), copy `data/by_year/` into `app/data/by_year/` so the app folder is self-contained.

## Sources

* Colorado Directory of Manufacturers, 1961–2002 (scans from CU Boulder Libraries via interlibrary loan; not redistributed here).
* US EPA Facility Registry Service, state combined file for Colorado; EPA TRI facility table (Envirofacts).
* CDPHE Hazardous Materials & Waste Management Division layers, Colorado EnviroScreen 2.0 (census tracts), CDPHE Health Facilities,
  CDE school locations — via geodata.colorado.gov.
* US Census Bureau TIGER/Line 2023 ADDRFEAT.
* Frickel, S. & Elliott, J. R. (2018). *Sites Unseen: Uncovering Hidden Hazards in American Cities.* Russell Sage Foundation.

A site that appears on no inventory is a lead for records review or soil testing, not evidence of contamination.
