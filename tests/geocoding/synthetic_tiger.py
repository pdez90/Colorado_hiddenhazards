"""A small synthetic TIGER ADDRFEAT-like shapefile for Denver, plus the ZIP tables the geocoder needs.

Streets (all around the Ellsworth Ave / Broadway baselines, ELLS=39.7163, BWAY=-104.9875):
  Kalamath St      north of Ellsworth, plain name: 100-199 (80223), 400-599 (80204), 600-698 left side only (80204), 2100-2199 (80204), 4000-4099 (80211)
  S Kalamath St    south of Ellsworth: 400-599 (80223)        -> the number 450 exists on both the plain and the S street
  W 5th Ave        E-W avenue, three vertices: 2100-2199 (80204)
  E 24th Ave       E-W avenue: 2300-2399 (80205)
  24th St          diagonal downtown street: 2300-2399 (80205)  -> '2350 24TH' is on two streets of different type
  Broadway         600-699 (80203); S Broadway 1000-1099 (80210)
  S Bannock St     3500-3599 (80110, Englewood: a neighbouring ZIP of Denver's, not a Denver ZIP)
Filler segments ('N F80204A1 St', 'W F80204B1 Ave', ...) give 80204, 80211, 80223, 80219, 80205 and 80210 enough prefixed segments to
be Denver-grid ZIPs with a known half (>= 50 segments, >= 80% on one side of each baseline); 80203 and 80110 have no half.
The house-number range on a side is LFROMHN-LTOHN (left of the from->to direction) and RFROMHN-RTOHN.
"""
import os, pickle, numpy as np, pandas as pd, geopandas as gpd
from shapely.geometry import LineString

ELLS, BWAY = 39.7163, -104.9875
KAL = -105.0000
# FULLNAME, coords [(lon, lat), ...], (LFROM, LTO), (RFROM, RTO), ZIPL, ZIPR
SEGMENTS = [
    ('Kalamath St',   [(KAL, 39.7170), (KAL, 39.7185)], (100, 198), (101, 199), '80223', '80223'),   # 80223 straddles Ellsworth
    ('Kalamath St',   [(KAL, 39.7200), (KAL, 39.7215)], (400, 498), (401, 499), '80204', '80204'),
    ('Kalamath St',   [(KAL, 39.7215), (KAL, 39.7230)], (500, 598), (501, 599), '80204', '80204'),
    ('Kalamath St',   [(KAL, 39.7230), (KAL, 39.7245)], (600, 698), (None, None), '80204', '80204'),
    ('Kalamath St',   [(KAL, 39.7400), (KAL, 39.7415)], (2100, 2198), (2101, 2199), '80204', '80204'),
    ('Kalamath St',   [(KAL, 39.7700), (KAL, 39.7715)], (4000, 4098), (4001, 4099), '80211', '80211'),
    ('S Kalamath St', [(KAL, 39.7120), (KAL, 39.7105)], (401, 499), (400, 498), '80223', '80223'),
    ('S Kalamath St', [(KAL, 39.7105), (KAL, 39.7090)], (501, 599), (500, 598), '80223', '80223'),
    ('W 5th Ave',     [(-104.9900, 39.7250), (-104.9925, 39.7250), (-104.9950, 39.7252)], (2100, 2198), (2101, 2199), '80204', '80204'),
    ('E 24th Ave',    [(-104.9850, 39.7520), (-104.9800, 39.7520)], (2300, 2398), (2301, 2399), '80205', '80205'),
    ('24th St',       [(-104.9900, 39.7560), (-104.9880, 39.7575)], (2300, 2398), (2301, 2399), '80205', '80205'),
    ('Broadway',      [(BWAY, 39.7250), (BWAY, 39.7265)], (600, 698), (601, 699), '80203', '80203'),
    ('S Broadway',    [(BWAY, 39.7050), (BWAY, 39.7035)], (1001, 1099), (1000, 1098), '80210', '80210'),
    ('S Bannock St',  [(-104.9890, 39.6500), (-104.9890, 39.6485)], (3500, 3598), (3501, 3599), '80110', '80110'),
]
# ZIP: (centroid lat, lon, N/S half, E/W half) ; the half is used to place filler segments
ZIPS = {'80204': (39.735, -105.020, 'N', 'W'), '80211': (39.770, -105.020, 'N', 'W'), '80223': (39.705, -105.010, 'S', 'W'),
        '80219': (39.695, -105.030, 'S', 'W'), '80205': (39.755, -104.970, 'N', 'E'), '80210': (39.700, -104.960, 'S', 'E'),
        '80203': (39.730, -104.980, None, None), '80110': (39.650, -104.990, None, None), '80501': (40.170, -105.100, None, None)}
