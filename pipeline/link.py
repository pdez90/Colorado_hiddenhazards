"""Link directory listings across years into establishments (firm-at-place) using fuzzy name + location blocking."""
import pandas as pd, numpy as np, re
from rapidfuzz import fuzz
df=pd.read_pickle('work/inv/records_geo.pkl').reset_index(drop=True)
df['name_n']=df.name_n.fillna('')
df['blk']=np.where(df.zip5.str.match(r'^8[01]\d{3}$'), df.zip5, df.city_g.fillna('').str.upper())
parent=list(range(len(df)))
def find(a):
    while parent[a]!=a:
        parent[a]=parent[parent[a]]; a=parent[a]
    return a
def union(a,b):
    ra,rb=find(a),find(b)
    if ra!=rb: parent[rb]=ra
# also block by city for records without zip -> compare with all zips mapped to that city
for blk,g in df.groupby('blk'):
    if not blk or len(g)<2: continue
    idx=g.index.values; names=g.name_n.values; streets=g.street_n.fillna('').values
    for a in range(len(idx)):
        for b in range(a+1,len(idx)):
            if not names[a] or not names[b]: continue
            s=fuzz.token_set_ratio(names[a],names[b])
            same_st = streets[a] and streets[a]==streets[b]
            num_a=re.match(r'^(\d+)',streets[a]); num_b=re.match(r'^(\d+)',streets[b])
            same_num = num_a and num_b and num_a.group(1)==num_b.group(1)
            if s>=92 or (s>=80 and (same_st or same_num)):
                union(idx[a],idx[b])
# second pass: no-zip records (1961-65) to zip records in same city by name
cz=df[df.blk.str.match(r'^8')].groupby(df.city_g.fillna('')).groups
for city,g in df[~df.blk.str.match(r'^8')].groupby('blk'):
    if not city or city not in cz: continue
    cand=df.loc[cz[city]]
    for i,r in g.iterrows():
        if not r.name_n: continue
        sc=cand.name_n.apply(lambda n: fuzz.token_set_ratio(r.name_n,n) if n else 0)
        j=sc.idxmax() if len(sc) else None
        if j is not None and sc[j]>=92: union(i,j)
df['estab_id']=[find(i) for i in range(len(df))]
df['estab_id']=df.groupby('estab_id').ngroup().map(lambda x:'E%06d'%x)
df.to_pickle('work/inv/records_linked.pkl')
g=df.groupby('estab_id').year.agg(['min','max','nunique'])
print('records',len(df),'establishments',len(g)); print(g['nunique'].describe().round(2).to_dict())
