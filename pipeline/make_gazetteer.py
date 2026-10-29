"""Colorado place names and ZIP->city/county lookups from the EPA FRS facility file (used for city headings and geocoding)."""
import pandas as pd, os
def main():
    os.makedirs('work/inv', exist_ok=True)
    f = pd.read_csv('work/reg/CO_FACILITY_FILE.CSV', dtype=str, usecols=lambda c: c in ('CITY_NAME', 'STATE_CODE', 'POSTAL_CODE', 'COUNTY_NAME'))
    f = f[f.STATE_CODE == 'CO']
    c = f.CITY_NAME.str.upper().str.strip().value_counts()
    open('work/inv/co_cities.txt', 'w').write('\n'.join(c[c >= 3].index))
    f['z'] = f.POSTAL_CODE.str[:5]
    f.dropna(subset=['z', 'CITY_NAME']).groupby('z').CITY_NAME.agg(lambda s: s.str.upper().mode().iat[0]).to_csv('work/inv/zip_city.csv')
    f.dropna(subset=['z', 'COUNTY_NAME']).groupby('z').COUNTY_NAME.agg(lambda s: s.str.upper().mode().iat[0]).to_csv('work/inv/zip_county.csv')
    print('gazetteer: places', int((c >= 3).sum()))
if __name__ == '__main__': main()
