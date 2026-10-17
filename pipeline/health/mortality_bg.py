"""Block-group mortality analysis: do hidden hazardous sites predict natural-cause mortality beyond regulated hazards?

Inputs (NOT in the repository - restricted vital-records data stay on the analyst's machine):
  work/health/deaths_bg_year.csv   deaths by 2010 block group x year x cause (aggregated from Colorado death records 2000-2020)
  work/health/bgroup_noyr.gpkg     2010 block groups with annual population (2000-2020) and PM2.5 / NO2
Public inputs: EnviroScreen 2.0 block groups (2020 boundaries; SES, age structure and regulated-proximity indicators, carried to
2010 block groups by area-weighted overlay), app/data/sites.csv, TRI, cleanup sites.

Outcome: natural-cause deaths 2015-2019 (pre-COVID), offset log(person-years 2015-2019).
Models: negative binomial GLM with county fixed effects, cluster-robust SE by tract, nested as in health_models.py
(M1 SES+age+PM2.5 -> M2 +regulated -> M3 +known historical -> M4 +hidden; placebo = non-hazardous manufacturers).
Exposure = Gaussian kernel density (sigma 500 m, 2 km cut) at the block-group representative point, log1p, per SD.
Outputs data/results/mortality_bg_models.csv / .md (coefficients and rate ratios only; no small-area counts).
"""
import warnings, numpy as np, pandas as pd, geopandas as gpd
import statsmodels.api as sm, statsmodels.formula.api as smf
from scipy.spatial import cKDTree
warnings.filterwarnings('ignore')
UTM = 26913
Y0, Y1 = 2015, 2019

g = gpd.read_file('work/health/bgroup_noyr.gpkg')[['bg', 'fipscoor', 'geometry'] + [f'pop_{y}' for y in range(Y0, Y1 + 1)] + [f'pm_{y}' for y in range(Y0, Y1 + 1)]]
g['bg'] = g.bg.astype(str).str.zfill(12)
g = g.to_crs(UTM)
g['pyears'] = g[[f'pop_{y}' for y in range(Y0, Y1 + 1)]].sum(axis=1)
g['pm25'] = g[[f'pm_{y}' for y in range(Y0, Y1 + 1)]].mean(axis=1)
d = pd.read_csv('work/health/deaths_bg_year.csv', dtype={'bg': str})
d = d[(d.year >= Y0) & (d.year <= Y1)]
nat = d[d.natural_cause == 1].groupby('bg').deaths.sum().rename('deaths_nat')
allc = d.groupby('bg').deaths.sum().rename('deaths_all')
g = g.merge(nat, left_on='bg', right_index=True, how='left').merge(allc, left_on='bg', right_index=True, how='left')
g[['deaths_nat', 'deaths_all']] = g[['deaths_nat', 'deaths_all']].fillna(0)

# 2020 EnviroScreen block-group covariates -> 2010 block groups, area-weighted
es = gpd.read_file('work/health/enviroscreen_v2_blockgroups.geojson').to_crs(UTM)
cov = {'low_income': 'Prcnt_lw_', 'people_of_color': 'Prc___', 'less_than_hs': 'Pr_____', 'ling_iso': 'Prcnt_ln_', 'over64': 'Pp__64',
       'under5': 'Pp__5', 'prox_hazwaste': 'Prxmty_t_h', 'prox_npl': 'Pr__N_P_L_', 'prox_rmp': 'Pr__R_M_P_', 'diesel_pm': 'Ds____PM_', 'traffic': 'Tr____'}
for k, c in cov.items(): es[k] = pd.to_numeric(es[c], errors='coerce')
ov = gpd.overlay(g[['bg', 'geometry']], es[list(cov) + ['geometry']], how='intersection', keep_geom_type=True)
ov['a'] = ov.area
W = ov.groupby('bg').apply(lambda x: pd.Series({k: np.average(x[k].fillna(x[k].mean() if x[k].notna().any() else 0), weights=x.a) for k in cov}), include_groups=False)
g = g.merge(W, left_on='bg', right_index=True, how='left')
g['area_km2'] = g.area / 1e6
g['log_density'] = np.log1p(g[f'pop_{Y1}'] / g.area_km2)
g['tract'] = g.bg.str[:11]

# exposures at the block-group representative point
pt = g.geometry.representative_point(); CP = np.c_[pt.x, pt.y]
def xy(df):
    q = gpd.GeoDataFrame(df, geometry=gpd.points_from_xy(df.lon, df.lat), crs=4326).to_crs(UTM); return np.c_[q.geometry.x, q.geometry.y]
