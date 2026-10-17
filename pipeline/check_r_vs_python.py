"""Compare the R re-implementation (R/build_sites.R, R/health_models.R, R/mortality_bg.R) with the Python pipeline.
Sites are matched by their member addresses (site IDs are arbitrary). Writes data/results/r_vs_python.md."""
import os, pandas as pd, numpy as np

out = ['# R vs Python', '']
s = pd.read_pickle('work/inv/sites_final.pkl'); r = pd.read_pickle('work/inv/records_final.pkl')
R = pd.read_csv('work/inv/sites_R.csv'); RR = pd.read_csv('work/inv/records_sites_R.csv')
pk = r[r.site_id.notna()].groupby('site_id').geo_key.apply(frozenset)
rk = RR[RR.site_id.notna()].groupby('site_id').geo_key.apply(frozenset)
P = pd.DataFrame({'k': pk}).join(s.set_index('site_id')[['radar_status', 'fe_hazard', 'confidence', 'lat', 'lon']])
Q = pd.DataFrame({'k': rk}).join(R.set_index('site_id')[['radar_status', 'fe_hazard', 'confidence', 'lat', 'lon']])
M = P.reset_index().merge(Q.reset_index(), on='k', how='inner', suffixes=('_py', '_r'))
H = M[M.fe_hazard_py]
out += ['## Sites (R/build_sites.R vs pipeline/build_sites.py + finalize.py)', '',
        f'* sites: Python {len(P):,}, R {len(Q):,}, identical membership {len(M):,}',
        f'* hazardous-sector sites with the same inventory status: {(H.radar_status_py == H.radar_status_r).sum():,} of {len(H):,}',
        f'* same confidence class: {(H.confidence_py == H.confidence_r).sum():,} of {len(H):,}',
        f'* max coordinate difference: {6371000 * np.radians(np.hypot(M.lat_py - M.lat_r, M.lon_py - M.lon_r)).max():.3f} m', '']
d = H[H.radar_status_py != H.radar_status_r]
if len(d): out += ['Differences:', '', d[['site_id_py', 'radar_status_py', 'radar_status_r']].to_markdown(index=False), '']

if os.path.exists('work/health/bg_exposures_R.csv'):
    a = pd.read_csv('work/health/bg_exposures.csv', dtype={'GEOID': str}); b = pd.read_csv('work/health/bg_exposures_R.csv', dtype={'GEOID': str})
    a['GEOID'] = a.GEOID.str.zfill(12); b['GEOID'] = b.GEOID.str.zfill(12); m = a.merge(b, on='GEOID', suffixes=('_py', '_r'))
    cs = [c for c in a.columns if c.endswith('_kd') or c.endswith('_n1k')]
    mx = max(float(np.nanmax(np.abs(m[c + '_py'] - m[c + '_r']))) for c in cs)
    out += ['## Exposures (R/build_exposures.R vs pipeline/health/build_exposures.py)', '',
            f'* block groups: Python {len(a):,}, R {len(b):,}, matched {len(m):,}; {len(cs)} exposure columns; largest absolute difference {mx:.1g}', '']

def cmp(py, rr, keys, cols, title):
    global out
    if not (os.path.exists(py) and os.path.exists(rr)): return
    a = pd.read_csv(py); b = pd.read_csv(rr); m = a.merge(b, on=keys, suffixes=('_py', '_r'))
    out += [f'## {title}', '', f'{len(m)} model rows compared; largest absolute difference per quantity:', '', '| quantity | max abs diff | max abs value |', '|---|---|---|']
    for c in cols:
        if f'{c}_py' in m and f'{c}_r' in m:
            x = pd.to_numeric(m[f'{c}_py'], errors='coerce'); y = pd.to_numeric(m[f'{c}_r'], errors='coerce')
            out.append(f'| {c} | {np.nanmax(np.abs(x - y)):.2g} | {np.nanmax(np.abs(x)):.3g} |')
    out.append('')
cmp('data/results/health_models.csv', 'data/results/health_models_R.csv', ['outcome', 'model'],
    ['n', 'r2_ols', 'aic_sem', 'lambda_sem', 'z_hidden_b', 'z_hidden_se', 'z_hidden_p', 'z_hidden_b_ols', 'z_known_hist_b', 'z_placebo_b', 'lr'],
    'Tract models (R/health_models.R vs pipeline/health/health_models.py)')
cmp('data/results/mortality_bg_models.csv', 'data/results/mortality_bg_models_R.csv', ['outcome', 'model'],
    ['n', 'deaths', 'alpha', 'aic', 'z_hidden_rr', 'z_hidden_lo', 'z_hidden_hi', 'z_hidden_p', 'z_placebo_rr', 'z_known_hist_rr'],
    'Block-group mortality (R/mortality_bg.R vs pipeline/health/mortality_bg.py)')
open('data/results/r_vs_python.md', 'w').write('\n'.join(out) + '\n'); print('\n'.join(out))
