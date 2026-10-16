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
t = gpd.read_file('app/data/enviroscreen_tracts.geojson')[['GEOID', 'geometry']]
g = gpd.GeoDataFrame(F, geometry=gpd.points_from_xy(F.lon, F.lat), crs=4326)
j = gpd.sjoin(g, t.to_crs(4326), how='left', predicate='within'); j = j[~j.index.duplicated()]
F = pd.DataFrame(j.drop(columns=['geometry', 'index_right']))
keep = ['hfirm', 'name', 'name_quality', 'town', 'county', 'street', 'lat', 'lon', 'precision', 'sectors', 'app_sectors', 'fe_hazard',
        'first_year', 'last_year', 'editions', 'years', 'example', 'persists_to_1961plus', 'link', 'dcm_name', 'dcm_years', 'dcm_site', 'GEOID']
F[keep].to_csv('app/data/historical_sites.csv', index=False)
P = F[F.dcm_site.notna() & (F.dcm_site != '')].groupby('dcm_site').agg(hist_first_year=('first_year', 'min'),
        hist_names=('name', lambda s: ' | '.join(sorted(set(s))[:3]))).reset_index().rename(columns={'dcm_site': 'site_id'})
P.to_csv('app/data/site_precursors.csv', index=False)
print(len(F), 'historical firm-locations for app;', len(P), '1961-2002 sites with a pre-1960 precursor')
print(F.precision.value_counts().to_string())
