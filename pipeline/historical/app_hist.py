"""App inputs for the pre-1960 layer: historical firm-locations with tract GEOID and app sector names, plus the
earliest pre-1960 year for 1961-2002 sites that a historical firm links to (by name or address)."""
import pandas as pd, geopandas as gpd
F = pd.read_csv('data/historical/CO_pre1960_hazardous_sites.csv')
F = F[F.lat.notna()].copy()
SEC = {'Smelting & refining': 'Primary metals', 'Foundry': 'Primary metals', 'Iron & steel works': 'Primary metals',
       'Machine shop / machinery': 'Industrial machinery', 'Metal working': 'Fabricated metals',
       'Chemicals': 'Chemicals', 'Paint & varnish': 'Chemicals', 'Soap': 'Chemicals', 'Explosives': 'Chemicals', 'Fertilizer & rendering': 'Chemicals',
       'Petroleum refining & asphalt': 'Petroleum refining', 'Rubber': 'Rubber & plastics', 'Plastics': 'Rubber & plastics',
       'Transportation equipment': 'Transportation equipment'}
F['app_sectors'] = F.sectors.map(lambda s: ';'.join(sorted({SEC.get(x.strip(), 'Extended sectors') for x in str(s).split(';')})))
# tract GEOID from the full-resolution EnviroScreen tracts (as pipeline/app_inputs.py does for the 1961-2002 sites): the app's simplified
# outlines leave slivers along streets, where street-level geocodes fall
import json, os
from shapely.geometry import shape
if os.path.exists('work/reg/context_layers.json'):
    t = gpd.GeoDataFrame([{'GEOID': str(f['properties']['GEOID']), 'geometry': shape(f['geometry'])}
                          for f in json.load(open('work/reg/context_layers.json'))['enviroscreen_tract']], crs=4326)
else:
    t = gpd.read_file('app/data/enviroscreen_tracts.geojson')[['GEOID', 'geometry']]
g = gpd.GeoDataFrame(F, geometry=gpd.points_from_xy(F.lon, F.lat), crs=4326)
j = gpd.sjoin(g, t.to_crs(4326), how='left', predicate='within'); j = j[~j.index.duplicated()]
# the simplified tract outlines leave slivers along streets, where street-level geocodes fall: a point in no tract takes the nearest tract
# within 60 m (UTM), as R/rezoning_denver.R does
miss = j.GEOID.isna()
if miss.any():
    gu, tu = g[miss].to_crs(26913), t.to_crs(26913)
    nn = gpd.sjoin_nearest(gu[['geometry']], tu, how='left', max_distance=60, distance_col='_d'); nn = nn[~nn.index.duplicated()]
    j.loc[nn.index, 'GEOID'] = nn.GEOID
F = pd.DataFrame(j.drop(columns=['geometry', 'index_right']))
keep = ['hfirm', 'name', 'name_quality', 'town', 'county', 'street', 'lat', 'lon', 'precision', 'sectors', 'app_sectors', 'fe_hazard',
        'first_year', 'last_year', 'editions', 'years', 'example', 'persists_to_1961plus', 'link', 'dcm_name', 'dcm_years', 'dcm_site', 'GEOID']
F[keep].to_csv('app/data/historical_sites.csv', index=False)
P = F[F.dcm_site.notna() & (F.dcm_site != '')].groupby('dcm_site').agg(hist_first_year=('first_year', 'min'),
        hist_names=('name', lambda s: ' | '.join(sorted(set(s))[:3]))).reset_index().rename(columns={'dcm_site': 'site_id'})
P.to_csv('app/data/site_precursors.csv', index=False)
print(len(F), 'historical firm-locations for app;', len(P), '1961-2002 sites with a pre-1960 precursor')
print(F.precision.value_counts().to_string())
