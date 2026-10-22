"""Prepare compact inputs for the Shiny app -> app/data/
Every point layer gets the GEOID of the EnviroScreen census tract it falls in."""
import pandas as pd, numpy as np, json, os, re
import geopandas as gpd
from shapely.geometry import shape
os.makedirs('app/data', exist_ok=True)
CTX = json.load(open('work/reg/context_layers.json'))

# ---- EnviroScreen tracts (field aliases -> short names)
A = CTX['aliases']['enviroscreen_tract']
KEEP = {  # alias -> column name used in the app
 'EnviroScreen Percentile Score': 'enviroscreen_pctl',
 'Pollution and Climate Burden Percentile Score': 'pollution_climate_pctl',
 'Health and Social Factors Percentile Score': 'health_social_pctl',
 'Environmental Exposures Percentile Score': 'env_exposures_pctl',
 'Environmental Effects Percentile Score': 'env_effects_pctl',
 'Demographics Percentile Score': 'demographics_pctl',
 'Sensitive Populations Percentile Score': 'sensitive_pop_pctl',
 'Low Income (decimal percent)': 'low_income',
 'People of Color (decimal percent)': 'people_of_color',
 'Less Than High School Education (decimal percent)': 'less_than_hs',
 'Linguistic Isolation (decimal percent)': 'linguistic_isolation',
 'Housing Cost Burdened (decimal percent)': 'housing_burden',
 'Disability (decimal percent)': 'disability',
 'Life Expectancy (years)': 'life_expectancy',
 'Asthma Hospitalization Rate': 'asthma_rate',
 'Lead Exposure Risk (percentage)': 'lead_risk',
 'Proximity to Hazardous Waste Facilities (percentile)': 'prox_hazwaste_pctl',
 'Proximity to National Priorities List Sites (percentile)': 'prox_npl_pctl',
 'Total Population': 'population', 'County': 'county'}
inv = {v.strip(): k for k, v in A.items()}
rows = []
for f in CTX['enviroscreen_tract']:
    p = f['properties']; r = {'GEOID': str(p['GEOID'])}
    for al, col in KEEP.items():
        r[col] = p.get(inv.get(al))
    r['geometry'] = shape(f['geometry']); rows.append(r)
es = gpd.GeoDataFrame(rows, crs=4326)
for c in ['low_income', 'people_of_color', 'less_than_hs', 'linguistic_isolation', 'housing_burden', 'disability']:
    es[c] = pd.to_numeric(es[c], errors='coerce') * 100     # to percent
tracts = es[['GEOID', 'geometry']].copy()          # full geometry for point-in-tract joins (simplified tracts leave gaps and overlaps)
es['geometry'] = es.geometry.simplify(0.0003, preserve_topology=True)
es.to_file('app/data/enviroscreen_tracts.geojson', driver='GeoJSON', COORDINATE_PRECISION=5)

def with_tract(df, lat='lat', lon='lon'):
    g = gpd.GeoDataFrame(df.copy(), geometry=gpd.points_from_xy(df[lon], df[lat]), crs=4326)
    j = gpd.sjoin(g, tracts, how='left', predicate='within')
    j = j[~j.index.duplicated()]
    miss = j['GEOID'].isna() & g.geometry.notna() & ~g.geometry.is_empty    # on a tract edge: nearest tract within about 100 m
    if miss.any():
        nr = gpd.sjoin_nearest(g[miss], tracts, how='left', max_distance=0.001)
        nr = nr[~nr.index.duplicated()]
        j.loc[nr.index, 'GEOID'] = nr['GEOID']
    out = pd.DataFrame(j.drop(columns=['geometry', 'index_right'], errors='ignore'))
    return out

# ---- historical hazardous sites + site-years
s = pd.read_pickle('work/inv/sites_export.pkl')
s = s[s.fe_hazard | s.ext_hazard].copy()
for c in s.columns:
    if s[c].dtype == object: s[c] = s[c].apply(lambda v: re.sub(r'^[=+@\-]+\s*', '', v) if isinstance(v, str) else v)
s['known_match'] = s[['cleanup_match', 'tri_match', 'rcra_handler_match', 'solid_waste_match', 'other_epa_match']].fillna('').agg(
    lambda r: next((x for x in r if x), ''), axis=1)
sc = ['site_id', 'lat', 'lon', 'address', 'city', 'county', 'zip', 'first_year', 'last_year', 'hazard_years', 'fe_hazard', 'ext_hazard',
      'fe_sectors', 'ext_sectors', 'radar', 'confidence', 'geo_level', 'industry_evidence', 'n_hazard_establishments', 'hazard_firms', 'known_match']
S = with_tract(s[sc]); S.to_csv('app/data/sites.csv', index=False)
df = pd.read_pickle('work/inv/records_final.pkl')
SEC = {'28': 'Chemicals', '29': 'Petroleum refining', '30': 'Rubber & plastics', '33': 'Primary metals', '34': 'Fabricated metals',
       '35': 'Industrial machinery', '37': 'Transportation equipment'}
h = df[df.site_id.isin(S.site_id) & (df.fe_hazard | df.ext_hazard)].copy()
h['sectors'] = h.apply(lambda r: ';'.join(sorted({SEC[c[:2]] for c in r.sic if c[:2] in SEC} | ({'Extended sectors'} if r.ext_hazard else set()))), axis=1)
sy = h.groupby(['site_id', 'year']).agg(sectors=('sectors', lambda x: ';'.join(sorted({t for v in x for t in v.split(';') if t}))),
                                         firms=('name', lambda x: ' | '.join(dict.fromkeys(str(v) for v in x))[:300])).reset_index()
