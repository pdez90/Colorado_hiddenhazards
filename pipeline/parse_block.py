"""Parser for block-format Colorado Directory of Manufacturers geographic sections (1966-1986).
Each listing: NAME / street zip phone / ORG EST-yyyy market size / officers... / [mailing] / SIC lines.
Anchor = ORG line. Uses column-segmented OCR lines from segment.py."""
import re, sys, os, glob, json, statistics
sys.path.insert(0, os.path.dirname(__file__))
from segment import page_lines
from geoctx import heading

CITIES = set(open('work/inv/co_cities.txt').read().split('\n'))
DIGMAP = str.maketrans({'O':'0','Q':'0','D':'0','o':'0','C':'0','c':'0','U':'0','I':'1','l':'1','L':'1','i':'1','|':'1','!':'1',
                        'S':'9','s':'9','$':'9','B':'8','Z':'2','z':'2','G':'6','g':'9','T':'7','A':'4','&':'8','E':'8','e':'8','€':'8','@':'8','?':'7','F':'7','b':'6'})
# house numbers only: checked against the same firm's clean number in other editions, an OCR 'S' in a house number is a 5
# (22 of 32 cases, a 9 in 2), 'E' is a 1 (8 of 8) and 'G' a 0 (5 of 6); the general map above (S->9, E->8, G->6) is right
# for ZIPs and SIC codes but moved '520 ELIZABETH' to 920
HOUSEMAP = {**DIGMAP, **str.maketrans({'S':'5','s':'5','$':'5','E':'1','G':'0'})}
# Colorado ZIPs (from make_gazetteer); used to stop a 5-digit house number or an out-of-state ZIP being rewritten into a ZIP
try: _COZIPS=set(l.split(',')[0] for l in open('work/inv/zip_city.csv').read().split('\n')[1:] if l)
except OSError: _COZIPS=set()
STATE_BEFORE = re.compile(r"\b(?!CO\b)(AL|AK|AZ|AR|CA|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY|CALIF|TEXAS|KANSAS|NEBR|ILL|MASS|WIS|MINN|OKLA|TENN|MICH)\W{0,3}$")
SIZE_BINS=['1-9','0-9','1-19','0-19','10-19','20-49','20-99','50-99','100-249','250-499','250-999','500-999','100-499']
ORG_START = re.compile(r"^\W{0,3}(CORP|C0RP|CORE|COKP|CORPUS|CORPRL|CORPI|COOP|CO-OP|S\W?\s?P\W?ROP|S[eE]PROP|SePROP|SPROP|S PRO|PART|PTNR|DIV|SUBS|SUB|BRANCH|BR|ASSOC|TRUST|INC|LTD|COUNTY|CITY|GOVT|NON|PUB|PRIV|ESTATE|JOINT|COOPERATIVE|CORPORATION)\b", re.I)
EST = re.compile(r"[E€][S5$][T7]\W{0,2}\s?([0-9OoIlSs$BZ]{4})")
SIZE = re.compile(r"(\d[\dOoIl]*)\s*(?:T[O0C]|-)\s*(\d[\dOoIl]*)|(1000|1,000)\s*OR\s*MORE|EMP|ENP|EMF|EnP|EmP", re.I)
PHONE = re.compile(r"\d{3}\s?[-=~]\s?\d{4}")
ZIPTOK = re.compile(r"(?<![\w-])([0-9A-Za-z$@&\u20ac]{5})[a-z]?(?:-\d{4})?(?![\w-])")
SICLINE = re.compile(r"^\W{0,2}([0-9OIlSBZ]{4})[\.,:;]?\s+(.{3,})$")
OFFICER = re.compile(r"\b(PRES|PRESIDENT|OWNER|OWNR|MGR|MANAGER|PTNR|PARTNER|SEC|TREAS|V\s?P|VICE|DIR|SUPT|CHAIRMAN|GEN MGR|OFCR|OFFICER|EXEC|ENGR|SUPERINTENDENT|CONTROLLER|SECRETARY|ADMINISTRATOR|PURCH|PURCHASING|MKTG|PLT MGR|PLANT|TREASURER)\W*$", re.I)

