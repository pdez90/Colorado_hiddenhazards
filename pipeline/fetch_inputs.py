"""Download every public input used by the pipeline into work/.

  python pipeline/fetch_inputs.py            # everything
  python pipeline/fetch_inputs.py tiger frs  # selected groups

Groups
  tiger    US Census TIGER/Line 2023 ADDRFEAT (address ranges), 64 Colorado counties -> work/tiger/
  frs      EPA Facility Registry Service state combined file for Colorado          -> work/reg/
  tri      EPA TRI facility table for Colorado (Envirofacts)                        -> work/reg/tri_facility_CO.csv
  cdphe    CDPHE Hazardous Materials & Waste Mgmt Division layers (ArcGIS REST)     -> work/reg/cdphe_hmwmd_layers.json
  context  CDPHE EnviroScreen 2.0 tracts, CDPHE health facilities, CDE schools      -> work/reg/context_layers.json

The Colorado Directory of Manufacturers scans are not public downloads; place them in work/pdf/.
"""
import os, sys, json, time, zipfile, io
import requests

W = 'work'
S = requests.Session(); S.headers['User-Agent'] = 'Colorado_hiddenhazards research pipeline'

def get(url, **kw):
    for i in range(5):
        try:
            r = S.get(url, timeout=120, **kw); r.raise_for_status(); return r
        except Exception as e:
            if i == 4: raise
            time.sleep(3 * (i + 1))

def arcgis_layer(url, page=1000, extra=''):
    """All features of one ArcGIS REST layer as GeoJSON features, paging past maxRecordCount."""
    feats, off = [], 0
    while True:
        j = get(f"{url}/query?where=1%3D1&outFields=*&outSR=4326&f=geojson&resultOffset={off}&resultRecordCount={page}{extra}").json()
        f = j.get('features', []); feats += f
        if len(f) == 0 or (len(f) < page and not j.get('properties', {}).get('exceededTransferLimit')): break
        off += len(f)
    return feats

def tiger():
    os.makedirs(f'{W}/tiger', exist_ok=True)
    base = 'https://www2.census.gov/geo/tiger/TIGER2023/ADDRFEAT/'
    fips = [f'08{c:03d}' for c in range(1, 126, 2)] + ['08014']
    for f in sorted(set(fips)):
        fn = f'tl_2023_{f}_addrfeat.zip'
        r = S.get(base + fn, timeout=120)
        if r.status_code != 200: continue
        zipfile.ZipFile(io.BytesIO(r.content)).extractall(f'{W}/tiger')
        print('tiger', fn)

def frs():
    os.makedirs(f'{W}/reg', exist_ok=True)
    r = get('https://ordsext.epa.gov/FLA/www3/state_files/state_combined_co.zip')
    zipfile.ZipFile(io.BytesIO(r.content)).extractall(f'{W}/reg'); print('frs ok')

def tri():
    os.makedirs(f'{W}/reg', exist_ok=True)
    r = get('https://data.epa.gov/efservice/tri_facility/state_abbr/CO/CSV')
    open(f'{W}/reg/tri_facility_CO.csv', 'wb').write(r.content); print('tri ok')

CDPHE = 'https://services3.arcgis.com/66aUo8zsujfVXRIT/arcgis/rest/services/'
HMWMD = ['CDPHE_Superfund', 'CDPHE_Brownfield', 'FederalFacilities3', 'RCRA_corrective_action', 'RCRA',
         'Institutional_Controls_PROD_local', 'Solid_Waste_Facilities', 'UMTRA',
         'Voluntary_Cleanup_and_Redevelopment_Program_(VCUP)_new', 'Composting_Sites']

def cdphe():
    out = {}
    for s in HMWMD:
        info = get(CDPHE + s + '/FeatureServer?f=json').json()
        for L in info.get('layers', []):
            out[f"{s}__{L['name']}"] = arcgis_layer(f"{CDPHE}{s}/FeatureServer/{L['id']}")
            print('cdphe', s, len(out[f"{s}__{L['name']}"]))
    json.dump(out, open(f'{W}/reg/cdphe_hmwmd_layers.json', 'w'))

CONTEXT = {
    'enviroscreen_tract': (CDPHE + 'ColoradoEnviroScreen_v2_Tract_24118_Final/FeatureServer/0', '&geometryPrecision=5&maxAllowableOffset=0.0002'),
    'health_facilities': (CDPHE + 'CDPHE_Health_Facilities/FeatureServer/0', ''),
    'schools': ('https://www.cohealthmaps.dphe.state.co.us/arcgis/rest/services/OPEN_DATA/cdphe_cdoe_colorado_schools_districts/MapServer/0', ''),
}
def context():
    out = {'aliases': {}}
    for k, (u, extra) in CONTEXT.items():
        li = get(u + '?f=json').json()
        out['aliases'][k] = {f['name']: f['alias'] for f in li.get('fields', [])}
        out[k] = arcgis_layer(u, 1000, extra); print('context', k, len(out[k]))
    json.dump(out, open(f'{W}/reg/context_layers.json', 'w'))

if __name__ == '__main__':
    groups = sys.argv[1:] or ['tiger', 'frs', 'tri', 'cdphe', 'context']
    for g in groups: globals()[g]()
