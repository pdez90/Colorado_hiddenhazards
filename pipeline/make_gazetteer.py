"""Colorado place names and ZIP->city/county lookups from the EPA FRS facility file (used for city headings and geocoding).

co_cities.txt is the list the parsers accept as town headings. An FRS city string seen 3 times is taken as a place name,
except (is_town): the state's name and other state names, county names ('ADAMS', 'WELD COUNTY', 'UNINCORPORATED OURAY
COUNTY') and strings that are not names ('KERSEY 8.6 MI. NE OF', 'UNK'). A state or county name is kept when it is also
a real town, i.e. the usual city of at least one ZIP code (DENVER, PUEBLO, BOULDER, YUMA, KIT CARSON ...)."""
import pandas as pd, os, re
STATES = {'COLORADO', 'CO', 'COLO', 'ALABAMA', 'ALASKA', 'ARIZONA', 'ARKANSAS', 'CALIFORNIA', 'CONNECTICUT', 'DELAWARE', 'FLORIDA', 'GEORGIA',
          'HAWAII', 'IDAHO', 'ILLINOIS', 'INDIANA', 'IOWA', 'KANSAS', 'KENTUCKY', 'LOUISIANA', 'MAINE', 'MARYLAND', 'MASSACHUSETTS',
          'MICHIGAN', 'MINNESOTA', 'MISSISSIPPI', 'MISSOURI', 'MONTANA', 'NEBRASKA', 'NEVADA', 'NEW HAMPSHIRE', 'NEW JERSEY',
          'NEW MEXICO', 'NEW YORK', 'NORTH CAROLINA', 'NORTH DAKOTA', 'OHIO', 'OKLAHOMA', 'OREGON', 'PENNSYLVANIA', 'RHODE ISLAND',
          'SOUTH CAROLINA', 'SOUTH DAKOTA', 'TENNESSEE', 'TEXAS', 'UTAH', 'VERMONT', 'VIRGINIA', 'WASHINGTON', 'WEST VIRGINIA',
          'WISCONSIN', 'WYOMING'}
COUNTIES = {'ADAMS','ALAMOSA','ARAPAHOE','ARCHULETA','BACA','BENT','BOULDER','BROOMFIELD','CHAFFEE','CHEYENNE','CLEAR CREEK','CONEJOS','COSTILLA','CROWLEY','CUSTER','DELTA','DENVER','DOLORES','DOUGLAS','EAGLE','ELBERT','EL PASO','FREMONT','GARFIELD','GILPIN','GRAND','GUNNISON','HINSDALE','HUERFANO','JACKSON','JEFFERSON','KIOWA','KIT CARSON','LAKE','LA PLATA','LARIMER','LAS ANIMAS','LINCOLN','LOGAN','MESA','MINERAL','MOFFAT','MONTEZUMA','MONTROSE','MORGAN','OTERO','OURAY','PARK','PHILLIPS','PITKIN','PROWERS','PUEBLO','RIO BLANCO','RIO GRANDE','ROUTT','SAGUACHE','SAN JUAN','SAN MIGUEL','SEDGWICK','SUMMIT','TELLER','WASHINGTON','WELD','YUMA'}
NOT_A_NAME = re.compile(r"\d|\b(COUNTY|UNINCORPORATED|LOCALITY|UNK|UNKNOWN|AREA|MI\.?\s+[NSEW]{1,2}\s+OF)\b")
def is_town(name, zip_towns):
    """name: upper-case FRS city string; zip_towns: set of names that are the usual city of some ZIP code."""
    n = (name or '').strip()
    if len(n) < 3 or NOT_A_NAME.search(n): return False
    if n in STATES or n in COUNTIES: return n in zip_towns
    return True
def zip_share_towns(f, min_rows=3, min_share=0.2):
    """Names that hold a real share of one ZIP code's facilities without being its most frequent city string: OURAY has
    58 of the rows of ZIP 81427 but 'UNINCORPORATED OURAY COUNTY' has more. A county written in the city field
    (PROWERS: 4 rows among Lamar's hundreds) never reaches the share. f: FRS rows with CITY_NAME and z."""
    g = f[f.z.fillna('').str.match(r'^8[01]\d{3}$') & (f.z != '80000')].assign(c=lambda d: d.CITY_NAME.str.upper().str.strip())
    n = g.groupby(['z', 'c']).size().rename('n').reset_index()
    n['share'] = n.n / n.groupby('z').n.transform('sum')
    return set(n[(n.n >= min_rows) & (n.share >= min_share)].c)
def main():
    os.makedirs('work/inv', exist_ok=True)
    f = pd.read_csv('work/reg/CO_FACILITY_FILE.CSV', dtype=str, usecols=lambda c: c in ('CITY_NAME', 'STATE_CODE', 'POSTAL_CODE', 'COUNTY_NAME'))
    f = f[f.STATE_CODE == 'CO']
    c = f.CITY_NAME.str.upper().str.strip().value_counts()
    f['z'] = f.POSTAL_CODE.str[:5]
    zc = f.dropna(subset=['z', 'CITY_NAME']).groupby('z').CITY_NAME.agg(lambda s: s.str.upper().mode().iat[0])
    zip_towns = set(zc[zc.index.str.match(r'^8[01]\d{3}$')].str.strip()) | zip_share_towns(f)
    seen = list(c[c >= 3].index)
    towns = [n for n in seen if is_town(n, zip_towns)]
    open('work/inv/co_cities.txt', 'w').write('\n'.join(towns))
    zc.to_csv('work/inv/zip_city.csv')
    f.dropna(subset=['z', 'COUNTY_NAME']).groupby('z').COUNTY_NAME.agg(lambda s: s.str.upper().mode().iat[0]).to_csv('work/inv/zip_county.csv')
    print('gazetteer: places', len(towns), '; rejected as state / county / not a name:', len(seen) - len(towns))
if __name__ == '__main__': main()
