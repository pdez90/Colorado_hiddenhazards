"""One CSV per directory edition with every listing, its industry coding and geocode -> data/by_year/CO_DCM_<year>_geocoded.csv"""
import pandas as pd, numpy as np, os
GEO_NOTE = {'address': 'street address interpolated on TIGER segment',
            'address_approx': 'street matched with OCR correction / neighbouring ZIP / nearest segment: verify',
            'zip_centroid': 'ZIP code centroid only (a direction-less address that two streets could hold keeps its street coordinate for inspection but counts as unplaced)', 'city_centroid': 'city centroid only', 'none': 'not located'}
def main():
    os.makedirs('data/by_year', exist_ok=True)
    df = pd.read_pickle('work/inv/records_final.pkl')
    sites = pd.read_pickle('work/inv/sites_export.pkl')[['site_id', 'radar', 'match_basis', 'confidence', 'county']]
    df = df.merge(sites, on='site_id', how='left')
    zco = pd.read_csv('work/inv/zip_county.csv', dtype=str); zmap = dict(zip(zco.z, zco.COUNTY_NAME.str.replace(' COUNTY', '').str.title()))
    df['county'] = df['county'].fillna(df.zip5.map(zmap))
    J = lambda x: ';'.join(x) if isinstance(x, list) else ''
    df['sic_codes'] = df.sic.apply(J); df['sic_descriptions'] = df.sic_desc.apply(J); df['naics_codes'] = df.naics.apply(J)
    df['geo_note'] = df.geo_level.map(GEO_NOTE)
    cols = {'year': 'edition_year', 'vol': 'source_volume', 'page': 'source_page', 'name': 'firm_name', 'street': 'street_address',
            'city_g': 'city', 'zip5': 'zip', 'county': 'county', 'est': 'year_established', 'size': 'employment_class',
            'sic_codes': 'sic_codes', 'sic_descriptions': 'sic_descriptions', 'sic_source': 'industry_code_source', 'naics_codes': 'naics_codes',
            'fe_hazard': 'fe_hazardous_sector', 'fe_sectors': 'fe_sectors', 'ext_hazard': 'extended_hazard_sector', 'ext_sectors': 'extended_sectors',
            'estab_id': 'establishment_id', 'site_id': 'site_id', 'lat': 'latitude', 'lon': 'longitude', 'geo_level': 'geocode_level',
            'geo_quality': 'geocode_method', 'geo_note': 'geocode_note', 'radar': 'site_regulatory_status', 'match_basis': 'site_match_basis', 'confidence': 'site_confidence',
            'addr_raw': 'address_as_ocr'}
    for c in cols:
        if c not in df: df[c] = None
    out = df[list(cols)].rename(columns=cols)
    for c in ['firm_name', 'street_address', 'address_as_ocr']:
        out[c] = out[c].astype(str).str.replace(r'^[=+@\-]+\s*', '', regex=True).replace('nan', '')
    for y, g in out.groupby('edition_year'):
        g.sort_values(['county', 'city', 'firm_name']).to_csv(f'data/by_year/CO_DCM_{y}_geocoded.csv', index=False)
        print(y, len(g))

if __name__ == '__main__': main()
