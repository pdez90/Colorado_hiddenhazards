"""Second, independent geocoding check: Colorado's statewide public address points (rooftop/parcel points aggregated by
the Governor's Office of Information Technology), which do not come from TIGER/Line address ranges.

For a random sample of hazardous sites (700 address-level, 300 approximate; seed 42), look up the same house number and
street name in the address-point layer, keep points within 20 km of the stated town (GNIS) (with the same prefix direction when one
was printed; all directions when none was), report addresses whose candidate points lie >300 m apart as 'undecidable', and measure
the distance to our geocode for the rest.
Writes data/results/geocoding_validation_addresspoints.csv.

Service: https://gis.colorado.gov/public/rest/services/Address_and_Parcel/Colorado_Public_Addresses/FeatureServer/0
The committed results were produced with exactly these queries, sent from a browser because the build machine had no
route to gis.colorado.gov; running this script anywhere with internet access reproduces them (allowing for edits to the
address-point layer since October 2026).
"""
import json, sys, time, urllib.parse, urllib.request
import numpy as np, pandas as pd
sys.path.insert(0, 'pipeline')
from tiger_geocode import parse_addr

URL = 'https://gis.colorado.gov/public/rest/services/Address_and_Parcel/Colorado_Public_Addresses/FeatureServer/0/query'

def query(num, core, loose=False):
    first = core.split(' ')[0].replace("'", "''")
    where = f"AddrNum='{num}' AND " + (f"StreetName LIKE '{first}%'" if loose else f"StreetName='{core.replace(chr(39), chr(39) * 2)}'")
    qs = urllib.parse.urlencode(dict(where=where, outFields='AddrFull,PreDir,County,Latitude,Longitude', returnGeometry='false',
                                     resultRecordCount=50, f='json'))
    for _ in range(3):
        try:
            j = json.load(urllib.request.urlopen(URL + '?' + qs, timeout=30))
            return [(a['Latitude'], a['Longitude'], a.get('County') or '', a.get('PreDir') or '') for a in (f['attributes'] for f in j.get('features', []))]
        except Exception:
            time.sleep(2)
    FAILED.append(num)                     # the service could not be reached: counted, so the run can refuse to overwrite saved results
    return []

FAILED = []

def dist(la1, lo1, la2, lo2):
    return 6371000 * np.hypot(np.radians(la2 - la1), np.radians(lo2 - lo1) * np.cos(np.radians(la1)))

def classify(cands, pre, c0, lat, lon):
    """One sampled address against the address-point candidates (lat, lon, county, predir). Candidates must lie within 20 km of the
    town point c0 (lat, lon; None = no town). An address printed with a direction is compared with the points carrying that
    direction. One printed without a direction is compared with ALL points of that number (plain and directional): preferring the plain
    points would agree with the geocoder by construction whenever both '4300 Lipan' and '4300 S Lipan' exist. When the candidates
    disagree by more than 300 m the truth is 'undecidable' and the row is reported separately; dmin (nearest candidate) and dmax are
    still written."""
    cc = [c for c in cands if c0 and dist(c0[0], c0[1], c[0], c[1]) < 20000]
    if pre: cc = [c for c in cc if c[3][:1].upper() == pre[:1]]
    ds = [dist(lat, lon, c[0], c[1]) for c in cc]
    spread = len(ds) > 1 and max(ds) - min(ds) > 300
    return dict(status=('undecidable' if spread else 'found') if cc else 'not_found', ambiguous=spread,
                n_candidates=len(cc), n_plain=sum(1 for c in cc if not c[3]), dmin=min(ds) if ds else np.nan, dmax=max(ds) if ds else np.nan)

def main():
    r = pd.read_pickle('work/inv/records_final.pkl')
    h = r[r.site_id.notna() & r.geo_level.isin(['address', 'address_approx'])].sort_values('year').drop_duplicates('site_id', keep='last')
    s = pd.concat([h[h.geo_level == 'address'].sample(700, random_state=42), h[h.geo_level == 'address_approx'].sample(300, random_state=42)])
    G = pd.read_csv('data/historical/gnis_places_co.csv'); G = G[G.feature_class == 'Populated Place'].drop_duplicates('name')
    town = {n: (a, b) for n, a, b in zip(G.name, G.lat, G.lon)}
    rows = []
    for i, x in enumerate(s.itertuples()):
        num, core, pre, _ = parse_addr(x.street)
        cand = query(num, core, loose=(x.geo_level != 'address')) if num is not None and core else []
        c0 = town.get(str(x.city_g).upper())
        rows.append(dict(site_id=x.site_id, street=x.street, city=x.city_g, year=x.year, level=x.geo_level, quality=x.geo_quality,
                         **classify(cand, pre, c0, x.lat, x.lon)))
    R = pd.DataFrame(rows)
    if len(FAILED) > 0.05 * len(s) or not (R.status == 'found').any():
        sys.exit(f'address-point service unreachable for {len(FAILED)} of {len(s)} queries: saved results left in place')
    R.to_csv('data/results/geocoding_validation_addresspoints.csv', index=False)
    print(R.groupby('level').status.value_counts().unstack(fill_value=0))
    f = R[R.status == 'found']
    print(f.groupby('level').dmin.describe(percentiles=[.5, .9]).round(0))
    print(f.groupby('level').dmin.agg(within_250m=lambda d: (d <= 250).mean(), over_1km=lambda d: (d > 1000).mean()).round(3))
    u = R[R.status == 'undecidable']
    if len(u): print('undecidable (same number on several streets/sides > 300 m apart): our point within 250 m of the nearest candidate',
                     round((u.dmin <= 250).mean(), 3), '; of the farthest', round((u.dmax <= 250).mean(), 3), 'n =', len(u))

if __name__ == '__main__': main()
