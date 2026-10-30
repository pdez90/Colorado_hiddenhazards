"""pipeline/build_sites.py rules on synthetic points and inventory records."""
import numpy as np, pandas as pd, pytest
import build_sites as bs

LAT0, LON0 = 39.72, -105.0
def dlat(m): return m / 111320.0
def dlon(m): return m / (111320.0 * np.cos(np.radians(LAT0)))

def pts(rows):
    return pd.DataFrame(rows, columns=['geo_key', 'lat', 'lon', 'street_n'])

# ---- clustering
def test_cluster_links_points_within_30m_transitively():
    P = pts([('a', LAT0, LON0, '400 KALAMATH ST'), ('b', LAT0 + dlat(25), LON0, '402 KALAMATH ST'), ('c', LAT0 + dlat(50), LON0, '404 KALAMATH ST'),
             ('d', LAT0 + dlat(200), LON0, '420 KALAMATH ST')])
    s = bs.cluster_sites(P)
    assert s[0] == s[1] == s[2] and s[3] != s[0] and set(s) == {'S00000', 'S00001'}

def test_cluster_parity_rule_keeps_the_two_sides_apart():
    """Two points on the same street, odd and even numbers, 24 m apart (12 m offsets on each side): not linked directly."""
    P = pts([('a', LAT0, LON0 - dlon(12), '450 KALAMATH ST'), ('b', LAT0, LON0 + dlon(12), '451 KALAMATH ST'),
             ('c', LAT0 + dlat(3), LON0 - dlon(12), '452 KALAMATH ST'), ('d', LAT0 + dlat(3), LON0 + dlon(12), '453 KALAMATH ST')])
    s = bs.cluster_sites(P)
    assert s[0] == s[2] and s[1] == s[3] and s[0] != s[1]

def test_cluster_parity_rule_only_for_the_same_street():
    """Odd/even on different streets (or a different direction) still link; so do numberless addresses."""
    P = pts([('a', LAT0, LON0, '450 KALAMATH ST'), ('b', LAT0, LON0 + dlon(20), '451 S KALAMATH ST'),
             ('c', LAT0 + dlat(10), LON0, '451 W 5TH AVE'), ('d', LAT0 - dlat(10), LON0, 'KALAMATH ST')])
    assert bs.cluster_sites(P).nunique() == 1

def test_cluster_parity_rule_is_not_transitive_protection():
    """A third point of another street between the two sides bridges them (the rule only removes the direct link)."""
    P = pts([('a', LAT0, LON0 - dlon(12), '450 KALAMATH ST'), ('b', LAT0, LON0 + dlon(12), '451 KALAMATH ST'), ('c', LAT0, LON0, '100 W 5TH AVE')])
    assert bs.cluster_sites(P).nunique() == 1

def test_cluster_same_parity_same_side_links():
    P = pts([('a', LAT0, LON0, '450 KALAMATH ST'), ('b', LAT0 + dlat(20), LON0, '460 KALAMATH ST'), ('c', LAT0 + dlat(40), LON0, '470 KALAMATH ST')])
    assert bs.cluster_sites(P).nunique() == 1

def test_cluster_empty_and_single():
    assert len(bs.cluster_sites(pts([]))) == 0
    assert list(bs.cluster_sites(pts([('a', LAT0, LON0, '1 MAIN ST')]))) == ['S00000']

def test_cluster_ids_deterministic_in_input_order():
    P = pts([('a', LAT0, LON0, '1 A ST'), ('b', LAT0 + 0.01, LON0, '1 B ST'), ('c', LAT0 + 0.02, LON0, '1 C ST')])
    assert list(bs.cluster_sites(P)) == ['S00000', 'S00001', 'S00002']

# ---- spread
def test_spread_m():
    assert bs.spread_m([LAT0], [LON0]) == 0.0
    assert bs.spread_m([LAT0, LAT0 + dlat(20)], [LON0, LON0]) == pytest.approx(10, rel=0.002)
    assert bs.spread_m([LAT0, LAT0, LAT0], [LON0 - dlon(30), LON0, LON0 + dlon(30)]) == pytest.approx(30, rel=0.002)
    assert bs.spread_m([], []) == 0.0

