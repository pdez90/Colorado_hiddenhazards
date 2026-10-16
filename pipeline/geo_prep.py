import pandas as pd, re
df=pd.read_pickle('work/inv/records.pkl')
zc=pd.read_csv('work/inv/zip_city.csv',dtype=str).set_index(df.columns[0] if False else 'z')['CITY_NAME'].to_dict()
def city_for(r):
    z=r['zip'] if isinstance(r['zip'],str) else ''
    c=(r.get('city_ctx') or '')
    if isinstance(c,str): c=c.upper().strip()
    if z and z in zc: return zc[z]
    return c or ''
df['city_g']=df.apply(city_for,axis=1)
def kind(s):
    s=s or ''
    if not s: return 'none'
    if re.match(r"^(P ?O ?BOX|BOX|DRAWER|P O DRAWER)\b",s): return 'pobox'
    if re.match(r"^(RT|RR|ROUTE|STAR RT|RFD|R F D)\b",s): return 'rural'
    if re.match(r"^\d",s): return 'street'
    return 'named'   # e.g. 'FACTORY GROUNDS', 'MAIN ST' no number, 'S OF FORT COLLINS'
df['addr_kind']=df.street_n.apply(kind)
df['zip5']=df.zip.fillna('').astype(str).str[:5]
df['geo_key']=(df.street_n.fillna('')+'|'+df.city_g.fillna('')+'|'+df.zip5)
df.to_pickle('work/inv/records_geo.pkl')
h=df[df.fe_hazard|df.ext_hazard]
print('hazard records',len(h)); print(h.addr_kind.value_counts().to_dict())
u=h[h.addr_kind.isin(['street','named'])].drop_duplicates('geo_key')
print('unique geocodable hazard addresses',len(u))
print('all unique street addresses',df[df.addr_kind=='street'].geo_key.nunique())
