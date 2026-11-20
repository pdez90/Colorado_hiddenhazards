"""Build historical industrial sites (Frickel & Elliott style) and compare to regulatory inventories.
The rules (geocode level, site clustering with the across-the-street parity rule, name matching, match basis, radar status) are
module-level functions so that tests/geocoding can exercise them on synthetic data; the pipeline run is under __main__."""
import pandas as pd, numpy as np, re, sys, collections, os
sys.path.insert(0,'pipeline'); sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from sklearn.neighbors import BallTree
from rapidfuzz import fuzz
from tiger_geocode import parse_addr
def hav(lat1,lon1,lat2,lon2):
    a=np.radians([lat1,lon1,lat2,lon2]); d=np.sin((a[2]-a[0])/2)**2+np.cos(a[0])*np.cos(a[2])*np.sin((a[3]-a[1])/2)**2
    return 2*6371000.0*np.arcsin(np.sqrt(d))

def addr_key(street_n):
    """'230 YUMA ST STE 4' -> '230 YUMA'; '1145 S 5TH AVE' -> '1145 S 5TH': house number, direction and street name, without the street
    type or a unit, so that a directory address (which rarely prints the type) keys to the same string as an inventory address."""
    num,core,pre,suf=parse_addr(str(street_n or ''))
    if num is None: return str(street_n or '').strip()
    return ' '.join(x for x in (str(num),pre,core) if x)

def loose_key(street_n):
    """House number and street name only, without direction, type or unit: '6330 N WASHINGTON' and '6330 WASHINGTON ST STE 1' both give
    '6330 WASHINGTON'. Used only for records within 250 m of the site's point (19 Nov 2026), where a direction printed on one side only
    cannot point to the other half of the grid."""
    num,core,pre,suf=parse_addr(str(street_n or ''))
    return f"{num} {core}" if num is not None and core else ''

def norm_street(s):
    from consolidate import norm_street as _ns   # consolidate -> sic_predict loads work/inv/sic_clf.pkl at import; keep it out of import time
    return _ns(s)

def geo_level(q):
    """Geocode quality code -> level. A street printed without its direction that exists on both the plain and a directional street
    ('4300 LIPAN' / '4300 S LIPAN') and whose ZIP/town cannot say which (_dirambig) is not placed: it keeps its street point but counts
    as zip_centroid. Resolved cases (_dirzip by the ZIP's side of the Denver grid, _dirtype by the printed street type) are exact; a
    glued direction letter split off the street name (_dirsplit) is approximate."""
    q=pd.Series(q).fillna('none').astype(str)
    return np.select([q.str.contains('dirambig'), q.str.contains('range_interp')&~q.str.contains('fuzzy|nearzips|trim|dirloose|sufloose|dirsplit'),
                      q.str.contains('range_interp|street_nearest'), q.eq('zip_centroid'), q.eq('city_centroid')],
                     ['zip_centroid','address','address_approx','zip_centroid','city_centroid'],'none')
def placed_loose(q):
    return pd.Series(q).fillna('none').astype(str).str.contains('fuzzy|nearzips|trim|dirloose|sufloose|street_nearest').values

# ---- sites: cluster located records within 30 m. Points sit 12 m off the street centre-line on their own side, so the two sides of a
# street are 24 m apart; two points on the same street with odd and even numbers (opposite sides) are never linked directly.
SITE_M=30.0
def cluster_sites(pts,radius_m=SITE_M):
    """pts: DataFrame with lat, lon, street_n (one row per geocoded point). Returns site ids ('S00000', ...) aligned with pts.index:
    connected components of points within radius_m, with the across-the-street parity rule (union-find, deterministic)."""
    pts=pts.reset_index(drop=True)
    _p=[parse_addr(s) for s in pts.street_n]
    num=[a[0] for a in _p]; base=[(a[2]+' '+str(a[1])).strip() for a in _p]
    if not len(pts): return pd.Series([],dtype=object)
    tree=BallTree(np.radians(pts[['lat','lon']].values),metric='haversine')
    nb=tree.query_radius(np.radians(pts[['lat','lon']].values),r=radius_m/6371000.0)
    parent=list(range(len(pts)))
    def find(a):
        while parent[a]!=a: parent[a]=parent[parent[a]]; a=parent[a]
        return a
    def across_street(i,j):
        return base[i]==base[j] and num[i] is not None and num[j] is not None and (int(num[i])%2)!=(int(num[j])%2)
    for i,ns in enumerate(nb):
        for j in ns:
            if across_street(i,j): continue
            ri,rj=find(i),find(j)
            if ri!=rj: parent[rj]=ri
    root=pd.Series([find(i) for i in range(len(pts))])
    return root.groupby(root).ngroup().map(lambda x:'S%05d'%x)

