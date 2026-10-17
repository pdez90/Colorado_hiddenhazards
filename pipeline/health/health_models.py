"""Do hidden hazards matter for health? Nested tract-level models (Colorado, ~1,400 populated tracts).

M1  outcome ~ demographics/SES (low income, people of color, < high school, linguistic isolation, age 65+, under 5, log density)
M2  + hazards regulators already track (EnviroScreen proximity to hazardous-waste, NPL and RMP facilities; TRI and
      cleanup-site density)
M3  + historical hazardous-sector sites that are on some inventory ("known")
M4  + historical hazardous-sector sites on no inventory ("hidden")
Placebo: M2 + non-hazardous manufacturers from the same directories (same data source, same geocoding, no hazardous process).

Each model is fit by OLS (HC3 errors) and as a spatial error model (ML, queen contiguity) because outcomes and exposures
cluster in space. Exposures are log(1 + kernel density) standardised to SD units, so coefficients are the change in the
outcome per 1 SD of exposure. Outputs data/results/health_models.csv and health_models.md.
"""
import warnings, numpy as np, pandas as pd, geopandas as gpd
import statsmodels.api as sm
from scipy import stats
import libpysal, spreg
warnings.filterwarnings('ignore')

A = pd.read_csv('work/health/tract_analysis.csv', dtype={'tract': str})
A['tract'] = A.tract.str.zfill(11)
A = A[A.population >= 500].copy()
for c in ['asthma_hosp', 'low_birth_wt', 'life_exp']:                # 0 = suppressed small numbers
    A.loc[A[c] <= 0, c] = np.nan
A['log_asthma'] = np.log(A.asthma_hosp)
A['log_density'] = np.log1p(A.pop_density)
EXPO = ['hidden', 'hidden_hiconf', 'hidden_persist10', 'known_hist', 'hist_all', 'tri', 'cleanup', 'placebo', 'pre1960']
for e in EXPO:
    x = np.log1p(A[f'{e}_kd']); A[f'z_{e}'] = (x - x.mean()) / x.std()
for c in ['prox_hazwaste', 'prox_npl', 'prox_rmp']:
    x = np.log1p(A[c]); A[f'z_{c}'] = (x - x.mean()) / x.std()

SES = ['low_income', 'people_of_color', 'less_than_hs', 'ling_iso', 'over64', 'under5', 'log_density']
REG = ['z_prox_hazwaste', 'z_prox_npl', 'z_prox_rmp', 'z_tri', 'z_cleanup']
OUT = {'log_asthma': 'Asthma hospitalization rate (log)', 'low_birth_wt': 'Low birth weight (%)', 'life_exp': 'Life expectancy (years)',
       'heart_dis': 'Heart disease (index)', 'cancer': 'Cancer (index)', 'diabetes': 'Diabetes (index)', 'mental_health': 'Poor mental health (%)'}

tr = gpd.read_file('app/data/enviroscreen_tracts.geojson')[['GEOID', 'geometry']]
tr['GEOID'] = tr.GEOID.astype(str).str.zfill(11)

def fit(y, X, spatial=True):
    d = A[[y] + X + ['tract']].dropna()
    ols = sm.OLS(d[y], sm.add_constant(d[X])).fit(cov_type='HC3')
    res = dict(n=len(d), ols=ols)
    if spatial:
        g = tr.set_index('GEOID').loc[d.tract].reset_index()
        w = libpysal.weights.Queen.from_dataframe(g, use_index=False, silence_warnings=True)
        # islands keep zero rows; row-standardise
        w.transform = 'r'
        m = spreg.ML_Error(d[[y]].values, d[X].values, w=w, name_y=y, name_x=X)
        res['sem'] = m
    return res

def coef(r, var, kind):
    if kind == 'ols':
        o = r['ols']; return o.params[var], o.bse[var], o.pvalues[var]
    m = r['sem']; i = ['CONSTANT'] + m.name_x[1:]
    k = m.name_x.index(var)
    b = m.betas[k][0]; se = m.std_err[k]; p = m.z_stat[k][1]; return b, se, p

rows = []
for y, label in OUT.items():
    specs = {'M1 SES': SES, 'M2 +regulated': SES + REG, 'M3 +known historical': SES + REG + ['z_known_hist'],
             'M4 +hidden': SES + REG + ['z_known_hist', 'z_hidden'], 'Placebo: M2 +non-hazardous mfrs': SES + REG + ['z_placebo'],
             'M4 +placebo': SES + REG + ['z_known_hist', 'z_hidden', 'z_placebo']}
    fits = {k: fit(y, X) for k, X in specs.items()}
    ll = {k: f['sem'].logll for k, f in fits.items()}
    for k, f in fits.items():
        r = dict(outcome=label, model=k, n=f['n'], r2_ols=round(f['ols'].rsquared, 4), aic_sem=round(f['sem'].aic, 1), logll_sem=round(f['sem'].logll, 2),
                 lambda_sem=round(float(f['sem'].lam), 3))
        for v in ['z_known_hist', 'z_hidden', 'z_placebo', 'z_tri', 'z_cleanup', 'z_prox_hazwaste', 'z_prox_npl']:
            if v in f['sem'].name_x:
                b, se, p = coef(f, v, 'sem'); r[f'{v}_b'] = b; r[f'{v}_se'] = se; r[f'{v}_p'] = p
                bo, seo, po = coef(f, v, 'ols'); r[f'{v}_b_ols'] = bo; r[f'{v}_p_ols'] = po
        rows.append(r)
    # likelihood-ratio tests between nested spatial models
    for a, b in [('M2 +regulated', 'M1 SES'), ('M3 +known historical', 'M2 +regulated'), ('M4 +hidden', 'M3 +known historical'),
                 ('Placebo: M2 +non-hazardous mfrs', 'M2 +regulated'), ('M4 +placebo', 'M4 +hidden')]:
        lr = 2 * (ll[a] - ll[b]); rows.append(dict(outcome=label, model=f'LR {a} vs {b}', lr=round(lr, 2), lr_p=stats.chi2.sf(lr, 1 if 'regulated' not in a else len(REG))))
    print(label, 'done')

R = pd.DataFrame(rows)
R.to_csv('data/results/health_models.csv', index=False)

# compact summary table
def star(p): return '***' if p < .001 else '**' if p < .01 else '*' if p < .05 else ''
lines = ['| Outcome | Hidden sites, M4 (per SD) | Known historical, M4 | Placebo (non-hazardous mfrs), M4+placebo | ΔAIC M3→M4 | LR p (M4 vs M3) |', '|---|---|---|---|---|---|']
for label in OUT.values():
    g = R[R.outcome == label].set_index('model')
    m4 = g.loc['M4 +hidden']; m3 = g.loc['M3 +known historical']; mp = g.loc['M4 +placebo']
    lr = g.loc['LR M4 +hidden vs M3 +known historical']
    lines.append(f"| {label} | {m4.z_hidden_b:.3f} ({m4.z_hidden_se:.3f}){star(m4.z_hidden_p)} | {m4.z_known_hist_b:.3f} ({m4.z_known_hist_se:.3f}){star(m4.z_known_hist_p)} | "
                 f"{mp.z_placebo_b:.3f} ({mp.z_placebo_se:.3f}){star(mp.z_placebo_p)} | {m4.aic_sem - m3.aic_sem:.1f} | {lr.lr_p:.3g} |")
open('data/results/health_models.md', 'w').write('\n'.join(lines) + '\n')
print('\n'.join(lines))