def norm_digits(s):
    return s.translate(DIGMAP)

EIGHTLIKE=set('8B&E€@e6S$s3g9024ÉẞßÐ')   # characters Tesseract produces for a printed 8 (2 and 4 checked: '20218' = 80218)
def parse_zip(text):
    """Last ZIP-like token on the line. The first digit is forced to 8 (OCR reads 8 as 6, 3, 9, e, S, @ ...), but only
    freely when the raw character looks like an 8: a token starting with 1/5/7 is a house number ('10401 W 120TH AVE' is
    not ZIP 80401) or an out-of-state ZIP ('NEW YORK, NY 10036', 'DES MOINES, IA 50303'), so it is accepted only when
    it is not the leading token, no state abbreviation precedes it and the result is a Colorado ZIP."""
    best=None
    for m in ZIPTOK.finditer(text):
        raw=m.group(1)
        if sum(ch.isdigit() for ch in raw)<1: continue
        z=norm_digits(raw)
        if not z.isdigit(): continue
        z='8'+z[1:]
        if z[1] not in '01': continue
        if not (80000<=int(z)<=81699): continue
        if raw[0] not in EIGHTLIKE:
            lead=not re.search(r"[A-Za-z0-9]",text[:m.start()])
            if lead or STATE_BEFORE.search(text[:m.start()]) or (_COZIPS and z not in _COZIPS): continue
        best=(z,m.start(),m.end())
    return best

def snap_size(u):
    if re.search(r"1,?[0O]{3}\s*(OR|\+)\s*MORE|1000\+",u): return '1000+'
    tail=u
    mk=re.search(r"\b(REG|NTL|INTL|LOC|DIST|STATE|CNTY|COUNTY|NATNL|INTNL|LOCAL|NAT|OIST|ATL)\b\.?",u)
    if mk: tail=u[mk.end():]
    tail=re.sub(r"EST\W*\S{4}","",tail)
    tail=re.sub(r"^.*?(EMP|ENP|EMF|EPP|EHP)\W*","",tail)
    m=re.search(r"(\S{1,4})\s*(?:T[O0Cc]|10|1C|16|70|-|TC)\s*(\S{1,4})\s*$",tail.strip())
    if m:
        a=re.sub(r"\D","",norm_digits(m.group(1))); b=re.sub(r"\D","",norm_digits(m.group(2)))
        if a and b:
            cand=f"{int(a)}-{int(b)}"
            if cand in SIZE_BINS: return cand
            for bn in SIZE_BINS:
                x,y=bn.split('-')
                if y==b or (len(b)>=2 and y.endswith(b[-2:]) and len(y)==len(b)): 
                    if x==a or x[-1:]==a[-1:]: return bn
            for bn in SIZE_BINS:
                if bn.split('-')[1]==b: return bn
    return ''

