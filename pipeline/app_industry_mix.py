"""Phases of Colorado manufacturing for the app's Trends tab (app/data/industry_mix.csv, app/data/firm_longevity.csv).
industry_mix: per directory edition, establishments listed in each SIC major group (all manufacturers, not only hazardous),
with the share of that edition's coded listings. Editions differ in coverage (1971, 1985, 1992, 2002 are partial), so shares
are more comparable across years than counts.
firm_longevity: per establishment, first and last edition listed and hazardous-sector flag (for survival / turnover plots)."""
import pandas as pd

SIC2 = {'10': 'Metal mining & ore milling', '20': 'Food', '21': 'Tobacco', '22': 'Textiles', '23': 'Apparel', '24': 'Lumber & wood',
        '25': 'Furniture', '26': 'Paper', '27': 'Printing & publishing', '28': 'Chemicals*', '29': 'Petroleum refining*',
        '30': 'Rubber & plastics*', '31': 'Leather', '32': 'Stone, clay & glass', '33': 'Primary metals*', '34': 'Fabricated metals*',
        '35': 'Industrial machinery & computers*', '36': 'Electronic & electrical', '37': 'Transportation equipment*',
        '38': 'Instruments', '39': 'Miscellaneous manufacturing'}
r = pd.read_pickle('work/inv/records_final.pkl')
r['sic2'] = r.sic.apply(lambda L: L[0][:2] if len(L) else '')
r['group'] = r.sic2.map(SIC2).fillna('Other / not coded')
m = r[r.group != 'Other / not coded'].drop_duplicates(['year', 'estab_id', 'group']).groupby(['year', 'group']).size().rename('establishments').reset_index()
m['share'] = m.establishments / m.groupby('year').establishments.transform('sum')
m['hazardous_sector'] = m.group.str.endswith('*')
m.to_csv('app/data/industry_mix.csv', index=False)
L = r.groupby('estab_id').agg(first_year=('year', 'min'), last_year=('year', 'max'), editions=('year', 'nunique'),
                              hazardous=('hazard_any', 'any'), group=('group', lambda x: x.mode().iloc[0])).reset_index()
L.to_csv('app/data/firm_longevity.csv', index=False)
print(len(m), 'year x group rows;', len(L), 'establishments')
