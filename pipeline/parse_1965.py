"""1965 format: 'SIC Ecode NAME' line, then street line. City headings as standalone lines; page header 'CITY nn'."""
import re, sys, os, glob, json
sys.path.insert(0, os.path.dirname(__file__))
from segment import page_lines
from geoctx import heading
from parse_block import norm_digits, city_heading, fix_street, CITIES

HEAD = re.compile(r"^\W{0,3}([0-9OIlSBZ$€£]{4})\s+[E€£]\s?([0-9OIlS]?)\W?\s+(.+)$")
ECODE = {'0':'0-19','1':'1-19','2':'20-99','3':'100-249','4':'250-999','5':'1000+'}

def fix_dir(s):
    s=re.sub(r"\b(h|hk|Ww|w|W|H)\.?(?=\s)", "W", s)
    return s

def parse(vol, tsvdir, year):
    recs=[]; city=None; county=None
    for p in sorted(glob.glob(f"{tsvdir}/{vol}/p*.tsv")):
        pg=int(os.path.basename(p)[1:4])
        L,cuts=page_lines(p,adaptive=(2,))   # 2-column pages; forced split when the gutter is missed
        if not L: continue
        top=min(l['y'] for l in L)
        i=0
        while i<len(L):
            t=L[i]['text'].strip()
            if L[i]['y']-top<60 and len(t)<40:
                h=heading(re.sub(r"[\d\u2014\-]+"," ",t).strip())
                if h and h[0] in('city','both'): city=h[1]
                i+=1; continue
            m=HEAD.match(t)
            if m:
                code=norm_digits(m.group(1).replace('€','8').replace('£','8'))
                e=norm_digits(m.group(2)) if m.group(2) else ''
                name=m.group(3).strip()
                street=''
                if i+1<len(L) and not HEAD.match(L[i+1]['text'].strip()) and not heading(L[i+1]['text']):
                    street=L[i+1]['text'].strip(' _.~-'); i+=1
                recs.append(dict(vol=vol,year=year,page=pg,col=L[i]['col'],y=L[i]['y'],name=name,
                    street=fix_street(fix_dir(street)),addr_raw=street,zip='',city_ctx=city or '',county_ctx=county or '',
                    sic=[code] if code.isdigit() else [],sic_desc=[],size=ECODE.get(e,''),est=None))
            else:
                h=heading(t)
                if h:
                    if h[0]=='county': county=h[1]; city=None
                    elif h[0]=='city': city=h[1]
                    else: county=h[1]; city=h[1]
            i+=1
    return recs

if __name__=='__main__':
    vol=sys.argv[1]; year=int(sys.argv[2]); tsvdir=sys.argv[3] if len(sys.argv)>3 else 'work/tsv'
    R=parse(vol,tsvdir,year)
    with open(f'work/parsed/{vol}.jsonl','w') as f:
        for r in R: f.write(json.dumps(r)+'\n')
    print(vol,len(R),'with sic',sum(1 for r in R if r['sic']),'with city',sum(1 for r in R if r['city_ctx']))
