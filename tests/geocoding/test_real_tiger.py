"""Real Denver TIGER ADDRFEAT (work/tiger/tl_2023_08031): build the index (cached under .cache/real) and re-geocode 30 committed Denver keys
from data/geocoder/geocode_keys_with_python_results.csv. Those results were produced before the review (no side offset), so the only
difference allowed is the 12 m perpendicular offset: same quality code, point 12 m away.
Marked slow; skipped when work/tiger is absent.   pytest tests/geocoding -m slow"""
import os, shutil, pytest, numpy as np, pandas as pd
from geotest import ROOT, CACHE

TIGER = os.path.join(ROOT, 'work', 'tiger', 'tl_2023_08031_addrfeat.shp')
pytestmark = [pytest.mark.slow, pytest.mark.skipif(not os.path.exists(TIGER), reason='work/tiger (Denver ADDRFEAT) not present')]

@pytest.fixture(scope='module')
def real_geocoder():
    import tiger_geocode as tg
    root = os.path.join(CACHE, 'real')
    for d in ('work/tiger', 'work/inv'): os.makedirs(os.path.join(root, d), exist_ok=True)
    for ext in ('shp', 'shx', 'dbf', 'prj'):
        dst = os.path.join(root, 'work/tiger', f'tl_2023_08031_addrfeat.{ext}')
        if not os.path.exists(dst): os.symlink(TIGER[:-3] + ext, dst)
    zc = pd.read_csv(os.path.join(ROOT, 'data/geocoder/zip_city.csv'), dtype=str); zc.to_csv(os.path.join(root, 'work/inv/zip_city.csv'), index=False)
    pd.read_csv(os.path.join(ROOT, 'data/geocoder/zip_centroids.csv'), dtype={'zip5': str}).to_pickle(os.path.join(root, 'work/inv/zip_centroids.pkl'))
    idx = os.path.join(root, 'work/inv/tiger_index.pkl')
    cwd = os.getcwd(); os.chdir(root)
    try:
        if not os.path.exists(idx) or os.path.getmtime(idx) < os.path.getmtime(tg.__file__): tg.build()
        return tg.Geocoder()
    finally: os.chdir(cwd)

def sample_keys(n=30):
    k = pd.read_csv(os.path.join(ROOT, 'data/geocoder/geocode_keys_with_python_results.csv'), dtype=str, keep_default_na=False)
    k = k[(k.city == 'DENVER') & k.zip.str.match(r'^802\d\d$') & (k.quality_py == 'range_interp') & k.street.str.match(r'^\d+ (N|S|E|W) [A-Z]')]
    k = k.sort_values('geo_key').reset_index(drop=True)
    return k.iloc[np.linspace(0, len(k) - 1, n).round().astype(int)]

def dist_m(la1, lo1, la2, lo2): return 6371000 * np.hypot(np.radians(la2 - la1), np.radians(lo2 - lo1) * np.cos(np.radians(la1)))

def test_real_index_builds(real_geocoder):
    assert len(real_geocoder.G) > 20000 and ('80223', 'KALAMATH') in real_geocoder.idx

def test_thirty_denver_keys_differ_only_by_the_offset(real_geocoder):
    K = sample_keys(); assert len(K) == 30
    rows = []
    for r in K.itertuples():
        la, lo, q = real_geocoder.geocode(r.street, r.city, r.zip)
        rows.append((r.street, r.zip, q, dist_m(float(r.lat_py), float(r.lon_py), la, lo)))
    R = pd.DataFrame(rows, columns=['street', 'zip', 'quality', 'd_m']); print(R.to_string())
    assert (R.quality == 'range_interp').all(), R[R.quality != 'range_interp']
    assert R.d_m.between(11.5, 12.5).all(), R[~R.d_m.between(11.5, 12.5)]
    # the same keys with the Python results, for the R port's real-key check (testthat/test-real_tiger.R)
    import json
    out = []
    for r in K.itertuples():
        la, lo, q = real_geocoder.geocode(r.street, r.city, r.zip)
        out.append(dict(street=r.street, city=r.city, zip=r.zip, lat_py_old=float(r.lat_py), lon_py_old=float(r.lon_py), quality_old=r.quality_py, lat=float(la), lon=float(lo), quality=q))
    json.dump(out, open(os.path.join(CACHE, 'real', 'python_real_keys.json'), 'w'), indent=1)

def test_real_grid_info(real_geocoder):
    """The real Denver TIGER gives the known halves: 80223 and 80219 south of Ellsworth, 80211 north; 80204 west of Broadway, 80205 east."""
    g = real_geocoder
    assert {'80204', '80205', '80211', '80219', '80223'} <= g.gridzips
    assert g.half.get(('80223', 'NS')) == 'S' and g.half.get(('80219', 'NS')) == 'S' and g.half.get(('80211', 'NS')) == 'N'
    assert g.half.get(('80204', 'EW')) == 'W' and g.half.get(('80205', 'EW')) == 'E'

def test_real_review_examples(real_geocoder):
    """The review's own examples on the real streets: 4000 S Kalamath is never put on north Kalamath St; a plain '1200 KALAMATH' is decided
    by the ZIP (80204 north of Ellsworth -> Kalamath St; 80223 -> S Kalamath St); with no ZIP it is ambiguous. (4300 S Lipan lies in
    Arapahoe County, outside this county file.)"""
    la, lo, q = real_geocoder.geocode('4000 S KALAMATH', 'DENVER', '80223')
    assert not (q.startswith('range_interp') and la > 39.7163), (la, lo, q)
    la, lo, q = real_geocoder.geocode('1200 KALAMATH', 'DENVER', '80204')
    assert q == 'range_interp_dirzip' and la > 39.7163, (la, lo, q)
    la2, lo2, q2 = real_geocoder.geocode('1200 KALAMATH', 'DENVER', '80223')
    assert q2 == 'range_interp_dirzip_cityzips' and la2 < 39.7163, (la2, lo2, q2)
    assert 'dirambig' in real_geocoder.geocode('1200 KALAMATH', 'DENVER', '')[2]
    # 80223 straddles Ellsworth: 450 Kalamath's nearest plain segment end is north, but 450 S Kalamath exists in the ZIP
    la3, lo3, q3 = real_geocoder.geocode('450 KALAMATH', 'DENVER', '80223')
    assert q3 == 'range_interp_dirzip' and la3 < 39.7163, (la3, lo3, q3)
