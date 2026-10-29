"""Combine parsed volumes into one establishment-year table, assign SIC (observed or predicted), hazard flags.
The stages are functions (load_parsed -> assign_sic -> fix_ocr_codes -> drop_bad_hazard -> hazard_flags) so the rules
can be exercised on small frames in tests/digitization; main() runs them in that order on work/parsed."""
import json, glob, re, os, sys, collections
import pandas as pd, numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from sic_predict import predict
from rapidfuzz import fuzz

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

def load_parsed(pattern='work/parsed/*.jsonl'):
    """One row per parsed listing of every volume in VOLUMES; list columns normalised, optional columns present."""
    rows=[]
    for f in sorted(glob.glob(pattern)):
        vol=os.path.basename(f)[:-6]
        if vol not in YEAR_OF: continue
        for l in open(f):
            r=json.loads(l); r['year']=YEAR_OF[vol]; r['vol']=vol; rows.append(r)
    return prepare(pd.DataFrame(rows))

def strip_quotes(df):
    """Remove double-quote characters (OCR noise) from every text field. A CSV field that begins or ends with an
    escaped quote is misread by data.table::fread (1.14.x: a name starting with two quote characters comes back
    with four, and each fread/fwrite round trip doubles it), so quotes must never reach the exported files."""
    for c in df.columns:
        if pd.api.types.is_object_dtype(df[c]) or pd.api.types.is_string_dtype(df[c]):   # pandas 3 infers 'str' dtype
            df[c]=df[c].apply(lambda v: v.replace('"','').strip() if isinstance(v,str) else
                              ([x.replace('"','').strip() if isinstance(x,str) else x for x in v] if isinstance(v,list) else v))
    return df

def prepare(df):
    strip_quotes(df)
    for c in ['sic','sic_desc']: df[c]=df[c].apply(lambda x: x if isinstance(x,list) else [])
    for c in ['product','county_ctx','size','est','naics']:
        if c not in df: df[c]=None
    return df

def assign_sic(df):
    """SIC for records without printed codes: classifier prediction / keyword on the description, keyword on the name,
    or the NAICS->SIC map (1999, 2002). Sets sic, sic_source, sic_pred_score in place."""
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
    m=df.sic.str.len().eq(0) & df.naics.str.len().gt(0)
    df.loc[m,'sic']=df.loc[m,'naics'].apply(sic_from_naics)
    df.loc[m,'sic_source']='naics'
    return df

NX={'321114':'2491','316110':'3111','334412':'3672','334413':'3674','334419':'3679','335911':'3691','335912':'3692','325992':'3861','324121':'2951','331110':'3312'}
def sic_from_naics(L):
    out=[]
    for n in L:
        if n[:6] in NX: out.append(NX[n[:6]])
        elif n[:3] in NAICS_FE: out.append(NAICS_FE[n[:3]]+'00')
        elif n[:3]=='212': out.append('1000')
    return out

