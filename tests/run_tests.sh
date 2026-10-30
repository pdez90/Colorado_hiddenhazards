#!/usr/bin/env bash
# Run every test suite of the project and report pass/fail per suite.
#
#   tests/run_tests.sh            # everything, including the slow Shiny app smoke test
#   tests/run_tests.sh --fast     # skip tests marked `slow` (the app smoke test)
#   tests/run_tests.sh --python   # Python suites only;  --r : R suite only
#
# Exit status is non-zero if any suite fails. Extra arguments after `--` go to pytest.
# The Python suites use $PYTHON if set (e.g. PYTHON=/opt/miniconda3/bin/python3 tests/run_tests.sh), else python3.
set -u
cd "$(dirname "$0")/.." || exit 2
export LANG=C.UTF-8 LC_ALL=C.UTF-8
PY="${PYTHON:-python3}"

FAST=0; RUN_PY=1; RUN_R=1; PYTEST_EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --fast) FAST=1 ;;
    --python) RUN_R=0 ;;
    --r) RUN_PY=0 ;;
    --) shift; PYTEST_EXTRA=("$@"); break ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

declare -a NAMES STATUSES TIMES
run_suite() {  # name, command...
  local name="$1"; shift
  echo; echo "=== $name"; echo "+ $*"
  local t0=$SECONDS
  "$@"; local rc=$?
  NAMES+=("$name"); TIMES+=("$((SECONDS - t0))s")
  if [ $rc -eq 0 ]; then STATUSES+=("PASS"); else STATUSES+=("FAIL (exit $rc)"); fi
  return $rc
}

PY_DIRS=()
for d in tests/digitization tests/geocoding tests/outputs; do [ -d "$d" ] && PY_DIRS+=("$d"); done

overall=0
if [ $RUN_PY -eq 1 ]; then
  if [ ${#PY_DIRS[@]} -eq 0 ]; then
    echo "no Python test directories found"; overall=1
  else
    MARK=(); [ $FAST -eq 1 ] && MARK=(-m "not slow")
    # one pytest process per suite: each has its own conftest.py (same module name) and the
    # digitization suite chdirs into a scratch workspace, so they must not share a process
    for d in "${PY_DIRS[@]}"; do
      run_suite "python ($d)" "$PY" -m pytest "$d" ${MARK[@]+"${MARK[@]}"} -p no:cacheprovider ${PYTEST_EXTRA[@]+"${PYTEST_EXTRA[@]}"} || overall=1
    done
  fi
fi

if [ $RUN_R -eq 1 ]; then
  if [ -d tests/r ]; then
    # test_dir() stops with an error (non-zero exit) when any test fails
    run_suite "r (testthat tests/r)" Rscript -e 'testthat::test_dir("tests/r")' || overall=1
  else
    echo "tests/r not found"; overall=1
  fi
fi

echo; echo "=== summary"
for i in "${!NAMES[@]}"; do printf '  %-50s %-14s %s\n' "${NAMES[$i]}" "${STATUSES[$i]}" "${TIMES[$i]}"; done
if [ $overall -eq 0 ]; then echo "ALL SUITES PASSED"; else echo "SOME SUITES FAILED"; fi
exit $overall
