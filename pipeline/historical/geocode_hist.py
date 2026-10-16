"""Place pre-1960 hazardous-trade listings.
Street level only where today's numbering applies: Denver from 1891 on (the city renumbered in 1887), and
other larger cities from 1910 on; only exact address-range matches (no fuzzy/nearest) are accepted.
Everything else goes to the USGS GNIS point for the town (precision='town')."""
import os, re, sys
import pandas as pd
REPO = '.'
HERE = os.path.dirname(os.path.abspath(__file__))
df = pd.read_csv('work/hist/hist_hazard_entries.csv', dtype={'street': str})
G = pd.read_csv('data/historical/gnis_places_co.csv')
G['rank'] = G.feature_class.map({'Populated Place': 0, 'Census': 1, 'Civil': 2})
G = G.sort_values('rank').drop_duplicates('name')
TC = {r.name: (r.lat, r.lon, r.county_name) for r in G.itertuples()}

BIGCITY = {'PUEBLO', 'COLORADO SPRINGS', 'BOULDER', 'GRAND JUNCTION', 'TRINIDAD', 'GREELEY', 'FORT COLLINS', 'CANON CITY',
           'LOVELAND', 'LONGMONT', 'DURANGO', 'GOLDEN', 'ENGLEWOOD', 'LITTLETON', 'LEADVILLE', 'STERLING', 'LA JUNTA', 'ROCKY FORD'}
RENAME = {'HOLLADAY': 'MARKET', 'MCGAA': 'MARKET', 'BDWY': 'BROADWAY', 'BDWAY': 'BROADWAY', 'BWAY': 'BROADWAY', 'MKT': 'MARKET',
          'WASH': 'WASHINGTON', 'SANTA': 'SANTA FE', 'ARAPA': 'ARAPAHOE', 'LINCO': 'LINCOLN', 'UNIV': 'UNIVERSITY', 'PENNA': 'PENNSYLVANIA',
          'PENN': 'PENNSYLVANIA', 'CALIF': 'CALIFORNIA', 'COLO': 'COLORADO', 'LAW': 'LAWRENCE', 'LARI': 'LARIMER', 'CHAMP': 'CHAMPA'}

def street_ok(r):
    if not isinstance(r.street, str) or not re.match(r"^\d+ ", r.street): return False
    if r.town == 'DENVER': return r.year >= 1891
    return r.town in BIGCITY and r.year >= 1910

sys.path.insert(0, 'pipeline')
from tiger_geocode import Geocoder
geo = Geocoder()
out = []
for r in df.itertuples():
    lat = lon = None; prec = 'none'
    if street_ok(r):
        st = r.street.upper()
        st = re.sub(r"[^A-Z0-9 ]", "", st)
        if re.search(r"\b(BLDG|BLK|BLOCK|BUILDING)\b", str(r.entry).upper()[str(r.entry).upper().find(st.split()[-1]):][:30]): st = ''
        for a, b in RENAME.items(): st = re.sub(rf"\b{a}\b", b, st)
        st = re.sub(r"(\d+)D\b", r"\1ND", st)                     # '3d' -> '3RD' handled by ordfix; '2d' -> '2ND'
        st = re.sub(r"\b(\d+)ND\b", lambda m: m.group(1) + {1: 'ST', 2: 'ND', 3: 'RD'}.get(int(m.group(1)) % 10 if int(m.group(1)) % 100 not in (11, 12, 13) else 0, 'TH'), st)
        la, lo, q = geo.geocode(st, r.town, '') if st else (None, None, 'none')
        if q.startswith('range_interp'): lat, lon, prec = la, lo, 'street'
    if lat is None and isinstance(r.town, str) and r.town in TC:
        lat, lon, _ = TC[r.town]; prec = 'town'
    out.append((lat, lon, prec, TC.get(r.town, (None, None, ''))[2] if isinstance(r.town, str) else ''))
df[['lat', 'lon', 'precision', 'county']] = pd.DataFrame(out, index=df.index)
df.to_csv('work/hist/hist_hazard_geocoded.csv', index=False)
print(df.precision.value_counts().to_string())
print(df.groupby('year').precision.apply(lambda s: (s == 'street').sum()).to_string())
