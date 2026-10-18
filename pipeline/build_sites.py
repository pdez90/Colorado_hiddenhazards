"""Build historical industrial sites (Frickel & Elliott style) and compare to regulatory inventories."""
import pandas as pd, numpy as np, re, sys, collections
sys.path.insert(0,'pipeline')
from sklearn.neighbors import BallTree
from rapidfuzz import fuzz
from consolidate import norm_street, FE_MAJOR

df=pd.read_pickle('work/inv/records_linked.pkl')
# edition set: config/editions.json restricts the directory to the editions whose scans are complete (see R/edition_coverage.R)
import json, os
ED=json.load(open('config/editions.json')) if os.path.exists('config/editions.json') else {'mode':'all'}
if ED.get('mode')=='complete':
    keep=set(ED['complete_editions']); n0=len(df); df=df[df.year.isin(keep)].copy()
    print(f"edition set 'complete': {len(df)} of {n0} records kept from {len(keep)} editions {sorted(keep)}")
geo=pd.read_csv('work/geo/tiger_results.csv')
df=df.merge(geo,on='geo_key',how='left')
q=df.geo_quality.fillna('none')
df['geo_level']=np.select([q.str.contains('range_interp')&~q.str.contains('fuzzy|nearzips|trim|dirloose|sufloose|dirambig'), q.str.contains('range_interp|street_nearest'), q.eq('zip_centroid'), q.eq('city_centroid')],
                          ['address','address_approx','zip_centroid','city_centroid'],'none')
# a street printed without its direction that exists on both the plain and a directional street ('4300 LIPAN' / '4300 S LIPAN')
# is address_approx (the point may be on the wrong side of town), but when it is right it is exact, so the inventory search
# radius is not widened for it the way it is for fuzzy / neighbouring-ZIP / trimmed placements
df['placed_loose']=q.str.contains('fuzzy|nearzips|trim|dirloose|sufloose|street_nearest')
df['located']=df.geo_level.isin(['address','address_approx'])
df['hazard_any']=df.fe_hazard|df.ext_hazard

# ---- sites: cluster located records within 30 m
L=df[df.located].copy()
pts=L.drop_duplicates('geo_key')[['geo_key','lat','lon']].reset_index(drop=True)
tree=BallTree(np.radians(pts[['lat','lon']].values),metric='haversine')
nb=tree.query_radius(np.radians(pts[['lat','lon']].values),r=30/6371000.0)
parent=list(range(len(pts)))
def find(a):
    while parent[a]!=a: parent[a]=parent[parent[a]]; a=parent[a]
    return a
for i,ns in enumerate(nb):
    for j in ns:
        ri,rj=find(i),find(j)
        if ri!=rj: parent[rj]=ri
pts['site_root']=[find(i) for i in range(len(pts))]
pts['site_id']=pts.groupby('site_root').ngroup().map(lambda x:'S%05d'%x)
df=df.merge(pts[['geo_key','site_id']],on='geo_key',how='left')

def agg_site(g):
    h=g[g.hazard_any]
    yrs=sorted(g.year.unique())
    fe_secs=sorted({s for x in g.fe_sectors.dropna() for s in str(x).split('; ') if s})
    ext_secs=sorted({s for x in g.ext_sectors.dropna() for s in str(x).split('; ') if s})
    firms=g.sort_values('year').drop_duplicates('estab_id')
    hz=h.sort_values('year').drop_duplicates('estab_id')
    best=g.sort_values(['geo_level','year']).iloc[0]
    la,lo=g.lat.mean(),g.lon.mean()
    spread=float(np.max(6371000*np.hypot(np.radians(g.lat-la),np.radians(g.lon-lo)*np.cos(np.radians(la))))) if len(g) else 0.0
    return pd.Series(dict(
        lat=la, lon=lo, spread_m=spread, address=best.street_n, city=best.city_g, zip=best.zip5,
        geo_level='address' if (g.geo_level=='address').any() else 'address_approx',
        placed_loose=bool((g.placed_loose | ~g.located).all()),
        first_year=min(yrs), last_year=max(yrs), n_editions=len(yrs), years=';'.join(map(str,yrs)),
        n_establishments=firms.estab_id.nunique(), n_hazard_establishments=hz.estab_id.nunique(),
        fe_hazard=bool(g.fe_hazard.any()), ext_hazard=bool(g.ext_hazard.any()),
        fe_sectors='; '.join(fe_secs), ext_sectors='; '.join(ext_secs),
        hazard_years=';'.join(map(str,sorted(h.year.unique()))),
        hazard_firms=' | '.join(f"{r['name']} ({r['year']}{'-'+str(int(h[h.estab_id==r['estab_id']].year.max())) if h[h.estab_id==r['estab_id']].year.max()>r['year'] else ''}; SIC {','.join(r['sic'][:3])})" for _,r in hz.iterrows())[:900],
        all_firms=' | '.join(f"{r['name']} ({r['year']})" for _,r in firms.iterrows())[:900],
        earliest_est=pd.to_numeric(g.est,errors='coerce').min(),
        max_size=g['size'].dropna().astype(str).max() if g['size'].notna().any() else '',
        names_n=sorted({n for n in g.name_n if n})))   # all names, in a fixed order (a set sliced to 12 varied between runs)
sites=df[df.site_id.notna()].groupby('site_id').apply(agg_site).reset_index()