# ---- name matching
@pytest.mark.parametrize('a,b,exp', [
    ('CRYSTAL CHEMICAL', 'CRYSTAL', False),                       # one shared word used to score 100 (token set); now rejected
    ('SERUM LABORATORIES', 'SERUM', False),
    ('ACME PLATING WORKS', 'ACME PLATING', True),                 # two shared informative tokens, token set 100
    ('ACME PLATING WORKS', 'PLATING WORKS ACME', True),           # word order (token sort)
    ('ACME PLATNG WORKS', 'ACME PLATING WORKS', True),            # OCR noise within 88
    ('ACME PLATING', 'ACME ELECTROPLATING', False),
    ('', 'ACME', False), ('ACME', '', False),
    ('ROCKY MOUNTAIN STEEL', 'ROCKY MOUNTAIN NEWS', False),       # two shared tokens but token set < 88 and sort < 88
    ('ROCKY MOUNTAIN STEEL', 'ROCKY MOUNTAIN STEEL MILLS', True),
])
def test_name_match(a, b, exp):
    assert bs.name_match(a, b) is exp

def test_nn_strips_stop_words_and_places():
    assert bs.nn('The Colorado Springs Chemical Co., Inc.') == 'CHEMICAL'
    assert bs.nn('Denver Precision Castings of Colorado') == ''
    assert bs.nn("Gates Rubber Co") == 'GATES RUBBER'

def test_match_basis_precedence():
    assert bs.match_basis({'entity', 'boundary', 'prox'}) == 'same entity (name or address)'
    assert bs.match_basis({'boundary', 'prox'}) == 'inside a cleanup boundary'
    assert bs.match_basis({'prox'}) == 'nearby record only'
    assert bs.match_basis(set()) == 'none'

# ---- inventory matching on synthetic records
def site(lat=LAT0, lon=LON0, spread=0.0, address='450 KALAMATH ST', zip5='80204', city='DENVER', names=('ACME PLATING WORKS',)):
    return dict(lat=lat, lon=lon, spread_m=spread, address=address, zip=zip5, city=city, names_n=list(names))
def reg(name, tier, lat=None, lon=None, address='', zip5='', city='', source='EPA_FRS', geom=None):
    return dict(name=name, tier=tier, lat=lat, lon=lon, address=address, zip=zip5, city=city, source=source, geom_wkt=geom)
def run(sites, regs):
    S = pd.DataFrame(sites); R = pd.DataFrame(regs, columns=['name', 'tier', 'lat', 'lon', 'address', 'zip', 'city', 'source', 'geom_wkt'])
    return bs.match_inventory(S, R)

def test_name_match_within_250m_is_entity():
    M = run([site()], [reg('Acme Plating Works Inc', 'rcra_handler', LAT0 + dlat(200), LON0)])
    r = M.iloc[0]
    assert r.match_basis == 'same entity (name or address)' and 'name match, 199 m' in r.rcra_handler_match      # 200 m by 111320 m/deg, 199.8 on the sphere
    assert r.radar_status == '3 RCRA hazardous-waste handler' and r.rcra_handler_nearest_m == 200

def test_name_match_beyond_250m_is_not_seen():
    M = run([site()], [reg('Acme Plating Works Inc', 'rcra_handler', LAT0 + dlat(300), LON0)])
    r = M.iloc[0]
    assert r.match_basis == 'none' and r.radar_status == '6 Not on any list' and np.isnan(r.rcra_handler_nearest_m)

def test_address_match_without_coordinates_is_entity():
    M = run([site()], [reg('Something Else LLC', 'tri', None, None, address='450 Kalamath Street', zip5='80204')])
    r = M.iloc[0]
    assert r.match_basis == 'same entity (name or address)' and r.tri_match.endswith('(address match)') and r.radar_status == '2 TRI reporter'

def test_address_match_blank_zip_uses_city():
    M = run([site(zip5='')], [reg('Other Name', 'other_epa', address='450 KALAMATH ST', zip5='80204', city='Denver')])
    assert M.iloc[0].match_basis == 'same entity (name or address)' and M.iloc[0].radar_status == '5 Other EPA permit only'
    # a ZIP that matches no record falls back to street + city too (an OCR'd ZIP does not hide the record); a different city does not
    M = run([site(zip5='80205')], [reg('Other Name', 'other_epa', address='450 KALAMATH ST', zip5='80204', city='Denver')])
    assert M.iloc[0].match_basis == 'same entity (name or address)'
    M = run([site(zip5='80205', city='AURORA')], [reg('Other Name', 'other_epa', address='450 KALAMATH ST', zip5='80204', city='Denver')])
    assert M.iloc[0].match_basis == 'none'

