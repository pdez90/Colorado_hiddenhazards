"""The stage scripts run end to end on the synthetic fixture: geo_prep -> run_geocode -> build_sites -> finalize -> export ->
export_by_year -> validate_geocoding, in a scratch copy of the repository layout. Checks the hand-offs between stages (columns, levels,
site ids, radar/match_basis/confidence) rather than any one rule."""
import os, shutil, json, numpy as np, pandas as pd, pytest
import geo_prep, run_geocode, build_sites, finalize, export, export_by_year, validate_geocoding

LAT0 = 39.72

def records():
    """Directory listings as consolidate/link leave them (records_linked.pkl)."""
    rows = [
        # a plating works at 450 Kalamath (80204) in three editions, with a printed SIC in 1970; a pharmacy later at the same address
        dict(year=1965, name='ACME PLATING WORKS', name_n='ACME PLATING WORKS', street_n='450 KALAMATH ST', zip=None, city_ctx='Denver', estab_id='e1', fe_hazard=True, ext_hazard=False, fe_sectors='Fabricated metals', ext_sectors=None, sic=['3471'], sic_source='inferred'),
        dict(year=1970, name='ACME PLATING WORKS INC', name_n='ACME PLATING WORKS', street_n='450 KALAMATH ST', zip='80204', city_ctx='Denver', estab_id='e1', fe_hazard=True, ext_hazard=False, fe_sectors='Fabricated metals', ext_sectors=None, sic=['3471'], sic_source='directory'),
        dict(year=1977, name='ACME PLATING WORKS', name_n='ACME PLATING WORKS', street_n='452 KALAMATH ST', zip='80204', city_ctx='Denver', estab_id='e1', fe_hazard=True, ext_hazard=False, fe_sectors='Fabricated metals', ext_sectors=None, sic=['3471'], sic_source='directory'),
        dict(year=1990, name='CORNER PHARMACY', name_n='CORNER PHARMACY', street_n='450 KALAMATH ST', zip='80204', city_ctx='Denver', estab_id='e2', fe_hazard=False, ext_hazard=False, fe_sectors=None, ext_sectors=None, sic=['5912'], sic_source='directory'),
        # across the street: odd number, its own site
        dict(year=1970, name='WESTERN FOUNDRY CO', name_n='WESTERN FOUNDRY', street_n='451 KALAMATH ST', zip='80204', city_ctx='Denver', estab_id='e3', fe_hazard=True, ext_hazard=False, fe_sectors='Primary metals', ext_sectors=None, sic=['3321'], sic_source='directory'),
        # 450 S Kalamath printed without its direction, ZIP decides (80223): exact, moved to the S street
        dict(year=1970, name='SOUTH SIDE CHEMICAL CO', name_n='SOUTH SIDE CHEMICAL', street_n='450 KALAMATH', zip='80223', city_ctx='Denver', estab_id='e4', fe_hazard=True, ext_hazard=False, fe_sectors='Chemicals', ext_sectors=None, sic=['2899'], sic_source='directory'),
        # the same without a ZIP: ambiguous, not placed
        dict(year=1965, name='SOUTH SIDE CHEMICAL CO', name_n='SOUTH SIDE CHEMICAL', street_n='450 KALAMATH', zip=None, city_ctx='Denver', estab_id='e4', fe_hazard=True, ext_hazard=False, fe_sectors='Chemicals', ext_sectors=None, sic=['2899'], sic_source='inferred'),
        # wrong side of the grid: not placed; a glued direction letter: approximate; a ZIP in the street field
        dict(year=1965, name='GRID TEST MACHINE CO', name_n='GRID TEST MACHINE', street_n='4000 S KALAMATH', zip='80223', city_ctx='Denver', estab_id='e5', fe_hazard=True, ext_hazard=False, fe_sectors='Industrial machinery', ext_sectors=None, sic=['3599'], sic_source='inferred'),
        dict(year=1965, name='GLUED RUBBER CO', name_n='GLUED RUBBER', street_n='450 SKALAMATH', zip='80223', city_ctx='Denver', estab_id='e6', fe_hazard=True, ext_hazard=False, fe_sectors='Rubber & plastics', ext_sectors=None, sic=['3069'], sic_source='inferred'),
        dict(year=1965, name='ZIP IN STREET CO', name_n='ZIP IN STREET', street_n='2150 W 5TH AVE 0204', zip=None, city_ctx='Denver', estab_id='e7', fe_hazard=True, ext_hazard=False, fe_sectors='Chemicals', ext_sectors=None, sic=['2800'], sic_source='inferred'),
        # no street address
        dict(year=1965, name='BOX CO', name_n='BOX', street_n='P O BOX 123', zip='80204', city_ctx='Denver', estab_id='e8', fe_hazard=True, ext_hazard=False, fe_sectors='Chemicals', ext_sectors=None, sic=['2800'], sic_source='inferred'),
    ]
    df = pd.DataFrame(rows)
    df['vol'] = df.year.astype(str); df['page'] = 1; df['street'] = df.street_n; df['est'] = None; df['size'] = None
    df['naics'] = [[] for _ in range(len(df))]; df['sic_desc'] = [['x'] for _ in range(len(df))]; df['addr_raw'] = df.street_n
    return df