sy.to_csv('app/data/site_years.csv', index=False)

# ---- TRI facilities (EPA TRI facility table, all years 1987-present)
t = pd.read_csv('work/reg/tri_facility_CO.csv', dtype=str)
reg = pd.read_pickle('work/inv/reg.pkl')
tr = reg[reg.source == 'EPA_TRI'].dropna(subset=['lat', 'lon']).copy()
tr = tr.merge(t[['tri_facility_id', 'fac_closed_ind']], left_on='src_id', right_on='tri_facility_id', how='left')
tr['status'] = np.where(tr.fac_closed_ind == '1', 'Closed', 'Open')
with_tract(tr[['src_id', 'name', 'address', 'city', 'zip', 'lat', 'lon', 'status']]).to_csv('app/data/tri_facilities.csv', index=False)

# ---- cleanup / contamination overlays
def pts(df, layer):
    d = df.dropna(subset=['lat', 'lon']).copy(); d['layer'] = layer
    return d[['layer', 'source', 'src_id', 'name', 'address', 'city', 'lat', 'lon', 'programs']]
fr = reg[reg.source == 'EPA_FRS']
has = lambda p: fr.programs.str.split('|').apply(lambda L: p in L)
ov = pd.concat([
    pts(reg[reg.source == 'CDPHE_CDPHE_Brownfield'], 'Brownfields'),
    pts(fr[has('ACRES')], 'Brownfields'),
    pts(reg[reg.source == 'CDPHE_Voluntary_Cleanup_and_Redevelopment_Program_(VCUP)_new'], 'Voluntary cleanup (VCUP)'),
    pts(fr[has('SEMS')], 'Superfund (SEMS)'),
    pts(reg[reg.source.isin(['CDPHE_CDPHE_Superfund', 'CDPHE_UMTRA', 'CDPHE_FederalFacilities3'])], 'Superfund (SEMS)'),
    pts(reg[reg.source == 'CDPHE_RCRA_corrective_action'], 'RCRA corrective action'),
    pts(reg[reg.source == 'CDPHE_Institutional_Controls_PROD_local'], 'Environmental covenants / land-use controls')])
ov['source'] = ov.source.str.replace('EPA_FRS', 'EPA').str.replace('CDPHE_CDPHE_', 'CDPHE ').str.replace('CDPHE_', 'CDPHE ')
ov.to_csv('app/data/cleanup_sites.csv', index=False)

# ---- schools
sch = pd.DataFrame([f['properties'] for f in CTX['schools']])
sch = sch[sch.Type_.str.contains('School Physical', na=False)]
def gr(x):
    # CDE grade codes: 002/004 preschool, 006/007 kindergarten, 010..120 = grades 1..12
    try:
        c = int(x)
        return 'PK' if c < 6 else ('K' if c < 10 else str(c // 10))
    except Exception: return ''
sch = pd.DataFrame(dict(name=sch.School_Name.str.strip(), type=np.where(sch.Type_.str.startswith('Public'), 'Public school', 'Non-public school'),
                        grades=sch.Lowest_Grade.map(gr) + '-' + sch.Highest_Grade.map(gr),
                        address=sch.Address.str.strip().str.title() + ', ' + sch.City.str.strip().str.title(),
                        district=sch.District_Name, lat=pd.to_numeric(sch.LATITUDE), lon=pd.to_numeric(sch.LONGITUDE)))
with_tract(sch.dropna(subset=['lat', 'lon'])).to_csv('app/data/schools.csv', index=False)

# ---- health facilities
hf = pd.DataFrame([dict(f['properties'], lon=f['geometry']['coordinates'][0], lat=f['geometry']['coordinates'][1]) for f in CTX['health_facilities'] if f.get('geometry')])
CLINIC = {'FEDERALLY QHC', 'DOC CLINIC', 'COMMUNITY CLINIC/EMERGENCY', 'BIRTH CENTERS', 'CIHCS'}
RESID = {'Nursing Facilities', 'Assisted Living Residence'}
def cat(r):
    if r.Facility_Type == 'Hospital' or r.Facility_Type_Detail == 'FREESTANDING EMERGENCY DEPARTMENT': return 'Hospital'
    if r.Facility_Type == 'Community Clinic' or r.Facility_Type_Detail in CLINIC: return 'Clinic'
    if r.Facility_Type in RESID or r.Facility_Type_Detail in ('RESIDENTIAL TREATMENT', 'ADULT DAY', 'CONVALESCENT CENTER'): return 'Residential & long-term care'
    return None
hf['category'] = hf.apply(cat, axis=1)
hf = hf[hf.category.notna() & (hf.Operating_Status == 'Active')]
hf = pd.DataFrame(dict(name=hf.Facility_Name.str.title(), category=hf.category, type=hf.Facility_Type_Detail.str.title(),
                       address=hf.Address_Full, lat=hf.lat, lon=hf.lon))
with_tract(hf).to_csv('app/data/health_facilities.csv', index=False)
print('app data:', len(S), 'sites;', len(sy), 'site-years;', len(tr), 'TRI;', len(ov), 'cleanup;', len(sch), 'schools;', len(hf), 'health;', len(es), 'tracts')
