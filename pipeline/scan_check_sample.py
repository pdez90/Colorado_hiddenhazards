"""Draw the random sample read against the page images in data/results/scan_check_2026-11-13.csv (seed 20261113).
30 pre-1960 street-level hazardous-sector firm-locations and 30 1961-2002 hazardous-sector sites; one listing of each is read.
    python3 pipeline/scan_check_sample.py   -> work/scancheck/scancheck_sample.csv
The pages were rendered from the scans (work/pdf, work/hist/pdf) at 200 dpi and read by eye; the reading is the committed CSV."""
import os
import numpy as np, pandas as pd
rng = np.random.default_rng(20261113)
L = pd.read_csv('data/historical/CO_pre1960_hazardous_listings.csv', dtype=str)
S = pd.read_csv('data/historical/CO_pre1960_hazardous_sites.csv', dtype=str)
rows = []
for _, r in S[(S.precision == 'street') & (S.fe_hazard == 'True')].sample(30, random_state=20261113).iterrows():
    x = L[L.hfirm == r.hfirm].sample(1, random_state=int(rng.integers(1e9))).iloc[0]
    rows.append(dict(sample='pre1960', id=r.hfirm, vol=x.vol, year=x.year, page=x.page, listing_name=x['name'], pub_street=r.street))
D = pd.read_csv('data/results/CO_directory_listings_1961-2002.csv', dtype=str)
T = pd.read_csv('app/data/sites.csv', dtype=str)
for _, r in T[T.fe_hazard == 'TRUE'].sample(30, random_state=20261113).iterrows():
    x = D[(D.site_id == r.site_id) & (D.fe_hazard == 'True')].sample(1, random_state=int(rng.integers(1e9))).iloc[0]
    rows.append(dict(sample='1961-2002', id=r.site_id, vol=x.source_volume, year=x.year, page=x.page, listing_name=x['name'], pub_street=x.street))
os.makedirs('work/scancheck', exist_ok=True)
pd.DataFrame(rows).to_csv('work/scancheck/scancheck_sample.csv', index=False)
