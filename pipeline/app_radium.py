"""Radium, uranium and vanadium firms in both directories -> app/data/radium_firms.csv (one row per firm and place).

Colorado supplied most of the world's radium in 1910-1922 from carnotite ore (Paradox Valley, Uravan mineral belt) refined
in Denver, sold 'radium water' and radium baths as cures, and later hosted uranium/vanadium mills. Firms are found by
words in the name or in what the directory says they made (radium, uranium, vanadium, carnotite, thorium, radioactive,
pitchblende) or by SIC 1094 (uranium-radium-vanadium ores). Detection instruments and exploration consultants are not
processors and are left out. Locations: street-level where the 1961-2002 listing geocoded to an address, otherwise the
town (and for pre-1960 entries always the town)."""
import re, pandas as pd, numpy as np

RADIO = r"(?i)radium|uranium|vanadium|carnotite|thorium|radioactiv|pitchblende"
INSTR = r"(?i)(?:radium|radon|uranium)\s+(?:detect\w*|instrument\w*)|for uranium explor\w*|geophysical"
r = pd.read_pickle('work/inv/records_final.pkl')
txt = (r.name.fillna('') + ' ' + r.sic_desc.apply(lambda x: ' ; '.join(map(str, x))) + ' ' + r['product'].fillna('').astype(str))
txt = txt.str.replace(INSTR, ' ', regex=True)
m = txt.str.contains(RADIO) | r.sic.apply(lambda L: any(str(c).startswith('1094') for c in L))
R = r[m & r.lat.notna()].copy()
R['what'] = R.sic_desc.apply(lambda x: '; '.join(dict.fromkeys(str(d).strip().lower() for d in x if str(d).strip())))
a = R.sort_values('year').groupby('estab_id').agg(name=('name', 'last'), first_year=('year', 'min'), last_year=('year', 'max'),
        years=('year', lambda s: ' '.join(map(str, sorted(set(s))))), what=('what', lambda s: '; '.join(dict.fromkeys(x for v in s for x in v.split('; ') if x))[:200]),
        street=('street', 'last'), city=('city_g', 'last'), lat=('lat', 'last'), lon=('lon', 'last'), geo_level=('geo_level', 'last'),
        site_id=('site_id', lambda s: next((x for x in s if isinstance(x, str)), ''))).reset_index()
a['precision'] = np.where(a.geo_level.isin(['address', 'address_approx']), 'street', 'town')
a['source'] = 'Directory of Colorado Manufacturers'
H = pd.read_csv('app/data/historical_sites.csv')
h = H[H.sectors.fillna('').str.contains('Radium')].copy()
h = h.assign(what=h.example.fillna('').str[:200], city=h.town, site_id='', source='Colorado State Business Directory')
cols = ['name', 'first_year', 'last_year', 'years', 'what', 'street', 'city', 'lat', 'lon', 'precision', 'site_id', 'source']
out = pd.concat([a[cols], h[cols]], ignore_index=True).sort_values('first_year')
out['name'] = out.name.fillna('').astype(str).str.strip(' ,.&-')
out.loc[out.name.str.match(r"^\W*\d|.*\bBOX\b|^$"), 'name'] = '[firm name not legible in the scan]'
out.to_csv('app/data/radium_firms.csv', index=False)
print(len(out), 'radium/uranium/vanadium firm-places:', out.source.value_counts().to_dict())
print(out[['first_year', 'last_year', 'name', 'city', 'precision']].to_string())
