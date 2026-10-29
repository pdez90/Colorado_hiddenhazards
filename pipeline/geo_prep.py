import pandas as pd, re
# a ZIP printed after the street often lands in the street field ('1546 GLENARM PL 0202' = 80202, the leading 8 lost);
# move it to the ZIP when the ZIP is blank and the code exists in Colorado; drop other trailing ZIP-like fragments
def zip_from_street(r,zips):
    """r: mapping with street_n, zip; zips: set of Colorado ZIP codes. Returns (street, zip)."""
    s=r['street_n'] or ''; z=r['zip'] if isinstance(r['zip'],str) else ''
    m=re.search(r"\s(0\d{3}|8[01]\d{3}|8\d{4})$",s)
    if not m or not re.match(r"^\d+\s+\S+\s+\S",s): return s,z
    t=m.group(1); cand='8'+t if len(t)==4 else t
    if not z and cand in zips: z=cand
    return s[:m.start()].strip(),z
def city_for(r,zc):
    """City for geocoding: the ZIP's city when the ZIP is known (zc: zip -> CITY_NAME), else the page's town heading."""
    z=r['zip'] if isinstance(r['zip'],str) else ''
    c=(r.get('city_ctx') or '')
    if isinstance(c,str): c=c.upper().strip()
    if z and z in zc: return zc[z]
    return c or ''
def kind(s):
    s=s or ''
    if not s: return 'none'
    if re.match(r"^(P ?O ?BOX|BOX|DRAWER|P O DRAWER)\b",s): return 'pobox'
    if re.match(r"^(RT|RR|ROUTE|STAR RT|RFD|R F D)\b",s): return 'rural'
    if re.match(r"^\d",s): return 'street'
    return 'named'   # e.g. 'FACTORY GROUNDS', 'MAIN ST' no number, 'S OF FORT COLLINS'
def main():
    df=pd.read_pickle('work/inv/records.pkl')
    zc=pd.read_csv('work/inv/zip_city.csv',dtype=str).set_index('z')['CITY_NAME'].to_dict()
    _ZIPS=set(zc)
    df[['street_n','zip']]=[zip_from_street(r,_ZIPS) for _,r in df.iterrows()]
    df['city_g']=df.apply(lambda r: city_for(r,zc),axis=1)
    df['addr_kind']=df.street_n.apply(kind)
    df['zip5']=df.zip.fillna('').astype(str).str[:5]
    df['geo_key']=(df.street_n.fillna('')+'|'+df.city_g.fillna('')+'|'+df.zip5)
    df.to_pickle('work/inv/records_geo.pkl')
    h=df[df.fe_hazard|df.ext_hazard]
    print('hazard records',len(h)); print(h.addr_kind.value_counts().to_dict())
    u=h[h.addr_kind.isin(['street','named'])].drop_duplicates('geo_key')
    print('unique geocodable hazard addresses',len(u))
    print('all unique street addresses',df[df.addr_kind=='street'].geo_key.nunique())
if __name__=='__main__': main()