MARKET=r"(REG|NTL|INTL|LOC|DIST|STATE|CNTY|COUNTY|NATNL|INTNL|LOCAL|NAT)"
# an ORG line whose founding year is blank ('S.PROP EST- STATE EMP-1 TO 9') or whose size is written 'EMP-20 TO 49':
# without these the next listing's name, address and SIC lines were swallowed by the previous record (2-10% of
# listings per edition, 1968 10%)
EST_BLANK = re.compile(r"\b[E€][S5$][T7]\W{0,3}\s*(?:"+MARKET+r"|E[MNH]P)\b")
EMPSIZE = re.compile(r"\bE[MNH]P\W{0,3}\s*\d[\dOoIl]*\s*(?:T[O0C]|-)\s*\d|\bEMP\W{0,2}\s*(?:1,?000|1000)")
BARESIZE = re.compile(r"^\W{0,2}\d[\dOoIl]{0,3}\s*T[O0C]\s*\d[\dOoIl]{0,3}\W{0,2}$")   # '0 TO 19' on its own line (1966)
def is_org(t):
    u=t.upper()
    if EST.search(u): return True
    if EST_BLANK.search(u) or EMPSIZE.search(u): return True
    # 1970 layout: the organisation word shares its line with the ZIP and phone ('CORP 80201 826-1145')
    if ORG_START.search(u) and (PHONE.search(u) or parse_zip(u)): return True
    if ORG_START.search(u) and (SIZE.search(u) or re.search(r"\b(REG|NTL|INTL|LOC|DIST|STATE|CNTY|NATNL|INTNL|LOCAL|NAT)\b",u)): return True
    if re.search(r"\b(REG|NTL|INTL|LOC|DIST|STATE|CNTY|NATNL|INTNL|LOCAL)\b\W+\d+\s*T[O0]\s*\d+",u): return True
    return False

def parse_org(t):
    u=t.upper(); d={}
    m=EST.search(u)
    if m:
        y=norm_digits(m.group(1))
        if y.isdigit():
            if y[:2]=='15': y='19'+y[2:]
            y=int(y)
            if 1800<=y<=2003: d['est']=y
    d['size']=snap_size(u)
    m=ORG_START.search(u)
    if m: d['org']=m.group(1)
    mk=re.search(r"\b(REG|NTL|INTL|LOC|DIST|STATE|CNTY|COUNTY|NATNL|INTNL|LOCAL|NAT)\b",u)
    if mk: d['market']=mk.group(1)
    return d

def is_addr(t):
    u=t.upper()
    if parse_zip(u): return True
    if PHONE.search(u) and re.match(r"^\W{0,2}[0-9OIl]{1,6}\b",u): return True
    if re.match(r"^\W{0,2}(P\W?\s?O\W?\s?B[O0]X|BOX|RT\b|ROUTE|RR\b|STAR RT|HWY|HIGHWAY)",u): return True
    if re.match(r"^\W{0,2}\d{1,6}\s+\S+",u) and PHONE.search(u): return True
    return False

def parse_sic(t):
    if PHONE.search(t) or parse_zip(t): return None
    m=SICLINE.match(t.strip())
    if not m: return None
    c=norm_digits(m.group(1))
    if not c.isdigit(): return None
    if not (2000<=int(c)<=3999 or 1000<=int(c)<=1499 or 7300<=int(c)<=7399): return None
    desc=m.group(2).strip()
    if not re.search(r"[A-Za-z]{3}",desc): return None
    if 1000<=int(c)<=1499 and street_like(desc): return None
    return c,desc

STREETWORD = re.compile(r"\b(ST|STREET|AVE?|AVENUE|RD|ROAD|DR|DRIVE|PL|PLACE|CT|COURT|WAY|BLVD|LN|LANE|HWY|CIR|PKWY|BOX|SQ FT|COUNTY|EMPLOYEES)\b|\(\s?[8B]\d?|^(N|S|E|W|NO|SO|NORTH|SOUTH|EAST|WEST)\b|^(IN|A)\s", re.I)
def street_like(desc):
    """A 'mining' code 1000-1499 followed by a street ('1015 W 12TH AVE', '1080 FORD ST', '1145 ithaca Dr') is a mailing
    or street line whose house number happens to fall in the SIC range, not an ore mill; 1988 had 124 such codes."""
    return bool(STREETWORD.search(desc)) or not re.search(r"[A-Za-z]{4}",desc)

def city_heading(t):
    u=re.sub(r"[^A-Z \-\.']","",t.upper()).strip()
    u=re.sub(r"\s+"," ",u)
    u=re.sub(r"\s*\(.*","",u)
    u=re.sub(r"\s+(COUNTY|CO)$","",u)
    if u in CITIES and len(u)>=3: return u
    return None

