"""1988 format:
NAME (1-2 lines)
street (zip)
CITY - COUNTY COUNTY
yyyy=EST (303)xxx-xxxx MARKET
ORG size=EMP
officers...
SIC lines (dddd text, may wrap)
"""
import re, sys, os, glob, json
sys.path.insert(0, os.path.dirname(__file__))
from segment import page_lines
from parse_block import norm_digits, fix_street, parse_sic, PHONE, NUMSTART, POBOX, street_like

ESTL = re.compile(r"^\W{0,2}(\S{4})\s*[=:\-]+\s*[EB8][S5$][T7]")
ZIPP = re.compile(r"\(?\s*([0-9A-Za-z]{5})\s*\)?\s*$")
CITYL = re.compile(r"^([A-Z][A-Z \.'\-]+?)\s*[-—\.]\s*([A-Z][A-Z \.'\-]*?)\s*COUN", re.I)

def street_above(L, j, lo, addr, cityline):
    """The street line when it carries no '(ZIP' of its own. j: index of the line above the address / town line found
    so far; lo: first line that can belong to this listing. Returns (index of the line above the street, address text).
    The ZIP is often read as a line of its own ('2180 S DELEWARE' / '(enzze') or lost ('3010 S TEJON eer'), and a
    house number 2000-3999 makes the street line look like a SIC line, which ended the search for the name: 107 listings
    of 1988 came out without a firm name. The line right above the town line (or above a bare ZIP) is the street when
    it starts with a number or 'PO BOX' and what follows is not a code description; OCR specks (<= 3 characters)
    between the lines are skipped."""
    junk=lambda q: len(re.sub(r"[^A-Za-z0-9]","",L[q]['text']))<=2 or (len(L[q]['text'].strip())<=3 and not L[q]['text'].strip().isupper())
    def is_street(t):
        if POBOX.match(t): return True
        if not NUMSTART.match(t): return False
        s=parse_sic(t)
        return not s or street_like(s[1]) or len(s[1].split())<=2
    q=j
    while q>=lo and junk(q): q-=1
    if q<lo: return j,addr
    t=L[q]['text'].strip()
    bare_zip = addr is not None and not re.search(r"[A-Za-z0-9]",addr[:addr.find('(')])
    if (bare_zip or (addr is None and cityline is not None)) and is_street(t) and q-1>=lo and not parse_sic(L[q-1]['text']):
        addr=t+(' '+addr.strip() if addr else ''); q-=1
        while q>=lo and junk(q): q-=1
        return q,addr
    return j,addr