def test_boundary_only_is_boundary_basis_and_cleanup_tier():
    poly = f'POLYGON(({LON0 - 0.001} {LAT0 - 0.001}, {LON0 + 0.001} {LAT0 - 0.001}, {LON0 + 0.001} {LAT0 + 0.001}, {LON0 - 0.001} {LAT0 + 0.001}, {LON0 - 0.001} {LAT0 - 0.001}))'
    M = run([site()], [reg('Old Smelter Site', 'cleanup', None, None, source='CDPHE_VCUP', geom=poly)])
    r = M.iloc[0]
    assert r.match_basis == 'inside a cleanup boundary' and '(inside site boundary)' in r.cleanup_match and r.radar_status == '1 Cleanup / contamination list'
    far = site(lat=LAT0 + 0.01)
    assert run([far], [reg('Old Smelter Site', 'cleanup', None, None, source='CDPHE_VCUP', geom=poly)]).iloc[0].match_basis == 'none'

def test_proximity_only_within_tier_radius():
    M = run([site()], [reg('Corner Pharmacy', 'rcra_handler', LAT0 + dlat(35), LON0)])
    r = M.iloc[0]
    assert r.match_basis == 'nearby record only' and r.radar_status == '3 RCRA hazardous-waste handler' and '; 34 m]' in r.rcra_handler_match
    M = run([site()], [reg('Corner Pharmacy', 'rcra_handler', LAT0 + dlat(45), LON0)])
    r = M.iloc[0]
    assert r.match_basis == 'none' and r.radar_status == '6 Not on any list' and r.rcra_handler_match == '' and r.rcra_handler_nearest == 'Corner Pharmacy'

def test_tier_radii():
    for tier, rad in bs.RULES.items():
        assert run([site()], [reg('X', tier, LAT0 + dlat(rad - 1), LON0)]).iloc[0].match_basis == 'nearby record only'
        assert run([site()], [reg('X', tier, LAT0 + dlat(rad + 2), LON0)]).iloc[0].match_basis == 'none'

def test_radius_grows_with_spread_capped_at_250():
    assert run([site(spread=30)], [reg('X', 'rcra_handler', LAT0 + dlat(65), LON0)]).iloc[0].match_basis == 'nearby record only'
    assert run([site(spread=30)], [reg('X', 'rcra_handler', LAT0 + dlat(75), LON0)]).iloc[0].match_basis == 'none'
    assert run([site(spread=500)], [reg('X', 'rcra_handler', LAT0 + dlat(249), LON0)]).iloc[0].match_basis == 'nearby record only'
    assert run([site(spread=500)], [reg('X', 'rcra_handler', LAT0 + dlat(252), LON0)]).iloc[0].match_basis == 'none'

def test_no_250m_widening_for_approximate_sites():
    """An approximately located site (placed_loose) used to be searched over 250 m for the proximity rule; it now gets the base radius."""
    s = site(); s['placed_loose'] = True; s['geo_level'] = 'address_approx'
    M = run([s], [reg('Supermarket', 'rcra_handler', LAT0 + dlat(120), LON0)])
    assert M.iloc[0].match_basis == 'none' and M.iloc[0].radar_status == '6 Not on any list'

def test_radar_precedence_over_tiers():
    regs = [reg('A', 'other_epa', LAT0 + dlat(10), LON0), reg('B', 'solid_waste', LAT0 + dlat(10), LON0 + dlon(10)),
            reg('C', 'rcra_handler', LAT0 - dlat(10), LON0), reg('D', 'tri', LAT0, LON0 + dlon(20)), reg('E', 'cleanup', LAT0, LON0 - dlon(20))]
    M = run([site()], regs)
    assert M.iloc[0].radar_status == '1 Cleanup / contamination list' and M.iloc[0].match_basis == 'nearby record only'
    for drop, exp in [('E', '2 TRI reporter'), ('D', '3 RCRA hazardous-waste handler'), ('C', '4 Solid waste facility'), ('B', '5 Other EPA permit only'), ('A', '6 Not on any list')]:
        regs = [r for r in regs if r['name'] != drop]
        assert run([site()], regs).iloc[0].radar_status == exp

def test_entity_beats_proximity_in_basis_and_hits_listed_once():
    M = run([site()], [reg('Acme Plating Works', 'rcra_handler', LAT0 + dlat(10), LON0), reg('Pharmacy', 'rcra_handler', LAT0 + dlat(20), LON0)])
    r = M.iloc[0]
    assert r.match_basis == 'same entity (name or address)' and r.rcra_handler_match.count('Acme Plating Works') == 1 and 'Pharmacy' in r.rcra_handler_match

