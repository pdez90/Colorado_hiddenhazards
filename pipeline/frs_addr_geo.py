import pandas as pd, numpy as np, sys
sys.path.insert(0,'pipeline')
from consolidate import norm_street
reg=pd.read_pickle('work/inv/reg.pkl')
r=reg.dropna(subset=['lat','lon']).copy()
r['street_n']=r.address.fillna('').apply(norm_street); r['zip5']=r.zip.fillna('').astype(str).str[:5]
r=r[r.street_n.str.match(r'^\d')]
addr=r.groupby(['street_n','zip5']).agg(lat=('lat','median'),lon=('lon','median'),n=('lat','size')).reset_index()
zc=r[r.zip5.str.match(r'^8[01]\d{3}$')].groupby('zip5').agg(zlat=('lat','median'),zlon=('lon','median'),zn=('lat','size')).reset_index()
addr.to_pickle('work/inv/frs_addr.pkl'); zc.to_pickle('work/inv/zip_centroids.pkl')
print('FRS address points',len(addr),'ZIP centroids',len(zc))
