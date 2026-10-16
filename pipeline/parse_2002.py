import re, sys, os, glob, json
sys.path.insert(0, os.path.dirname(__file__))
from segment import page_lines
from parse_block import fix_street, norm_digits
HEADC = re.compile(r"^([A-Z][A-Za-z\.' ]+?)\s+(city|town|CDP|City and County)?\s*,\s*([A-Z][A-Za-z ]+?)\s+County", re.I)
NAMEL = re.compile(r"^(.*?[A-Z0-9&].*?)\s*\(\s*([0-9OIlS]{5,6})\s*\)\s*$")
def parse(vol, year, ncols=2):
    L=[]
    for p in sorted(glob.glob(f"work/tsv/{vol}/p*.tsv")):
        pg=int(os.path.basename(p)[1:4])
        pl,_=page_lines(p,ncols=ncols)
        for l in pl: l['page']=pg; L.append(l)
    recs=[]; city=''; county=''; pend=None
    i=0
    while i<len(L):
        t=L[i]['text'].strip()
        m=HEADC.match(t)
        if m and 'Population' not in t:
            city=m.group(1).strip().upper(); county=m.group(3).strip().upper(); i+=1; continue
        mn=NAMEL.match(t)
        if not mn and i+1<len(L) and re.match(r"^\(\s*[0-9OIlS]{5,6}\s*\)\s*$",L[i+1]['text'].strip()):
            mn=NAMEL.match(t+' '+L[i+1]['text'].strip()); i+=1 if mn else 0
        if mn:
            name=mn.group(1).strip(); naics=norm_digits(mn.group(2))
            street=''; z=''
            if i+1<len(L):
                a=L[i+1]['text'].strip()
                mz=re.search(r"\b([8B&][0O1][0-9OIlS]{3})(?:-?\d{4})?\s*$",a)
                if mz:
                    zz=norm_digits(mz.group(1)); zz='8'+zz[1:]
                    if zz.isdigit(): z=zz
                    street=fix_street(a[:mz.start()])
                    i+=1
            recs.append(dict(vol=vol,year=year,page=L[i]['page'],col=L[i]['col'],name=name,street=street,zip=z,city_ctx=city,county_ctx=county,
                             sic=[],sic_desc=[],naics=[naics] if naics.isdigit() else []))
        i+=1
    return recs
if __name__=='__main__':
    vol=sys.argv[1]; year=int(sys.argv[2]); nc=int(sys.argv[3]) if len(sys.argv)>3 else 2
    R=parse(vol,year,nc)
    with open(f'work/parsed/{vol}.jsonl','w') as f:
        for r in R: f.write(json.dumps(r)+'\n')
    print(vol,len(R),'zip',sum(1 for r in R if r['zip']),'naics',sum(1 for r in R if r['naics']),'city',sum(1 for r in R if r['city_ctx']))
