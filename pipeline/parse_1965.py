"""1965 format, two columns per page:

    COUNTY                       <- heading at the column's left margin
    TOWN                         <- heading at the column's left margin
    2042 E1 NAME OF FIRM         <- record line at the left margin: SIC code, employment class E0-E5, name
         street or locality      <- indented by ~130 px

The layout, not the wording, tells the three kinds of line apart (review 4, findings E2/E3):
* a line at the left margin that does not start with a code is a heading, whether or not the OCR spelt the town right
  ('BOLLDER', 'COLCRACO SPRINGS', 'CURANGO'): it is matched to the gazetteer with an OCR-tolerant comparison, and a
  heading that matches nothing is kept as printed (BURNS, GILMAN, ROCKY FLATS are real places missing from the
  gazetteer). Before, an unreadable heading left the previous town in force: 107 Colorado Springs firms were filed
  under AIR FORCE ACADEMY, 101 Boulder firms under ALLENSPARK, Durango under LA PLATA (the county).
* an indented line is a street / locality line, never a record ('2354 E. PIKES PEAK AVE' was read as code 2354, class
  E, firm 'PIKES PEAK AVE') and never a heading ('WOODLAND PARK' as the address of a Colorado Springs firm).
* the running title at the top of the page ('58 BENT-BOULDER', 'EL PASO 79') names counties and sets nothing.
The printed code is returned as read (sic, when the four characters normalise to digits) together with the raw
characters (sic_raw); consolidate.validate_bare_codes checks it against the codes the directory uses."""
import re, sys, os, glob, json
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from segment import page_lines
from geoctx import heading, COUNTIES
from parse_block import norm_digits, city_heading, fix_street, CITIES, STREETWORD
from rapidfuzz import fuzz, process

# strict record line (used to locate the left margin): four code characters, E + class digit, name
HEAD = re.compile(r"^\W{0,3}([0-9OIlSBZ$€£]{4})\s+[E€£]\s?([0-9OIlS]?)\W?\s+(.+)$")
ECODE = {'0':'0-19','1':'1-19','2':'20-99','3':'100-249','4':'250-999','5':'1000+'}
INDENT = 60      # px to the right of the margin from which a line is an address line (streets sit at +130, records within +-20)
CODECH = r"0-9A-Za-z$€£@&%é"

def fix_dir(s):
    s=re.sub(r"\b(h|hk|Ww|w|W|H)\.?(?=\s)", "W", s)
    return s

def split_record(t):
    """(raw code, raw class token, name) when the line reads 'code class NAME' through OCR noise, else None.
    '2C42 El NATIONAL ALFALFA', '3€11 Eo BOULDER NUCLEAR', '2354 —l OUT WEST TENT', '3444-E1 FUNNELL SHEET METAL',
    'x! 2051 E E2 RAINBO BAKERS', '_.24$9 £1 COLSON SIGN CO.'"""
    s=re.sub(r"^[^0-9A-Za-z$€£]*(?:[A-Za-z!]{1,2}[!\.]?\s+(?=\S{4,}))?","",t.strip())      # leading specks: 'x! ', 'C '
    m=re.match(rf"^[_\.]*([{CODECH}]{{4,5}})[_\W]{{0,3}}(?:\s+|-+)([E€£]\s[E€£]?[0-9A-Za-z]|\S{{1,3}})\s+(\S.{{2,}})$",s)
    if not m: return None
    code,cls,name=m.group(1),m.group(2),m.group(3)
    m2=re.match(r"^([E€£][lL1I0-5])\s+(\S.{2,})$",name)
    if m2 and not re.match(r"^[E€£]",cls): cls,name=m2.group(1),m2.group(2)     # a speck between code and class: '2026 h El REED*S DAIRY'
    digits=sum(ch.isdigit() for ch in code); norm=norm_digits(code)
    codeish = digits>=2 and sum(ch.isdigit() for ch in norm)>=len(norm)-1
    strict_cls = bool(re.match(r"^[E€£]\W?\s?[E€£]?[0-5OoIlL]$",cls))
    if not ((codeish and len(re.sub(r"\W","",cls))<=3) or (strict_cls and digits>=1)): return None
    if not re.search(r"[A-Za-z]{2}",name): return None
    # number + direction + street is an address ('2354 E. PIKES PEAK AVE', '8885 W. 14TH AVE', '2930 h. 32ND'), not a code,
    # a class and a firm called PIKES PEAK AVE: the token after the number is not a class (E + digit) and what follows
    # is a street
    street = re.search(r"\b(AVE|AVENUE|ST|STREET|BLVD|RD|ROAD|DR|DRIVE|WAY|PL|PLACE|HWY)\.?\W*$",name.upper()) or re.match(r"^\d{1,3}(ST|ND|RD|TH)\b",name.upper())
    if street and not strict_cls and len(name.split())<=4 and not re.search(r"\d",cls): return None
    if re.match(r"^[NnSsWwh]\.?$",cls): return None       # N. / S. / W. is a direction, never a class ('1020 S. TEJON')
    return code,cls,name

