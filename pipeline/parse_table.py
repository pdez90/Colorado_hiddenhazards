"""1961/1962 table format: COMPANY NAME | ADDRESS | EMPLOYMENT | PRODUCT, grouped under county & city headings."""
import re, sys, os, glob, json, statistics
sys.path.insert(0, os.path.dirname(__file__))
from segment import load_words, find_columns
from geoctx import heading
from parse_block import fix_street

EMP = re.compile(r"^\s*([0-9OIlS]{1,4})\s*[-–~]\s*([0-9OIlS]{1,4})\s*$")
def rows(W, mh):
    W=sorted(W,key=lambda w:w['t']+w['h']/2)
    R=[]
    for w in W:
        cy=w['t']+w['h']/2
        if R and abs(cy-R[-1]['cy'])<0.5*mh:
            R[-1]['ws'].append(w); n=len(R[-1]['ws']); R[-1]['cy']=(R[-1]['cy']*(n-1)+cy)/n
        else: R.append(dict(cy=cy,ws=[w]))
    for r in R: r['ws'].sort(key=lambda w:w['l'])
    return R

def parse(vol,tsvdir,year):
    recs=[]; city=None; county=None
    for p in sorted(glob.glob(f"{tsvdir}/{vol}/p*.tsv")):
        pg=int(os.path.basename(p)[1:4])
        W=load_words(p)
        if len(W)<20: continue
        hs=[w['h'] for w in W if w['h']>5]; mh=statistics.median(hs)
        W=[w for w in W if w['h']<4*mh]
        pw=max(w['l']+w['w'] for w in W)+5
        # header row positions
        hdr=[w for w in W if w['s'].upper().strip(':') in ('ADDRESS','EMPLOYMENT','PRODUCT','CLASSIFICATION','INDUSTRY')]
        cuts=None
        xa=[w['l'] for w in W if w['s'].upper()=='ADDRESS']
        xe=[w['l'] for w in W if w['s'].upper()=='EMPLOYMENT']
        xp=[w['l'] for w in W if w['s'].upper() in('PRODUCT','INDUSTRY')]
        if xa and xe and xp:
            cuts=[min(xa)-15, min(xe)-15, min(xp)-15]
        else:
            c=find_columns(W,pw,mingap=int(1.5*mh))
            if len(c)>=3: cuts=c[:3]
        R=rows(W,mh)
        for r in R:
            text=' '.join(w['s'] for w in r['ws']).strip()
            if not cuts:
                continue
            f=['','','','']
            for w in r['ws']:
                k=sum(1 for c in cuts if w['l']>=c)
                f[k]+=' '+w['s']
            f=[x.strip() for x in f]
            # heading rows: only field0, no other fields
            if f[0] and not f[1] and not f[2] and not f[3]:
                h=heading(f[0])
                if h:
                    if h[0]=='county': county=h[1]; city=None
                    elif h[0]=='city': city=h[1]
                    else: county=h[1]; city=h[1]
                    continue
                # continuation of previous name (wrapped)
                if recs and recs[-1]['page']==pg and abs(r['cy']-recs[-1]['y'])<2.5*mh and not re.search(r'COMPANY|NAME',f[0]):
                    recs[-1]['name_cont']=f[0]
                continue
            if re.search(r"COMPANY|EMPLOYMENT",text.upper()): continue
            if not f[0] and recs and recs[-1]['page']==pg and abs(r['cy']-recs[-1]['y'])<2.5*mh:
                # product wrap line
                if f[3]: recs[-1]['product']+=' '+f[3]
                continue
            if not f[0]: continue
            emp=f[2]
            mm=re.match(r"^\s*([0-9OIlS]{1,4}\s*[-\u2013~]\s*[0-9OIlS]{1,4}|\d{1,4}\+?)\s*(.*)$",emp)
            if mm:
                emp=mm.group(1).replace(' ','')
                if mm.group(2): f[3]=(mm.group(2)+' '+f[3]).strip()
            elif emp and not re.search(r"\d",emp):
                f[3]=(emp+' '+f[3]).strip(); emp=''
            recs.append(dict(vol=vol,year=year,page=pg,col=0,y=int(r['cy']),name=f[0],street=fix_street(f[1]),addr_raw=f[1],
                zip='',city_ctx=city or '',county_ctx=county or '',size=emp,product=f[3],sic=[],sic_desc=[f[3]] if f[3] else [],est=None))
    return recs

if __name__=='__main__':
    vol=sys.argv[1]; year=int(sys.argv[2]); tsvdir=sys.argv[3] if len(sys.argv)>3 else 'work/tsv'
    R=parse(vol,tsvdir,year)
    with open(f'work/parsed/{vol}.jsonl','w') as f:
        for r in R: f.write(json.dumps(r)+'\n')
    print(vol,len(R),'with product',sum(1 for r in R if r['product']),'with city',sum(1 for r in R if r['city_ctx']), 'with street', sum(1 for r in R if r['street']))
