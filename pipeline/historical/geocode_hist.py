"""Place pre-1960 hazardous-trade listings.
Street level only where today's numbering applies: Denver from 1891 on (the city renumbered in 1887), and
other larger cities from 1910 on; only exact address-range matches (no fuzzy/nearest) are accepted.
Everything else goes to the USGS GNIS point for the town (precision='town')."""
import os, re, sys
import pandas as pd
REPO = '.'
HERE = os.path.dirname(os.path.abspath(__file__))

BIGCITY = {'PUEBLO', 'COLORADO SPRINGS', 'BOULDER', 'GRAND JUNCTION', 'TRINIDAD', 'GREELEY', 'FORT COLLINS', 'CANON CITY',
           'LOVELAND', 'LONGMONT', 'DURANGO', 'GOLDEN', 'ENGLEWOOD', 'LITTLETON', 'LEADVILLE', 'STERLING', 'LA JUNTA', 'ROCKY FORD'}
RENAME = {'HOLLADAY': 'MARKET', 'MCGAA': 'MARKET', 'BDWY': 'BROADWAY', 'BDWAY': 'BROADWAY', 'BWAY': 'BROADWAY', 'MKT': 'MARKET',
          'WASH': 'WASHINGTON', 'SANTA': 'SANTA FE', 'ARAPA': 'ARAPAHOE', 'LINCO': 'LINCOLN', 'UNIV': 'UNIVERSITY', 'PENNA': 'PENNSYLVANIA',
          'PENN': 'PENNSYLVANIA', 'CALIF': 'CALIFORNIA', 'COLO': 'COLORADO', 'LAW': 'LAWRENCE', 'LARI': 'LARIMER', 'CHAMP': 'CHAMPA'}

def street_ok(r):
    if not isinstance(r.street, str) or not re.match(r"^\d+ ", r.street): return False
    if getattr(r, 'office', False) is True: return False          # office address, not the works
    if r.town == 'DENVER': return r.year >= 1891
    return r.town in BIGCITY and r.year >= 1910

def hist_street(street, entry=''):
    """Today's spelling of a directory street ('125 S Weber', '1721 Holladay', '2d av'): upper case, abbreviations expanded, '2d' -> '2ND';
    '' when the entry places the firm in a building/block rather than at the number."""
    st = re.sub(r"[^A-Z0-9 ]", "", str(street).upper())
    e = str(entry).upper()
    if st and re.search(r"\b(BLDG|BLK|BLOCK|BUILDING)\b", e[e.find(st.split()[-1]):][:30]): return ''
    for a, b in RENAME.items(): st = re.sub(rf"\b{a}\b(?!\s+{b.split()[-1]}\b)", b, st)     # 'SANTA' -> 'SANTA FE', but 'SANTA FE' stays
    st = re.sub(r"(\d+)D\b", r"\1ND", st)                     # '3d' -> '3RD' handled by ordfix; '2d' -> '2ND'
    st = re.sub(r"\b(\d+)ND\b", lambda m: m.group(1) + {1: 'ST', 2: 'ND', 3: 'RD'}.get(int(m.group(1)) % 10 if int(m.group(1)) % 100 not in (11, 12, 13) else 0, 'TH'), st)
    return st

def street_level(q):
    """Street level when the number was interpolated on a segment of the right street; a direction settled by the ZIP or the street type
    (_dirzip, _dirtype) counts, an unresolved direction (_dirambig) does not; fuzzy street names never do."""
    return bool(q) and q.startswith('range_interp') and 'dirambig' not in q and 'fuzzy' not in q

def main():
    df = pd.read_csv('work/hist/hist_hazard_entries.csv', dtype={'street': str})
    G = pd.read_csv('data/historical/gnis_places_co.csv')
    G['rank'] = G.feature_class.map({'Populated Place': 0, 'Census': 1, 'Civil': 2})
    G = G.sort_values('rank').drop_duplicates('name')
    TC = {r.name: (r.lat, r.lon, r.county_name) for r in G.itertuples()}
    sys.path.insert(0, 'pipeline')
    from tiger_geocode import Geocoder
    geo = Geocoder()
    out = []
    for r in df.itertuples():
        lat = lon = None; prec = 'none'
        if street_ok(r):
            st = hist_street(r.street, r.entry)
            la, lo, q = geo.geocode(st, r.town, '') if st else (None, None, 'none')
            if street_level(q): lat, lon, prec = la, lo, 'street'
        if lat is None and isinstance(r.town, str) and r.town in TC:
            lat, lon, _ = TC[r.town]; prec = 'town'
        out.append((lat, lon, prec, TC.get(r.town, (None, None, ''))[2] if isinstance(r.town, str) else ''))
    df[['lat', 'lon', 'precision', 'county']] = pd.DataFrame(out, index=df.index)
    df.to_csv('work/hist/hist_hazard_geocoded.csv', index=False)
    print(df.precision.value_counts().to_string())
    print(df.groupby('year').precision.apply(lambda s: (s == 'street').sum()).to_string())

if __name__ == '__main__': main()
