"""Runs the testthat suite (tests/geocoding/testthat) after the Python results have been written to .cache, so the R port is checked
against the very same synthetic fixture and Python outputs. Skipped when Rscript is not installed."""
import os, shutil, subprocess, pytest
from geotest import HERE, ROOT, CACHE

def test_python_results_written(python_results):
    assert len(python_results) > 40 and all(os.path.exists(os.path.join(CACHE, f)) for f in ('python_geocodes.json', 'python_parse.json', 'python_fuzz.json'))
    assert python_results[('450 KALAMATH', 'DENVER', '80223')]['quality'] == 'range_interp_dirzip'

@pytest.mark.skipif(shutil.which('Rscript') is None, reason='Rscript not installed')
def test_r_port_matches_python(python_results):
    env = dict(os.environ, AUDIT_ROOT=ROOT, AUDIT_TESTING='1')
    r = subprocess.run(['Rscript', os.path.join(HERE, 'run_r_tests.R')], cwd=ROOT, env=env, capture_output=True, text=True, timeout=900)
    out = r.stdout + r.stderr
    print(out[-6000:])
    assert r.returncode == 0, out[-3000:]
    assert '0 failed' in out
    # the only R test allowed to skip is the real-TIGER check, and only when the slow Python test did not run (no work/tiger, or -m "not slow")
    if os.path.exists(os.path.join(CACHE, 'real', 'python_real_keys.json')):
        assert ', 0 skipped' in out, 'R tests skipped although the real-key results exist: ' + out[-2000:]
    else:
        assert ', 0 skipped' in out or ', 1 skipped' in out, out[-2000:]