# ---- regulatory comparison
reg=pd.read_pickle('work/inv/reg.pkl')
STOP=r"\b(THE|INC|CO|CORP|CORPORATION|COMPANY|LLC|LTD|MFG|MANUFACTURING|OF|AND|DIV|DIVISION|INDUSTRIES|PRODUCTS|COLORADO|DENVER|INCORPORATED)\b"
def nn(s): s=re.sub(r"[^A-Z0-9 ]"," ",str(s).upper()); s=re.sub(STOP," ",s); return re.sub(r"\s+"," ",s).strip()
reg['nn']=reg.name.apply(nn); reg['street_n']=reg.address.fillna('').apply(norm_street); reg['zip5']=reg.zip.fillna('').astype(str).str[:5]
R=reg.dropna(subset=['lat','lon']).reset_index(drop=True)
rt=BallTree(np.radians(R[['lat','lon']].values),metric='haversine')
ind,dist=rt.query_radius(np.radians(sites[['lat','lon']].values),r=250/6371000.0,return_distance=True,sort_results=True)
addr_ix=reg.groupby(['street_n','zip5']).indices
reg['city_u']=reg.city.fillna('').astype(str).str.upper().str.strip() if 'city' in reg else ''
addr_city_ix=reg.groupby(['street_n','city_u']).indices
# polygons for containment
from shapely import wkt as _w
from shapely.geometry import Point
from shapely.strtree import STRtree
polys=reg[reg.geom_wkt.notna()] if 'geom_wkt' in reg else reg.iloc[0:0]
PG=[_w.loads(x).buffer(0.0004) for x in polys.geom_wkt]  # ~40 m buffer
ptree=STRtree(PG) if PG else None
RULES={'cleanup':75,'tri':100,'rcra_handler':40,'other_epa':40,'solid_waste':75}
out=[]
for k,(i,s) in enumerate(sites.iterrows()):
    ii,dd=ind[k],dist[k]*6371000.0
    names=[nn(x) for x in s.names_n] if isinstance(s.names_n,list) else []
    rec={}
    am=list(addr_ix.get((s.address, s.zip),[])) if s.zip else []
    if not am: am=list(addr_city_ix.get((s.address, str(s.city or '').upper().strip()),[]))     # blank ZIP: match on street + city
    am_t=collections.defaultdict(list)
    for j in am: am_t[reg.iloc[j]['tier']].append(f"{reg.iloc[j]['name']} [{reg.iloc[j]['source'].replace('EPA_','').replace('CDPHE_','CDPHE ')}]")
    inpoly=[]
    if ptree is not None:
        for j in ptree.query(Point(s.lon,s.lat)):
            if PG[j].contains(Point(s.lon,s.lat)): inpoly.append(f"{polys.iloc[j]['name']} [{polys.iloc[j]['source'].replace('CDPHE_','CDPHE ')}]")
    for tier,rad in RULES.items():
        cand=[(j,d) for j,d in zip(ii,dd) if R.at[j,'tier']==tier]
        # approximate locations get the full 250 m search radius, and every site's radius grows by the spread of its
        # member points, so a site is called 'not on any list' only when no record is near any plausible location
        r_eff=max(rad,250) if s.placed_loose else min(250,rad+s.spread_m)
        prox=[(j,d) for j,d in cand if d<=r_eff]
        nm=[(j,d) for j,d in cand if names and R.at[j,'nn'] and max(fuzz.token_set_ratio(R.at[j,'nn'],n) for n in names)>=88]
        hits=[]
        for j,d in nm: hits.append(f"{R.at[j,'name']} [{R.at[j,'source'].replace('EPA_','').replace('CDPHE_','CDPHE ')}; name match, {int(d)} m]")
        for j,d in prox:
            if j not in [x for x,_ in nm]: hits.append(f"{R.at[j,'name']} [{R.at[j,'source'].replace('EPA_','').replace('CDPHE_','CDPHE ')}; {int(d)} m]")
        hits+= [h+' (address match)' for h in am_t.get(tier,[])]
        if tier=='cleanup': hits+= [h+' (inside site boundary)' for h in inpoly]
        rec[f'{tier}_match']=' | '.join(dict.fromkeys(hits))[:400]
        rec[f'{tier}_nearest_m']=round(cand[0][1]) if cand else np.nan
        rec[f'{tier}_nearest']=R.at[cand[0][0],'name'] if cand else ''
    out.append(rec)
M=pd.DataFrame(out)
sites=pd.concat([sites.reset_index(drop=True),M],axis=1)
sites['radar_status']=np.select([sites.cleanup_match!='', sites.tri_match!='', sites.rcra_handler_match!='', sites.solid_waste_match!='', sites.other_epa_match!=''],
    ['1 Cleanup / contamination list','2 TRI reporter','3 RCRA hazardous-waste handler','4 Solid waste facility','5 Other EPA permit only'],'6 Not on any list')
df.to_pickle('work/inv/records_final.pkl'); sites.to_pickle('work/inv/sites.pkl')
H=sites[sites.fe_hazard]
print('located records',df.located.sum(),'of',len(df)); print('sites',len(sites),'F&E hazardous sites',len(H),'extended-only',int((sites.ext_hazard&~sites.fe_hazard).sum()))
print(H.radar_status.value_counts().to_string())