ZIP_CITY = {z: 'DENVER' for z in ZIPS}; ZIP_CITY['80110'] = 'ENGLEWOOD'; ZIP_CITY['80501'] = 'LONGMONT'
N_FILL = 28   # per axis and ZIP: 56 filler segments, so each ZIP with a half has >= 50 segments

def filler(z, lat, lon, ns, ew):
    rows = []
    for i in range(N_FILL):
        la = lat + (0.0003 * i - 0.004); lo = lon + 0.0001 * (i % 7)
        rows.append((f'{ns} F{z}A{i} St', [(lo, la), (lo, la + 0.0002)], (100 + 10 * i, 108 + 10 * i), (101 + 10 * i, 109 + 10 * i), z, z))
        rows.append((f'{ew} F{z}B{i} Ave', [(lo, la + 0.0001), (lo + 0.0002, la + 0.0001)], (100 + 10 * i, 108 + 10 * i), (101 + 10 * i, 109 + 10 * i), z, z))
    return rows

def all_segments():
    segs = list(SEGMENTS)
    for z, (la, lo, ns, ew) in ZIPS.items():
        if ns: segs += filler(z, la, lo, ns, ew)
    return segs

def write_fixture(root):
    """root/work/tiger/tl_synth_addrfeat.shp, root/work/inv/{zip_city.csv, zip_centroids.pkl}, root/data/geocoder/{zip_city.csv, zip_centroids.csv}.
    Returns root. The Python Geocoder is built by chdir(root) + tiger_geocode.build(); the R port reads the same files by path."""
    for d in ('work/tiger', 'work/inv', 'data/geocoder'):
        os.makedirs(os.path.join(root, d), exist_ok=True)
    segs = all_segments()
    def hn(v): return None if v is None else str(v)
    g = gpd.GeoDataFrame({'FULLNAME': [s[0] for s in segs],
                          'LFROMHN': [hn(s[2][0]) for s in segs], 'LTOHN': [hn(s[2][1]) for s in segs],
                          'RFROMHN': [hn(s[3][0]) for s in segs], 'RTOHN': [hn(s[3][1]) for s in segs],
                          'ZIPL': [s[4] for s in segs], 'ZIPR': [s[5] for s in segs]},
                         geometry=[LineString(s[1]) for s in segs], crs='EPSG:4269')
    g.to_file(os.path.join(root, 'work/tiger/tl_synth_addrfeat.shp'))
    zc = pd.DataFrame({'z': list(ZIP_CITY), 'CITY_NAME': list(ZIP_CITY.values())})
    zc.to_csv(os.path.join(root, 'work/inv/zip_city.csv'), index=False); zc.to_csv(os.path.join(root, 'data/geocoder/zip_city.csv'), index=False)
    cen = pd.DataFrame({'zip5': list(ZIPS), 'zlat': [v[0] for v in ZIPS.values()], 'zlon': [v[1] for v in ZIPS.values()], 'zn': 10})
    cen.to_pickle(os.path.join(root, 'work/inv/zip_centroids.pkl')); cen.to_csv(os.path.join(root, 'data/geocoder/zip_centroids.csv'), index=False)
    return root

def build_index(root, tiger_geocode):
    """Run the pipeline's own build() inside root (it reads work/tiger/*_addrfeat.shp and writes work/inv/tiger_index.pkl)."""
    cwd = os.getcwd(); os.chdir(root)
    try: tiger_geocode.build()
    finally: os.chdir(cwd)
    return os.path.join(root, 'work/inv/tiger_index.pkl')

if __name__ == '__main__':
    import sys
    write_fixture(sys.argv[1] if len(sys.argv) > 1 else '.')