S = pd.read_csv('app/data/sites.csv'); S = S[S.fe_hazard]
R = pd.read_pickle('work/inv/records_final.pkl')
nh = R[(R.geo_level == 'address') & ~R.hazard_any.astype(bool) & ~R.site_id.isin(set(pd.read_csv('app/data/sites.csv').site_id))].copy()
nh['k'] = nh.lat.round(4).astype(str) + nh.lon.round(4).astype(str); nh = nh.drop_duplicates('k')
dd, _ = cKDTree(xy(S)).query(xy(nh)); nh = nh[dd > 100]
groups = {'hidden': S[S.radar == 'Not on any list'], 'hidden_hiconf': S[(S.radar == 'Not on any list') & (S.confidence == 'high')],
          'known_hist': S[S.radar != 'Not on any list'], 'tri': pd.read_csv('app/data/tri_facilities.csv'),
          'cleanup': pd.read_csv('app/data/cleanup_sites.csv'), 'placebo': nh}
for k, df in groups.items():
    P = xy(df.dropna(subset=['lat', 'lon'])); t = cKDTree(P); kd = np.zeros(len(CP))
    for i, js in enumerate(t.query_ball_point(CP, 2000)):
        if js: kd[i] = np.exp(-0.5 * (np.hypot(*(P[js] - CP[i]).T) / 500) ** 2).sum()
    x = np.log1p(kd); g[f'z_{k}'] = (x - x.mean()) / x.std()
for c in ['prox_hazwaste', 'prox_npl', 'prox_rmp']:
    x = np.log1p(g[c]); g[f'z_{c}'] = (x - x.mean()) / x.std()

D = g[(g.pyears >= 500 * 5)].dropna(subset=list(cov) + ['pm25']).copy()
D['log_py'] = np.log(D.pyears)
D = D.replace([np.inf, -np.inf], np.nan).dropna(subset=['log_density', 'fipscoor'] + [c for c in D.columns if c.startswith('z_')]).reset_index(drop=True)
SES = 'low_income + people_of_color + less_than_hs + ling_iso + over64 + I(over64**2) + under5 + log_density + pm25 + C(fipscoor)'
REG = ' + z_prox_hazwaste + z_prox_npl + z_prox_rmp + z_tri + z_cleanup'
specs = {'M1 SES+age+PM2.5': SES, 'M2 +regulated': SES + REG, 'M3 +known historical': SES + REG + ' + z_known_hist',
         'M4 +hidden': SES + REG + ' + z_known_hist + z_hidden', 'M4 hidden high-confidence only': SES + REG + ' + z_known_hist + z_hidden_hiconf',
         'Placebo: M2 +non-hazardous mfrs': SES + REG + ' + z_placebo', 'M4 +placebo': SES + REG + ' + z_known_hist + z_hidden + z_placebo'}
rows = []
for y in ['deaths_nat', 'deaths_all']:
    # NB dispersion from the fullest model, then GLM NB with cluster-robust SE by tract
    alpha = smf.negativebinomial(f'{y} ~ ' + specs['M4 +placebo'], data=D, offset=D.log_py).fit(disp=0, maxiter=200).params['alpha']
    for name, rhs in specs.items():
        m = smf.glm(f'{y} ~ ' + rhs, data=D, offset=D.log_py, family=sm.families.NegativeBinomial(alpha=alpha)).fit(cov_type='cluster', cov_kwds={'groups': pd.factorize(D.tract)[0]})
        r = dict(outcome=y, model=name, n=int(m.nobs), deaths=int(D[y].sum()), aic=round(m.aic, 1), alpha=round(alpha, 4))
        for v in ['z_hidden', 'z_hidden_hiconf', 'z_known_hist', 'z_placebo', 'z_tri', 'z_cleanup', 'z_prox_hazwaste', 'z_prox_npl', 'z_prox_rmp']:
            if v in m.params:
                b, se = m.params[v], m.bse[v]
                r[f'{v}_rr'] = np.exp(b); r[f'{v}_lo'] = np.exp(b - 1.96 * se); r[f'{v}_hi'] = np.exp(b + 1.96 * se); r[f'{v}_p'] = m.pvalues[v]
        rows.append(r)
    print(y, 'done')
T = pd.DataFrame(rows); T.to_csv('data/results/mortality_bg_models.csv', index=False)
f = lambda r, v: f"{r[v+'_rr']:.3f} ({r[v+'_lo']:.3f}–{r[v+'_hi']:.3f})" + ('*' if r[v + '_p'] < .05 else '') if pd.notna(r.get(v + '_rr')) else ''
L = ['| Outcome | Model | Hidden sites RR per SD | Known historical | Placebo (non-hazardous) | Cleanup sites | AIC |', '|---|---|---|---|---|---|---|']
for _, r in T.iterrows():
    hv = 'z_hidden_hiconf' if 'high-confidence' in r.model else 'z_hidden'
    L.append(f"| {'natural-cause' if r.outcome == 'deaths_nat' else 'all-cause'} | {r.model} | {f(r, hv)} | {f(r, 'z_known_hist')} | {f(r, 'z_placebo')} | {f(r, 'z_cleanup')} | {r.aic} |")
open('data/results/mortality_bg_models.md', 'w').write(f'Block groups: {T.n.iloc[0]}, natural-cause deaths {Y0}-{Y1}: {T.deaths.iloc[0]:,}\n\n' + '\n'.join(L) + '\n')
print('\n'.join(L))