def spread_m(lat,lon):
    """Largest distance of a site's member points from their mean (metres, equirectangular as in the pipeline)."""
    lat=np.asarray(lat,dtype=float); lon=np.asarray(lon,dtype=float)
    if not len(lat): return 0.0
    la,lo=lat.mean(),lon.mean()
    return float(np.max(6371000*np.hypot(np.radians(lat-la),np.radians(lon-lo)*np.cos(np.radians(la)))))

def agg_site(g):
    h=g[g.hazard_any]
    yrs=sorted(g.year.unique())
    fe_secs=sorted({s for x in g.fe_sectors.dropna() for s in str(x).split('; ') if s})
    ext_secs=sorted({s for x in g.ext_sectors.dropna() for s in str(x).split('; ') if s})
    firms=g.sort_values('year').drop_duplicates('estab_id')
    hz=h.sort_values('year').drop_duplicates('estab_id')
    best=g.sort_values(['geo_level','year']).iloc[0]
    la,lo=g.lat.mean(),g.lon.mean()
    spread=spread_m(g.lat,g.lon) if len(g) else 0.0
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
        # names for the inventory name match: the hazardous firms' names only (a retailer or office that later shared the address
        # must not make the site 'known' through its own RCRA notification); a site without a hazardous firm keeps all names.
        # Fixed order (a set sliced to 12 varied between runs)
        names_n=sorted({n for n in (h.name_n if len(h) else g.name_n) if n})))

# ---- regulatory comparison
# words that carry no identity: legal forms, generic trade words and Colorado place names (two-word names first, so 'COLORADO SPRINGS'
# goes before 'COLORADO' can match alone). Identical to STOP in R/build_sites.R.
STOP=(r"\b(GRAND JUNCTION|FORT COLLINS|COLORADO SPRINGS|THE|INC|CO|CORP|CORPORATION|COMPANY|LLC|LTD|MFG|MANUFACTURING|OF|AND|DIV|DIVISION|INCORPORATED"
      r"|INDUSTRIES|SYSTEMS|PRODUCTS|CASTINGS|PRECISION|ENTERPRISES|SERVICES|SUPPLY"
      r"|COLORADO|DENVER|AURORA|BOULDER|PUEBLO|MONTROSE|ENGLEWOOD|LITTLETON|GOLDEN|LAKEWOOD|ARVADA|WESTMINSTER|LONGMONT|LOVELAND|GREELEY)\b")
def nn(s): s=re.sub(r"[^A-Z0-9 ]"," ",str(s).upper()); s=re.sub(STOP," ",s); return re.sub(r"\s+"," ",s).strip()
def name_match(a,b):
    """Same firm? token_set_ratio scores 100 whenever one token set is a subset of the other, so one shared word ('CRYSTAL', 'SERUM')
    used to match. A match now needs either (a) token_set_ratio >= 88 AND at least two shared informative tokens, or (b) token_sort_ratio
    >= 88 (the whole names agree up to word order and OCR noise). Identical to name_match() in R/build_sites.R."""
    if not a or not b: return False
    if fuzz.token_sort_ratio(a,b)>=88: return True
    return fuzz.token_set_ratio(a,b)>=88 and len(set(a.split())&set(b.split()))>=2