def inventory():
    return pd.DataFrame([
        dict(name='ACME PLATING WORKS INC', source='EPA_RCRAINFO', tier='rcra_handler', lat=LAT0 + 0.0015, lon=-105.0, address='450 Kalamath St', zip='80204', city='DENVER', geom_wkt=None),
        dict(name='DOWNTOWN DRY CLEANERS', source='EPA_RCRAINFO', tier='rcra_handler', lat=LAT0 + 50 / 98 * 0.0015, lon=-105.0 + 0.0003, address='', zip='', city='', geom_wkt=None),
    ])

@pytest.fixture(scope='module')
def run(synth_root, tmp_path_factory):
    root = str(tmp_path_factory.mktemp('stages'))
    shutil.copytree(synth_root, root, dirs_exist_ok=True)
    for d in ('work/geo', 'data/results', 'data/by_year', 'app/data', 'config'):
        os.makedirs(os.path.join(root, d), exist_ok=True)
    cwd = os.getcwd(); os.chdir(root)
    try:
        records().to_pickle('work/inv/records.pkl')
        pd.DataFrame({'z': ['80204', '80223', '80211', '80205', '80203', '80210', '80219', '80110'], 'COUNTY_NAME': ['DENVER COUNTY'] * 7 + ['ARAPAHOE COUNTY']}).to_csv('work/inv/zip_county.csv', index=False)
        json.dump({'mode': 'complete', 'complete_editions': [1965, 1970, 1977, 1990]}, open('config/editions.json', 'w'))
        geo_prep.main()
        pd.read_pickle('work/inv/records_geo.pkl').to_pickle('work/inv/records_linked.pkl')     # link.py is not under test
        run_geocode.main()
        inventory().to_pickle('work/inv/reg.pkl')
        build_sites.main(); finalize.main(); export.main(); export_by_year.main()
        # FRS check: one identical address with an independent coordinate 40 m away
        pd.DataFrame(dict(street_n=['450 KALAMATH ST'], zip5=['80204'], lat=[LAT0 + 50 / 98 * 0.0015 + 40 / 111320], lon=[-105.0001])).to_pickle('work/inv/frs_addr.pkl')
        validate_geocoding.main()
    finally: os.chdir(cwd)
    return root

