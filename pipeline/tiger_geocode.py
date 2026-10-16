"""Offline address-range geocoder using TIGER/Line 2023 ADDRFEAT for Colorado.
Quality levels: range_interp (number within a segment's range), street_nearest (street found, number outside ranges -> nearest segment end),
street_fuzzy_* (OCR-tolerant street name), zip_centroid, city_centroid, none."""
import geopandas as gpd, pandas as pd, numpy as np, re, glob, pickle, sys, collections
from rapidfuzz import process, fuzz
DIRS={'N':'N','S':'S','E':'E','W':'W','NORTH':'N','SOUTH':'S','EAST':'E','WEST':'W','NE':'NE','NW':'NW','SE':'SE','SW':'SW'}
TYPES={'ST':'ST','STREET':'ST','AVE':'AVE','AV':'AVE','AVENUE':'AVE','BLVD':'BLVD','BOULEVARD':'BLVD','RD':'RD','ROAD':'RD','DR':'DR','DRIVE':'DR',
 'PL':'PL','PLACE':'PL','CT':'CT','COURT':'CT','WAY':'WAY','LN':'LN','LANE':'LN','CIR':'CIR','CIRCLE':'CIR','PKWY':'PKWY','PARKWAY':'PKWY','HWY':'HWY','HIGHWAY':'HWY',
 'TER':'TER','TERRACE':'TER','TRL':'TRL','TRAIL':'TRL','LOOP':'LOOP','SQ':'SQ','ALY':'ALY','PIKE':'PIKE','EXPY':'EXPY','FWY':'FWY','RUN':'RUN','PT':'PT','XING':'XING'}
TYPES.update({'OR':'DR','ORIVE':'DR','DRIVE':'DR','SI':'ST','5T':'ST','PI':'PL','AVF':'AVE','AYE':'AVE','AVL':'AVE','BIVD':'BLVD','BLVO':'BLVD','8LVD':'BLVD','RO':'RD','R0':'RD','CI':'CT','LA':'LN'})
DIRS.update({'WE':'W','WH':'W','WW':'W','WWW':'W','HW':'W','EE':'E','SS':'S','NN':'N'})
ORD={'FIRST':'1ST','SECOND':'2ND','THIRD':'3RD','FOURTH':'4TH','FIFTH':'5TH','SIXTH':'6TH','SEVENTH':'7TH','EIGHTH':'8TH','NINTH':'9TH','TENTH':'10TH'}
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
    if tk and len(tk[0])<=6 and sum(c.isdigit() for c in tk[0])>=max(1,len(tk[0])-2) and not re.search(r'(ST|ND|RD|TH)$',tk[0]):
        tk[0]=tk[0].translate(str.maketrans('OQDCcIlLSBZGo','0000011159260')); s=' '.join(tk)
    m=re.match(r'^(\d+)[A-Z]?(?:\s*1/2)?\s+(.*)$',s)
    if not m: return None,None,'',''
    num=int(m.group(1)); rest=m.group(2)
    rest=re.split(r'\b(STE|SUITE|UNIT|NO|APT|BLDG|#|FL|RM)\b',rest)[0]
    pre,core,suf=parse_name(rest)
    return num,core,pre,suf

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
    pickle.dump(dict(G=pd.DataFrame(G),idx=dict(idx),cores={k:sorted(v) for k,v in cores.items()}),open('work/inv/tiger_index.pkl','wb'))
    print('segments',len(G),'keys',len(idx))

def interp(coords,t):
    d=np.r_[0,np.cumsum(np.hypot(*np.diff(coords,axis=0).T))]
    if d[-1]==0: return coords[0]
    x=t*d[-1]; k=np.searchsorted(d,x)-1; k=min(max(k,0),len(d)-2)
    f=(x-d[k])/max(d[k+1]-d[k],1e-12); return coords[k]+f*(coords[k+1]-coords[k])