def fix_ocr_codes(df):
    """OCR digit errors in printed SIC codes: when a printed code and its printed description disagree, the code is
    one digit away from a code whose usual description matches, and that code is common, use it ('2673 NITROGENOUS
    FERTILIZERS' -> 2873; '2092 EXPLOSIVES' -> 2892; '3291 MACHINE SHOPS, JOBBING' -> 3591). Logged in sic_ocr_fix.
    Returns TITLE, the usual (modal) printed description of every code, used again by drop_bad_hazard."""
    pairs=[(i,k,c,str(d)) for i,cs,ds,src in zip(df.index,df.sic,df.sic_desc,df.sic_source) if src=='directory' and len(cs)==len(ds)
           for k,(c,d) in enumerate(zip(cs,ds)) if str(d).strip()]
    PP=pd.DataFrame(pairs,columns=['i','k','code','desc'])
    PP['dl']=PP.desc.str.lower().str.strip()
    TITLE=PP.groupby('code').dl.agg(lambda x: x.value_counts().index[0]).to_dict(); SUPPORT=PP.code.value_counts().to_dict()
    # a code printed fewer than 3 times has no 'usual' description: its title would be its own (possibly misread) line,
    # so every such code looked consistent ('2986 BOTTLED AND CANNED SOFT DRINKS' at a bottler was never corrected to
    # 2086 and counted as petroleum refining) and confirmed() below could never reject it
    TITLE={c:t for c,t in TITLE.items() if SUPPORT[c]>=3}
    pr=predict(PP.desc.tolist()); PP['pred']=[x[0] for x in pr]; PP['score']=[x[1] for x in pr]
    one=lambda a,b: len(a)==len(b)==4 and sum(x!=y for x,y in zip(a,b))==1
    PP['ok']=[fuzz.token_set_ratio(d,TITLE.get(c,''))>=60 for c,d in zip(PP.code,PP.dl)]
    PP['pred_fit']=[fuzz.token_set_ratio(d,TITLE.get(c,'')) for c,d in zip(PP.pred,PP.dl)]
    # candidate = the classifier's prediction, or else the one-digit neighbour of the printed code whose usual description fits best
    COMMON=[c for c,n in SUPPORT.items() if n>=20 and len(c)==4]
    # (only when the misread moved the code into another major group - the case that flips hazard flags - the printed code's
    # usual description clearly does not fit (<40) and the neighbour's fits closely (>=90): '3011 JEWELRY' -> 3911, '2911 MEAT PACKING' -> 2011)
    def neighbour(code,dl):
        if fuzz.token_set_ratio(dl,TITLE.get(code,''))>=40: return None
        best=None
        for c in COMMON:
            if one(code,c) and c[:2]!=code[:2]:
                f=fuzz.token_set_ratio(dl,TITLE.get(c,''))
                if f>=90 and (best is None or f>best[1]): best=(c,f)
        return best
    bad=~PP.ok & ~(np.array([one(a,b) for a,b in zip(PP.code,PP.pred)],dtype=bool) & (PP.pred_fit>=80))
    for i in PP.index[bad]:
        nb=neighbour(PP.at[i,'code'],PP.at[i,'dl'])
        if nb: PP.at[i,'pred']=nb[0]; PP.at[i,'pred_fit']=nb[1]
    FX=PP[(PP.code!=PP.pred) & ~PP.ok & (PP.pred_fit>=80) & np.array([one(a,b) for a,b in zip(PP.code,PP.pred)],dtype=bool) & (PP.pred.map(SUPPORT).fillna(0)>=20)]
    df['sic_ocr_fix']=''
    for r in FX.itertuples():
        L=list(df.at[r.i,'sic']); L[r.k]=r.pred; df.at[r.i,'sic']=L
        df.at[r.i,'sic_ocr_fix']=(df.at[r.i,'sic_ocr_fix']+f' {r.code}->{r.pred}').strip()
    print('SIC OCR corrections:',len(FX),'codes in',FX.i.nunique(),'records')
    return TITLE

haz=lambda c: c[:2] in FE_MAJOR or c in EXT_4 or c[:2]=='10'
SOFT=r"SOFTWARE|PROGRAMMING|DATA PROCESSING|COMPUTER INTEGRATED SYSTEMS"
HARD=r"HARDWARE|EQUIP|CIRCUIT|PARTS|TRANSMISSION|MANUFACTUR|TERMINAL|DEVICE|SYSTEMS? FOR"
NAMEIND={'20':r"BAKER|BAKING|BISCUIT|DAIRY|DAIRIES|CREAMERY|BOTTLING|BREW|WINERY|DISTILL|\bMEATS?\b|SAUSAGE|CANDY|CANDIES|CONFECTION|"
              r"TORTILLA|COFFEE|ICE CREAM|CHEESE|FLOUR MILL|SNACK|NOODLE|\bFOODS?\b|SEVEN.UP|COCA.COLA|PEPSI|DR\.? PEPPER|ROYAL CROWN",
         '27':r"BINDERY|PRINTING(?! INK)|PRINTERS|PUBLISHING|PUBLISHERS|NEWSPAPER|\bPRESS\b|LITHOGRAPH|GAZETTE",   # 'PRINTING INK CO' is a chemical maker (2893), not a printer
         '23':r"GARMENT|APPAREL|SPORTSWEAR|DRAPER|TAILOR"}
DESCIND={'20':r"MILK|BREAD|BAKERY|SOFT DRINK|BEVERAGE|\bMEAT|SAUSAGE|CANDY|CHEESE|ICE CREAM|TORTILLA|COFFEE|FLOUR|MALT|WINE|WINERY|BREW",
         '27':r"PRINTING|PUBLISH|NEWSPAPER",'23':r"APPAREL|GARMENT|CLOTHING"}
HAZNAME=r"CHEM|PLASTIC|METAL|MACHIN|STEEL|IRON|RUBBER|PAINT|\bOIL\b|FERTIL|AUTO|TRUCK|TRAILER|TOOL|EQUIP|FOUNDR|WELD|ENGINE"
# a printed code is kept when its own printed description confirms the hazardous activity ('2893 PRINTING INK',
# '3079 INJECTION MOLDED PLASTIC PARTS' at a printer), either by naming it or by matching the code's usual title:
# the drop rule is for codes bled in from a neighbour, whose description does not belong to the firm's trade
HAZDESC=r"\bINKS?\b|CHEMIC|PLAT|PLASTIC|METAL|MACHIN|PESTIC|FERTIL|FOUNDR|CASTING|STEEL|ALLOY|GALVANIZ|ANODIZ|COATING|RESIN|ADHESIV|SOLVENT|EXPLOSIV|RUBBER|PETROL|REFIN"

