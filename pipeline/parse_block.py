"""Parser for block-format Colorado Directory of Manufacturers geographic sections (1966-1986).
Each listing: NAME / street zip phone / ORG EST-yyyy market size / officers... / [mailing] / SIC lines.
Anchor = ORG line. Uses column-segmented OCR lines from segment.py."""
import re, sys, os, glob, json, statistics
sys.path.insert(0, os.path.dirname(__file__))
from segment import page_lines
from geoctx import heading
from volumes import NO_PRINTED_CODES

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
# '3845 FOREST 80207 388-5821' and '305 WEST 81003 544-9544' are street lines, not 'EST-8020': no match at the end of
# FOREST / WEST. Other letters may precede ('CORO RGEST-1965', 'E€ST-1957').
EST = re.compile(r"(?<!W)(?<!F[OCUI0]R)[E€][S5$][T7]\W{0,2}\s?([0-9OoIlSs$BZ]{4})")
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
# a founding year with letters among its digits ('EST-194C', 'EST-19€2', 'EST-1e61': 98 ORG lines, 53 of them in 1968) and
# an ORG line whose year is unreadable ('CORP. EST- NAINL ERP-20 10 49'); the separator is required
EST_LOOSE = re.compile(r"(?<!W)(?<!F[OCUI0]R)[E€][S5$][T7]\s?[-=~—#:\.]{1,2}\s?([0-9A-Z$€&@]{4})\b")
def loose_year(u):
    """The four characters after 'EST-' when at least two are digits and all map to digits, else None."""
    m=EST_LOOSE.search(u)
    if m and sum(ch.isdigit() for ch in m.group(1))>=2 and norm_digits(m.group(1)).isdigit(): return norm_digits(m.group(1))
    return None
# the organisation word alone on its line ('S PROP', 'corp'): an ORG line when it stands right under an address line
ORGWORD = re.compile(r"^\W{0,3}(CORP|CORE|C0RP|S\W?\s?PROP|SePROP|PART|PTNR)\W{0,3}$", re.I)
def size_only(t):
    """A bare size class on its own line as the OCR returns it: '0 TO 19', 'o TO 19', 'o7TO0 19', '010 19', '© To 19',
    '100 TO 249' (1966 prints the size under the street of its short-form listings)."""
    if BARESIZE.match(t): return True
    u=t.strip(' .,;:_-\'"|')
    if len(u)>11 or PHONE.search(u) or not (' ' in u or re.search(r"[Tt]",u)): return False
    return bool(re.match(r"^[0-9OoIlCc©¢]{1,3}[Tt1][Oo0Cc]?[0-9OoIlSs$]{1,4}$",u.replace(' ','')))
def mailing_line(t):
    """'PO BOX 169 MONTE VISTA 81144', '6534 W 55TH AVE ARVADA 80003': a town name stands before the ZIP. The firm's own
    street line never names the town (it is the page's heading), so such a line is a mailing or head-office address."""
    z=parse_zip(t)
    w=re.sub(r"[^A-Z ]"," ",(t[:z[1]] if z else t).upper()).split()
    return any(' '.join(w[-k:]) in CITIES for k in (1,2,3) if len(w)>=k and len(' '.join(w[-k:]))>=4)
def is_org(t):
    u=t.upper()
    if EST.search(u): return True
    if loose_year(u): return True
    if ORG_START.search(u) and len(u)<45 and re.search(r"\s[E€][S5$][T7]\w?[-=~—\.]",u): return True
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
    if 'est' not in d and not m and loose_year(u):
        y=loose_year(u)
        if y[:2]=='15': y='19'+y[2:]
        if 1800<=int(y)<=2003: d['est']=int(y); d['est_loose']=True
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
    if re.match(r"^\W{0,2}(P\W?\s?[O0]\W?\s?B[O0]X|BOX|RT\b|ROUTE|RR\b|STAR RT|HWY|HIGHWAY)",u): return True
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

