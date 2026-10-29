"""Offline address-range geocoder using TIGER/Line 2023 ADDRFEAT for Colorado.
Quality levels: range_interp (number within a segment's range), street_nearest (street found, number outside ranges -> nearest segment end),
fuzzy_* (OCR-tolerant street name), zip_centroid, city_centroid, none.
Suffixes: _sufloose (street type disagrees), _dirambig (address printed without a direction; the number exists on both the plain and a
directional street and the ZIP/town cannot say which half: not placed), _dirzip (that ambiguity resolved by the ZIP's or town's side of the
Denver grid), _dirsplit (a direction letter glued to the street name, 'SBANNOCK', split off), _cityzips / _nearzips (found in another ZIP of
the town / a ZIP within 12 km), _trim (trailing or leading junk token dropped), _dirloose (direction-free second pass).
Points are offset 12 m from the street centre-line toward the side (left/right of the from->to direction) whose range held the number."""
import geopandas as gpd, pandas as pd, numpy as np, re, glob, pickle, sys, collections
from rapidfuzz import process, fuzz
DIRS={'N':'N','S':'S','E':'E','W':'W','NORTH':'N','SOUTH':'S','EAST':'E','WEST':'W','NE':'NE','NW':'NW','SE':'SE','SW':'SW'}
TYPES={'ST':'ST','STREET':'ST','AVE':'AVE','AV':'AVE','AVENUE':'AVE','BLVD':'BLVD','BOULEVARD':'BLVD','RD':'RD','ROAD':'RD','DR':'DR','DRIVE':'DR',
 'PL':'PL','PLACE':'PL','CT':'CT','COURT':'CT','WAY':'WAY','LN':'LN','LANE':'LN','CIR':'CIR','CIRCLE':'CIR','PKWY':'PKWY','PARKWAY':'PKWY','HWY':'HWY','HIGHWAY':'HWY',
 'TER':'TER','TERRACE':'TER','TRL':'TRL','TRAIL':'TRL','LOOP':'LOOP','SQ':'SQ','ALY':'ALY','PIKE':'PIKE','EXPY':'EXPY','FWY':'FWY','RUN':'RUN','PT':'PT','XING':'XING'}
TYPES.update({'OR':'DR','ORIVE':'DR','DRIVE':'DR','SI':'ST','5T':'ST','PI':'PL','AVF':'AVE','AYE':'AVE','AVL':'AVE','BIVD':'BLVD','BLVO':'BLVD','8LVD':'BLVD','RO':'RD','R0':'RD','CI':'CT','LA':'LN'})
DIRS.update({'WE':'W','WH':'W','WW':'W','WWW':'W','HW':'W','EE':'E','SS':'S','NN':'N','SO':'S','NO':'N','S0':'S','N0':'N'})   # 'So. Broadway', 'No. 5th'
ORD={'FIRST':'1ST','SECOND':'2ND','THIRD':'3RD','FOURTH':'4TH','FIFTH':'5TH','SIXTH':'6TH','SEVENTH':'7TH','EIGHTH':'8TH','NINTH':'9TH','TENTH':'10TH'}
OFFSET_M=12.0                      # distance of the point from the street centre-line, toward the matched side
ELLS,BWAY=39.7163,-104.9875        # Denver grid baselines: Ellsworth Ave (N/S house numbers), Broadway (E/W)
GRID_KM=40                         # the Denver grid is only tested for ZIPs within this distance of the baselines' crossing
GRID_CORE_KM=25                    # within this distance every street is on the grid (downtown ZIPs have too few prefixed streets to test)
def ordfix(t):
    m=re.match(r'^(\d+)(ST|ND|RD|TH)?$',t)
    if m and m.group(2) is None and len(t)<=3:
        n=int(t); suf='TH' if 10<=n%100<=20 else {1:'ST',2:'ND',3:'RD'}.get(n%10,'TH'); return f'{n}{suf}'
    return ORD.get(t,t)