def fix_tok_num(t):
    core=re.sub(r"[^\w$@&\u20ac]","",t)
    if not core: return t
    dig=sum(ch.isdigit() for ch in core)
    if dig>=max(1,len(core)*0.5):
        return core.translate(HOUSEMAP)   # house-number map: S->5, E->1, G->0 (see HOUSEMAP)
    return t
# street words spelt only with eight-like letters + an ordinal ending ('Ind' = industrial, 'List Dr' in Colorado Springs,
# 'Weld CoRd 78', 'Red Bird Farms'); the ordinal repair below turned them into '1ND', '11ST', '00RD', '81RD'
NOT_ORDINAL={'IND','LIST','CORD','BIRD','COST','LOST'}
def fix_street(st):
    toks=st.split()
    if not toks: return st
    toks[0]=fix_tok_num(toks[0])
    out=[]
    for t in toks:
        m=re.match(r"^([0-9OIlCcSB]{1,3})(ST|ND|RD|TH|TF|TK|TN|IH|SI|5T|1H|7H)$",t,re.I)
        if m and t.upper() in NOT_ORDINAL: m=None
        if m:
            n=norm_digits(m.group(1)); suf=m.group(2).upper()
            suf={'TF':'TH','TK':'TH','TN':'TH','IH':'TH','1H':'TH','7H':'TH','5T':'ST','SI':'ST'}.get(suf,suf)
            if n.isdigit(): t=n+suf
        out.append(t)
    s=' '.join(out)
    s=re.sub(r"[^A-Za-z0-9 #&\-/\.]","",s)
    return re.sub(r"\s+"," ",s).strip()

def join_wrapped(pl):
    """Join an indented continuation line to the line above it ('285 RIO GRANDE' / '    BLVD'; 'REV D J' / '   FLAHERTY').
    The 1970 OCR splits the right-hand half of many lines off as a separate, indented line, which then stands between
    the street and the ORG line and was taken for the firm's name."""
    out=[]; byc={}
    for l in pl: byc.setdefault(l['col'],[]).append(l['x'])
    left={c:statistics.median(xs) for c,xs in byc.items()}
    for l in sorted(pl,key=lambda l:(l['col'],l['y'])):
        prev=out[-1] if out else None
        if prev and prev['col']==l['col'] and l['x']-left[l['col']]>45 and 0<l['y']-prev['y']<=24 and len(l['text'])<=30 \
           and not re.match(r"^\W{0,2}\d{4}\b",l['text']) and not PHONE.search(l['text']) and not parse_zip(l['text']):
            prev['text']=prev['text']+' '+l['text']; continue
        out.append(dict(l))
    return out

