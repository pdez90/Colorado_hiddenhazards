"""Paragraph formats.
1990-1993: NAME (caps line) / officers. street, City zip. (phone) County. Began in YYYY. N employees. Org. / SIC (scope) product.
1999:      NAME / phone / officers. street, City CO zip-4. County, Metro. Began YYYY. N people. Org. / NAICS:desc, scope.
2002:      city heading 'X city, Y County' / NAME (NAICS) / street zip / phone
"""
import re, sys, os, glob, json
sys.path.insert(0, os.path.dirname(__file__))
from segment import page_lines
from parse_block import fix_street, norm_digits
from geoctx import heading

def is_name(t):
    t=t.strip()
    if len(t)<3: return False
    if re.match(r"^\W{0,2}\(?\d{3}\)?[-\s]?\d{3}[-\s]?\d{4}",t) or 'FAX' in t.upper(): return False
    if sum(ch.isdigit() for ch in t)>len(t)*0.3: return False
    letters=re.sub(r"[^A-Za-z]","",t)
    if len(letters)<3: return False
    up=sum(c.isupper() for c in letters)/len(letters)
    if up<0.9: return False
    if re.match(r"^\d{3,4}\s*\(",t) or re.match(r"^\d{5,6}[:\-]",t): return False
    if re.search(r"\b(FAX|COUNTY|BEGAN)\b",t.upper()) and up<1: return False
    return True

ADDR = re.compile(r"(?:^|[\.;]\s+|,\s+(?=\d))((?:\d[\w\-/]*|PO Box|P O Box|One|Two|Three|Hwy|Highway|Rt|Route|County Rd|CR)\b[^\.]*?(?:\.[^\.\d][^\.]*?)??),\s*([A-Z][A-Za-z\.' ]+?)\s*(?:,?\s*CO)?\s*,?\s*([8&B][0O1][0-9OIlS]{3})(?:-\d{4})?\b")

ADDR2 = re.compile(r"(?<![\d\-])((?:\d{1,6}[A-Z]?|PO Box \d+)\s+[A-Za-z0-9][^,\.]{2,60}?(?:\.\s?[A-Z][^,\.]{0,30}?)?),\s*([A-Z][A-Za-z\.' ]+?)\s+(?:CO|C0|CQ|Co)\s*\.?\s*([8&B][0O1][0-9OIlS]{3})")
def parse_text_record(name, text, year, vol, page, col):
    r=dict(vol=vol,year=year,page=page,col=col,name=name.strip(),zip='',street='',city_ctx='',county_ctx='',sic=[],sic_desc=[],naics=[])
    t=re.sub(r"\s+"," ",text)
    t_nomail=re.sub(r"Mail(ing)?\s*:.*?(?=(\(\d{3}\)|[A-Z][a-z]+ County|Began|$))","",t)
    m=ADDR.search(t_nomail)
    if not m:
        m=ADDR2.search(t_nomail)
    if not m:
        m3=re.search(r"(?<![\d\-])(\d{1,6}[A-Z]?\s+[A-Za-z0-9][^,]{2,50}?)(?:,\s*(?:Ste|Suite|Unit|No|#)[^,]{0,12})?,\s*([8&B][0O1][0-9OIlS]{3})(?:-\d{4})?\b",t_nomail)
        if m3:
            r['street']=fix_street(m3.group(1)); z=norm_digits(m3.group(2)); z='8'+z[1:]
            if z.isdigit(): r['zip']=z
            r['addr_raw']=m3.group(0)
    if m:
        r['street']=fix_street(m.group(1)); r['city_ctx']=re.sub(r"(\s+(CO|CC|C0|CQ))?\W*$","",m.group(2).strip().upper()).strip()
        z=norm_digits(m.group(3)); z='8'+z[1:]
        if z.isdigit(): r['zip']=z
        r['addr_raw']=m.group(0)
    mc=re.search(r"([A-Z][a-z]+(?: [A-Z][a-z]+)?) County",t)
    if mc: r['county_ctx']=mc.group(1).upper()
    mb=re.search(r"Beg[a-z]{1,3}\s*(?:in\s*)?(1[89]\d\d|20[0-2]\d)",t)
    if mb: r['est']=int(mb.group(1))
    ms=re.search(r"(\d[\d,]*\s*-\s*\d[\d,]*|\d[\d,]*\+?)\s*(employees|people|person)",t)
    if ms: r['size']=ms.group(1).replace(' ','')
    mo=re.search(r"(Private corporation|Public corporation|Sole proprietorship|Proprietorship|Partnership|Cooperative|Subsidiary|Division)",t)
    if mo: r['org']=mo.group(1)
    for c,d in re.findall(r"(?<!Began )(?<!in )\b(\d{4})\s*(?:\((?:[a-z]+)\)\s*)?([a-z][^\.]{2,80})",t):
        if (2000<=int(c)<=3999 or 1000<=int(c)<=1499) and c not in r['sic']: r['sic'].append(c); r['sic_desc'].append(d.strip())
    for c,d in re.findall(r"\b(\d{5,6})\s?[:\-]\s?([A-Za-z][^,\.]{2,70})",t):
        if c[:2] in ('31','32','33','21','11','42','54','56','81','22'): r['naics'].append(c); r['sic_desc'].append(d.strip())
    return r