def test_geo_prep_outputs(run):
    g = pd.read_pickle(os.path.join(run, 'work/inv/records_geo.pkl'))
    z = g[g.name == 'ZIP IN STREET CO'].iloc[0]
    assert z.street_n == '2150 W 5TH AVE' and z.zip == '80204' and z.city_g == 'DENVER'          # ZIP recovered from the street field
    assert g[g.name == 'BOX CO'].addr_kind.iloc[0] == 'pobox'
    assert (g.geo_key == g.street_n + '|' + g.city_g + '|' + g.zip5).all()
    assert g[(g.name == 'ACME PLATING WORKS') & (g.year == 1965)].city_g.iloc[0] == 'DENVER'       # from the page heading, no ZIP

def test_geocode_results(run):
    r = pd.read_csv(os.path.join(run, 'work/geo/tiger_results.csv'), dtype={'geo_key': str})
    q = dict(zip(r.geo_key, r.geo_quality))
    assert q['450 KALAMATH ST|DENVER|80204'] == 'range_interp_dirzip' and q['450 KALAMATH ST|DENVER|'] == 'range_interp_dirambig_cityzips'
    assert q['450 KALAMATH|DENVER|80223'] == 'range_interp_dirzip' and q['450 KALAMATH|DENVER|'] == 'range_interp_dirambig_cityzips'
    assert q['4000 S KALAMATH|DENVER|80223'] == 'zip_centroid' and q['450 SKALAMATH|DENVER|80223'] == 'range_interp_dirsplit'
    assert q['2150 W 5TH AVE|DENVER|80204'] == 'range_interp' and q['P O BOX 123|DENVER|80204'] == 'zip_centroid'
    assert r.geo_key.is_unique

def test_sites_and_levels(run):
    df = pd.read_pickle(os.path.join(run, 'work/inv/records_final.pkl')); s = pd.read_pickle(os.path.join(run, 'work/inv/sites_final.pkl'))
    lvl = df.set_index(['name', 'year']).geo_level
    assert lvl[('ACME PLATING WORKS', 1965)] == 'zip_centroid' and lvl[('ACME PLATING WORKS INC', 1970)] == 'address'
    assert lvl[('SOUTH SIDE CHEMICAL CO', 1970)] == 'address' and lvl[('SOUTH SIDE CHEMICAL CO', 1965)] == 'zip_centroid'
    assert lvl[('GRID TEST MACHINE CO', 1965)] == 'zip_centroid' and lvl[('GLUED RUBBER CO', 1965)] == 'address_approx'
    sid = df.set_index(['name', 'year']).site_id
    assert sid[('ACME PLATING WORKS INC', 1970)] == sid[('ACME PLATING WORKS', 1977)] == sid[('CORNER PHARMACY', 1990)]   # 450 and 452, same side
    assert sid[('WESTERN FOUNDRY CO', 1970)] != sid[('ACME PLATING WORKS INC', 1970)]                                      # 451: across the street
    assert pd.isna(sid[('ACME PLATING WORKS', 1965)]) and pd.isna(sid[('GRID TEST MACHINE CO', 1965)])
    assert sid[('SOUTH SIDE CHEMICAL CO', 1970)] == sid[('GLUED RUBBER CO', 1965)]                                         # both at 450 S Kalamath
    assert len(s) == 4 and s.site_id.is_unique

def test_site_attributes(run):
    s = pd.read_pickle(os.path.join(run, 'work/inv/sites_final.pkl')).set_index('address')
    a = s.loc['450 KALAMATH ST']
    assert a.names_n == ['ACME PLATING WORKS'] and a.n_establishments == 2 and a.n_hazard_establishments == 1 and a.first_year == 1970 and a.last_year == 1990
    assert a.hazard_years == '1970;1977' and a.geo_level == 'address' and a.industry_evidence == 'printed' and a.confidence == 'high'
    assert a.radar_status == '3 RCRA hazardous-waste handler' and a.match_basis == 'same entity (name or address)' and 'address match' in a.rcra_handler_match
    assert 0 < a.spread_m < 5 and a.county == 'DENVER COUNTY' and a.hazard_span_years == 7
    w = s.loc['451 KALAMATH ST']
    assert w.radar_status == '3 RCRA hazardous-waste handler' and w.match_basis == 'nearby record only'       # the dry cleaner 26 m away
    c = s.loc['450 KALAMATH']
    assert c.geo_level == 'address' and c.radar_status == '6 Not on any list' and c.match_basis == 'none' and c.confidence == 'high'
    assert set(c.names_n) == {'GLUED RUBBER', 'SOUTH SIDE CHEMICAL'} and c.zip == '80223'

