"""Publish the R health models as the project's health tables (the Python versions need libpysal/spreg, which the analysis Mac lacks).

  python3 pipeline/health/write_health_tables.py      (after R/build_exposures.R, R/health_models.R and R/mortality_bg.R)

Reads data/results/health_models_R.csv and mortality_bg_models_R.csv (same columns as the Python outputs; R and Python agree to
<1e-6 in the coefficients) and writes data/results/health_models.csv / .md and mortality_bg_models.csv / .md in the format of
pipeline/health/health_models.py and mortality_bg.py. Only coefficients, rate ratios and sample totals are written.
"""
import pandas as pd

def star(p): return '***' if p < .001 else '**' if p < .01 else '*' if p < .05 else ''

H = pd.read_csv('data/results/health_models_R.csv')
H.to_csv('data/results/health_models.csv', index=False)
OUT = ['Asthma hospitalization rate (log)', 'Low birth weight (%)', 'Life expectancy (years)', 'Heart disease (index)', 'Cancer (index)',
       'Diabetes (index)', 'Poor mental health (%)']
L = ['| Outcome | Hidden sites, M4 (per SD) | Known historical, M4 | Placebo (non-hazardous mfrs), M4+placebo | ΔAIC M3→M4 | LR p (M4 vs M3) |',
     '|---|---|---|---|---|---|']
for label in OUT:
    g = H[H.outcome == label].set_index('model')
    m4, m3, mp = g.loc['M4 +hidden'], g.loc['M3 +known historical'], g.loc['M4 +placebo']
    lr = g.loc['LR M4 +hidden vs M3 +known historical']
    L.append(f"| {label} | {m4.z_hidden_b:.3f} ({m4.z_hidden_se:.3f}){star(m4.z_hidden_p)} | {m4.z_known_hist_b:.3f} ({m4.z_known_hist_se:.3f}){star(m4.z_known_hist_p)} | "
             f"{mp.z_placebo_b:.3f} ({mp.z_placebo_se:.3f}){star(mp.z_placebo_p)} | {m4.aic_sem - m3.aic_sem:.1f} | {lr.lr_p:.3g} |")
open('data/results/health_models.md', 'w').write('\n'.join(L) + '\n')
print('\n'.join(L))

T = pd.read_csv('data/results/mortality_bg_models_R.csv')
T.to_csv('data/results/mortality_bg_models.csv', index=False)
f = lambda r, v: (f"{r[v + '_rr']:.3f} ({r[v + '_lo']:.3f}–{r[v + '_hi']:.3f})" + ('*' if r[v + '_p'] < .05 else '')) if v + '_rr' in r and pd.notna(r[v + '_rr']) else ''
M = ['| Outcome | Model | Hidden sites RR per SD | Known historical | Placebo (non-hazardous) | Cleanup sites | AIC |', '|---|---|---|---|---|---|---|']
for _, r in T.iterrows():
    hv = 'z_hidden_hiconf' if 'high-confidence' in r.model else 'z_hidden'
    M.append(f"| {'natural-cause' if r.outcome == 'deaths_nat' else 'all-cause'} | {r.model} | {f(r, hv)} | {f(r, 'z_known_hist')} | {f(r, 'z_placebo')} | {f(r, 'z_cleanup')} | {r.aic:.1f} |")
open('data/results/mortality_bg_models.md', 'w').write(f'Block groups: {int(T.n.iloc[0])}, natural-cause deaths 2015-2019: {int(T.deaths.iloc[0]):,}\n\n' + '\n'.join(M) + '\n')
print('\n'.join(M))
