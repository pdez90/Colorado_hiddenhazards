"""Geocoding accuracy check.
1. External: directory addresses that exactly match an address in EPA's Facility Registry (independent coordinates from
   facility reporting / EPA geocoding) -> distance between our TIGER geocode and the FRS coordinate.
2. Coverage: share of listings at each geocode level, by edition.
Writes data/results/geocoding_validation.md and .csv files."""
import pandas as pd, numpy as np, os
os.makedirs('data/results', exist_ok=True)
df = pd.read_pickle('work/inv/records_final.pkl'); addr = pd.read_pickle('work/inv/frs_addr.pkl')
u = df[df.located].drop_duplicates('geo_key')[['geo_key', 'street_n', 'zip5', 'lat', 'lon', 'geo_level', 'geo_quality']]
m = u.merge(addr, on=['street_n', 'zip5'], suffixes=('', '_frs'))
def hav(a, b, c, d):
    a, b, c, d = map(np.radians, (a, b, c, d))
    return 2 * 6371000 * np.arcsin(np.sqrt(np.sin((c - a) / 2) ** 2 + np.cos(a) * np.cos(c) * np.sin((d - b) / 2) ** 2))
m['dist_m'] = hav(m.lat, m.lon, m.lat_frs, m.lon_frs)
rows = []
for lvl, g in m.groupby('geo_level'):
    d = g.dist_m
    rows.append(dict(geocode_level=lvl, n=len(g), median_m=round(d.median()), p75_m=round(d.quantile(.75)), p90_m=round(d.quantile(.9)),
                     within_100m=round((d <= 100).mean(), 3), within_250m=round((d <= 250).mean(), 3), over_1km=round((d > 1000).mean(), 3)))
ext = pd.DataFrame(rows); ext.to_csv('data/results/geocoding_validation_frs.csv', index=False)
cov = df.groupby('year').geo_level.value_counts(normalize=True).unstack(fill_value=0).round(3)
cov.insert(0, 'listings', df.groupby('year').size()); cov.to_csv('data/results/geocoding_coverage_by_year.csv')
with open('data/results/geocoding_validation.md', 'w') as f:
    f.write('# Geocoding validation\n\n## Distance to EPA Facility Registry coordinates for identical addresses\n\n')
    f.write(ext.to_markdown(index=False) + '\n\n')
    f.write('FRS coordinates have their own error (often 30-100 m), so these distances overstate our error somewhat; '
            'addresses that also appear in FRS are cleaner than average, so they may understate it.\n\n')
    f.write('## Geocode level by edition (share of listings)\n\n' + cov.to_markdown() + '\n')
print(ext.to_string(index=False))