def test_only_hazardous_firm_names_are_matched():
    """agg_site keeps the hazardous firms' names for the inventory name match; a later retailer at the address does not count."""
    g = pd.DataFrame(dict(year=[1965, 1980], name=['Acme Plating Works', 'Corner Pharmacy'], name_n=['ACME PLATING WORKS', 'CORNER PHARMACY'],
                          estab_id=['e1', 'e2'], hazard_any=[True, False], fe_hazard=[True, False], ext_hazard=[False, False],
                          fe_sectors=['Fabricated metals', None], ext_sectors=[None, None], sic=[['3471'], ['5912']], est=[None, None], size=[None, None],
                          lat=[LAT0, LAT0], lon=[LON0, LON0], geo_level=['address', 'address'], placed_loose=[False, False], located=[True, True],
                          street_n=['450 KALAMATH ST'] * 2, city_g=['DENVER'] * 2, zip5=['80204'] * 2))
    s = bs.agg_site(g)
    assert s.names_n == ['ACME PLATING WORKS'] and s.n_establishments == 2 and s.n_hazard_establishments == 1 and s.geo_level == 'address'
    g2 = g.assign(hazard_any=False, fe_hazard=False)
    assert bs.agg_site(g2).names_n == ['ACME PLATING WORKS', 'CORNER PHARMACY']       # no hazardous firm: all names

def test_geo_level_and_placed_loose_series():
    q = pd.Series(['range_interp', 'range_interp_dirambig', 'fuzzy_range_interp', 'street_nearest', 'zip_centroid', None])
    assert list(bs.geo_level(q)) == ['address', 'zip_centroid', 'address_approx', 'address_approx', 'zip_centroid', 'none']
    assert list(bs.placed_loose(q)) == [False, False, True, True, False, False]

def test_per_tier_evidence_columns():
    """Each tier records its strongest evidence ({tier}_basis: entity > boundary > prox > '') and the distance to the nearest
    differently named record inside the tier's radius ({tier}_prox_m), so the known/hidden sensitivity analysis
    (R/known_hidden_sensitivity.R) can vary the proximity rule without re-running the match."""
    M = run([site()], [reg('Corner Pharmacy', 'rcra_handler', LAT0 + dlat(35), LON0),
                       reg('Acme Plating Works Inc', 'tri', LAT0 + dlat(90), LON0),
                       reg('Car Wash', 'other_epa', LAT0 + dlat(60), LON0)])
    r = M.iloc[0]
    assert r.rcra_handler_basis == 'prox' and r.rcra_handler_prox_m == 35
    assert r.tri_basis == 'entity' and np.isnan(r.tri_prox_m)            # the only TRI record is the firm itself
    assert r.other_epa_basis == '' and np.isnan(r.other_epa_prox_m)      # 60 m is outside the 40 m radius
    assert r.cleanup_basis == '' and r.solid_waste_basis == ''
    poly = f'POLYGON(({LON0 - 0.001} {LAT0 - 0.001}, {LON0 + 0.001} {LAT0 - 0.001}, {LON0 + 0.001} {LAT0 + 0.001}, {LON0 - 0.001} {LAT0 + 0.001}, {LON0 - 0.001} {LAT0 - 0.001}))'
    r = run([site()], [reg('Old Smelter Site', 'cleanup', None, None, source='CDPHE_VCUP', geom=poly)]).iloc[0]
    assert r.cleanup_basis == 'boundary'
    r = run([site()], [reg('Something Else LLC', 'tri', None, None, address='450 Kalamath Street', zip5='80204')]).iloc[0]
    assert r.tri_basis == 'entity'

def test_county_from_tracts_overrides_zip_county():
    """export.county_from_tracts: a site takes the county of the 2020 tract its point lies in (ZIPs cross county lines, and the ZIP
    table built from FRS facilities even carries a 'PORTABLE SOURCE' county); a point in no tract keeps its ZIP county."""
    import export, geopandas as gpd
    from shapely.geometry import box
    T = gpd.GeoDataFrame({'GEOID': ['08031000100', '08001000100'], 'County': ['Denver County', 'Adams County']},
                         geometry=[box(-105.0, 39.7, -104.9, 39.8), box(-104.9, 39.7, -104.8, 39.8)], crs=4326)
    s = pd.DataFrame({'lat': [39.75, 39.75, 40.5], 'lon': [-104.95, -104.85, -104.95], 'county': ['Adams', 'Portable Source', 'Weld']})
    assert export.county_from_tracts(s, T).tolist() == ['Denver', 'Adams', 'Weld']