def parse_lines(L, vol, year):
    recs=[]; cur=None; city=''
    for l in L:
        t=l['text'].strip()
        if not t or re.match(r"^\d{1,3}$",t) or re.search(r"GEOGRAPHICAL SECTION",t.upper()): continue
        mcont=re.match(r"^([A-Z][A-Z \.']+),\s*Cont",t)
        if mcont: city=mcont.group(1).strip(); continue
        if re.match(r"^\(\s*[A-Z][a-z]+(?: [A-Z][a-z]+)? County\s*\)$",t): continue
        hh=heading(t) if t.isupper() and len(t)<30 else None
        if hh and hh[0] in ('city','both'):
            city=hh[1]
            if cur: recs.append(cur); cur=None
            continue
        if is_name(t) and not (cur and cur['text'].rstrip().endswith((',','-')) and len(cur['text'])<40) and not (cur and cur['text']=='' and len(cur['name'])<45 and not re.search(r"(INC|CO|CORP|LTD|LLC|COMPANY)\.?$",cur['name'])):
            if cur: recs.append(cur)
            cur=dict(name=t,text='',page=l.get('page',0),col=l.get('col',0),city=city)
        elif cur: cur['text']+=' '+t
    if cur: recs.append(cur)
    out=[]
    for c in recs:
        r=parse_text_record(c['name'],c['text'],year,vol,c['page'],c['col'])
        if not r['city_ctx'] and c.get('city'): r['city_ctx']=c['city']
        if r['zip'] or r['sic'] or r['naics'] or r.get('est'): out.append(r)
    return out

def parse_tsv(vol,tsvdir,year,ncols=3):
    L=[]
    for p in sorted(glob.glob(f"{tsvdir}/{vol}/p*.tsv")):
        pg=int(os.path.basename(p)[1:4])
        pl,_=page_lines(p,ncols=ncols)
        for l in pl: l['page']=pg; L.append(l)
    return parse_lines(L,vol,year)

def parse_coltxt(vol,year):
    L=[]
    for p in sorted(glob.glob(f"work/coltxt/{vol}/p*.txt")):
        pg=int(os.path.basename(p)[1:4]); col=0
        for line in open(p):
            if line.startswith('=====COL'): col=int(line.split()[-1]); continue
            L.append(dict(text=line.rstrip('\n'),page=pg,col=col))
    return parse_lines(L,vol,year)

if __name__=='__main__':
    vol=sys.argv[1]; year=int(sys.argv[2]); mode=sys.argv[3] if len(sys.argv)>3 else 'tsv'
    R=parse_coltxt(vol,year) if mode=='coltxt' else parse_tsv(vol,'work/tsv',year)
    with open(f'work/parsed/{vol}.jsonl','w') as f:
        for r in R: f.write(json.dumps(r)+'\n')
    print(vol,len(R),'zip',sum(1 for r in R if r['zip']),'sic',sum(1 for r in R if r['sic']),'naics',sum(1 for r in R if r['naics']),'est',sum(1 for r in R if r.get('est')))
