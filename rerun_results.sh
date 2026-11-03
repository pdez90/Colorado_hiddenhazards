#!/usr/bin/env bash
# Rerun every result script that reads the site inventory or the pre-1960 layer, in dependency order.
#
#   bash rerun_results.sh            # from the repository root, after ./run_all.sh (inventory + pre-1960 chains)
#   bash rerun_results.sh --from site_fate      # resume at a step (any script name below, without R/ and .R)
#   bash rerun_results.sh --from health         # only the tract and block-group health models (then the tables, SI and manifest)
#
# Each step reads files that the steps before it write, so the order matters:
#   denver_1880 writes the 1878-85 firm points that denver_eds_analysis reads; holc_covenants writes the HOLC areas that zoning_1925
#   reads, and zoning_1925 writes the 1929 zoning shares that
#   holc_covenants reads; site_fate writes the parcel years that mortality_redevelopment and archival_followup read; censoc_denver_1940 writes the linked
#   1940 residents that the CenSoc follow-ups read; app_census_layers writes app/data/tract_panel.csv that several later steps read,
#   and runs again after corridors because it also copies the corridor cells into app/data.
# Restricted or licensed inputs (Brown/IPUMS/CenSoc files in work/, the Colorado death records in ~/Downloads/CO_HIA, the 1955
# zone-map scan) are read in place and never copied into the repository; a step whose inputs are missing stops the run.
# The tract and block-group health models run last, from inputs read in place (R/prepare_health_inputs.R: the death records and block-group
# populations in ~/Downloads/CO_HIA and the EnviroScreen 2.0 block groups in ~/Downloads); the R versions are published
# (pipeline/health/write_health_tables.py), because the Python versions need libpysal/spreg. Not included: network downloads
# (R/fetch_*.R, R/benchmarks.R).
set -euo pipefail
cd "$(dirname "$0")"
STEPS=(
  denver_1880 denver_eds_analysis county_panel_1880_1940 ej_panel app_census_layers known_hidden_sensitivity
  holc_covenants zoning_1925 holc_covenants zoning_1944 zoning_1955 zoning_2023 zoning_over_time rezoning_denver loc_sanborn_1903
  denver_tracts_1950_2020 descriptive_sequences corridors app_census_layers landuse_1937_1997 highways_denver context_layers statewide
  site_fate archival_followup sanborn_check hedonic_denver ownership_denver housing_conditions_denver
  mortality_block mortality_redevelopment
  censoc_denver_1940 censoc_extensions censoc_enlistment mlp_residential_history
)
from="${2:-}"; [[ "${1:-}" == "--from" ]] || from=""
started=$([[ -z "$from" ]] && echo 1 || echo 0)
for s in "${STEPS[@]}"; do
  [[ "$s" == "$from" ]] && started=1
  [[ "$started" == 1 ]] || continue
  echo ">> Rscript R/$s.R"
  Rscript "R/$s.R"
done
if [[ -z "$from" || "$from" == health ]]; then started=1; fi
if [[ "$started" == 1 ]]; then
  echo ">> health models"
  Rscript R/prepare_health_inputs.R
  Rscript R/build_exposures.R
  Rscript R/health_models.R
  Rscript R/mortality_bg.R
  python3 pipeline/health/write_health_tables.py
fi
python3 paper/make_tables.py
python3 paper/si/make_si.py
Rscript -e 'rsconnect::writeManifest("app")'
echo ">> done; now run tests/run_tests.sh"
