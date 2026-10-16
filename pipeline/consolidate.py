"""Combine parsed volumes into one establishment-year table, assign SIC (observed or predicted), hazard flags."""
import json, glob, re, os, sys, collections
import pandas as pd
sys.path.insert(0, os.path.dirname(__file__))
from sic_predict import predict

from volumes import VOLUMES
YEAR_OF = {v: y for v, (y, _, _) in VOLUMES.items()}

FE_MAJOR = {'28':'Chemicals','29':'Petroleum refining','30':'Rubber & plastics','33':'Primary metals','34':'Fabricated metals','35':'Industrial machinery','37':'Transportation equipment'}
EXT_4 = {'2491':'Wood preserving','3111':'Leather tanning','3671':'Electronic tubes','3672':'Printed circuit boards','3674':'Semiconductors',
         '3679':'Electronic components','3691':'Storage batteries','3692':'Primary batteries','3861':'Photographic equipment/chemicals',
         '2951':'Asphalt paving mixtures','3312':'Blast furnaces & coke'}
EXT_2 = {'10':'Metal mining / ore milling','36':None}
NAICS_FE = {'325':'28','324':'29','326':'30','331':'33','332':'34','333':'35','336':'37'}
KW = [(r"\bREFIN(ERY|ING)\b",'2911'),(r"\bSMELT",'3339'),(r"\bFOUNDR",'3369'),(r"\bPLATING|ELECTROPLAT|ANODIZ",'3471'),
      (r"\bTANN(ERY|ING)\b",'3111'),(r"CREOSOT|WOOD PRESERV|TIE TREAT|TREATED (POLES|TIMBER|LUMBER)",'2491'),
      (r"\bBATTER(Y|IES)\b",'3691'),(r"\bURANIUM|VANADIUM|\bORE\b|CONCENTRAT|REDUCTION WORKS|MILL(ING)? (ORE|CUSTOM)",'1099'),
      (r"\bASPHALT\b",'2951'),(r"\bPAINTS?\b|VARNISH|LACQUER",'2851'),(r"FERTILIZ",'2873'),(r"EXPLOSIV|POWDER CO",'2892'),
      (r"\bCOKE\b",'3312'),(r"INSECTICID|PESTICID|HERBICID|AGRICULTURAL CHEM",'2879'),(r"\bCHEMICAL",'2899'),
      (r"\bPLASTIC",'3079'),(r"\bRUBBER\b",'3069'),(r"MACHINE SHOP|MACHINE WORK|MACHINING",'3599'),(r"SHEET METAL",'3444'),
      (r"STRUCTURAL STEEL|ORNAMENTAL IRON|IRON WORKS",'3441'),(r"\bGALVANIZ",'3479'),(r"\bOIL\b.*\bREFIN|PETROLEUM PROD",'2911')]

def kw_sic(t):
    u=(t or '').upper()
    for pat,c in KW:
        if re.search(pat,u): return c
    return None

def norm_name(s):
    s=(s or '').upper()
    s=re.sub(r"[^A-Z0-9 &]"," ",s)
    s=re.sub(r"\b(THE|INC|INCORPORATED|CO|COMPANY|CORP|CORPORATION|LTD|LLC|MFG|MANUFACTURING|OF|AND|&)\b"," ",s)
    return re.sub(r"\s+"," ",s).strip()
def norm_street(s):
    s=(s or '').upper()
    s=re.sub(r"[^A-Z0-9 ]"," ",s)
    rep={'STREET':'ST','AVENUE':'AVE','AV':'AVE','BOULEVARD':'BLVD','ROAD':'RD','DRIVE':'DR','PLACE':'PL','COURT':'CT','NORTH':'N','SOUTH':'S','EAST':'E','WEST':'W','HIGHWAY':'HWY','PARKWAY':'PKWY','CIRCLE':'CIR','LANE':'LN'}
    s=' '.join(rep.get(t,t) for t in s.split())
    return s.strip()

