import pandas as pd, numpy as np, sys, glob, warnings
sys.path.insert(0,'pipeline')
from consolidate import norm_street
reg=pd.read_pickle('work/inv/reg.pkl')
r=reg.dropna(subset=['lat','lon']).copy()
r['street_n']=r.address.fillna('').apply(norm_street); r['zip5']=r.zip.fillna('').astype(str).str[:5]
r=r[r.street_n.str.match(r'^\d')]
addr=r.groupby(['street_n','zip5']).agg(lat=('lat','median'),lon=('lon','median'),n=('lat','size')).reset_index()
zc=r[r.zip5.str.match(r'^8[01]\d{3}$')].groupby('zip5').agg(zlat=('lat','median'),zlon=('lon','median'),zn=('lat','size')).reset_index()

# A ZIP centroid drives the geocoder's 15 km town check and the ZIP fallback point. The median of the inventory records filed under a
# ZIP is used only when it rests on 3+ records and lies within 50 km of the median of the ZIP's own TIGER street segments; otherwise
# (one or two records, or records whose ZIP is wrong) the TIGER median is used (FINDING 6 of 12 Nov 2026; 20 Nov 2026).
def hav_km(a1,o1,a2,o2):
    a1,o1,a2,o2=map(np.radians,(a1,o1,a2,o2))
    return 2*6371*np.arcsin(np.sqrt(np.sin((a2-a1)/2)**2+np.cos(a1)*np.cos(a2)*np.sin((o2-o1)/2)**2))
shp=sorted(glob.glob('work/tiger/*_addrfeat.shp'))
if shp:
    import geopandas as gpd
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        G=pd.concat([gpd.read_file(f,columns=['ZIPL','ZIPR']) for f in shp],ignore_index=True); c=G.geometry.centroid
    T=pd.concat([pd.DataFrame({'z':G.ZIPL,'x':c.x,'y':c.y}),pd.DataFrame({'z':G.ZIPR,'x':c.x,'y':c.y})]).dropna()
    tz=T[T.z.astype(str).str.match(r'^8[01]\d{3}$')].groupby('z').agg(tlat=('y','median'),tlon=('x','median')).reset_index().rename(columns={'z':'zip5'})
    zc=zc.merge(tz,on='zip5',how='left')
    far=(hav_km(zc.zlat,zc.zlon,zc.tlat,zc.tlon)>50)&zc.tlat.notna()
    use_t=zc.tlat.notna()&((zc.zn<3)|far)
    print('ZIP centroids taken from TIGER streets:',int(use_t.sum()),'of',len(zc),'(inventory median > 50 km off:',int(far.sum()),')')
    zc.loc[use_t,'zlat']=zc.loc[use_t,'tlat']; zc.loc[use_t,'zlon']=zc.loc[use_t,'tlon']
    zc=zc.drop(columns=['tlat','tlon'])
else:
    print('work/tiger not present: ZIP centroids from inventory records only')
zc=zc.sort_values('zip5').reset_index(drop=True)
addr.to_pickle('work/inv/frs_addr.pkl'); zc.to_pickle('work/inv/zip_centroids.pkl')
zc.to_csv('data/geocoder/zip_centroids.csv',index=False)   # the R geocoder (R/geocode_tiger.R) reads the same centroids
print('FRS address points',len(addr),'ZIP centroids',len(zc))