RULES={'cleanup':75,'tri':100,'rcra_handler':40,'other_epa':40,'solid_waste':75}
BASIS=['same entity (name or address)','inside a cleanup boundary','nearby record only','none']
def match_basis(b): return BASIS[0] if 'entity' in b else BASIS[1] if 'boundary' in b else BASIS[2] if 'prox' in b else BASIS[3]
RADAR=[(c+'_match',l) for c,l in (('cleanup','1 Cleanup / contamination list'),('tri','2 TRI reporter'),('rcra_handler','3 RCRA hazardous-waste handler'),
                                 ('solid_waste','4 Solid waste facility'),('other_epa','5 Other EPA permit only'))]
def radar_status(M):
    """Best inventory tier with any hit (cleanup > TRI > RCRA handler > solid waste > other EPA), else '6 Not on any list'."""
    return np.select([M[c]!='' for c,_ in RADAR],[l for _,l in RADAR],'6 Not on any list')

def match_inventory(sites,reg,review_path='data/raw/known_match_review.csv'):
    """One row per site: per-tier hits, nearest record, and match_basis. sites: lat, lon, spread_m, address (normalised street), zip,
    city, names_n (list of normalised firm names). reg: name, source, tier, lat, lon, address, zip, city, optional geom_wkt."""
    from shapely import wkt as _w
    from shapely.geometry import Point
    from shapely.strtree import STRtree
    reg=reg.copy()
    reg['nn']=reg.name.apply(nn); reg['street_n']=reg.address.fillna('').apply(norm_street); reg['zip5']=reg.zip.fillna('').astype(str).str[:5]
    # the address key drops the street type and any unit: directories print '230 YUMA', the inventories '230 YUMA ST' / '230 YUMA ST STE 4'
    reg['akey']=reg.street_n.apply(addr_key)
    R=reg.dropna(subset=['lat','lon']).reset_index(drop=True)
    if len(R):
        rt=BallTree(np.radians(R[['lat','lon']].values),metric='haversine')
        ind,dist=rt.query_radius(np.radians(sites[['lat','lon']].values),r=250/6371000.0,return_distance=True,sort_results=True)
    else: ind=[np.array([],dtype=int)]*len(sites); dist=[np.array([])]*len(sites)
    addr_ix=reg.groupby(['akey','zip5']).indices
    reg['city_u']=reg.city.fillna('').astype(str).str.upper().str.strip() if 'city' in reg else ''
    addr_city_ix=reg.groupby(['akey','city_u']).indices
    # the same street address written differently: another ZIP or town name (a directory's 'GOLDEN' for an inventory's 'WHEAT RIDGE',
    # 'AURORA' for 'COMMERCE CITY'), or the N/S/E/W printed on one side only; accepted when the record's point is within 250 m (19 Nov 2026)
    reg['lkey']=reg.street_n.apply(loose_key)
    loose_ix=reg.groupby('lkey').indices; loose_ix.pop('',None)   # positions in reg, as for addr_ix
    # records printed without a usable point (no coordinates, or (0,0) / outside Colorado) can still be the same firm: they are matched
    # by name within the site's ZIP or town, with the same name rule as the 250 m search (FINDING 3 of 12 Nov 2026; 20 Nov 2026)
    _np=reg[reg.lat.isna() & (reg.nn!='')]
    nopt_zip=_np.groupby('zip5').indices if len(_np) else {}; nopt_city=_np.groupby('city_u').indices if len(_np) else {}
    _np_pos=np.flatnonzero((reg.lat.isna() & (reg.nn!='')).values)
    reviewed=collections.defaultdict(list)
    if review_path and os.path.exists(review_path) and 'src_id' in reg:
        rv=pd.read_csv(review_path,dtype=str,keep_default_na=False); rv=rv[rv.verdict=='same']
        pos={(a,str(b)):j for j,(a,b) in enumerate(zip(reg.source,reg.src_id))}
        for k,c,a,b in zip(rv.site_akey,rv.site_city,rv.reg_source,rv.reg_src_id):
            if (a,b) in pos: reviewed[(k,c.upper().strip())].append(pos[(a,b)])
    # polygons for containment
    polys=reg[reg.geom_wkt.notna()] if 'geom_wkt' in reg else reg.iloc[0:0]
    # polygons and site points in metres (UTM 13N): a site counts as inside a cleanup boundary only when its point is inside the
    # polygon; a point within 40 m of a boundary (geocoding error, or the firm's lot next to the mapped one) counts as a nearby record
    from pyproj import Transformer; from shapely.ops import transform as _tf
    _to_utm=Transformer.from_crs('EPSG:4326','EPSG:26913',always_xy=True).transform
    PG=[_tf(_to_utm,_w.loads(x)) for x in polys.geom_wkt]
    ptree=STRtree(PG) if PG else None
    NEAR_BOUNDARY_M=40
    out=[]
    for k,(i,s) in enumerate(sites.iterrows()):
        ii,dd=ind[k],dist[k]*6371000.0
        names=[nn(x) for x in s.names_n] if isinstance(s.names_n,list) else []
        rec={}
        ak=addr_key(s.address)
        am=list(addr_ix.get((ak, s.zip),[])) if s.zip else []
        if not am:   # blank ZIP: match on street + city
            am=list(addr_city_ix.get((ak, str(s.city or '').upper().strip()),[]))
        # either way, only a record within 250 m (or without a point): the key drops the street type, so '230 DOVER DR' and '230 DOVER RD'
        # share it, and an undirected Denver address ('450 KALAMATH') would otherwise claim a record on the other half of the grid
        am=[j for j in am if pd.isna(reg.lat.iat[j]) or hav(s.lat,s.lon,reg.lat.iat[j],reg.lon.iat[j])<=250]
        lk=loose_key(s.address)
        if lk: am+= [j for j in loose_ix.get(lk,[]) if j not in am and pd.notna(reg.lat.iat[j]) and hav(s.lat,s.lon,reg.lat.iat[j],reg.lon.iat[j])<=250]
        # author-reviewed matches (data/raw/known_match_review.csv): the same firm at the same address whose inventory point lies beyond
        # 250 m of ours, or whose name or address is spelled too differently for the rules; found by a search out to 400 m, 18 Nov 2026
        am+= [j for j in reviewed.get((ak, str(s.city or '').upper().strip()),[]) if j not in am]
        am_t=collections.defaultdict(list)
        for j in am: am_t[reg.iloc[j]['tier']].append(f"{reg.iloc[j]['name']} [{reg.iloc[j]['source'].replace('EPA_','').replace('CDPHE_','CDPHE ')}]")
        npm=set()
        if names:
            for loc in list(nopt_zip.get(s.zip,[]) if s.zip else [])+(list(nopt_city.get(str(s.city or '').upper().strip(),[])) if str(s.city or '').strip() else []):
                j=_np_pos[loc]
                if j not in am and any(name_match(reg.nn.iat[j],n) for n in names): npm.add(j)
        np_t=collections.defaultdict(list)
        for j in sorted(npm): np_t[reg.iloc[j]['tier']].append(f"{reg.iloc[j]['name']} [{reg.iloc[j]['source'].replace('EPA_','').replace('CDPHE_','CDPHE ')}]")
        inpoly=[]; nearpoly=[]   # (label, distance m) for boundaries within NEAR_BOUNDARY_M but not containing the point
        if ptree is not None:
            pu=_tf(_to_utm,Point(s.lon,s.lat))
            for j in ptree.query(pu.buffer(NEAR_BOUNDARY_M)):
                lab=f"{polys.iloc[j]['name']} [{polys.iloc[j]['source'].replace('CDPHE_','CDPHE ')}]"
                if PG[j].contains(pu): inpoly.append(lab)
                else:
                    dm=PG[j].distance(pu)
                    if dm<=NEAR_BOUNDARY_M: nearpoly.append((lab,dm))
        basis=set()   # evidence behind every hit, over all tiers: 'entity' (name or address), 'boundary', 'prox'
        for tier,rad in RULES.items():
            cand=[(j,d) for j,d in zip(ii,dd) if R.at[j,'tier']==tier]
            # every site's search radius grows by the spread of its member points, so a site is called 'not on any list' only when no
            # record is near any plausible location. Approximately located sites (fuzzy street, neighbouring ZIP, trimmed number, nearest
            # segment end) used to get the full 250 m radius for this proximity test; that did not make their point any more accurate, it
            # only let any inventory record in the neighbourhood (a pharmacy's or supermarket's RCRA notification, a car wash's permit)
            # make the site 'known'. The true record of such a firm is still found by name or address, which do not depend on the point,
            # so the base radii now apply to every site.
            r_eff=min(250,rad+s.spread_m)
            prox=[(j,d) for j,d in cand if d<=r_eff]
            nm=[(j,d) for j,d in cand if names and R.at[j,'nn'] and any(name_match(R.at[j,'nn'],n) for n in names)]
            hits=[]
            for j,d in nm: hits.append(f"{R.at[j,'name']} [{R.at[j,'source'].replace('EPA_','').replace('CDPHE_','CDPHE ')}; name match, {int(d)} m]")
            for j,d in prox:
                if j not in [x for x,_ in nm]: hits.append(f"{R.at[j,'name']} [{R.at[j,'source'].replace('EPA_','').replace('CDPHE_','CDPHE ')}; {int(d)} m]")
            hits+= [h+' (address match)' for h in am_t.get(tier,[])]
            hits+= [h+' (name match in the same town; record has no map point)' for h in np_t.get(tier,[])]
            if tier=='cleanup': hits+= [h+' (inside site boundary)' for h in inpoly]+[f"{h}; {int(dm)} m from site boundary" for h,dm in nearpoly]
            if nm or am_t.get(tier) or np_t.get(tier): basis.add('entity')
            if tier=='cleanup' and inpoly: basis.add('boundary')
            if prox or (tier=='cleanup' and nearpoly): basis.add('prox')
            # per-tier evidence for the sensitivity analysis (R/known_hidden_sensitivity.R): strongest basis in this tier and the
            # distance to the nearest differently named record inside the tier's radius (a boundary within 40 m counts at its distance)
            nm_ids={x for x,_ in nm}; pd_other=[d for j,d in prox if j not in nm_ids]+([dm for _,dm in nearpoly] if tier=='cleanup' else [])
            rec[f'{tier}_basis']=('entity' if (nm or am_t.get(tier) or np_t.get(tier)) else 'boundary' if (tier=='cleanup' and inpoly) else 'prox' if pd_other else '')
            rec[f'{tier}_prox_m']=round(min(pd_other)) if pd_other else np.nan
            rec[f'{tier}_match']=' | '.join(dict.fromkeys(hits))[:400]
            rec[f'{tier}_nearest_m']=round(cand[0][1]) if cand else np.nan
            rec[f'{tier}_nearest']=R.at[cand[0][0],'name'] if cand else ''
        # what the site's inventory match rests on, strongest evidence first. 'nearby record only' = a differently named record within the
        # tier's radius and nothing else: the site counts as 'known' (radar) but the record may belong to another occupant of the block.
        rec['match_basis']=match_basis(basis)
        out.append(rec)
    M=pd.DataFrame(out,index=sites.index)
    M['radar_status']=radar_status(M)
    return M

