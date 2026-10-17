import pandas as pd, json, re, numpy as np
R='work/reg/'
f=pd.read_csv(R+'CO_FACILITY_FILE.CSV',dtype=str)
f=f[f.STATE_CODE=='CO']
f['lat']=pd.to_numeric(f.LATITUDE83,errors='coerce'); f['lon']=pd.to_numeric(f.LONGITUDE83,errors='coerce')
f.loc[f.lon>0,'lon']=-f.loc[f.lon>0,'lon']
pg=f.PGM_SYS_ACRNMS.fillna('')
CONTAM={'SEMS','ACRES','RCRAINFO','LUST-ARRA','BRAC','FFEP','FFDOCKET','TSCA','STATE'}
def progs(s): return sorted({p.split(':')[0].strip() for p in s.split(',') if p.strip()})
f['programs']=pg.apply(lambda s:'|'.join(progs(s)))
CLEAN={'SEMS','ACRES','BRAC','FFEP','FFDOCKET','LUST-ARRA','STATE'}
def cat(s):
    P=set(s.split('|'))
    if P&CLEAN: return 'cleanup'
    if 'TRIS' in P: return 'tri'
    if 'RCRAINFO' in P: return 'rcra_handler'
    return 'other_epa'
f['tier']=f.programs.apply(cat)
reg=pd.DataFrame(dict(source='EPA_FRS',src_id=f.REGISTRY_ID,name=f.PRIMARY_NAME,address=f.LOCATION_ADDRESS,city=f.CITY_NAME,zip=f.POSTAL_CODE.str[:5],
    lat=f.lat,lon=f.lon,programs=f.programs,tier=f.tier))
# TRI facility file (has own coords in DMS)
t=pd.read_csv(R+'tri_facility_CO.csv',dtype=str)
def dms(v):
    try:
        v=int(float(v)); d=v//10000; m=(v//100)%100; s=v%100; return d+m/60+s/3600
    except: return np.nan
t['lat']=pd.to_numeric(t.pref_latitude,errors='coerce').fillna(t.fac_latitude.apply(dms))
t['lon']=-(pd.to_numeric(t.pref_longitude,errors='coerce').fillna(t.fac_longitude.apply(dms)).abs())
reg=pd.concat([reg,pd.DataFrame(dict(source='EPA_TRI',src_id=t.tri_facility_id,name=t.facility_name,address=t.street_address,city=t.city_name,zip=t.zip_code.str[:5],lat=t.lat,lon=t.lon,programs='TRI',tier='tri'))])
# CDPHE HMWMD layers (geodata.colorado.gov)
J=json.load(open(R+'cdphe_hmwmd_layers.json'))
def pick(p,keys):
    for k in keys:
        if k in p and p[k] not in (None,''): return p[k]
    return None
rows=[]
for k,feats in J.items():
    svc=k.split('__')[0]
    if svc=='Composting_Sites': continue
    tier={'RCRA':'rcra_handler','Solid_Waste_Facilities':'solid_waste'}.get(svc,'cleanup')
    for ft in feats:
        p=ft.get('properties',{}); g=ft.get('geometry') or {}
        lat=lon=np.nan
        try:
            cs=g.get('coordinates')
            if g['type']=='Point': lon,lat=cs
            else:
                ring=cs[0] if g['type']=='Polygon' else cs[0][0]
                a=np.array(ring); lon,lat=a[:,0].mean(),a[:,1].mean()
        except Exception: pass
        wkt=None
        try:
            if g.get('type') in ('Polygon','MultiPolygon'):
                from shapely.geometry import shape; wkt=shape(g).wkt
        except Exception: pass
        rows.append(dict(geom_wkt=wkt,source='CDPHE_'+svc,src_id=str(pick(p,['Handler_ID','RV_Nmbr','ID','PGM_ID','LocationID','FID','OBJECTID'])),
            name=pick(p,['Site','NAME','Site_name','facility_names','Handler_name','Facility']),
            address=pick(p,['Address','address']),city=pick(p,['City','CITY','CityNam']),zip=str(pick(p,['ZipCode','ZIPCODE','Zip']) or '')[:5],
            lat=lat,lon=lon,programs=svc,tier=tier))
reg=pd.concat([reg,pd.DataFrame(rows)],ignore_index=True)
reg=reg[(reg.lat.between(36.5,41.5))&(reg.lon.between(-109.5,-101.5))|reg.lat.isna()]
reg.to_pickle('work/inv/reg.pkl'); reg.to_csv('work/inv/reg.csv',index=False)   # CSV for R/build_sites.R
print(reg.groupby(['source','tier']).size().to_string()); print('with coords',reg.lat.notna().mean().round(3))