def class_of(cls):
    d=norm_digits(re.sub(r"\W","",cls)[-1:]) if re.sub(r"\W","",cls) else ''
    return ECODE.get(d,'') if re.match(r"^\W*[E€£e\-—=]",cls) or len(re.sub(r"\W","",cls))==2 else ''

def margins(L):
    """Left margin of each column as a function of y (the scans are slightly rotated: up to 50 px down a page):
    {col: (slope, intercept)} fitted through the strict record lines, or the 20th percentile of x when there are few."""
    out={}
    for c in sorted({l['col'] for l in L}):
        P=[(l['y'],l['x']) for l in L if l['col']==c and HEAD.match(l['text'].strip())]
        if len(P)>=6:
            y=np.array([p[0] for p in P],float); x=np.array([p[1] for p in P],float)
            a,b=np.polyfit(y,x,1); r=x-(a*y+b); keep=np.abs(r)<=max(15,2*np.median(np.abs(r)))
            if keep.sum()>=6: a,b=np.polyfit(y[keep],x[keep],1)
            if abs(a)>0.06: a,b=0.0,float(np.median(x))
            out[c]=(float(a),float(b))
        else:
            xs=[l['x'] for l in L if l['col']==c and len(l['text'].strip())>=6]
            out[c]=(0.0,float(np.percentile(xs,20)) if xs else 0.0)
    return out

# letters this scan's OCR confuses, mapped to one representative: D, O, G, Q are read as C ('CEAVER', 'FCRT CCLLINS',
# 'CECARECGE'), U as L ('BOLLDER'), H as F ('FAMILTON')
SKEL=str.maketrans('CDGQULHF','OOOOLLFF'.replace('L','L'))
SKEL=str.maketrans({'C':'O','D':'O','G':'O','Q':'O','U':'L','H':'F'})
NOT_PLACE=re.compile(r"\b(INC|CO|CORP|COMPANY|SHOP|MFG|FOUNDRY|PAINT|BATTERY|SECTION|PRODUCTS|WORKS|BROS|SONS?|THE|AND|OF|DAIRY|BAKERY|PRESS|PRINTING|"
                     r"NEWS|LUMBER|SUPPLY|SERVICE|BLDG|BUILDING|BOX|ROUTE|ROAD|STREET|AVE|HIGHWAY|HWY|NORTH|SOUTH|EAST|WEST|COUNTY|"
                     r"INDEX|ALPHABETICAL|GEOGRAPHICAL|MANUFACTURERS|DIRECTORY|PAGE|CONTINUED)\b")
_PLACES=None
def resolve_heading(t):
    """A heading line -> (kind, NAME, how): kind 'county' when NAME is a county's name (whether the line is the county
    heading or the heading of the town of that name is decided by what follows it, see parse), else 'city';
    how = 'exact', 'fuzzy' (OCR-tolerant gazetteer match) or 'asprinted' (no match: the heading as read).
    None when the line is not a heading (digits, lower case, long, firm or address words)."""
    global _PLACES
    u=t.upper() if t.isupper() else t
    m=re.match(r"^[^A-Za-z]{0,4}([A-Z][A-Z\.' ]{1,28}[A-Z\.])(?:[^A-Za-z0-9]{0,3}|\W+[A-Za-z]{1,3}\W*)$",u.strip())
    if not m or re.search(r"\d",t): return None
    name=re.sub(r"\s+"," ",m.group(1)).strip(" .'")
    if len(name.split())>3: return None
    name=re.sub(r"^FT\b\.?\s*","FORT ",name)
    h=heading(name)
    if h: return ('county' if h[1] in COUNTIES else 'city',h[1],'exact')
    if len(name)<4 or NOT_PLACE.search(name) or re.match(r"^(E[L1I]?|L|I)\s",name): return None
    if _PLACES is None:
        _PLACES=sorted({c for c in CITIES if len(c)>=4 and re.fullmatch(r"[A-Z\.' ]+",c)}|set(COUNTIES))
    key=name.replace('.','')
    sk=key.translate(SKEL)
    sc=sorted(((fuzz.ratio(sk,c.replace('.','').translate(SKEL)),fuzz.ratio(key,c),c) for c in _PLACES if abs(len(c)-len(key))<=2),reverse=True)
    # the best match must be strictly better than the runner-up (the gazetteer holds misspellings: 'COLORADO SPINGS');
    # a four-letter name must agree in every letter up to the confusions above ('HUGC', 'EACS', 'MEAC')
    if sc and sc[0][0]>=(80 if len(key)>=5 else 100) and (len(sc)<2 or sc[0][:2]>sc[1][:2]):
        n=sc[0][2]
        return ('county' if n in COUNTIES else 'city',n,'fuzzy')
    # as printed: one to three capitalised words, each a plausible word (a vowel, 3+ letters or a known particle)
    w=name.split()
    if all((len(x)>=3 and re.search(r"[AEIOUY]",x)) or x in ('LA','DE','EL','ST','FT','MT','LAS','DEL') for x in w) and len(set(name.replace(' ','')))>=4:
        return ('city',name,'asprinted')
    return None