def parse_volume(vol, tsvdir, year):
    pages=sorted(glob.glob(f"{tsvdir}/{vol}/p*.tsv"))
    L=[]
    for p in pages:
        # adaptive column split: the automatic gutter search misses a gutter on 10-30% of these 3-column pages
        pl,cuts=page_lines(p,adaptive=(3,2))
        if year in (1970,1971): pl=join_wrapped(pl)
        pg=int(os.path.basename(p)[1:4])
        # drop page header line(s): first line of each column if it has a page number and is at top
        top=min([l['y'] for l in pl], default=0)
        for l in pl:
            l['page']=pg
            l['hdr']= (l['y']-top<40 and re.search(r"\b\d{1,3}\b",l['text']) and len(l['text'])<45)
            L.append(l)
    recs=[]; city=None; county=None
    n=len(L)
    def prev_text(i):
        j=i-1
        while j>=0 and (L[j]['hdr'] or len(L[j]['text'].strip())<3): j-=1
        return j
    org_set={i for i,l in enumerate(L) if not l['hdr'] and is_org(l['text'])}
    # a bare size line ('0 TO 19') right under an address line is the ORG line of a listing whose organisation word was lost
    for i,l in enumerate(L):
        if i in org_set or l['hdr'] or not BARESIZE.match(l['text']): continue
        j=prev_text(i)
        if j>=0 and is_addr(L[j]['text']): org_set.add(i)
    # 1970 layout: the market/size half of the ORG line is often read as a separate line right under it ('CORP 80202 825-3927' /
    # 'H A NTL 0 TO 19'); keep only the first as the anchor, or every second listing came out without a name
    for i in sorted(org_set):
        u=L[i]['text'].upper()
        if EST.search(u) or ORG_START.search(u): continue
        j=prev_text(i)
        if j in org_set: org_set.discard(i)
    org_idx=sorted(org_set)
    # a street+phone line inside a record's body is the next listing's address (its ORG line was not recognised):
    # start a new record there instead of appending its SIC codes to the previous firm
    def street_phone(t):
        return bool(PHONE.search(t)) and bool(re.match(r"^\W{0,2}\d",t)) and is_addr(t)
    anchors=[(i,'org') for i in org_idx]
    for k,i in enumerate(org_idx):
        nxt=org_idx[k+1] if k+1<len(org_idx) else n
        for q in range(i+2, nxt-3):
            t=L[q]['text']; pt=L[q-1]['text']
            if L[q]['hdr'] or L[q-1]['hdr'] or not street_phone(t): continue
            if q-1 in org_set or parse_sic(pt) or is_addr(pt) or not re.search(r"[A-Za-z]{3}",pt): continue
            anchors.append((q,'addr'))
    anchors.sort()
    used=set()
    for k,(i,kind) in enumerate(anchors):
        addr=None; name=None; addr_text=''
        if kind=='org':
            # find address & name above
            j=prev_text(i)
            if j>=0 and is_addr(L[j]['text']) and j not in used:
                addr=j; j=prev_text(j)
            elif j>=0 and j not in used and not parse_sic(L[j]['text']):
                # NAME / street phone / PARENT COMPANY, CITY / ORG: the parent line sits between the address and the
                # ORG line ('PACKAGING CORP OF AMERICA' / '1377 S JASON 80209 777-3300' / 'PACKAGING CORP OF AM EVANSTON, IL');
                # it used to be taken for the name and the address was lost. A phone marks the firm's own street line.
                j2=prev_text(j)
                if j2>=0 and j2 not in used and is_addr(L[j2]['text']) and PHONE.search(L[j2]['text']):
                    j3=prev_text(j2)
                    if j3>=0 and j3 not in used and not parse_sic(L[j3]['text']) and not is_org(L[j3]['text']) and not is_addr(L[j3]['text']):
                        addr=j2; j=j3
            if j>=0 and j not in used and not parse_sic(L[j]['text']) and not is_org(L[j]['text']):
                name=j
            # also allow addr line that is 2 lines (street then zip-phone)
            if name is not None and addr is not None and is_addr(L[name]['text']) and name-1>=0 and not parse_sic(L[name-1]['text']):
                # two-line address
                name2=name-1
                addr_txt=L[name]['text']+' '+L[addr]['text']
                used.update([name,addr]); name=name2; addr_text=addr_txt
            else:
                addr_text=L[addr]['text'] if addr is not None else ''
            # 1970 layout: ZIP and phone sit on the ORG line, so the street line above has neither ('1200 13TH')
            bare_street = name is not None and addr is None and re.match(r"^\W{0,2}\d{1,6}\s+\S",L[name]['text']) \
                          and (PHONE.search(L[i]['text']) or parse_zip(L[i]['text']))
            if name is not None and addr is None and (is_addr(L[name]['text']) or bare_street):
                addr=name; name=None; addr_text=L[addr]['text']
                q=prev_text(addr)
                if q>=0 and q not in used and not parse_sic(L[q]['text']) and not is_org(L[q]['text']): name=q
        else:
            addr=i; name=i-1; addr_text=L[addr]['text']
        rec={'vol':vol,'year':year,'page':L[i]['page'],'col':L[i]['col'],'y':L[i]['y']}
        rec['name']=L[name]['text'].strip() if name is not None else ''
        rec['addr_raw']=addr_text
        z=parse_zip(addr_text) if addr_text else None
        if z:
            rec['zip']=z[0]; street=addr_text[:z[1]].strip(' ,.')
        else:
            rec['zip']=''; street=PHONE.sub('',addr_text).strip(' ,.')
            # 1970 layout: ZIP and phone are printed on the ORG line ('CORP EST-1920 80002 421-5123'), not the street line
            if kind=='org' and PHONE.search(L[i]['text']):
                z2=parse_zip(L[i]['text'])
                if z2: rec['zip']=z2[0]
        street=PHONE.sub('',street).strip(' ,.')
        rec['street']=fix_street(street)
        if kind=='org':
            rec.update(parse_org(L[i]['text'])); rec['org_raw']=L[i]['text']
            # size printed on the line under the ORG line (1970 layout, see above)
            if not rec.get('size') and i+1<n and not parse_sic(L[i+1]['text']) and SIZE.search(L[i+1]['text'].upper()):
                rec['size']=snap_size(L[i+1]['text'].upper())
        else: rec['org_raw']=''
        # city context: scan backwards from name for headings since previous record
        lo = anchors[k-1][0]+1 if k>0 else 0
        hi = name if name is not None else (addr if addr is not None else i)
        for q in range(lo,hi):
            if parse_sic(L[q]['text']): continue
            txt=L[q]['text']
            if L[q]['hdr']:
                txt=re.sub(r"[\d\u2014\-]+"," ",txt).strip()
                if re.search(r"\s{2,}|\u2014",L[q]['text']) and not heading(txt): continue
            h=heading(txt)
            if h:
                if h[0]=='county': county=h[1]; city=None
                elif h[0]=='city': city=h[1]
                else: county=h[1]; city=h[1]
        rec['city_ctx']=city or ''; rec['county_ctx']=county or ''
        # body: lines after org until next record's name
        if k+1<len(anchors):
            nxt,nkind=anchors[k+1]
            body_end = max(i+1,nxt-2) if nkind=='org' else max(i+1,nxt-1)
            tail = range(body_end,nxt) if nkind=='org' else range(0)
        else:
            nxt=n; body_end=n; tail=range(0)
        sics=[]; extra=[]
        for q in range(i+1, body_end):
            if L[q]['hdr']: continue
            s=parse_sic(L[q]['text'])
            if s: sics.append(s)
            else: extra.append(L[q]['text'])
        # lines nxt-2,nxt-1 may still be SIC lines if next rec lacks address
        for q in tail:
            s=parse_sic(L[q]['text'])
            if s and s[0][0] in '23' and not re.search(r"\b(ST|AVE|BLVD|RD|DR|WAY|PL|CT)\b",s[1]): sics.append(s)
        rec['sic']=[c for c,_ in sics]; rec['sic_desc']=[d for _,d in sics]
        rec['extra']=extra[:6]
        used.update([x for x in (name,addr,i) if x is not None])
        recs.append(rec)
    return recs

if __name__=='__main__':
    vol=sys.argv[1]; year=int(sys.argv[2]); tsvdir=sys.argv[3] if len(sys.argv)>3 else 'work/tsv'
    recs=parse_volume(vol,tsvdir,year)
    os.makedirs('work/parsed',exist_ok=True)
    with open(f'work/parsed/{vol}.jsonl','w') as f:
        for r in recs: f.write(json.dumps(r)+'\n')
    import collections
    print(vol, len(recs), 'with zip', sum(1 for r in recs if r['zip']), 'with sic', sum(1 for r in recs if r['sic']), 'with est', sum(1 for r in recs if r.get('est')))