def parse(vol, tsvdir, year):
    L=[]
    for p in sorted(glob.glob(f"{tsvdir}/{vol}/p*.tsv")):
        pg=int(os.path.basename(p)[1:4])
        pl,_=page_lines(p)
        for l in pl: l['page']=pg; L.append(l)
    anchors=[i for i,l in enumerate(L) if ESTL.search(l['text']) or (re.search(r"EST\b",l['text']) and re.search(r"\(\d{3}\)",l['text']))]
    recs=[]
    for k,i in enumerate(anchors):
        j=i-1; cityline=None; addr=None; names=[]
        lo=anchors[k-1]+2 if k>0 else 0
        for q in range(i-1, max(lo-1,i-4), -1):
            t=L[q]['text']
            if addr is None and re.search(r"\(\s*[0-9A-Za-z]{5}",t):
                addr=t; j=q-1
                mc=re.search(r"\(\s*[0-9A-Za-z]{5}\)?\s*(.+)$",t)
                if mc and cityline is None and len(mc.group(1))>3: cityline=mc.group(1)+' - COUNTY'
                break
            if cityline is None and re.search(r"COUN|CNTY",t.upper()): cityline=t; j=q-1
        prev_end = anchors[k-1]+2 if k>0 else 0
        j,addr=street_above(L,j,prev_end,addr,cityline)
        while j>=prev_end and len(names)<2:
            t=L[j]['text'].strip()
            if parse_sic(t) or re.search(r",\s*(PRESIDENT|OWNER|MANAGER|PARTNER|VICE|SECRETARY|GENERAL|CHIEF|SALES|DIRECTOR|TREASURER)",t.upper()): break
            if re.match(r"^\d{1,4}\s+[A-Z]+\s*-\s*[A-Z]+$",t) or re.match(r"^[A-Z][A-Z ]+\s*-\s*[A-Z][A-Z ]+\s+\d{1,4}$",t): break  # page header
            # the wrapped end of the previous listing's last SIC description ('3499 VACUUM FLANGES, FITTINGS' / '+ VALVES';
            # '3629 WELDING APPARATUS,' / 'ELECTRIC') is not the first line of this firm's name
            if names and j-1>=prev_end and parse_sic(L[j-1]['text']) and (re.match(r"^\W*[+&]",t) or re.search(r"([,+&]|\bAND|\bOR)\s*$",L[j-1]['text'].strip())): break
            names.insert(0,t); j-=1
            if len(names)==1 and re.search(r"(INC|CO|CORP|LTD|COMPANY|CORPORATION)\.?$",t.upper()):
                # likely complete single-line name unless previous line is a name start
                pass
        name=' '.join(names)
        rec=dict(vol=vol,year=year,page=L[i]['page'],col=L[i]['col'],y=L[i]['y'],name=name,addr_raw=addr or '',zip='',street='',city_ctx='',county_ctx='')
        if addr:
            m=re.search(r"\(\s*([0-9A-Za-z]{5})",addr)
            if m:
                z=norm_digits(m.group(1))
                if z.isdigit():
                    z='8'+z[1:]
                    if z[1] in '01': rec['zip']=z
                rec['street']=fix_street(addr[:m.start()].strip(' ,'))
            else: rec['street']=fix_street(addr)
        if cityline:
            m=CITYL.search(cityline.upper())
            if m: rec['city_ctx']=m.group(1).strip(); rec['county_ctx']=m.group(2).strip()
            else: rec['city_ctx']=re.sub(r"\s*-\s*COUNTY$","",cityline.upper()).strip()
        m=ESTL.search(L[i]['text'])
        if m:
            y=norm_digits(m.group(1))
            if y.isdigit() and 1800<=int(y)<=1993: rec['est']=int(y)
        # org/size line
        if i+1<len(L):
            t=L[i+1]['text'].upper()
            ms=re.search(r"(\d[\d,]*\s*-\s*\d[\d,]*|\d+\+)\s*=",t)
            if ms: rec['size']=ms.group(1).replace(' ','')
            mo=re.match(r"^(PUBLIC|PRIVATE|PARTNERSHIP|SOLE PROPRIETORSHIP|COOPERATIVE|SUBSIDIARY|DIVISION|NON-?PROFIT|GOVERNMENT)",t)
            if mo: rec['org']=mo.group(1)
        nxt=anchors[k+1] if k+1<len(anchors) else len(L)
        sics=[]
        for q in range(i+2, nxt):
            s=parse_sic(L[q]['text'])
            if s: sics.append(s)
        rec['sic']=[c for c,_ in sics]; rec['sic_desc']=[d for _,d in sics]
        recs.append(rec)
    return recs

if __name__=='__main__':
    vol=sys.argv[1]; year=int(sys.argv[2]); tsvdir=sys.argv[3] if len(sys.argv)>3 else 'work/tsv'
    R=parse(vol,tsvdir,year)
    with open(f'work/parsed/{vol}.jsonl','w') as f:
        for r in R: f.write(json.dumps(r)+'\n')
    print(vol,len(R),'zip',sum(1 for r in R if r['zip']),'sic',sum(1 for r in R if r['sic']),'city',sum(1 for r in R if r['city_ctx']),'est',sum(1 for r in R if r.get('est')))