def county_heading(L, i, off):
    """Line i reads as a county's name. The county heading is followed by a town heading; the heading of a town that
    shares a county's name (DENVER, PUEBLO, BOULDER, and PITKIN in Gunnison County, MONTEZUMA in Summit County) is
    followed by its listings. True when the next line at the margin is another heading, or the page ends."""
    for q in range(i+1,min(len(L),i+8)):
        t=L[q]['text'].strip(); d=off(L[q])
        if len(t)<4 or d>=INDENT: continue
        if split_record(t): return False
        if -70<d<INDENT-15 and resolve_heading(t): return True
    return True

STATS={}
def parse(vol, tsvdir, year):
    recs=[]; city=None; county=None
    st=STATS[vol]=dict(headings_exact=0,headings_fuzzy=0,headings_asprinted=0,address_lines_not_records=0)
    for p in sorted(glob.glob(f"{tsvdir}/{vol}/p*.tsv")):
        pg=int(os.path.basename(p)[1:4])
        L,cuts=page_lines(p,adaptive=(2,))   # 2-column pages; forced split when the gutter is missed
        if not L: continue
        top=min(l['y'] for l in L)
        if not any(HEAD.match(l['text'].strip()) for l in L): continue      # front matter, indexes
        M=margins(L)
        off=lambda l: l['x']-(M[l['col']][0]*l['y']+M[l['col']][1])
        i=0
        while i<len(L):
            l=L[i]; t=l['text'].strip(); d=off(l)
            if l['y']-top<60 and len(t)<40 and not split_record(t):
                i+=1; continue                       # running title: counties on the page, page number
            sr=split_record(t) if d<INDENT else None
            if sr is None and d<INDENT+35:
                # the code was lost but the class and the name were read ('El ZIMMER AUTOMOTIVE'): a listing without a printed code
                mc=re.match(r"^\W{0,3}([E€£][lL1I0-5])\s+([A-Z][A-Z0-9 \.,'&+*\-]{4,})$",t)
                if mc and not resolve_heading(t): sr=('',mc.group(1),mc.group(2))
            if sr is None and d>=INDENT and HEAD.match(t): st['address_lines_not_records']+=1
            if sr:
                raw,cls,name=sr
                code=norm_digits(raw.replace('€','8').replace('£','8'))
                street=''
                if i+1<len(L) and L[i+1]['col']==l['col'] and off(L[i+1])>=INDENT-20 and not split_record(L[i+1]['text'].strip()) \
                   and 0<L[i+1]['y']-l['y']<90:
                    street=L[i+1]['text'].strip(' _.~-:|'); i+=1
                recs.append(dict(vol=vol,year=year,page=pg,col=L[i]['col'],y=L[i]['y'],name=name.strip(),
                    street=fix_street(fix_dir(street)),addr_raw=street,zip='',city_ctx=city or '',county_ctx=county or '',
                    sic=[code] if (len(code)==4 and code.isdigit()) else [],sic_raw=raw,sic_desc=[],size=class_of(cls),est=None))
            elif -70<d<INDENT-15:
                h=resolve_heading(t)
                # a heading that matches no known place must stand clear of the line above, as printed headings do
                # (a garbled street line at the margin, '___ SEU WEBSTER', does not)
                if h and h[2]=='asprinted':
                    prev=[x for x in L[:i] if x['col']==l['col'] and len(x['text'].strip())>=4]
                    if prev and l['y']-prev[-1]['y']<40: h=None
                if h:
                    st['headings_'+h[2]]+=1
                    if h[0]=='county' and (county_heading(L,i,off) or h[1] not in CITIES):
                        county=h[1]; city=None      # (a county name over listings whose town heading was lost: no town)
                    else: city=h[1]
            i+=1
    return recs

if __name__=='__main__':
    vol=sys.argv[1]; year=int(sys.argv[2]); tsvdir=sys.argv[3] if len(sys.argv)>3 else 'work/tsv'
    R=parse(vol,tsvdir,year)
    with open(f'work/parsed/{vol}.jsonl','w') as f:
        for r in R: f.write(json.dumps(r)+'\n')
    print(vol,len(R),'with sic',sum(1 for r in R if r['sic']),'with city',sum(1 for r in R if r['city_ctx']),STATS[vol])
