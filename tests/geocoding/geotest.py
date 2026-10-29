"""Paths and helpers shared by the geocoding tests (kept out of conftest.py: several test suites share one pytest process, and
`from conftest import ...` would resolve to whichever suite's conftest was imported first)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
CACHE = os.path.join(HERE, '.cache')
for p in (os.path.join(ROOT, 'pipeline'), os.path.join(ROOT, 'pipeline', 'historical'), HERE):
    if p not in sys.path: sys.path.insert(0, p)
# GEOCODE_PY_DIR=<dir holding another tiger_geocode.py> runs the suite against that version (check_old_logic.sh uses it to show which
# tests fail on the pre-review geocoder)
if os.environ.get('GEOCODE_PY_DIR'): sys.path.insert(0, os.environ['GEOCODE_PY_DIR'])

def make_geocoder(synth_root, **kw):
    """A Geocoder on the fixture directory (its __init__ reads work/inv/* relative to the working directory)."""
    import tiger_geocode as tg
    cwd = os.getcwd(); os.chdir(synth_root)
    try: return tg.Geocoder(**kw)
    finally: os.chdir(cwd)
