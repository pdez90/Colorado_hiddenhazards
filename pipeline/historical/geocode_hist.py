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
    """Street level only when the number was interpolated on a segment of the exact street in the stated town (or one of its ZIPs):
    `range_interp` and `range_interp_cityzips`, optionally with a direction settled by the ZIP or the street type (_dirzip, _dirtype).
    Loosened matches (_dirloose, _sufloose, _trim, _nearzips, fuzzy names) and an unresolved direction (_dirambig) never count: a
    nineteenth-century address must not be carried to a different street or town by an OCR-tolerant match."""
    if not q or not q.startswith('range_interp'): return False
    parts = set(q.split('_')[2:])          # suffixes after 'range_interp'
    return parts <= {'cityzips', 'dirzip', 'dirtype'}

REVIEW = 'data/historical/street_review.csv'
TOWN_REVIEW = 'data/historical/town_review.csv'   # hand review of every town-level listing (3 November 2026)
FE_GROUP = {'Chemicals': '28', 'Paint & varnish': '28', 'Soap': '28', 'Explosives': '28', 'Fertilizer & rendering': '28', 'Petroleum refining & asphalt': '29',
            'Rubber': '30', 'Plastics': '30', 'Smelting & refining': '33', 'Foundry': '33', 'Iron & steel works': '33', 'Metal working': '34',
            'Machine shop / machinery': '35', 'Transportation equipment': '37'}   # every other sector is EXT (extended)
REVIEW_KEY = ['year', 'town', 'nkey', 'sector']

def apply_review(df, rv, town_level=False):
    """Apply the hand review of street placements (data/historical/street_review.csv, 3 November 2026): every listing that the
    previous run placed at a street address was read against the OCR text of its page. Verdicts:
      ok           keep as parsed
      fix_address  the firm's own printed address replaces the parsed one (empty street_fix: placed at the town only)
    (any verdict but not_works: a non-empty street_fix / name_fix replaces the parsed street / name; street_fix 'none' places
    the listing at its town only)
      fix_name     the true firm name replaces the parsed one
      not_works    dropped (a sales branch, dealer, office, residence or service, or the trade word belonged to a neighbour)
      other_town   moved to town_fix (and street_fix when given)
      doubtful     kept, flagged in the `review` column
    The town review (data/historical/town_review.csv) adds other_sector (sector_fix replaces the sector and its F&E group).
    Rows are matched on (year, town, nkey, sector) as written by run_hist.py; a listing with no review row gets review = ''."""
    rv = rv.fillna('')
    for c in ('street_fix', 'town_fix', 'name_fix', 'sector_fix'):
        if c not in rv: rv[c] = ''
    df = df.copy()
    if 'review' not in df: df['review'] = ''
    if 'town_only' not in df: df['town_only'] = False
    key = lambda d: list(zip(d.year.astype(int), d.town.fillna(''), d.nkey.fillna(''), d.sector.fillna('')))
    idx = dict(zip(key(df), df.index))
    drop = []
    for r, k in zip(rv.itertuples(), key(rv)):
        i = idx.get(k)
        if i is None: continue
        v = r.verdict; df.at[i, 'review'] = v
        if town_level:                                   # town review: never placed at a street address nobody checked; the printed
            df.at[i, 'town_only'] = True                # address is kept (R/denver_1880.R places 1878-85 Denver firms on the 1880
            if r.town_fix and r.town_fix != r.town: df.at[i, 'street'] = ''   # building file) unless the listing moved town
        if v == 'not_works': drop.append(i); continue
        if v == 'fix_address' or r.street_fix:                                       # fix_address with no street_fix, or 'none': town only
            df.at[i, 'street'] = '' if r.street_fix == 'none' else r.street_fix
        if r.name_fix:                                   # the corrected name also gives the key, so two copies of one firm in an edition collapse
            df.at[i, 'name'] = r.name_fix; df.at[i, 'nkey'] = re.sub(r'[^A-Z0-9]', '', r.name_fix.upper())
        if r.town_fix: df.at[i, 'town'] = r.town_fix; df.at[i, 'town_src'] = 'review'   # other_town, or a doubtful row whose town is clear
        sf = r.sector_fix
        if sf: df.at[i, 'sector'] = sf; df.at[i, 'fe_group'] = FE_GROUP.get(sf, 'EXT')
    df = df.drop(index=drop)
    # a correction can turn a listing into a copy of another one in the same edition (an advertisement moved to its own town)
    return df.drop_duplicates(['year', 'town', 'nkey', 'sector'])

def main():
    df = pd.read_csv('work/hist/hist_hazard_entries.csv', dtype={'street': str})
    if os.path.exists(REVIEW):
        rv = pd.read_csv(REVIEW, dtype=str); rv['year'] = rv.year.astype(int)
        n0 = len(df); df = apply_review(df, rv)
        print('street review:', rv.verdict.value_counts().to_dict(), '- dropped', n0 - len(df))
    if os.path.exists(TOWN_REVIEW):
        tv = pd.read_csv(TOWN_REVIEW, dtype=str); tv['year'] = tv.year.astype(int)
        n0 = len(df); df = apply_review(df, tv, town_level=True)
        print('town review:', tv.verdict.value_counts().to_dict(), '- dropped', n0 - len(df))
    G = pd.read_csv('data/historical/gnis_places_co.csv')
    # historical places (mining camps, vanished towns) from the full USGS GNIS file (R/fetch_gnis_historical.R), and the directory's
    # spelling variants of gazetteer names (data/historical/town_aliases.csv: EMPIRE CITY -> EMPIRE, CANON CITY -> CAÑON CITY)
    if os.path.exists('data/historical/gnis_places_co_historical.csv'):
        G = pd.concat([G, pd.read_csv('data/historical/gnis_places_co_historical.csv').assign(feature_class='Populated Place')], ignore_index=True)
    G['rank'] = G.feature_class.map({'Populated Place': 0, 'Census': 1, 'Civil': 2})
    G = G.sort_values('rank').drop_duplicates('name')
    TC = {r.name: (r.lat, r.lon, r.county_name) for r in G.itertuples()}
    if os.path.exists('data/historical/town_aliases.csv'):   # the variant spelling is kept as the town; only the point comes from the gazetteer name
        for v, n in pd.read_csv('data/historical/town_aliases.csv', dtype=str).dropna().values:
            if n in TC and v not in TC: TC[v] = TC[n]
    sys.path.insert(0, 'pipeline')
    from tiger_geocode import Geocoder
    geo = Geocoder()
    out = []
    for r in df.itertuples():
        lat = lon = None; prec = 'none'
        if street_ok(r) and not getattr(r, 'town_only', False):
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
