# Colorado Hidden Hazards

Historical hazardous industrial sites in Colorado, 1961–2002, identified from the *Colorado Directory of Manufacturers*
(plus a pre-1960 layer of hazardous trades from the *Colorado State Business Directory*, 1877–1950),
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
| `data/historical/` | Pre-1960 layer: hazardous-trade listings (`CO_pre1960_hazardous_listings.csv`) and firm-locations (`CO_pre1960_hazardous_sites.csv`) from the Colorado State Business Directory, 1877–1950; GNIS place gazetteer |
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
not been checked against historical maps (e.g. Sanborn atlases); treat them as approximate. Vetting this layer removed 1,266 entries
that were workers listed at their home addresses ("Cain Patrick, stoker, Denver Gas Co, 2422 Champa"), not works. It also stopped
placing 684 office listings at their downtown office addresses.

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

## Before 1960: Colorado State Business Directory, 1877–1950

The manufacturers' directory starts in 1961, but Colorado's smelters, foundries, assay offices and gas works go back to the 1870s.
`pipeline/historical/` reads the searchable text of the CU Boulder scans of the *Colorado State Business Directory*
(17 editions: 1871 Rocky Mountain Directory, 1875, 1877–1883, 1887, 1888, 1891, 1910, 1913, 1915, 1939, 1950) and:

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

Result: 4,411 hazardous-trade listings → 4,217 firm-locations; 387 at a street address; 164 link to the 1961–2002 directory,
giving 130 later sites a documented pre-1960 hazardous precursor.
**Caveats:** the text layers are uncorrected OCR with columns interleaved, so names can be garbled (`name_quality`), some entries are
missed, and counts are not comparable between editions or with the manufacturers' directory. 1871, 1875 and the user-supplied 1877
volumes are read from the Internet Archive / Google Books copies, which carry text layers.

## The Shiny app

```r
source("app/install_packages.R")
shiny::runApp("app")
```

* **Map** – historical hazardous sites coloured by current regulatory status or by **persistence** (years between first and last hazardous
  listing, extended back to the pre-1960 directories where a precursor is found), filtered by years listed (1877–2002), sector, status and confidence;
  a **pre-1960 layer** (brown; town-level points clustered, black ring = firm or address still listed after 1960);
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
* Colorado State Business Directory (Gazetteer Publishing / J.A. Blake), 1877–1950: CU Boulder Libraries digital collections, linked from
  History Colorado's business-directory guide (https://www.historycolorado.org/business-directories).
* USGS Geographic Names Information System (domestic and historical populated places).
* US Census Bureau TIGER/Line 2023 ADDRFEAT.
* Frickel, S. & Elliott, J. R. (2018). *Sites Unseen: Uncovering Hidden Hazards in American Cities.* Russell Sage Foundation.

A site that appears on no inventory is a lead for records review or soil testing, not evidence of contamination.
