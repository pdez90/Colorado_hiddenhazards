"""Shared fixtures: the synthetic Denver ADDRFEAT fixture (built once per session under tests/geocoding/.cache/synthetic), the Python
Geocoder on it, and the JSON file of Python results that the R parity test (testthat/test-geocode_tiger.R) reads."""
import os, sys, json, types, shutil, pytest

from geotest import HERE, ROOT, CACHE, make_geocoder   # noqa: F401  (also puts pipeline/ on sys.path)
import tiger_geocode   # noqa: E402  (bound now, before pipeline modules re-insert their own directory at the front of sys.path)

# pipeline/consolidate.py imports sic_predict (the description -> SIC classifier, which the tests do not need). Should that module still
# unpickle work/inv/sic_clf.pkl at import time, give it a stand-in so consolidate.norm_street can be imported without work/
try: import sic_predict  # noqa: F401
except Exception:
    stub = types.ModuleType('sic_predict'); stub.predict = lambda texts: [('', 0.0, '')] * len(texts); sys.modules['sic_predict'] = stub

def pytest_configure(config):
    config.addinivalue_line('markers', 'slow: builds the real Denver TIGER index (needs work/tiger); deselect with -m "not slow"')

def pytest_collection_modifyitems(session, config, items):
    # the R suite (test_r_port.py) reads what the other tests wrote to .cache (synthetic results, and the real-key results of the slow
    # test when it ran), so it goes last
    items.sort(key=lambda it: it.fspath.basename == 'test_r_port.py')

@pytest.fixture(scope='session')
def synth_root():
    """Directory laid out like the repository (work/tiger, work/inv, data/geocoder) holding the synthetic fixture and its index."""
    import synthetic_tiger as st, tiger_geocode as tg
    root = os.path.join(CACHE, 'synthetic')
    if os.path.isdir(root): shutil.rmtree(root)
    st.write_fixture(root)
    st.build_index(root, tg)
    return root

@pytest.fixture(scope='session')
def geocoder(synth_root):
    import tiger_geocode as tg
    cwd = os.getcwd(); os.chdir(synth_root)
    try: g = tg.Geocoder()
    finally: os.chdir(cwd)
    return g

@pytest.fixture(scope='session')
def python_results(geocoder):
    """Every case in cases.CASES geocoded by Python, written to .cache/python_geocodes.json for the R parity test."""
    from cases import CASES
    rows = []
    for street, city, zip5 in CASES:
        la, lo, q = geocoder.geocode(street, city, zip5)
        rows.append(dict(street=street, city=city, zip=zip5, lat=None if la is None else float(la), lon=None if lo is None else float(lo), quality=q))
    os.makedirs(CACHE, exist_ok=True)
    json.dump(rows, open(os.path.join(CACHE, 'python_geocodes.json'), 'w'), indent=1)
    # parse_addr on the edge cases, and rapidfuzz scores on name pairs, for the R parity tests
    import tiger_geocode as tg
    from rapidfuzz import fuzz
    from cases import PARSE_CASES, FUZZ_PAIRS
    json.dump([dict(addr=a, num=n, core=c, pre=p, suf=sf) for a in PARSE_CASES for n, c, p, sf in [tg.parse_addr(a)]],
              open(os.path.join(CACHE, 'python_parse.json'), 'w'), indent=1)
    json.dump([dict(a=a, b=b, ratio=fuzz.ratio(a, b), token_sort=fuzz.token_sort_ratio(a, b), token_set=fuzz.token_set_ratio(a, b)) for a, b in FUZZ_PAIRS],
              open(os.path.join(CACHE, 'python_fuzz.json'), 'w'), indent=1)
    return {(r['street'], r['city'], r['zip']): r for r in rows}
