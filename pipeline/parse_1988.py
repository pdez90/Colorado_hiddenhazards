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
from parse_block import norm_digits, fix_street, parse_sic, PHONE

ESTL = re.compile(r"^\W{0,2}(\S{4})\s*[=:\-]+\s*[EB8][S5$][T7]")
ZIPP = re.compile(r"\(?\s*([0-9A-Za-z]{5})\s*\)?\s*$")
CITYL = re.compile(r"^([A-Z][A-Z \.'\-]+?)\s*[-—\.]\s*([A-Z][A-Z \.'\-]*?)\s*COUN", re.I)

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
        while j>=prev_end and len(names)<2:
            t=L[j]['text'].strip()
            if parse_sic(t) or re.search(r",\s*(PRESIDENT|OWNER|MANAGER|PARTNER|VICE|SECRETARY|GENERAL|CHIEF|SALES|DIRECTOR|TREASURER)",t.upper()): break
            if re.match(r"^\d{1,4}\s+[A-Z]+\s*-\s*[A-Z]+$",t): break  # page header
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
