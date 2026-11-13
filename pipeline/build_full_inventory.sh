#!/usr/bin/env bash
# data/full_inventory/: the same site inventory built from ALL 25 editions of the manufacturers' directory, partial ones included
# (kept for reference; R/edition_coverage.R and R/benchmarks.R read it). Run from the repository root AFTER ./run_all.sh:
#   bash pipeline/build_full_inventory.sh
# It switches config/editions.json to mode "all", reruns the site steps (build_sites -> app_site_firms), copies the four all-edition
# outputs into data/full_inventory/, then switches back to mode "complete" and reruns the same steps, so the published files are
# again those of the 13 complete editions (the script checks that they come back byte-identical). R/fix_direction_geocodes.R is
# run last and covers both sets.
set -euo pipefail
cd "$(dirname "$0")/.."
PUB=(data/results/CO_directory_listings_1961-2002.csv app/data/sites.csv app/data/site_firms.csv data/results/CO_historical_industrial_sites.geojson)
sum_pub() { md5sum "${PUB[@]}" data/by_year/*.csv | md5sum | cut -c1-32; }
steps() { for s in build_sites finalize export export_by_year validate_geocoding app_inputs app_site_firms app_industry_mix; do echo ">> pipeline/$s.py"; python3 "pipeline/$s.py" > /dev/null; done; }
setmode() { python3 - "$1" <<'PY'
import json, sys
p = 'config/editions.json'; c = json.load(open(p)); c['mode'] = sys.argv[1]; json.dump(c, open(p, 'w'), indent=2); open(p, 'a').write('\n')
PY
}
[[ "$(python3 -c "import json; print(json.load(open('config/editions.json'))['mode'])")" == complete ]] || { echo "config/editions.json is not in mode 'complete'"; exit 1; }
before=$(sum_pub); cfg=$(md5sum config/editions.json | cut -c1-32); cp config/editions.json /tmp/editions.json.keep
trap 'cp /tmp/editions.json.keep config/editions.json' EXIT
setmode all; steps
mkdir -p data/full_inventory/by_year; rm -f data/full_inventory/by_year/*.csv
cp data/results/CO_directory_listings_1961-2002.csv data/full_inventory/
cp app/data/sites.csv app/data/site_firms.csv data/full_inventory/
cp data/by_year/CO_DCM_*_geocoded.csv data/full_inventory/by_year/
cp /tmp/editions.json.keep config/editions.json; rm -f data/by_year/CO_DCM_*_geocoded.csv; steps
[[ "$(md5sum config/editions.json | cut -c1-32)" == "$cfg" ]] || { echo "config/editions.json was not restored"; exit 1; }
echo ">> R/fix_direction_geocodes.R"; Rscript R/fix_direction_geocodes.R
mkdir -p app/data/by_year && cp data/by_year/CO_DCM_*_geocoded.csv app/data/by_year/
after=$(sum_pub)
[[ "$before" == "$after" ]] || { echo "the complete-edition files did not come back identical ($before vs $after)"; exit 1; }
echo ">> data/full_inventory rebuilt: $(($(wc -l < data/full_inventory/CO_directory_listings_1961-2002.csv) - 1)) listings, $(($(wc -l < data/full_inventory/sites.csv) - 1)) hazardous sites"