def main():
    rows=[]
    for f in sorted(glob.glob('work/parsed/*.jsonl')):
        vol=os.path.basename(f)[:-6]
        if vol not in YEAR_OF: continue
        for l in open(f):
            r=json.loads(l); r['year']=YEAR_OF[vol]; r['vol']=vol; rows.append(r)
    df=pd.DataFrame(rows)
    for c in ['sic','sic_desc']: df[c]=df[c].apply(lambda x: x if isinstance(x,list) else [])
    for c in ['product','county_ctx','size','est','naics']:
        if c not in df: df[c]=None
    # predicted SIC for records lacking codes but with descriptions
    need=df[(df.sic.str.len()==0)]
    texts=[]; idx=[]
    for i,r in need.iterrows():
        t=r['product'] if isinstance(r['product'],str) and r['product'] else (r['sic_desc'][0] if r['sic_desc'] else '')
        if not t and isinstance(r.get('extra'),list):
            ex=[x for x in r['extra'] if not re.search(r"\b(PRES|OWNR|OWNER|MGR|PTNR|SEC|TREAS|VP|V P|SUPT|DIR)\W*$",x.upper()) and not re.search(r"\d{3}-\d{4}|BOX",x.upper()) and re.search(r"[A-Z]{4}",x.upper())]
            if ex: t=ex[-1]
        if t: texts.append(t); idx.append(i)
    df['sic_source']=df.sic.apply(lambda x:'directory' if x else '')
    df['sic_pred_score']=None
    if texts:
        P=predict(texts)
        for i,t,(c,sc,_) in zip(idx,texts,P):
            k=kw_sic(t)
            if k and (sc<0.6 or k[:2]!=c[:2]):
                df.at[i,'sic']=[k]; df.at[i,'sic_source']='keyword'
            elif sc>=0.45:
                df.at[i,'sic']=[c]; df.at[i,'sic_source']='predicted'; df.at[i,'sic_pred_score']=round(float(sc),2)
    # keyword fallback on name when still nothing
    for i,r in df[df.sic.str.len()==0].iterrows():
        k=kw_sic(r['name'])
        if k: df.at[i,'sic']=[k]; df.at[i,'sic_source']='name_keyword'
    if 'naics' not in df: df['naics']=None
    df['naics']=df.naics.apply(lambda x: x if isinstance(x,list) else [])
    NX={'321114':'2491','316110':'3111','334412':'3672','334413':'3674','334419':'3679','335911':'3691','335912':'3692','325992':'3861','324121':'2951','331110':'3312'}
    def sic_from_naics(L):
        out=[]
        for n in L:
            if n[:6] in NX: out.append(NX[n[:6]])
            elif n[:3] in NAICS_FE: out.append(NAICS_FE[n[:3]]+'00')
            elif n[:3]=='212': out.append('1000')
        return out
    m=df.sic.str.len().eq(0) & df.naics.str.len().gt(0)
    df.loc[m,'sic']=df.loc[m,'naics'].apply(sic_from_naics)
    df.loc[m,'sic_source']='naics'
    df['sic2']=df.sic.apply(lambda L: sorted({c[:2] for c in L}))
    df['fe_hazard']=df.sic2.apply(lambda L: any(c in FE_MAJOR for c in L))
    df['fe_sectors']=df.sic2.apply(lambda L: '; '.join(FE_MAJOR[c] for c in L if c in FE_MAJOR))
    df['ext_hazard']=df.sic.apply(lambda L: any((c in EXT_4) or c[:2]=='10' for c in L)) & ~df.fe_hazard
    df['ext_sectors']=df.sic.apply(lambda L: '; '.join(sorted({EXT_4.get(c, 'Metal mining / ore milling' if c[:2]=='10' else '') for c in L if (c in EXT_4) or c[:2]=='10'})))
    df['name_n']=df.name.apply(norm_name); df['street_n']=df.street.apply(norm_street)
    df.to_pickle('work/inv/records.pkl')
    print(len(df),'records'); print(df.groupby('year').agg(n=('name','size'),fe=('fe_hazard','sum'),ext=('ext_hazard','sum'),zip=('zip',lambda s:(s.fillna('')!='').mean().round(2))).to_string())
    print(df.sic_source.value_counts().to_dict())
if __name__=='__main__': main()