NUMSTART = re.compile(r"^\W{0,2}\d{1,6}[A-Za-z]?\s+\S")
POBOX = re.compile(r"^\W{0,2}(P\W?\s?[O0]\W?\s?B[O0]X|BOX|RT\b|ROUTE|RR\b|STAR RT)", re.I)
FIRMSUF = re.compile(r"\b(INC|CO|CORP|COMPANY|CORPORATION|LTD|MFG|BROS|WORKS|SHOP|ASSN|ASSOC|INDUSTRIES|PRODUCTS)\W*$", re.I)
STARNAME = re.compile(r"^\W{0,2}(?:[\*®#•]|[\"e](?=[A-Z]{3}))")   # '*KROEGER PRESS', '®SIGNS', 'eMANLEY SHEET METAL CO'
STATS = {}   # per volume: fragments attached to their firm, nameless records left, name-like lines left in 'extra'

def zp_only(t):
    """A line holding only a ZIP and/or phone ('80205 534-5248', '80211 455-'): the right-hand half of a street line
    that the OCR returned as a line of its own."""
    if not (PHONE.search(t) or parse_zip(t)): return False
    u=PHONE.sub(' ',t); z=parse_zip(u)
    if z: u=u[:z[1]]+' '+u[z[2]:]
    return len(re.sub(r"[^A-Za-z0-9]","",u))<=3

def street_only(t, strong=False):
    """A street line without ZIP or phone ('2528 WALNUT', '3840 S JASON ST', 'P O BOX 65'). A house number 2000-3999
    makes such a line look like a SIC line ('2528' + description 'WALNUT'), which is why it was never taken for the
    address and its listing lost its name. strong: the ZIP/phone were found on the ORG line or on a line of their own,
    so the line above them is the street whatever it looks like; otherwise the text after the number must read as a
    street (a street word or direction, or one or two words that do not end like a firm name)."""
    if POBOX.match(t): return True
    if not NUMSTART.match(t) or is_org(t): return False
    if strong: return True
    rest=re.sub(r"^\W{0,2}\S+\s+","",t.strip())
    if FIRMSUF.search(rest): return False
    return bool(STREETWORD.search(rest)) or bool(re.match(r"^\d{1,3}(ST|ND|RD|TH)\b",rest,re.I)) or len(rest.split())<=2

def name_like_extra(body, examples=None):
    """Count of 'firm name / street line' pairs in a record's body: a listing that did not start a record of its own
    (its ORG line was not recognised and its street line carries no phone). body: list of line texts."""
    n=0
    for a,b in zip(body,body[1:]):
        if parse_sic(a) or is_addr(a) or is_org(a) or OFFICER.search(a) or NUMSTART.match(a) or POBOX.match(a): continue
        if not re.search(r"[A-Z]{3}",a) or re.search(r",\s*[A-Z][A-Za-z\. ]{1,12}$",a): continue      # 'EVANSTON, IL' parent line
        if (NUMSTART.match(b) or POBOX.match(b)) and (parse_zip(b) or PHONE.search(b)) and not is_org(b) and not mailing_line(b):
            n+=1
            if examples is not None and len(examples)<200: examples.append((a,b))
    return n

def merge_org_lines(L, org_set, prev_text):
    """The ORG line is often read as two lines ('CORP 80223 934-7882' / 'B EST-1964 REG 0 TO 19'; 'S PROP 246-3394' /
    'EST-1911 REG 0 TO 19'). Two ORG lines in a row are one listing's (a listing has at least a name between them):
    the second is a continuation of the first, not the anchor of a nameless record. Two lines that each print a
    founding year stay apart. Returns {anchor: [continuation line indexes]} and removes the continuations from org_set."""
    cont={}; owner={}
    for i in sorted(org_set):
        j=prev_text(i)
        a=owner.get(j, j if j in org_set else None)
        if a is None: continue
        txt=' '.join(L[x]['text'] for x in [a]+cont.get(a,[])).upper()
        if EST.search(txt) and EST.search(L[i]['text'].upper()): continue
        cont.setdefault(a,[]).append(i); owner[i]=a
    for a,c in cont.items(): org_set.difference_update(c)
    return cont

