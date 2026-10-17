"""Tract-level analysis file for 'do hidden hazards matter for health?'

Exposure is computed at block-group centroids and averaged to tracts. (CDPHE EnviroScreen 2.0 block-group health values are
copied from the tract, so outcomes only vary between tracts.)
  * Gaussian kernel density of sites (sigma = 500 m, cut at 2 km; also 1 km buffer counts) at each block-group centroid
  * tract exposure = mean over the tract's block groups
Exposure groups
  hidden      historical hazardous-sector sites (Frickel & Elliott sectors, 1961-2002 directory) on no current inventory
  known_hist  historical hazardous-sector sites that are on some inventory (cleanup, TRI, RCRA, other EPA, solid waste)
  tri, cleanup currently regulated / listed facilities
  placebo     manufacturers in NON-hazardous sectors from the same directories (address-level, not at a hazardous site)
  pre1960     pre-1960 hazardous-trade firms placed at a street address (sensitivity)
Outputs work/health/tract_analysis.csv and work/health/bg_exposures.csv
"""
import json, numpy as np, pandas as pd, geopandas as gpd
from scipy.spatial import cKDTree

UTM = 26913
bg = gpd.read_file('work/health/enviroscreen_v2_blockgroups.geojson').to_crs(UTM)
bg['GEOID'] = bg.GEOID.astype(str).str.zfill(12); bg['tract'] = bg.GEOID.str[:11]
cent = np.c_[bg.geometry.representative_point().x, bg.geometry.representative_point().y]

def pts(df, lat='lat', lon='lon'):
    g = gpd.GeoDataFrame(df, geometry=gpd.points_from_xy(df[lon], df[lat]), crs=4326).to_crs(UTM)
    return np.c_[g.geometry.x, g.geometry.y]

S = pd.read_csv('app/data/sites.csv')
S = S[S.fe_hazard]                                                    # Frickel & Elliott sectors
groups = {
    'hidden': S[S.radar == 'Not on any list'],
    'hidden_hiconf': S[(S.radar == 'Not on any list') & (S.confidence == 'high')],
    'known_hist': S[S.radar != 'Not on any list'],
    'hist_all': S,
    'hidden_persist10': S[(S.radar == 'Not on any list') & ((S.last_year - S.first_year) >= 10)],
    'tri': pd.read_csv('app/data/tri_facilities.csv'),
    'cleanup': pd.read_csv('app/data/cleanup_sites.csv'),
}
# placebo: non-hazardous manufacturers at address level, de-duplicated by location, away from any hazardous site
R = pd.read_pickle('work/inv/records_final.pkl')
haz_sites = set(pd.read_csv('app/data/sites.csv').site_id)
nh = R[(R.geo_level == 'address') & ~R.hazard_any.astype(bool) & ~R.site_id.isin(haz_sites)].copy()
nh['k'] = nh.lat.round(4).astype(str) + nh.lon.round(4).astype(str)
nh = nh.drop_duplicates('k')
P = pts(nh); Hx = pts(S)
d, _ = cKDTree(Hx).query(P)
groups['placebo'] = nh[d > 100]
H = pd.read_csv('app/data/historical_sites.csv')
groups['pre1960'] = H[H.precision != 'town']

SIG, CUT = 500.0, 2000.0
tree_c = cKDTree(cent)
out = pd.DataFrame({'GEOID': bg.GEOID, 'tract': bg.tract})
for name, df in groups.items():
    xy = pts(df.dropna(subset=['lat', 'lon']))
    dens = np.zeros(len(cent)); cnt1k = np.zeros(len(cent))
    t = cKDTree(xy)
    for i, js in enumerate(t.query_ball_point(cent, CUT)):
        if js:
            dd = np.hypot(*(xy[js] - cent[i]).T)
            dens[i] = np.exp(-0.5 * (dd / SIG) ** 2).sum()
            cnt1k[i] = (dd <= 1000).sum()
    out[f'{name}_kd'] = dens; out[f'{name}_n1k'] = cnt1k
    print(name, len(xy), 'sites; BGs with any within 1 km:', round((cnt1k > 0).mean(), 3))

# block-group covariates with real BG variation (demographics, regulated-proximity indicators)
num = lambda c: pd.to_numeric(bg[c], errors='coerce')
cov = {'low_income': 'Prcnt_lw_', 'people_of_color': 'Prc___', 'less_than_hs': 'Pr_____', 'ling_iso': 'Prcnt_ln_',
       'over64': 'Pp__64', 'under5': 'Pp__5', 'prox_hazwaste': 'Prxmty_t_h', 'prox_npl': 'Pr__N_P_L_', 'prox_rmp': 'Pr__R_M_P_',
       'prox_mining': 'Prx___', 'prox_oilgas': 'Prxmty_t_l', 'diesel_pm': 'Ds____PM_', 'traffic': 'Tr____', 'pm25': 'Fn_p_', 'ozone': 'Ozone',
       'air_toxics': 'Ar_t_'}
for k, c in cov.items(): out[k] = num(c).values
out['area_km2'] = bg.geometry.area.values / 1e6
out.to_csv('work/health/bg_exposures.csv', index=False)

# tract file: outcomes (identical across a tract's block groups) + tract means of exposures/covariates
outc = {'asthma_hosp': 'Ast__', 'low_birth_wt': 'Lw_b_', 'life_exp': 'Lf_xp', 'heart_dis': 'Hr___', 'cancer': 'Cncr_',
        'diabetes': 'Dbts_', 'mental_health': 'Mnt__'}
O = pd.DataFrame({'tract': bg.tract, **{k: num(c).values for k, c in outc.items()}}).groupby('tract').first()
X = out.drop(columns=['GEOID']).groupby('tract').agg({**{c: 'mean' for c in out.columns if c not in ('GEOID', 'tract', 'area_km2')}, 'area_km2': 'sum'})
X['n_bg'] = out.groupby('tract').size()
T = gpd.read_file('app/data/enviroscreen_tracts.geojson')[['GEOID', 'population', 'county']].rename(columns={'GEOID': 'tract'})
T['tract'] = T.tract.astype(str).str.zfill(11)
A = O.join(X).reset_index().merge(T, on='tract', how='left')
A['pop_density'] = A.population / A.area_km2
A.to_csv('work/health/tract_analysis.csv', index=False)
print(A.shape); print(A.describe().T[['mean', '50%', 'max']].round(2).to_string())