def test_exports(run):
    import openpyxl
    wb = openpyxl.load_workbook(os.path.join(run, 'data/results/CO_hazardous_sites_1961-2002.xlsx'))
    assert wb.sheetnames == ['Read me', 'Summary', 'Hidden sites', 'All F&E hazardous sites', 'Extended-sector sites', 'Coverage by edition']
    H = pd.read_excel(os.path.join(run, 'data/results/CO_hazardous_sites_1961-2002.xlsx'), 'All F&E hazardous sites')
    assert list(H.columns[:4]) == ['site_id', 'radar', 'match_basis', 'confidence'] and len(H) == 4
    assert wb['Summary']['D2'].value.startswith("=COUNTIFS('All F&E hazardous sites'!$B$2") and "$D$2" in wb['Summary']['D2'].value   # D = confidence
    hidden = pd.read_excel(os.path.join(run, 'data/results/CO_hazardous_sites_1961-2002.xlsx'), 'Hidden sites')
    assert list(hidden.address) == ['450 KALAMATH', '2150 W 5TH AVE'] and set(hidden.match_basis) == {'none'} and list(hidden.confidence) == ['high', 'medium']
    gj = json.load(open(os.path.join(run, 'data/results/CO_historical_industrial_sites.geojson')))
    assert len(gj['features']) == 4 and {f['properties']['match_basis'] for f in gj['features']} == {'same entity (name or address)', 'nearby record only', 'none'}
    L = pd.read_csv(os.path.join(run, 'data/results/CO_directory_listings_1961-2002.csv'), dtype=str, keep_default_na=False)
    assert len(L) == 11 and set(L.geo_level) == {'address', 'address_approx', 'zip_centroid'}
    U = pd.read_csv(os.path.join(run, 'data/results/CO_hazardous_listings_not_street_located.csv'), dtype=str)
    assert set(U.name) == {'ACME PLATING WORKS', 'SOUTH SIDE CHEMICAL CO', 'GRID TEST MACHINE CO', 'BOX CO'}
    by = {y: pd.read_csv(os.path.join(run, f'data/by_year/CO_DCM_{y}_geocoded.csv'), dtype=str, keep_default_na=False) for y in (1965, 1970, 1977, 1990)}
    assert sum(map(len, by.values())) == 11 and 'site_match_basis' in by[1970] and 'geocode_method' in by[1970]
    r = by[1970].set_index('firm_name')
    assert r.loc['SOUTH SIDE CHEMICAL CO', 'geocode_method'] == 'range_interp_dirzip' and r.loc['SOUTH SIDE CHEMICAL CO', 'site_regulatory_status'] == 'Not on any list'
    assert by[1965].set_index('firm_name').loc['GRID TEST MACHINE CO', 'geocode_note'].startswith('ZIP code centroid only')

def test_validation_outputs(run):
    ext = pd.read_csv(os.path.join(run, 'data/results/geocoding_validation_frs.csv'))
    assert list(ext.geocode_level) == ['address'] and ext.n.iloc[0] == 1 and 30 <= ext.median_m.iloc[0] <= 50
    cov = pd.read_csv(os.path.join(run, 'data/results/geocoding_coverage_by_year.csv'))
    assert list(cov.year) == [1965, 1970, 1977, 1990] and cov.listings.sum() == 11
    assert os.path.exists(os.path.join(run, 'data/results/geocoding_validation.md'))
