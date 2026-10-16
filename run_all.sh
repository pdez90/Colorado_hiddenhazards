#!/usr/bin/env bash
# Reproduce the full pipeline. Run from the repository root.
#   0. put the Colorado Directory of Manufacturers scans in work/pdf/  (see README)
#   1. pip install -r requirements.txt ; apt/brew install tesseract (5.3.x) 
set -euo pipefail
STAGE=${1:-all}
mkdir -p work/inv work/geo work/parsed data/results data/by_year app/data
py() { echo ">> $*"; python3 "$@"; }
if [[ $STAGE == all || $STAGE == fetch ]]; then py pipeline/fetch_inputs.py; fi
if [[ $STAGE == all || $STAGE == ocr ]]; then
  py pipeline/extract.py          # page images from the scans -> work/img
  py pipeline/ocr.py              # Tesseract -> work/tsv, work/coltxt
fi
if [[ $STAGE == all || $STAGE == ocr || $STAGE == parse ]]; then
  py pipeline/make_gazetteer.py
  py pipeline/parse_all.py        # -> work/parsed
fi
py pipeline/sic_classifier.py     # learns description -> SIC from editions that print codes
py pipeline/consolidate.py        # -> work/inv/records.pkl (SIC, F&E sector flags)
py pipeline/geo_prep.py
py pipeline/link.py               # establishments across years (~10 min)
py pipeline/build_reg.py          # regulatory inventories -> work/inv/reg.pkl
py pipeline/frs_addr_geo.py       # ZIP centroids + FRS address points
py pipeline/tiger_geocode.py build
py pipeline/run_geocode.py        # offline TIGER/Line address-range geocoder
py pipeline/build_sites.py        # sites (30 m clusters) + inventory matching
py pipeline/finalize.py
py pipeline/export.py             # data/results/*
py pipeline/export_by_year.py     # data/by_year/*
py pipeline/validate_geocoding.py
py pipeline/app_inputs.py         # app/data/*
# ---- pre-1960 layer: Colorado State Business Directory (1877-1950), hazardous historical trades
if [[ -d work/hist/pdf || -d work/hist/text ]]; then
  [[ -d work/hist/pdf ]] && bash pipeline/historical/extract_text.sh
  py pipeline/historical/run_hist.py       # town headings + entries + trade vocabulary -> work/hist/hist_hazard_entries.csv
  py pipeline/historical/geocode_hist.py   # street level (Denver 1891+, larger cities 1910+) else GNIS town point
  py pipeline/historical/link_hist.py      # firms across editions; links to 1961-2002 directory -> data/historical/*
  py pipeline/historical/app_hist.py       # app/data/historical_sites.csv, site_precursors.csv
fi
