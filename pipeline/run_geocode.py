import pandas as pd, sys
sys.path.insert(0,'pipeline')
from tiger_geocode import Geocoder
from concurrent.futures import ProcessPoolExecutor
df=pd.read_pickle('work/inv/records_linked.pkl')
u=df[df.addr_kind.isin(['street','named'])].drop_duplicates('geo_key')[['geo_key','street_n','city_g','zip5']].reset_index(drop=True)
# also city/zip-only keys for records without street (for centroid fallback)
v=df[~df.addr_kind.isin(['street','named'])].drop_duplicates('geo_key')[['geo_key','street_n','city_g','zip5']]
u=pd.concat([u,v]).drop_duplicates('geo_key').reset_index(drop=True)
G=None
def init():
    global G; G=Geocoder()
def work(rows):
    return [(k,)+tuple(G.geocode(s,c,z)) for k,s,c,z in rows]
chunks=[list(u.iloc[i:i+500].itertuples(index=False,name=None)) for i in range(0,len(u),500)]
with ProcessPoolExecutor(2,initializer=init) as ex:
    res=[r for part in ex.map(work,chunks) for r in part]
out=pd.DataFrame(res,columns=['geo_key','lat','lon','geo_quality'])
out.to_csv('work/geo/tiger_results.csv',index=False)
print(len(out)); print(out.geo_quality.value_counts().to_string())