def twin_keys(df):
    """A misread street number leaves a listing unlocated while the same establishment is located in other editions ('12280 W 90TH PL'
    for '12280 W 50TH PL'). Returns {row label: geo_key of the located listing} for unlocated listings whose street differs from a
    located listing of the same establishment and town in exactly one digit (same words, same number of digits), where that digit is
    not the last one of a number: a last-digit difference changes the side of the street (450 / 451) or the premises next door (450 /
    452), so it is not treated as a misreading. A listing left unplaced because its direction is ambiguous (dirambig) is never moved.
    Several candidate addresses: the one with the most listings, then the smallest key. Identical to twin_keys() in R/build_sites.R."""
    alpha=lambda x: re.sub(r'\d','#',str(x)); digits=lambda x: re.sub(r'\D','',str(x))
    def one_inner(a,b):     # same digit layout; exactly one digit differs, and it is not the last digit of its number
        if alpha(a)!=alpha(b): return False
        da,db=digits(a),digits(b)
        if len(da)!=len(db): return False
        k=[i for i,(x,y) in enumerate(zip(da,db)) if x!=y]
        if len(k)!=1: return False
        ends=set(); n=-1
        for m in re.finditer(r'\d+',str(a)): n+=len(m.group()); ends.add(n)
        return k[0] not in ends
    out={}
    d=df[df.estab_id.notna()&df.street_n.notna()&(df.street_n!='')]; d=d.assign(city_g=d.city_g.fillna(''))
    amb=df.geo_quality.fillna('').str.contains('dirambig')
    for _,g in d.groupby('estab_id',sort=False):
        if g.located.all() or not g.located.any(): continue
        L=g[g.located]
        for i,r in g[~g.located].iterrows():
            if amb.at[i] or not digits(r.street_n): continue
            c=collections.Counter(q.geo_key for q in L.itertuples() if q.city_g==r.city_g and one_inner(r.street_n,q.street_n))
            if c: out[i]=min(c,key=lambda k:(-c[k],k))
    return out