def drop_bad_hazard(df, TITLE):
    """Hazardous codes that cannot belong to the firm (logged in sic_dropped):
    (a) software: some 1980s-1999 editions file software houses under computer equipment (3573 'prepackaged software');
    (b) a predicted code that contradicts the firm's own name (a bottler predicted as a soap maker), or a code pair bled in from the neighbouring entry: the firm's name says bakery/dairy/bottler/printer etc., the record
        also carries a code of that industry, and the hazardous code is unrelated (a bakery with 'paving mixtures')."""
    def confirmed(c,d):
        return bool(re.search(HAZDESC,d)) or fuzz.token_set_ratio(d.lower(),TITLE.get(c,''))>=60
    df['sic_dropped']=''
    ANYIND='|'.join(DESCIND.values())
    for i,cs,ds,nm,src,prod in zip(df.index,df.sic,df.sic_desc,df.name,df.sic_source,df['product']):
        if not any(haz(c) for c in cs): continue
        nm=str(nm).upper(); paired=len(cs)==len(ds); keep=[]; drop=[]
        simple=not re.search(r"\d",nm) and len(nm.split())<=5 and not re.search(HAZNAME,nm)
        alltxt=(' '.join(map(str,ds))+' '+(prod if isinstance(prod,str) else '')).upper()
        # (c) a code predicted from a description that names a non-hazardous industry or software ('Winery' -> 3599)
        predbad=src=='predicted' and not re.search(r"\bCANS?\b|\bINKS?\b|MACHIN|EQUIP|CONTAINER|PRESSES|\bPLATES?\b|CHEMIC|METAL|PLASTIC|PESTIC|FERTIL",alltxt) and \
                (bool(re.search(ANYIND,alltxt)) or (bool(re.search(SOFT,alltxt)) and not re.search(HARD,alltxt)))
        for k,c in enumerate(cs):
            d=str(ds[k]).upper() if paired else ''
            bad=haz(c) and (predbad or (re.search(SOFT,d) and not re.search(HARD,d)) or
                            (simple and any(re.search(p,nm) and (src=='predicted' or any(x[:2]==s2 for x in cs) or re.search(DESCIND[s2],d)) for s2,p in NAMEIND.items())))
            if bad and src=='directory' and paired and d and not re.search(SOFT,d) and confirmed(c,d): bad=False
            (drop if bad else keep).append(c)
        if drop:
            if paired and keep: df.at[i,'sic_desc']=[d for c,d in zip(cs,ds) if c in keep]
            soft=bool(re.search(SOFT,alltxt))
            df.at[i,'sic']=keep or (['7372'] if soft else []); df.at[i,'sic_dropped']=' '.join(drop)
    print('hazardous codes dropped as software / bled-in:',(df.sic_dropped!='').sum(),'records')
    return df

def hazard_flags(df):
    """fe_hazard: any code in the F&E major groups (28-30, 33-35, 37); ext_hazard: an EXT_4 code or metal mining (10xx) without fe_hazard."""
    df['sic2']=df.sic.apply(lambda L: sorted({c[:2] for c in L}))
    df['fe_hazard']=df.sic2.apply(lambda L: any(c in FE_MAJOR for c in L))
    df['fe_sectors']=df.sic2.apply(lambda L: '; '.join(FE_MAJOR[c] for c in L if c in FE_MAJOR))
    df['ext_hazard']=df.sic.apply(lambda L: any((c in EXT_4) or c[:2]=='10' for c in L)) & ~df.fe_hazard
    df['ext_sectors']=df.sic.apply(lambda L: '; '.join(sorted({EXT_4.get(c, 'Metal mining / ore milling' if c[:2]=='10' else '') for c in L if (c in EXT_4) or c[:2]=='10'})))
    df['name_n']=df.name.apply(norm_name); df['street_n']=df.street.apply(norm_street)
    return df

def main():
    df=load_parsed()
    assign_sic(df)
    TITLE=fix_ocr_codes(df)
    drop_bad_hazard(df,TITLE)
    hazard_flags(df)
    df.to_pickle('work/inv/records.pkl')
    print(len(df),'records'); print(df.groupby('year').agg(n=('name','size'),fe=('fe_hazard','sum'),ext=('ext_hazard','sum'),zip=('zip',lambda s:(s.fillna('')!='').mean().round(2))).to_string())
    print(df.sic_source.value_counts().to_dict())
if __name__=='__main__': main()
