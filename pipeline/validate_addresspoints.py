"""Second, independent geocoding check: Colorado's statewide public address points (rooftop/parcel points aggregated by
the Governor's Office of Information Technology), which do not come from TIGER/Line address ranges.

For a random sample of hazardous sites (700 address-level, 300 approximate; seed 42), look up the same house number and
street name in the address-point layer, keep points within 20 km of the stated town (GNIS) with the same prefix direction,
drop addresses that match several points >300 m apart (ambiguous), and measure the distance to our geocode.
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
    return []

def dist(la1, lo1, la2, lo2):
    return 6371000 * np.hypot(np.radians(la2 - la1), np.radians(lo2 - lo1) * np.cos(np.radians(la1)))

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
    cc = [c for c in cand if c0 and dist(c0[0], c0[1], c[0], c[1]) < 20000]
    cc = [c for c in cc if c[3][:1].upper() == pre[:1]] if pre else ([c for c in cc if not c[3]] or cc)
    ds = [dist(x.lat, x.lon, c[0], c[1]) for c in cc]
    rows.append(dict(site_id=x.site_id, street=x.street, city=x.city_g, year=x.year, level=x.geo_level, quality=x.geo_quality,
                     status='found' if cc else 'not_found', ambiguous=len(ds) > 1 and max(ds) - min(ds) > 300,
                     dmin=min(ds) if ds else np.nan))
R = pd.DataFrame(rows)
R.to_csv('data/results/geocoding_validation_addresspoints.csv', index=False)
f = R[(R.status == 'found') & ~R.ambiguous]
print(f.groupby('level').dmin.describe(percentiles=[.5, .9]).round(0))
print(f.groupby('level').dmin.agg(within_250m=lambda d: (d <= 250).mean(), over_1km=lambda d: (d > 1000).mean()).round(3))