class Geocoder:
    def __init__(self, max_km=15):
        self.max_km=max_km
        D=pickle.load(open('work/inv/tiger_index.pkl','rb'))
        self.G=D['G']; self.idx=D['idx']; self.cores=D['cores']
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
    def place(self,ids,num,pre,suf,strict=True):
        """strict: the segment's prefix direction must equal the address's (both may be blank).
        Non-strict also lets an address without a direction match a directional segment and vice versa."""
        G=self.G; best=None
        for i in ids:
            r=G.iloc[i]
            if strict and (r.pre or '')!=(pre or ''): continue
            if pre and r.pre and r.pre!=pre: continue
            for side,(a,b) in (('L',(r.LFROMHN,r.LTOHN)),('R',(r.RFROMHN,r.RTOHN))):
                if pd.isna(a) or pd.isna(b): continue
                lo,hi=min(a,b),max(a,b)
                if lo<=num<=hi:
                    score=(0 if (not suf or r.suf==suf) else 1)+(0 if (num%2)==(a%2) else 0.5)
                    t=0.5 if a==b else (num-a)/(b-a)
                    if best is None or score<best[0]: best=(score,interp(r.coords,t),'range_interp')
        if best: return best[1],best[2]
        # nearest by number
        bd=None
        for i in ids:
            r=self.G.iloc[i]
            if strict and (r.pre or '')!=(pre or ''): continue
            if pre and r.pre and r.pre!=pre: continue
            for a,b in ((r.LFROMHN,r.LTOHN),(r.RFROMHN,r.RTOHN)):
                for v,t in ((a,0),(b,1)):
                    if pd.isna(v): continue
                    dd=abs(v-num)
                    if bd is None or dd<bd[0]: bd=(dd,interp(r.coords,t))
        if bd and bd[0]<=300: return bd[1],'street_nearest'
        return None,None
    def geocode(self,street,city,zip5):
        num,core,pre,suf=parse_addr(street)
        zip5=zip5 if isinstance(zip5,str) and re.match(r'^8[01]\d{3}$',zip5 or '') else ''
        city=(city or '').upper().strip()
        zips=[zip5] if zip5 else []
        cz=self.city_zips.get(city) or (self.city_zips.get(self.zip_city.get(zip5,'')) if zip5 else None) or []
        nb=[z for z in (self.nbr.get(zip5,[]) if zip5 else []) if z not in cz]
        variants=[]
        if core:
            toks=core.split()
            for k in range(len(toks),0,-1):
                c2=' '.join(toks[:k]); variants.append(c2)
                if len(variants)>=3: break
        # reference point for a sanity check: the stated city's ZIP centroids (or the stated ZIP's)
        refz=[self.zcent[z] for z in (cz or zips) if z in self.zcent]
        ref=tuple(np.median(np.array(refz),axis=0)) if refz else None
        def far(pt):
            if ref is None: return False
            dk=6371*np.hypot(np.radians(pt[1]-ref[0]),np.radians(pt[0]-ref[1])*np.cos(np.radians(ref[0])))
            return dk>self.max_km
        for strict in (True,False):                 # exact direction first (S BROADWAY never lands on BROADWAY)
          for vi,core in enumerate(variants if num is not None else []):
            for zs,tag in ((zips,''),([z for z in cz if z not in zips],'_cityzips'),(nb,'_nearzips')):
                if not zs: continue
                lt='' if strict else '_dirloose'
                ids=self.cands(zs,core)
                if ids:
                    pt,q=self.place(ids,num,pre,suf,strict)
                    if pt is not None and not far(pt): return pt[1],pt[0],q+tag+('_trim' if vi else '')+lt
                # fuzzy core within these zips
                allc=sorted({c for z in zs for c in self.cores.get(z,[])})
                if allc:
                    m=process.extractOne(core,allc,scorer=fuzz.ratio,score_cutoff=86)
                    if m:
                        pt,q=self.place(self.cands(zs,m[0]),num,pre,suf,strict)
                        if pt is not None and not far(pt): return pt[1],pt[0],'fuzzy_'+q+tag+('_trim' if vi else '')+lt
        if zip5 and zip5 in self.zcent: la,lo=self.zcent[zip5]; return la,lo,'zip_centroid'
        if cz:
            pts=[self.zcent[z] for z in cz if z in self.zcent]
            if pts: a=np.array(pts); return float(np.median(a[:,0])),float(np.median(a[:,1])),'city_centroid'
        return None,None,'none'

if __name__=='__main__':
    if sys.argv[1]=='build': build()