def parse_name(s):
    toks=re.sub(r'[^A-Z0-9 ]',' ',str(s).upper()).split()
    pre=suf=post=''
    if toks and toks[0] in DIRS and len(toks)>1: pre=DIRS[toks.pop(0)]
    if toks and toks[-1] in DIRS and len(toks)>1: post=DIRS[toks.pop()]
    if toks and toks[-1] in TYPES and len(toks)>1: suf=TYPES[toks.pop()]
    toks=[ordfix(re.sub(r'^(\d+)N0$',r'\1ND',re.sub(r'^(\d+)(5T|SI)$',r'\1ST',t))) for t in toks]
    return pre,' '.join(toks),suf
def parse_addr(s):
    s=str(s).upper().strip()
    tk=s.split(' ',1)
    # OCR letters in the house number (O->0, S->5 ...); not interstates (I70), not a direction letter glued to the number ('1731S WADSWORTH')
    if tk and len(tk[0])<=6 and sum(c.isdigit() for c in tk[0])>=max(1,len(tk[0])-2) and not re.search(r'(ST|ND|RD|TH)$',tk[0]) \
            and not re.match(r'^I\d+$',tk[0]) and not (re.match(r'^\d+[NSEW]$',tk[0]) and len(tk)>1 and tk[1].split(' ',1)[0] not in DIRS):
        tk[0]=tk[0].translate(str.maketrans('OQDCcIlLSBZGo','0000011158260')); s=' '.join(tk)
    # house number, an optional range end ('125-7'), an optional glued direction letter ('123N MAIN' = 123 N MAIN; any other glued
    # letter is a unit, '1234A'), an optional 1/2
    m=re.match(r'^(\d+)(?:-\d+)?([NSEW])?[A-Z]?(?:\s*1/2)?\s+(.*)$',s)
    if not m: return None,None,'',''
    num=int(m.group(1)); rest=m.group(3)
    if m.group(2) and rest.split(' ',1)[0] not in DIRS: rest=m.group(2)+' '+rest
    # unit markers; 'NO' only when a number that is not an ordinal follows ('BROADWAY NO 5', 'AVE NO 21'), so that 'NO 5TH ST' keeps its direction
    rest=re.split(r'(?:\b(?:STE|SUITE|UNIT|APT|BLDG|FL|RM)\b|\bNO\b(?=\s*\d+(?!\d*(?:ST|ND|RD|TH)\b))|#)',rest)[0]
    # a bare number after the street type is a unit ('2505 W 2ND AVE 7'); roads and highways keep their numbers
    rest=re.sub(r'\b(ST|STREET|AVE|AV|AVENUE|BLVD|BOULEVARD|DR|DRIVE|PL|PLACE|CT|COURT|WAY|LN|LANE|CIR|CIRCLE|PKWY|PARKWAY|TER|TERRACE)\s+\d+[A-Z]?\s*$',r'\1',rest.strip())
    pre,core,suf=parse_name(rest)
    return num,core,pre,suf