def parse_volume(vol, tsvdir, year, ctx=None):
    """ctx: optional dict carrying the town and county in force from the previous part-volume of the same edition
    ({'city':..,'county':..}); part 2 opens in the middle of a town, with no heading above its first listings. It is
    updated with the context at the end of this volume and, under 'page_start', the context in force when each page
    begins (the next part may repeat this volume's last pages; it must then start from the context before them)."""
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
    recs=[]; city=(ctx or {}).get('city'); county=(ctx or {}).get('county')
    n=len(L)
    stats=STATS[vol]=dict(attached=0, nameless=0, namelike_extra=0, examples=[])
    def prev_text(i):
        j=i-1
        while j>=0 and (L[j]['hdr'] or len(L[j]['text'].strip())<3): j-=1
        return j
    org_set={i for i,l in enumerate(L) if not l['hdr'] and is_org(l['text'])}
    # a bare size line ('0 TO 19') right under an address line is the ORG line of a listing whose organisation word was lost
    for i,l in enumerate(L):
        if i in org_set or l['hdr'] or not size_only(l['text']): continue
        j=prev_text(i)
        if j>=0 and is_addr(L[j]['text']): org_set.add(i)
    for i,l in enumerate(L):
        if i in org_set or l['hdr'] or not ORGWORD.match(l['text']): continue
        j=prev_text(i)
        if j>=0 and j not in org_set and is_addr(L[j]['text']) and (NUMSTART.match(L[j]['text']) or POBOX.match(L[j]['text'])): org_set.add(i)
    # the ORG line read as two lines: one anchor, the second line a continuation (see merge_org_lines)
    cont=merge_org_lines(L,org_set,prev_text)
    contset={c for cs in cont.values() for c in cs}
    org_idx=sorted(org_set)
    orgtext=lambda i: ' '.join(L[x]['text'] for x in [i]+cont.get(i,[]))
    # a street+phone line inside a record's body is the next listing's address (its ORG line was not recognised):
    # start a new record there instead of appending its SIC codes to the previous firm
    def street_phone(t):
        return bool(PHONE.search(t)) and bool(re.match(r"^\W{0,2}\d",t)) and is_addr(t)
    anchors=[(i,'org') for i in org_idx]
    for k,i in enumerate(org_idx):
        nxt=org_idx[k+1] if k+1<len(org_idx) else n
        seen_sic=False
        for q in range(i+1, nxt-3):
            t=L[q]['text']; pt=L[q-1]['text']
            if parse_sic(pt) and not L[q-1]['hdr']: seen_sic=True
            if q<i+2 or q in contset or q-1 in contset: continue
            if L[q]['hdr'] or L[q-1]['hdr']: continue
            # ... or a street+ZIP line (no phone) that follows the record's SIC lines: the SIC lines close a listing, a
            # mailing address or parent-company line comes before them, so name + street after them is a new listing
            # (1966 prints no codes: there the sign is the '*' before the name of a short-form listing, or a short size-like
            # line under the street, 'oro 19'.) A line that names a town before the ZIP is a mailing address, never a start.
            if not street_phone(t):
                if not (NUMSTART.match(t) and is_addr(t) and parse_zip(t) and not is_org(t) and not mailing_line(t)): continue
                if OFFICER.search(pt) or re.search(r",\s*[A-Z][A-Za-z\. ]{1,12}$",pt): continue
                nt=L[q+1]['text'].strip() if q+1<n else ''
                if not (seen_sic or STARNAME.match(pt) or (len(nt)<=10 and re.search(r"\d",nt) and not PHONE.search(nt))): continue
            if q-1 in org_set or parse_sic(pt) or is_addr(pt) or not re.search(r"[A-Za-z]{3}",pt): continue
            anchors.append((q,'addr'))
    anchors.sort()
    used=set()
    def free(q): return q>=0 and q not in used and q not in org_set and q not in contset
    def name_like(q):
        if not free(q): return False
        t=L[q]['text']
        return bool(re.search(r"[A-Za-z]{3}",t)) and not parse_sic(t) and not is_addr(t) and not OFFICER.search(t) and not zp_only(t)
    # ---- pass 1: the name and address lines of every anchor
    found=[]
    for k,(i,kind) in enumerate(anchors):
        addr=None; name=None; addr_text=''; extra_used=[]
        if kind=='org':
            ot=orgtext(i)
            org_zp=bool(PHONE.search(ot) or parse_zip(ot))
            j=prev_text(i); j2=prev_text(j) if j>=0 else -1; j3=prev_text(j2) if j2>=0 else -1
            tj=L[j]['text'] if j>=0 else ''; tj2=L[j2]['text'] if j2>=0 else ''
            got=False
            if free(j) and free(j2):
                # NAME / street / ZIP-phone / ORG, and the same with the two halves of the street line swapped
                if zp_only(tj) and not zp_only(tj2) and street_only(tj2,True) and name_like(j3):
                    addr=j2; name=j3; addr_text=tj2+' '+tj; extra_used=[j]; got=True
                elif zp_only(tj2) and not zp_only(tj) and street_only(tj,True) and not is_addr(tj) and name_like(j3):
                    addr=j; name=j3; addr_text=tj+' '+tj2; extra_used=[j2]; got=True
            if not got and free(j) and not is_addr(tj) and name_like(j2):
                s=parse_sic(tj)
                # NAME / street without ZIP or phone / ORG: a house number 2000-3999 reads as a SIC code
                if s and (street_only(tj,org_zp) and (org_zp or street_like(s[1]) or len(s[1].split())<=2)):
                    addr=j; name=j2; addr_text=tj; got=True
                elif not s and not org_zp and NUMSTART.match(tj) and street_only(tj) and (STREETWORD.search(tj) or re.search(r"^\W{0,2}\d+\s+(N|S|E|W)\s",tj.upper())):
                    addr=j; name=j2; addr_text=tj; got=True
            if not got and free(j) and free(j2) and parse_sic(tj) and is_addr(tj2) and PHONE.search(tj2) and name_like(j3):
                # NAME / street phone / mailing or parent line that starts with a 4-digit number / ORG
                addr=j2; name=j3; addr_text=tj2; extra_used=[j]; got=True
            if got: stats['attached']+=1
        if kind=='org' and not got:
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
            if j>=0 and j not in used and not parse_sic(L[j]['text']) and not is_org(L[j]['text']) and j not in contset:
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
            ot=orgtext(i)
            bare_street = name is not None and addr is None and re.match(r"^\W{0,2}\d{1,6}\s+\S",L[name]['text']) \
                          and (PHONE.search(ot) or parse_zip(ot))
            if name is not None and addr is None and (is_addr(L[name]['text']) or bare_street):
                addr=name; name=None; addr_text=L[addr]['text']
                q=prev_text(addr)
                if q>=0 and q not in used and not parse_sic(L[q]['text']) and not is_org(L[q]['text']) and q not in contset: name=q
        elif kind=='addr':
            addr=i; name=i-1; addr_text=L[addr]['text']
        mine=[x for x in [name,addr,i]+extra_used+cont.get(i,[]) if x is not None]
        used.update(mine)
        found.append(dict(i=i,kind=kind,name=name,addr=addr,addr_text=addr_text,top=min(mine),end=max(mine)))
    page_start={}
    # ---- pass 2: fields and body (the lines between this record's last line and the next record's first)
    for k,F in enumerate(found):
        i,kind,name,addr,addr_text=F['i'],F['kind'],F['name'],F['addr'],F['addr_text']
        ot=orgtext(i) if kind=='org' else ''
        rec={'vol':vol,'year':year,'page':L[i]['page'],'col':L[i]['col'],'y':L[i]['y']}
        rec['name']=L[name]['text'].strip() if name is not None else ''
        rec['addr_raw']=addr_text
        z=parse_zip(addr_text) if addr_text else None
        if z:
            rec['zip']=z[0]; street=addr_text[:z[1]].strip(' ,.')
        else:
            rec['zip']=''; street=PHONE.sub('',addr_text).strip(' ,.')
            # 1970 layout: ZIP and phone are printed on the ORG line ('CORP EST-1920 80002 421-5123'), not the street line
            # (the anchor line itself first: in the merged text a garbled size, '0 T0119', can read as a later ZIP)
            if kind=='org' and PHONE.search(ot):
                z2=parse_zip(L[i]['text']) or parse_zip(ot)
                if z2: rec['zip']=z2[0]
        street=PHONE.sub('',street).strip(' ,.')
        rec['street']=fix_street(street)
        if kind=='org':
            rec.update(parse_org(ot)); rec['org_raw']=ot
            # a year read through OCR letters is kept only when it can be this edition's ('EST-19€2' in 1968 is not 1982)
            if rec.pop('est_loose',False) and rec.get('est',0)>year: del rec['est']
            # size printed on the line under the ORG line (1970 layout, see above)
            if not rec.get('size') and F['end']+1<n and not parse_sic(L[F['end']+1]['text']) and SIZE.search(L[F['end']+1]['text'].upper()):
                rec['size']=snap_size(L[F['end']+1]['text'].upper())
        else: rec['org_raw']=''
        # city context: scan backwards from name for headings since previous record
        if k==0 or L[found[k-1]['i']]['page']!=L[i]['page']: page_start[L[i]['page']]=(city,county)
        lo = found[k-1]['i']+1 if k>0 else 0
        hi = F['top']
        for q in range(lo,hi):
            if q in used or parse_sic(L[q]['text']): continue
            txt=L[q]['text']
            if L[q]['hdr']:
                txt=re.sub(r"[\d—\-]+"," ",txt).strip()
                if re.search(r"\s{2,}|—",L[q]['text']) and not heading(txt): continue
            h=heading(txt)
            if h:
                if h[0]=='county': county=h[1]; city=None
                elif h[0]=='city': city=h[1]
                else: county=h[1]; city=h[1]
        rec['city_ctx']=city or ''; rec['county_ctx']=county or ''
        body_end = max(F['end']+1, found[k+1]['top']) if k+1<len(found) else n
        sics=[]; extra=[]
        for q in range(F['end']+1, body_end):
            if L[q]['hdr'] or q in used: continue
            s=parse_sic(L[q]['text'])
            if s: sics.append(s)
            else: extra.append(L[q]['text'])
        if year in NO_PRINTED_CODES:
            # this edition prints no codes: a line that reads as 'code + text' is a street line ('2040 LAWRENCE'), not an industry
            sics=[]
        rec['sic']=[c for c,_ in sics]; rec['sic_desc']=[d for _,d in sics]
        rec['extra']=extra[:6]
        stats['namelike_extra']+=name_like_extra([L[q]['text'] for q in range(F['end']+1, body_end) if not L[q]['hdr'] and q not in used], stats['examples'])
        if not rec['name']: stats['nameless']+=1
        recs.append(rec)
    if ctx is not None: ctx.update(city=city,county=county,page_start=page_start)
    return recs

if __name__=='__main__':
    vol=sys.argv[1]; year=int(sys.argv[2]); tsvdir=sys.argv[3] if len(sys.argv)>3 else 'work/tsv'
    recs=parse_volume(vol,tsvdir,year)
    os.makedirs('work/parsed',exist_ok=True)
    with open(f'work/parsed/{vol}.jsonl','w') as f:
        for r in recs: f.write(json.dumps(r)+'\n')
    import collections
    print(vol, len(recs), 'with zip', sum(1 for r in recs if r['zip']), 'with sic', sum(1 for r in recs if r['sic']), 'with est', sum(1 for r in recs if r.get('est')))
