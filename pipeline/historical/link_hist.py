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
H['hfirm'] = ['HF%05d' % find(i) for i in range(len(H))]

# --- (b) link to 1961-2002 directory establishments (same city, similar name) and sites (same address)
R = pd.read_pickle(os.path.join(REPO, 'work/inv/records_final.pkl'))
R = R[R.name.notna()].copy(); R['nk'] = R.name.map(nkey); R['city'] = R.city_g.fillna('').str.upper()
S = pd.read_csv(os.path.join(REPO, 'app/data/sites.csv'))
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
                        dcm_site=next((s for s in m.site_id if isinstance(s, str)), ''), link='name', link_score=int(sc.max()),
                        dcm_lat=m.lat.dropna().iloc[0] if m.lat.notna().any() else np.nan,
                        dcm_lon=m.lon.dropna().iloc[0] if m.lon.notna().any() else np.nan,
                        dcm_level=m.geo_level.dropna().iloc[0] if m.geo_level.notna().any() else '')
    if best is None:
        st = g[g.precision == 'street']
        if len(st):
            d = dist_m(st.lat.iloc[0], st.lon.iloc[0], S.lat.values, S.lon.values)
            j = int(np.argmin(d))
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
                          example=g.entry.iloc[0][:200], name_quality='ok' if (g.name_quality == 'ok').any() else 'poor'))
F = H.groupby('hfirm').apply(agg, include_groups=False).reset_index().merge(L, on='hfirm', how='left')
# if the firm reappears in the 1961-2002 directory at an address, use that more precise location
use = (F.precision == 'town') & F.dcm_level.eq('address') & F.dcm_lat.notna()
F.loc[use, ['lat', 'lon']] = F.loc[use, ['dcm_lat', 'dcm_lon']].values
F.loc[use, 'precision'] = 'street (via later directory)'
F['persists_to_1961plus'] = F.link.notna()
F.to_csv('data/historical/CO_pre1960_hazardous_sites.csv', index=False)
H.to_csv('data/historical/CO_pre1960_hazardous_listings.csv', index=False)
print(len(H), 'listings ->', len(F), 'historical firm-locations')
print(F.precision.value_counts().to_string()); print(F.link.value_counts(dropna=False).to_string())
print('multi-edition firms', (F.editions > 1).sum())
print(F[F.link.notna()].sample(15, random_state=2)[['name', 'town', 'years', 'dcm_name', 'dcm_years', 'link', 'link_score']].to_string())
