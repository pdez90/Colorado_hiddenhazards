"""Link pre-1960 hazardous listings (a) across editions into historical firms, and (b) to the 1961-2002 directory
establishments/sites, by name within town and by address. Writes hist_sites.csv (one row per historical location)."""
import os, re, sys
import numpy as np, pandas as pd
from rapidfuzz import fuzz
REPO = '.'
HERE = os.path.dirname(os.path.abspath(__file__))
H = pd.read_csv('work/hist/hist_hazard_geocoded.csv')
H = H[H.precision != 'none'].reset_index(drop=True)
STOP = r"\b(THE|CO|COMPANY|INC|CORP|CORPORATION|MFG|MANUFACTURING|WORKS|AND|OF|LTD|BROS|SONS?)\b"
GENERIC = r"\b(RUBBER|SHEET|METAL|IRON|STEEL|BRASS|FOUNDRY|FOUNDRIES|MACHINE|MACHINES|MACHINERY|SHOP|SHOPS|MACHINISTS?|TINNERS?|TANNERS?|TANNERY|ASSAY\w*|SMELT\w*|REFIN\w*|REDUCTION|SAMPLING|MILLS?|CHEMICALS?|GAS|ELECTRIC|LIGHT|OIL|SUPPLY|PLATING|WAGON|CARRIAGE|MAKERS?|DENVER|COLORADO|ROCKY|MOUNTAIN|WESTERN|AMERICAN|NATIONAL|UNION|CITY|STATE)\b"
PLACES = set(pd.read_csv('data/historical/gnis_places_co.csv').name) | {'KANSAS CITY', 'ST LOUIS', 'CHICAGO', 'NEW YORK', 'OMAHA'}
def nkey(s):
    s = re.sub(r"[^A-Z0-9& ]", " ", str(s).upper()); s = re.sub(STOP, " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    distinct = re.sub(GENERIC, " ", s).replace('&', ' ').strip()
    if s in PLACES or distinct in PLACES: return ''
    return s if len(re.sub(r"[^A-Z]", "", distinct)) >= 5 else ''     # names made only of trade/place words cannot be linked
H['nk'] = H.name.map(nkey)
def fkey(s):
    """The whole normalised name (legal-form words dropped), for firms whose name is made only of trade and place words
    (Vulcan Iron Works Co, Trinidad Sheet Metal Works): these have no distinctive key (nk == '') and used never to be merged."""
    s = re.sub(r"[^A-Z0-9& ]", " ", str(s).upper()); s = re.sub(STOP, " ", s)
    return re.sub(r"\s+", " ", s.replace('&', ' ')).strip()
H['fk'] = H.name.map(fkey)

# --- (a) historical firms: union-find on similar names within the same town
par = list(range(len(H)))
def find(i):
    while par[i] != i: par[i] = par[par[i]]; i = par[i]
    return i
for town, g in H.groupby('town'):
    idx = g.index.tolist(); nk = g.nk.tolist()
    for a in range(len(idx)):
        if len(nk[a]) < 4: continue
        for b in range(a + 1, len(idx)):
            if len(nk[b]) >= 4 and fuzz.token_sort_ratio(nk[a], nk[b]) >= 90:
                par[find(idx[a])] = find(idx[b])
# names without a distinctive key: the same whole name in the same town is one firm; so is a similar whole name at the same street-level point
for (town, k), g in H[H.nkey.fillna('').astype(str).str.len() >= 4].groupby(['town', 'nkey']):   # letter-for-letter the same printed name
    ix = g.index.tolist()
    for b in ix[1:]: par[find(b)] = find(ix[0])
for town, g in H[H.nk == ''].groupby('town'):
    for fk, gg in g[g.fk.str.len() >= 6].groupby('fk'):
        ix = gg.index.tolist()
        for b in ix[1:]: par[find(b)] = find(ix[0])
st = H[H.precision == 'street']
for (town, la, lo), g in st.groupby(['town', st.lat.round(5), st.lon.round(5)]):
    idx = g.index.tolist(); fk = g.fk.tolist()
    for a in range(len(idx)):
        for b in range(a + 1, len(idx)):
            if len(fk[a]) >= 6 and len(fk[b]) >= 6 and fuzz.token_sort_ratio(fk[a], fk[b]) >= 85: par[find(idx[a])] = find(idx[b])
H['firm'] = [find(i) for i in range(len(H))]
# --- a firm that moved is several firm-locations (scan check of 13 Nov 2026: 92 of 516 street-level firm-locations had merged
# listings at different addresses). Within a firm: street-level listings within 60 m of each other are one location; a town-level
# listing that prints an address joins the street-level location with the same printed address, or else forms a town-level
# location with the other listings printing that address (its address is not verified, so it is not placed at street level);
# a listing printing no address joins the location whose listing years lie nearest its own (the larger on a tie). The location
# holding the firm's id keeps it (a firm that did not move keeps its id); every other location is named by its lowest listing index.
def _m(la1, lo1, la2, lo2):
    return float(np.hypot((la1 - la2) * 111320, (lo1 - lo2) * 111320 * np.cos(np.radians(la1))))
def _akey(s):
    m = re.match(r"\s*(\d+)[\d\-/ ]*\s+(.+)", s) if isinstance(s, str) else None
    if not m: return ''
    nm = re.sub(r"\b(ST|STREET|AV|AVE|AVENUE|BLVD|PL|PLACE|N|S|E|W)\b", " ", m.group(2).upper())
    return m.group(1) + ' ' + re.sub(r"[^A-Z0-9]", "", nm)[:4]
H['hfirm'] = ''
for f, g in H.groupby('firm'):
    groups = []                                                         # [kind, lat, lon, {address keys}, [indices], [years]]
    for i, r in g[g.precision == 'street'].sort_values('year').iterrows():
        c = next((c for c in groups if _m(c[1], c[2], r.lat, r.lon) <= 60), None)
        if c is None: c = ['street', r.lat, r.lon, set(), [], []]; groups.append(c)
        c[3].add(_akey(r.street)); c[4].append(i); c[5].append(r.year)
    loose = []
    for i, r in g[g.precision != 'street'].iterrows():
        k = _akey(r.street)
        if not k: loose.append(i); continue
        c = next((c for c in groups if k in c[3]), None)
        if c is None: c = ['town', None, None, {k}, [], []]; groups.append(c)
        c[4].append(i); c[5].append(r.year)
    if not groups:
        H.loc[g.index, 'hfirm'] = 'HF%05d' % f; continue
    for i in loose:
        y = H.at[i, 'year']; c = min(groups, key=lambda c: (min(abs(y - v) for v in c[5]), -len(c[4])))
        c[4].append(i); c[5].append(y)
    for c in groups: H.loc[c[4], 'hfirm'] = 'HF%05d' % (f if f in c[4] else min(c[4]))

# --- (b) link to 1961-2002 directory establishments (same city, similar name) and sites (same address)
R = pd.read_pickle(os.path.join(REPO, 'work/inv/records_final.pkl'))
R = R[R.name.notna()].copy(); R['nk'] = R.name.map(nkey); R['city'] = R.city_g.fillna('').str.upper()
S = pd.read_csv(os.path.join(REPO, 'app/data/sites.csv'))
SITE_IDS = set(S.site_id)   # a name link names a site only when that site is in the published file
bycity = {c: g for c, g in R.groupby('city')}
def dist_m(la1, lo1, la2, lo2):
    return 6371000 * np.hypot(np.radians(la2 - la1), np.radians(lo2 - lo1) * np.cos(np.radians(la1)))
links = []
for f, g in H.groupby('hfirm'):
    town = g.town.iloc[0]; nk = max(g.nk, key=len)
    best = None
    if len(nk) >= 5 and town in bycity:
        C = bycity[town]
        sc = C.nk.map(lambda x: fuzz.token_sort_ratio(nk, x) if len(x) >= 5 else 0)
        if sc.max() >= 95:
            m = C[sc == sc.max()]
            best = dict(dcm_name=m.name.iloc[0], dcm_years=f"{int(m.year.min())}-{int(m.year.max())}",
                        dcm_site=next((s for s in m.site_id if isinstance(s, str) and s in SITE_IDS), ''), link='name', link_score=int(sc.max()),
                        # coordinates and level from one row, preferring an address-level geocode
                        **(lambda rr: dict(dcm_lat=rr.lat, dcm_lon=rr.lon, dcm_level=rr.geo_level) if rr is not None else dict(dcm_lat=np.nan, dcm_lon=np.nan, dcm_level=''))(
                            next((x for _, x in m.sort_values('geo_level').iterrows() if pd.notna(x.lat) and x.geo_level in ('address', 'address_approx')), None)))
    if best is None:
        st = g[g.precision == 'street']
        if len(st):
            pts = st.drop_duplicates(['lat', 'lon'])   # every street-level point the firm was listed at, not only the first
            dd = np.array([dist_m(la, lo, S.lat.values, S.lon.values) for la, lo in zip(pts.lat, pts.lon)])
            d = dd.min(axis=0); j = int(np.argmin(d))
            if d[j] <= 40:
                best = dict(dcm_name=S.hazard_firms.iloc[j][:80], dcm_years=f"{S.first_year.iloc[j]}-{S.last_year.iloc[j]}",
                            dcm_site=S.site_id.iloc[j], link='address', link_score=int(d[j]), dcm_lat=S.lat.iloc[j], dcm_lon=S.lon.iloc[j], dcm_level='address')
    links.append(dict(hfirm=f, **(best or {})))
L = pd.DataFrame(links)

# --- one row per historical firm-location
def agg(g):
    st = g[g.precision == 'street']
    r = st.iloc[0] if len(st) else g.iloc[0]
    yrs = sorted(g.year.unique())
    return pd.Series(dict(name=max(g['name'], key=lambda s: (g['name'] == s).sum() * 100 + min(len(s), 60)),
                          town=r.town, county=r.county, street=r.street if len(st) else '', lat=r.lat, lon=r.lon, precision=r.precision,
                          sectors='; '.join(sorted(g.sector.unique())), fe_hazard=bool((g.fe_group != 'EXT').any()),
                          first_year=yrs[0], last_year=yrs[-1], editions=len(yrs), years=' '.join(map(str, yrs)),
                          example=g.entry.iloc[0][:200], name_quality='ok' if (g.name_quality == 'ok').any() else 'poor',
                          review=(r.get('review', '') if len(st) and isinstance(r.get('review', ''), str) else '')))
F = H.groupby('hfirm').apply(agg, include_groups=False).reset_index().merge(L, on='hfirm', how='left')
# a town-level firm that reappears in the 1961-2002 directory keeps its town location: its later address (dcm_lat/dcm_lon) is a
# different, later place, and the pre-1960 layer places firms only at addresses printed in their own listings
F['persists_to_1961plus'] = F.link.notna()
F.to_csv('data/historical/CO_pre1960_hazardous_sites.csv', index=False)
H.to_csv('data/historical/CO_pre1960_hazardous_listings.csv', index=False)
print(len(H), 'listings ->', len(F), 'historical firm-locations')
print(F.precision.value_counts().to_string()); print(F.link.value_counts(dropna=False).to_string())
print('multi-edition firms', (F.editions > 1).sum())
print(F[F.link.notna()].sample(15, random_state=2)[['name', 'town', 'years', 'dcm_name', 'dcm_years', 'link', 'link_score']].to_string())
