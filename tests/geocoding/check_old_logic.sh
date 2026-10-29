#!/usr/bin/env bash
# Run the geocoding tests against the pre-review geocoder (pipeline/tiger_geocode.py at the given git revision, default HEAD) to see which
# tests fail on the old logic. Not part of the suite.   usage: tests/geocoding/check_old_logic.sh [rev]
set -euo pipefail
cd "$(dirname "$0")/../.."
REV=${1:-HEAD}; D=$(mktemp -d)
git show "$REV:pipeline/tiger_geocode.py" > "$D/tiger_geocode.py"
GEOCODE_PY_DIR=$D python3 -m pytest tests/geocoding -m "not slow" -q -p no:cacheprovider "${@:2}" || true
rm -rf "$D"
