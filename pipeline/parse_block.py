"""Parser for block-format Colorado Directory of Manufacturers geographic sections (1966-1986).
Each listing: NAME / street zip phone / ORG EST-yyyy market size / officers... / [mailing] / SIC lines.
Anchor = ORG line. Uses column-segmented OCR lines from segment.py."""
import re, sys, os, glob, json
sys.path.insert(0, os.path.dirname(__file__))
from segment import page_lines
from geoctx import heading

CITIES = set(open('work/inv/co_cities.txt').read().split('\n'))
DIGMAP = str.maketrans({'O':'0','Q':'0','D':'0','o':'0','C':'0','c':'0','U':'0','I':'1','l':'1','L':'1','i':'1','|':'1','!':'1',
                        'S':'9','s':'9','$':'9','B':'8','Z':'2','z':'2','G':'6','g':'9','T':'7','A':'4','&':'8','E':'8','e':'8','€':'8','@':'8','?':'7','F':'7','b':'6'})
SIZE_BINS=['1-9','0-9','1-19','0-19','10-19','20-49','20-99','50-99','100-249','250-499','250-999','500-999','100-499']
ORG_START = re.compile(r"^\W{0,3}(CORP|C0RP|CORE|COKP|CORPUS|CORPRL|CORPI|COOP|CO-OP|S\W?\s?P\W?ROP|SPROP|S PRO|PART|PTNR|DIV|SUBS|SUB|BRANCH|BR|ASSOC|TRUST|INC|LTD|COUNTY|CITY|GOVT|NON|PUB|PRIV|ESTATE|JOINT|COOPERATIVE|CORPORATION)\b", re.I)
EST = re.compile(r"[E€][S5$][T7]\W{0,2}\s?([0-9OoIlSs$BZ]{4})")
SIZE = re.compile(r"(\d[\dOoIl]*)\s*(?:T[O0C]|-)\s*(\d[\dOoIl]*)|(1000|1,000)\s*OR\s*MORE|EMP|ENP|EMF|EnP|EmP", re.I)
PHONE = re.compile(r"\d{3}\s?[-=~]\s?\d{4}")
ZIPTOK = re.compile(r"(?<![\w-])([0-9A-Za-z$@&\u20ac]{5})[a-z]?(?:-\d{4})?(?![\w-])")
SICLINE = re.compile(r"^\W{0,2}([0-9OIlSBZ]{4})[\.,:;]?\s+(.{3,})$")
OFFICER = re.compile(r"\b(PRES|PRESIDENT|OWNER|OWNR|MGR|MANAGER|PTNR|PARTNER|SEC|TREAS|V\s?P|VICE|DIR|SUPT|CHAIRMAN|GEN MGR|OFCR|OFFICER|EXEC|ENGR|SUPERINTENDENT|CONTROLLER|SECRETARY|ADMINISTRATOR|PURCH|PURCHASING|MKTG|PLT MGR|PLANT|TREASURER)\W*$", re.I)

def norm_digits(s):
    return s.translate(DIGMAP)

def parse_zip(text):
    best=None
    for m in ZIPTOK.finditer(text):
        raw=m.group(1)
        if sum(ch.isdigit() for ch in raw)<1: continue
        z=norm_digits(raw)
        if not z.isdigit(): continue
        z='8'+z[1:]
        if z[1] not in '01': continue
        if 80000<=int(z)<=81699: best=(z,m.start(),m.end())
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

def is_org(t):
    u=t.upper()
    if EST.search(u): return True
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
    return c,desc

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
        return norm_digits(core)
    return t
def fix_street(st):
    toks=st.split()
    if not toks: return st
    toks[0]=fix_tok_num(toks[0])
    out=[]
    for t in toks:
        m=re.match(r"^([0-9OIlCcSB]{1,3})(ST|ND|RD|TH|TF|TK|TN|IH|SI|5T|1H|7H)$",t,re.I)
        if m:
            n=norm_digits(m.group(1)); suf=m.group(2).upper()
            suf={'TF':'TH','TK':'TH','TN':'TH','IH':'TH','1H':'TH','7H':'TH','5T':'ST','SI':'ST'}.get(suf,suf)
            if n.isdigit(): t=n+suf
        out.append(t)
    s=' '.join(out)
    s=re.sub(r"[^A-Za-z0-9 #&\-/\.]","",s)
    return re.sub(r"\s+"," ",s).strip()

def parse_volume(vol, tsvdir, year):
    pages=sorted(glob.glob(f"{tsvdir}/{vol}/p*.tsv"))
    L=[]
    for p in pages:
        pl,cuts=page_lines(p)
        pg=int(os.path.basename(p)[1:4])
        # drop page header line(s): first line of each column if it has a page number and is at top
        top=min([l['y'] for l in pl], default=0)
        for l in pl:
            l['page']=pg
            l['hdr']= (l['y']-top<40 and re.search(r"\b\d{1,3}\b",l['text']) and len(l['text'])<45)
            L.append(l)
    recs=[]; city=None; county=None
    n=len(L)
    org_idx=[i for i,l in enumerate(L) if not l['hdr'] and is_org(l['text'])]
    used=set()
    for k,i in enumerate(org_idx):
        # find address & name above
        j=i-1
        while j>=0 and (L[j]['hdr'] or len(L[j]['text'].strip())<3): j-=1
        addr=None; name=None
        if j>=0 and is_addr(L[j]['text']) and j not in used:
            addr=j; j-=1
            while j>=0 and (L[j]['hdr'] or len(L[j]['text'].strip())<3): j-=1
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
        if name is not None and addr is None and is_addr(L[name]['text']):
            addr=name; name=None; addr_text=L[addr]['text']
            q=addr-1
            while q>=0 and (L[q]['hdr'] or len(L[q]['text'].strip())<3): q-=1
            if q>=0 and q not in used and not parse_sic(L[q]['text']) and not is_org(L[q]['text']): name=q
        rec={'vol':vol,'year':year,'page':L[i]['page'],'col':L[i]['col'],'y':L[i]['y']}
        rec['name']=L[name]['text'].strip() if name is not None else ''
        rec['addr_raw']=addr_text
        z=parse_zip(addr_text) if addr_text else None
        if z:
            rec['zip']=z[0]; street=addr_text[:z[1]].strip(' ,.')
        else:
            rec['zip']=''; street=PHONE.sub('',addr_text).strip(' ,.')
        street=PHONE.sub('',street).strip(' ,.')
        rec['street']=fix_street(street)
        rec.update(parse_org(L[i]['text'])); rec['org_raw']=L[i]['text']
        # city context: scan backwards from name for headings since previous record
        lo = org_idx[k-1]+1 if k>0 else 0
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
        nxt = org_idx[k+1] if k+1<len(org_idx) else n
        sics=[]; extra=[]
        for q in range(i+1, max(i+1,nxt-2)):
            if L[q]['hdr']: continue
            s=parse_sic(L[q]['text'])
            if s: sics.append(s)
            else: extra.append(L[q]['text'])
        # lines nxt-2,nxt-1 may still be SIC lines if next rec lacks address
        for q in range(max(i+1,nxt-2), nxt):
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