def seg_mid(coords):
    return coords[len(coords)//2]
def grid_info(G):
    """Denver-grid ZIPs and the half of the grid each lies in, from TIGER alone: a ZIP is on the Denver grid when its segments lie within
    GRID_KM of the Ellsworth/Broadway crossing and at least 95% of its direction-prefixed segments agree with the baselines (S south of
    Ellsworth, N north, E east of Broadway, W west), with at least 5 such segments on an axis. half[(zip, 'NS')] is 'N' or 'S' when at
    least 80% of the ZIP's segments (50 or more) lie on one side of Ellsworth; half[(zip, 'EW')] likewise for Broadway. (80223 and 80219
    reach a few blocks north of Ellsworth: 86-87% south.)"""
    rows=[]
    for r in G.itertuples():
        m=seg_mid(r.coords)
        for z in {r.ZIPL,r.ZIPR}:
            if isinstance(z,str) and z: rows.append((z,r.pre,m[1],m[0]))
    D=pd.DataFrame(rows,columns=['z','pre','lat','lon'])
    D['dk']=6371*np.hypot(np.radians(D.lat-ELLS),np.radians(D.lon-BWAY)*np.cos(np.radians(ELLS)))
    D['south']=D.lat<ELLS; D['east']=D.lon>BWAY
    gridzips=set(); half={}
    for z,g in D.groupby('z'):
        if g.dk.median()>GRID_KM: continue
        ns=g[g.pre.isin(['N','S'])]; ew=g[g.pre.isin(['E','W'])]
        ok_ns=len(ns)>=5 and (((ns.pre=='S')==ns.south).mean()>=0.95)
        ok_ew=len(ew)>=5 and (((ew.pre=='E')==ew.east).mean()>=0.95)
        if not (ok_ns or ok_ew): continue
        gridzips.add(z)
        if len(g)<50: continue
        s=g.south.mean(); e=g.east.mean()
        if s>=0.8: half[(z,'NS')]='S'
        elif s<=0.2: half[(z,'NS')]='N'
        if e>=0.8: half[(z,'EW')]='E'
        elif e<=0.2: half[(z,'EW')]='W'
    return gridzips,half

def build():
    rows=[]
    for f in sorted(glob.glob('work/tiger/*_addrfeat.shp')):
        g=gpd.read_file(f,columns=['FULLNAME','LFROMHN','LTOHN','RFROMHN','RTOHN','ZIPL','ZIPR'])
        g=g.to_crs(4326); rows.append(g)
    G=pd.concat(rows,ignore_index=True)
    G=G[G.FULLNAME.notna()].reset_index(drop=True)
    P=G.FULLNAME.apply(parse_name)
    G['pre']=[p[0] for p in P]; G['core']=[p[1] for p in P]; G['suf']=[p[2] for p in P]
    for c in ['LFROMHN','LTOHN','RFROMHN','RTOHN']: G[c]=pd.to_numeric(G[c].astype(str).str.replace(r'\D','',regex=True),errors='coerce')
    G['coords']=G.geometry.apply(lambda ge: np.array(ge.coords) if ge.geom_type=='LineString' else np.vstack([np.array(x.coords) for x in ge.geoms]))
    G=G.drop(columns='geometry')
    idx=collections.defaultdict(list)
    for i,r in enumerate(G.itertuples()):
        for z in {r.ZIPL,r.ZIPR}:
            if isinstance(z,str) and z: idx[(z,r.core)].append(i)
    cores=collections.defaultdict(set)
    for (z,c) in idx: cores[z].add(c)
    gridzips,half=grid_info(G)
    pickle.dump(dict(G=pd.DataFrame(G),idx=dict(idx),cores={k:sorted(v) for k,v in cores.items()},gridzips=gridzips,half=half),open('work/inv/tiger_index.pkl','wb'))
    print('segments',len(G),'keys',len(idx),'Denver-grid ZIPs',len(gridzips),'with a known half',len({z for z,_ in half}))

def interp(coords,t,side=''):
    """Point at fraction t along the segment; with side 'L'/'R' it is moved OFFSET_M metres to the left/right of the from->to direction."""
    c=np.cos(np.radians(coords[0,1]))
    dx=np.diff(coords,axis=0); d=np.r_[0,np.cumsum(np.hypot(dx[:,0]*c,dx[:,1]))]
    if d[-1]==0: return coords[0]
    x=t*d[-1]; k=np.searchsorted(d,x)-1; k=min(max(k,0),len(d)-2)
    f=(x-d[k])/max(d[k+1]-d[k],1e-12); p=coords[k]+f*(coords[k+1]-coords[k])
    if side in ('L','R'):
        ex,ey=dx[k,0]*c,dx[k,1]; n=np.hypot(ex,ey)
        if n>0:
            s=OFFSET_M/(n*111320.0)*(1 if side=='L' else -1)       # left of travel is (-ey, ex)
            p=p+np.array([-ey*s/c,ex*s])
    return p

class Geocoder:
    def __init__(self, max_km=15):
        self.max_km=max_km
        D=pickle.load(open('work/inv/tiger_index.pkl','rb'))
        self.G=D['G']; self.idx=D['idx']; self.cores=D['cores']; self.gridzips=D.get('gridzips',set()); self.half=D.get('half',{})
        zc=pd.read_csv('work/inv/zip_city.csv',dtype=str)
        self.city_zips=zc.groupby('CITY_NAME').z.apply(list).to_dict()
        self.zip_city=dict(zip(zc.z,zc.CITY_NAME))
        z=pd.read_pickle('work/inv/zip_centroids.pkl'); self.zcent={r.zip5:(r.zlat,r.zlon) for r in z.itertuples()}
        zz=list(self.zcent); A=np.radians(np.array([self.zcent[k] for k in zz]))
        self.nbr={}
        for i,k in enumerate(zz):
            d=6371*np.arccos(np.clip(np.sin(A[i,0])*np.sin(A[:,0])+np.cos(A[i,0])*np.cos(A[:,0])*np.cos(A[:,1]-A[i,1]),-1,1))
            self.nbr[k]=[zz[j] for j in np.argsort(d) if d[j]<12 and zz[j]!=k]
    def cands(self,zips,core):
        out=[]
        for z in zips: out+=self.idx.get((z,core),[])
        return out
    def grid_conflict(self,r,pre):
        """A prefixed address may use an unprefixed segment only when that segment lies on the prefix's side of the Denver grid:
        '4483 N WASHINGTON' may land on Washington St north of Ellsworth, '4000 S KALAMATH' never on Kalamath St (13 km north).
        The grid applies to segments in a Denver-grid ZIP or within GRID_CORE_KM of the baselines' crossing."""
        if not (pre and not r.pre): return False
        m=seg_mid(r.coords); d=pre[0]
        if not ((r.ZIPL in self.gridzips) or (r.ZIPR in self.gridzips)
                or 6371*np.hypot(np.radians(m[1]-ELLS),np.radians(m[0]-BWAY)*np.cos(np.radians(ELLS)))<GRID_CORE_KM): return False
        return (d=='S' and m[1]>ELLS) or (d=='N' and m[1]<ELLS) or (d=='W' and m[0]>BWAY) or (d=='E' and m[0]<BWAY)
    def place(self,ids,num,pre,suf,strict=True):
        """strict: the segment's prefix direction must equal the address's (both may be blank).
        Non-strict also lets an address without a direction match a directional segment and vice versa (see grid_conflict).
        Returns (point, quality, prefix and type of the matched segment)."""
        G=self.G; best=None
        for i in ids:
            r=G.iloc[i]
            if pre and r.pre and r.pre!=pre: continue
            if strict and (r.pre or '')!=(pre or ''): continue
            if self.grid_conflict(r,pre): continue
            for side,(a,b) in (('L',(r.LFROMHN,r.LTOHN)),('R',(r.RFROMHN,r.RTOHN))):
                if pd.isna(a) or pd.isna(b): continue
                lo,hi=min(a,b),max(a,b)
                if lo<=num<=hi:
                    sufbad=bool(suf and r.suf and r.suf!=suf)
                    score=(1 if sufbad else 0)+(0 if (num%2)==(a%2) else 0.5)
                    t=0.5 if a==b else (num-a)/(b-a)
                    if best is None or score<best[0]: best=(score,interp(r.coords,t,side),'range_interp'+('_sufloose' if sufbad else ''),r.pre or '',r.suf or '')
        if best: return best[1],best[2],best[3],best[4]
        # nearest by number
        bd=None
        for i in ids:
            r=self.G.iloc[i]
            if strict and (r.pre or '')!=(pre or ''): continue
            if pre and r.pre and r.pre!=pre: continue
            if self.grid_conflict(r,pre): continue
            for side,(a,b) in (('L',(r.LFROMHN,r.LTOHN)),('R',(r.RFROMHN,r.RTOHN))):
                for v,t in ((a,0),(b,1)):
                    if pd.isna(v): continue
                    dd=abs(v-num)
                    if bd is None or dd<bd[0]: bd=(dd,interp(r.coords,t,side),r.pre or '',r.suf or '')
        if bd and bd[0]<=300: return bd[1],'street_nearest',bd[2],bd[3]
        return None,None,'',''
    def geocode(self,street,city,zip5):
        num,core,pre,suf=parse_addr(street)
        zip5=zip5 if isinstance(zip5,str) and re.match(r'^8[01]\d{3}$',zip5 or '') else ''
        city=(city or '').upper().strip()
        zips=[zip5] if zip5 else []
        cz=self.city_zips.get(city) or (self.city_zips.get(self.zip_city.get(zip5,'')) if zip5 else None) or []
        # neighbouring ZIPs (12 km): of the printed ZIP, or, when none is printed, of the town's ZIPs
        if zip5: nb=[z for z in self.nbr.get(zip5,[]) if z not in cz]
        else: nb=list(dict.fromkeys(n for z in cz for n in self.nbr.get(z,[]) if n not in cz))
        variants=[]
        if core:
            toks=core.split()
            variants.append(core)
            # a leading one-character token, or a one-digit ordinal in front of a street name when no direction was read ('2150 5 KALAMATH':
            # the S read as 5), is junk: drop it first, and never trim such a name down to the bare ordinal ('5TH' would be 5th Avenue)
            junk=bool(len(toks)>1 and (len(toks[0])==1 or (not pre and re.match(r'^\d(ST|ND|RD|TH)$',toks[0]) and re.match(r'^[A-Z]{4,}',toks[1]))))
            if junk: variants.append(' '.join(toks[1:]))
            for k in range(len(toks)-1,0,-1):
                c2=' '.join(toks[:k])
                if c2 in variants or (k==1 and junk): continue
                variants.append(c2)
            variants=variants[:3]
        # reference point for a sanity check: the stated city's ZIP centroids (or the stated ZIP's)
        refz=[self.zcent[z] for z in (cz or zips) if z in self.zcent]
        ref=tuple(np.median(np.array(refz),axis=0)) if refz else None
        # a big town's outer ZIPs lie more than max_km from that median (Denver's 80249 is 25 km out), so a point is also accepted
        # when it is within max_km of the printed ZIP's own centroid
        zref=self.zcent.get(zip5) if zip5 else None
        def far(pt):
            if ref is None: return False
            def dk(r): return 6371*np.hypot(np.radians(pt[1]-r[0]),np.radians(pt[0]-r[1])*np.cos(np.radians(r[0])))
            return dk(ref)>self.max_km and (zref is None or dk(zref)>self.max_km)
        allzs=sorted(set(zips)|set(cz)|{n for z in (zips or cz) for n in self.nbr.get(z,[])})
        def holders(zs,core):
            # {prefix ('' = plain): street types} of the versions of this street that hold this number within ZIPs zs
            out=collections.defaultdict(set)
            for i in self.cands(zs,core):
                r=self.G.iloc[i]
                for a,b in ((r.LFROMHN,r.LTOHN),(r.RFROMHN,r.RTOHN)):
                    if pd.notna(a) and pd.notna(b) and min(a,b)<=num<=max(a,b): out[r.pre or ''].add(r.suf or '')
            return out
        def zip_half(axis):
            # the side of the Denver grid the printed ZIP lies on; failing that, the town's, when all its ZIPs with a known side agree
            if zip5: return self.half.get((zip5,axis),'')
            hs={self.half[(z,axis)] for z in cz if (z,axis) in self.half}
            return hs.pop() if len(hs)==1 else ''
        def move_to(core,d):
            # the same number on the version of the street with prefix d, anywhere in the town or its neighbouring ZIPs
            p2,q2,_,_=self.place(self.cands(allzs,core),num,d,suf,True)
            return (p2,q2) if (p2 is not None and q2.startswith('range_interp') and not far(p2)) else (None,None)
        def resolve(pt,q,core,msuf):
            """The address, printed without a direction, matched the plain street (type msuf) while a directional version of the street also
            holds the number ('4300 LIPAN' / '4300 S LIPAN'). Decide: by the printed street type when the two versions are different streets
            (24th St vs E 24th Ave: _dirtype); otherwise by the printed ZIP's own ranges, then by the ZIP's (or town's) half of the Denver
            grid (_dirzip). Returns the point (moved to the directional street when that is the answer) and the quality; _dirambig when
            nothing decides."""
            allh=holders(allzs,core); dirs=sorted(d for d in allh if d)
            if not dirs: return pt,q
            move=lambda d: move_to(core,d)
            # different street types: the printed type decides; with none printed, Denver's avenues carry E/W, so plain means the street
            if all(allh[d] and msuf not in allh[d] for d in dirs):
                if suf and suf!=msuf:
                    for d in dirs:
                        if suf in allh[d]:
                            p2,q2=move(d)
                            if p2 is not None and q2=='range_interp': return p2,q2+'_dirtype'
                return pt,q+'_dirtype'
            if zips:                                             # the printed ZIP's own ranges: which version holds the number there?
                own=holders(zips,core); od=sorted(d for d in own if d)
                if '' in own and not od: return pt,q+'_dirzip'
                if len(od)==1 and '' not in own:
                    p2,q2=move(od[0])
                    if p2 is not None and (q2=='range_interp' or q2==q): return p2,q2+'_dirzip'
            decided=None
            for d in dirs:
                axis='NS' if d in ('N','S') else 'EW'
                h=zip_half(axis)
                if not h: continue
                if h==d:                                         # the ZIP is on the directional street's side: use it
                    p2,q2=move(d)
                    if p2 is not None and (q2=='range_interp' or q2==q): return p2,q2+'_dirzip'
                    decided=False
                else: decided=True                               # the ZIP is on the plain street's side
            return pt,q+('_dirzip' if decided else '_dirambig')
        def try_place(ids,core_used,pre2,strict,tagq):
            pt,q,mpre,msuf=self.place(ids,num,pre2,suf,strict)
            if pt is None or far(pt): return None
            # plain street matched (or, the number being outside its ranges, its nearest end); a directional version may hold the number:
            # '450 KALAMATH' in 80223, where Kalamath St reaches a few blocks north of Ellsworth but 450 is on S Kalamath St
            if not pre2 and (q.startswith('range_interp') or q=='street_nearest') and mpre=='':
                pt,q=resolve(pt,q,core_used,msuf)
            elif not pre2 and q.startswith('range_interp') and mpre:     # direction-free pass put a plain address on a directional street:
                dirs=sorted(d for d in holders(allzs,core_used) if d)       # if the opposite direction holds the number too, the ZIP decides
                if len(dirs)>1:
                    h=zip_half('NS' if mpre[0] in ('N','S') else 'EW')
                    if h and h in dirs:
                        if h!=mpre:
                            p2,q2=move_to(core_used,h)
                            if p2 is not None: pt,q=p2,q2
                        q+='_dirzip'
                    else: q+='_dirambig'
            return pt[1],pt[0],tagq(q)
        for strict in (True,False):                 # exact direction first (S BROADWAY never lands on BROADWAY)
          for vi,core in enumerate(variants if num is not None else []):
            for zs,tag in ((zips,''),([z for z in cz if z not in zips],'_cityzips'),(nb,'_nearzips')):
                if not zs: continue
                lt='' if strict else '_dirloose'
                sfx=tag+('_trim' if vi else '')+lt
                ids=self.cands(zs,core)
                if ids:
                    res=try_place(ids,core,pre,strict,lambda q: q+sfx)
                    if res: return res
                # a direction letter glued to the name ('SBANNOCK' for 'S BANNOCK'): split it off when the rest is a known street here
                if not ids and not pre and len(core)>3 and core[0] in ('N','S','E','W') and core[1]!=' ':
                    ids2=self.cands(zs,core[1:])
                    if ids2:
                        res=try_place(ids2,core[1:],core[0],strict,lambda q: q+'_dirsplit'+sfx)
                        if res: return res
                # fuzzy core within these zips
                allc=sorted({c for z in zs for c in self.cores.get(z,[])})
                if allc:
                    dg=re.findall(r'\d+',core)
                    allc_d=[c for c in allc if re.findall(r'\d+',c)==dg]
                    m=process.extractOne(core,allc_d,scorer=fuzz.ratio,score_cutoff=86) if allc_d else None
                    if m:
                        pre2=pre
                        if not pre and m[0]==core[1:] and core[0] in ('N','S','E','W'): pre2=core[0]   # the 'misread' letter was the direction
                        res=try_place(self.cands(zs,m[0]),m[0],pre2,strict,lambda q: 'fuzzy_'+q+sfx)
                        if res: return res
        if zip5 and zip5 in self.zcent: la,lo=self.zcent[zip5]; return la,lo,'zip_centroid'
        if cz:
            pts=[self.zcent[z] for z in cz if z in self.zcent]
            if pts: a=np.array(pts); return float(np.median(a[:,0])),float(np.median(a[:,1])),'city_centroid'
        return None,None,'none'

if __name__=='__main__':
    if sys.argv[1]=='build': build()
