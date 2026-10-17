"""Per-site firm details for the app popups and downloads (app/data/site_firms.csv).
One row per establishment (firm linked across editions) at each mapped site: name, years listed, what the directory says
it made (product descriptions / SIC titles), SIC codes, year established, employment class, hazardous-sector flag."""
import pandas as pd, numpy as np

r_all = r = pd.read_pickle('work/inv/records_final.pkl')
S = pd.read_csv('app/data/sites.csv', usecols=['site_id'])
r = r[r.site_id.isin(S.site_id)].copy()

def flat(x):
    return [str(v) for v in (x if isinstance(x, (list, tuple, np.ndarray)) else ([] if pd.isna(x) else [x])) if str(v).strip()]

# SIC title fallback when the edition printed no description: the commonest directory description for that code
pairs = [(c, d.strip().lower()) for cs, ds in zip(r_all.sic, r_all.sic_desc) if len(flat(cs)) == len(flat(ds)) for c, d in zip(flat(cs), flat(ds))]
TITLE = pd.DataFrame(pairs, columns=['sic', 'd']).groupby('sic').d.agg(lambda x: x.value_counts().index[0]).to_dict()
import re
def clean_name(n):
    return re.sub(r'\s+\d+\s*(?:to|-)\s*\d+\s*$', '', str(n), flags=re.I).strip()
def clean_size(x):
    m = re.search(r'(\d+)\s*(?:-|to)\s*(\d+)', str(x), re.I)
    return f"{m.group(1)}-{m.group(2)}" if m else ''

rows = []
for (site, est_id), g in r.sort_values('year').groupby(['site_id', 'estab_id']):
    yrs = sorted(g.year.unique())
    desc = list(dict.fromkeys(d.strip().lower() for x in g.sic_desc for d in flat(x)))[:4]
    sics = list(dict.fromkeys(s for x in g.sic for s in flat(x)))[:4]
    if not desc and sics: desc = [TITLE[c] + ' (from SIC)' for c in sics if c in TITLE][:3]
    est = pd.to_numeric(g.est, errors='coerce').min()
    size = g['size'].dropna().astype(str)
    rows.append(dict(site_id=site, estab_id=est_id, name=clean_name(g.name.iloc[-1]), first_year=yrs[0], last_year=yrs[-1], editions=len(yrs),
                     makes='; '.join(desc), sic=' '.join(sics), sic_source=g.sic_source.dropna().iloc[-1] if g.sic_source.notna().any() else '',
                     established=int(est) if pd.notna(est) and 1850 <= est <= 2003 else None,
                     employees=next((clean_size(v) for v in size[::-1] if clean_size(v)), ''), hazardous=bool(g.hazard_any.any()),
                     sectors='; '.join(sorted({s for x in g.fe_sectors.dropna() for s in str(x).split('; ') if s} |
                                              {s for x in g.ext_sectors.dropna() for s in str(x).split('; ') if s}))))
F = pd.DataFrame(rows)
F = F.sort_values(['site_id', 'hazardous', 'first_year'], ascending=[True, False, True])
F.to_csv('app/data/site_firms.csv', index=False)
print(len(F), 'firm-site rows for', F.site_id.nunique(), 'sites')