def main():
    df=pd.read_pickle('work/inv/records_linked.pkl')
    # edition set: config/editions.json restricts the directory to the editions whose scans are complete (see R/edition_coverage.R)
    import json
    ED=json.load(open('config/editions.json')) if os.path.exists('config/editions.json') else {'mode':'all'}
    if ED.get('mode')=='complete':
        keep=set(ED['complete_editions']); n0=len(df); df=df[df.year.isin(keep)].copy()
        print(f"edition set 'complete': {len(df)} of {n0} records kept from {len(keep)} editions {sorted(keep)}")
    geo=pd.read_csv('work/geo/tiger_results.csv')
    df=df.merge(geo,on='geo_key',how='left')
    df['geo_level']=geo_level(df.geo_quality)
    df['placed_loose']=placed_loose(df.geo_quality)
    df['located']=df.geo_level.isin(['address','address_approx'])
    tw=twin_keys(df)
    if tw:      # the listing takes the located twin's address key, and with it the point (geo_twin marks it; the street stays as read)
        df['geo_twin']=df.index.isin(list(tw)); df.loc[list(tw),'geo_key']=list(tw.values())
        df=df.drop(columns=[c for c in geo.columns if c!='geo_key']+['geo_level','placed_loose','located']).merge(geo,on='geo_key',how='left')
        df['geo_level']=geo_level(df.geo_quality); df['placed_loose']=placed_loose(df.geo_quality); df['located']=df.geo_level.isin(['address','address_approx'])
    else: df['geo_twin']=False
    print('listings placed at the address of the same establishment one digit away:',len(tw))
    df['hazard_any']=df.fe_hazard|df.ext_hazard
    L=df[df.located].copy()
    pts=L.drop_duplicates('geo_key')[['geo_key','lat','lon','street_n']].reset_index(drop=True)
    pts['site_id']=cluster_sites(pts).values
    df=df.merge(pts[['geo_key','site_id']],on='geo_key',how='left')
    sites=df[df.site_id.notna()].groupby('site_id').apply(agg_site).reset_index()
    reg=pd.read_pickle('work/inv/reg.pkl')
    M=match_inventory(sites,reg)
    sites=pd.concat([sites.reset_index(drop=True),M.reset_index(drop=True)],axis=1)
    df.to_pickle('work/inv/records_final.pkl'); sites.to_pickle('work/inv/sites.pkl')
    H=sites[sites.fe_hazard]
    print('located records',df.located.sum(),'of',len(df)); print('sites',len(sites),'F&E hazardous sites',len(H),'extended-only',int((sites.ext_hazard&~sites.fe_hazard).sum()))
    print(H.radar_status.value_counts().to_string())
    print(pd.crosstab(H.radar_status,H.match_basis).to_string())

if __name__=='__main__': main()
