"""The October 2026 review rules, each on the synthetic Denver fixture (see synthetic_tiger.py). Every test here fails on the
pre-review geocoder (git HEAD~ pipeline/tiger_geocode.py: no offset, _dirambig for every plain/directional pair, no grid_conflict,
no SO/NO, no glued-letter split, trimming down to '5TH', no neighbour ZIPs without a printed ZIP)."""
import numpy as np, pytest
from build_sites import geo_level

S_KAL_LAT = 39.712 - 50 / 98 * 0.0015      # 450 on S Kalamath St (southbound segment from 39.7120)
KAL_LAT = 39.72 + 50 / 98 * 0.0015          # 450 on Kalamath St (northbound segment from 39.7200)

def level(q): return geo_level([q])[0]

# ---- an address printed without a direction whose number exists on the plain and on a directional street
def test_dir_resolved_by_own_zip_ranges_moves_to_directional(geocoder):
    """'450 KALAMATH' in 80223: that ZIP's ranges hold only S Kalamath, so the point moves 1 km south to S Kalamath and counts as exact.
    80223 straddles Ellsworth: plain Kalamath St has a 100-199 segment there, whose nearest end (street_nearest, 250 numbers away, on the
    north side) used to be returned before the plain/directional resolution could run (31 committed Denver keys)."""
    la, lo, q = geocoder.geocode('450 KALAMATH', 'DENVER', '80223')
    assert q == 'range_interp_dirzip' and la == pytest.approx(S_KAL_LAT, abs=1e-9) and level(q) == 'address'
    la, lo, q = geocoder.geocode('450 KALAMATH ST', 'DENVER', '80223')
    assert q == 'range_interp_dirzip' and la == pytest.approx(S_KAL_LAT, abs=1e-9)

def test_street_nearest_still_used_when_no_directional_version_holds_the_number(geocoder):
    """250 Kalamath in 80223: the plain 100-199 segment's end is 51 numbers away and no S segment holds 250 -> street_nearest, north side."""
    la, lo, q = geocoder.geocode('250 KALAMATH', 'DENVER', '80223')
    assert q == 'street_nearest' and la == pytest.approx(39.7185, abs=1e-9)

def test_dir_resolved_by_own_zip_ranges_keeps_plain(geocoder):
    la, lo, q = geocoder.geocode('450 KALAMATH', 'DENVER', '80204')
    assert q == 'range_interp_dirzip' and la == pytest.approx(KAL_LAT, abs=1e-9) and level(q) == 'address'

def test_dir_resolved_by_zip_half_of_grid(geocoder):
    """A ZIP that holds neither version decides by its half of the grid: 80219 (south) -> S Kalamath; 80211 (north) -> plain Kalamath."""
    la, lo, q = geocoder.geocode('450 KALAMATH', 'DENVER', '80219')
    assert q == 'range_interp_dirzip_cityzips' and la == pytest.approx(S_KAL_LAT, abs=1e-9)
    la, lo, q = geocoder.geocode('450 KALAMATH', 'DENVER', '80211')
    assert q == 'range_interp_dirzip_cityzips' and la == pytest.approx(KAL_LAT, abs=1e-9)

def test_dir_ambiguous_when_nothing_decides(geocoder):
    """No ZIP and a town on both halves, or a downtown ZIP without a half: _dirambig, kept at the plain street but not placed (zip_centroid level)."""
    la, lo, q = geocoder.geocode('450 KALAMATH', 'DENVER', '')
    assert q == 'range_interp_dirambig_cityzips' and la == pytest.approx(KAL_LAT, abs=1e-9) and level(q) == 'zip_centroid'
    assert geocoder.geocode('450 KALAMATH ST', 'DENVER', '80203')[2] == 'range_interp_dirambig_cityzips'
    assert geocoder.geocode('450 KALAMATH', 'ENGLEWOOD', '')[2] == 'range_interp_dirambig_nearzips'

def test_dir_resolved_by_street_type(geocoder):
    """24th St (downtown) and E 24th Ave both hold 2350: the printed type decides (_dirtype); with none printed, plain means the street."""
    st = geocoder.geocode('2350 24TH ST', 'DENVER', '80205'); av = geocoder.geocode('2350 24TH AVE', 'DENVER', '80205')
    none = geocoder.geocode('2350 24TH', 'DENVER', '80205'); ref = geocoder.geocode('2350 E 24TH AVE', 'DENVER', '80205')
    assert st[2] == av[2] == none[2] == 'range_interp_dirtype' and ref[2] == 'range_interp'
    assert st[0] == pytest.approx(none[0]) and st[0] > 39.7555                       # on 24th St
    assert av[0] == pytest.approx(ref[0]) and av[1] == pytest.approx(ref[1])        # moved to E 24th Ave
    assert {level(x[2]) for x in (st, av, none, ref)} == {'address'}

def test_dir_codes_map_to_levels():
    assert [level(q) for q in ['range_interp_dirzip', 'range_interp_dirtype', 'range_interp_dirzip_cityzips', 'range_interp_dirambig',
                               'range_interp_dirambig_cityzips', 'fuzzy_range_interp_dirzip_cityzips', 'range_interp_dirsplit',
                               'range_interp_cityzips_dirloose', 'street_nearest', 'zip_centroid', 'city_centroid', 'none', None]] == \
           ['address', 'address', 'address', 'zip_centroid', 'zip_centroid', 'address_approx', 'address_approx', 'address_approx',
            'address_approx', 'zip_centroid', 'city_centroid', 'none', 'none']

# ---- grid conflict
def test_grid_conflict_blocks_wrong_side(geocoder):
    """'4000 S KALAMATH' exists only as plain Kalamath St 6 km north of Ellsworth: the direction-loose pass may not use it."""
    la, lo, q = geocoder.geocode('4000 S KALAMATH', 'DENVER', '80223')
    assert q == 'zip_centroid' and (la, lo) == (39.705, -105.01)

def test_grid_conflict_allows_right_side(geocoder):
    la, lo, q = geocoder.geocode('4000 N KALAMATH', 'DENVER', '80223')
    assert q == 'range_interp_cityzips_dirloose' and la == pytest.approx(39.77, abs=1e-9) and level(q) == 'address_approx'

# ---- directions written out, glued, misread
def test_so_no_directions(geocoder):
    la, lo, q = geocoder.geocode('450 SO KALAMATH', 'DENVER', '80223')
    assert q == 'range_interp' and la == pytest.approx(S_KAL_LAT, abs=1e-9)
    la, lo, q = geocoder.geocode('1050 SO BROADWAY', 'DENVER', '80210')
    assert q == 'range_interp' and la < 39.7163
    la, lo, q = geocoder.geocode('650 BROADWAY NO 5', 'DENVER', '80203')      # 'NO 5' is a unit here
    assert q == 'range_interp' and la > 39.7163

def test_glued_direction_letter_split(geocoder):
    la, lo, q = geocoder.geocode('450 SKALAMATH', 'DENVER', '80223')
    assert q == 'range_interp_dirsplit' and la == pytest.approx(S_KAL_LAT, abs=1e-9) and level(q) == 'address_approx'

def test_direction_glued_to_number(geocoder):
    """'450S KALAMATH' / '1731S KALAMATH': the letter after the number is the direction, not an OCR 5."""
    la, lo, q = geocoder.geocode('450S KALAMATH', 'DENVER', '80223')
    assert q == 'range_interp' and la == pytest.approx(S_KAL_LAT, abs=1e-9)
    assert geocoder.geocode('1731S KALAMATH', 'DENVER', '80223')[2] == 'zip_centroid'    # 1731 is on no S Kalamath segment (not 17315 either)

def test_fuzzy_name_recovers_direction_from_zip(geocoder):
    la, lo, q = geocoder.geocode('450 KALAMETH ST', 'DENVER', '80223')
    assert q == 'fuzzy_range_interp_dirzip' and la == pytest.approx(S_KAL_LAT, abs=1e-9) and level(q) == 'address_approx'

def test_suffix_mismatch_is_loose(geocoder):
    assert geocoder.geocode('450 KALAMATH AVE', 'DENVER', '80204')[2] == 'range_interp_sufloose_dirzip'

# ---- trimming
def test_junk_token_dropped_never_trimmed_to_bare_ordinal(geocoder):
    """'2150 5 KALAMATH' (the S read as 5): the junk token goes first and the name is never cut down to '5TH' (W 5th Ave holds 2150)."""
    la, lo, q = geocoder.geocode('2150 5 KALAMATH', 'DENVER', '80204')
    assert q == 'range_interp_trim' and la == pytest.approx(39.74 + 50 / 98 * 0.0015, abs=1e-9) and lo == pytest.approx(-105.0, abs=0.0005)
    la5, lo5, q5 = geocoder.geocode('2150 W 5TH AVE', 'DENVER', '80204')
    assert abs(lo5 - lo) > 0.005                                                        # not on W 5th Ave

def test_trailing_junk_trimmed(geocoder):
    la, lo, q = geocoder.geocode('450 KALAMATH XYZ', 'DENVER', '80204')
    assert q == 'range_interp_dirzip_trim' and la == pytest.approx(KAL_LAT, abs=1e-9) and level(q) == 'address_approx'

# ---- ZIP search order
def test_blank_zip_uses_the_towns_neighbour_zips(geocoder):
    """S Bannock St is only in 80110 (Englewood): a Denver listing without a ZIP reaches it through the neighbours of Denver's ZIPs."""
    la, lo, q = geocoder.geocode('3550 S BANNOCK', 'DENVER', '')
    assert q == 'range_interp_nearzips' and la == pytest.approx(39.65 - 50 / 98 * 0.0015, abs=1e-9)
    assert geocoder.geocode('3550 S BANNOCK', 'DENVER', '80223')[2] == 'range_interp_nearzips'
    assert geocoder.geocode('3550 S BANNOCK ST', 'ENGLEWOOD', '80110')[2] == 'range_interp'

def test_search_order_zip_then_city_then_neighbours(geocoder):
    assert geocoder.geocode('450 S KALAMATH', 'DENVER', '80223')[2] == 'range_interp'
    assert geocoder.geocode('450 S KALAMATH', 'DENVER', '80204')[2] == 'range_interp_cityzips'
    assert geocoder.geocode('450 S KALAMATH', 'ENGLEWOOD', '80110')[2] == 'range_interp_nearzips'

def test_fallbacks(geocoder):
    assert geocoder.geocode('123 NOSUCH ST', 'DENVER', '80204') == (39.735, -105.02, 'zip_centroid')
    assert geocoder.geocode('450 KALAMATH', 'LONGMONT', '80501') == (40.17, -105.1, 'zip_centroid')      # 25 km away: not Denver's street
    assert geocoder.geocode('450 KALAMATH', 'NOWHERE', '') == (None, None, 'none')
    la, lo, q = geocoder.geocode('KALAMATH ST', 'DENVER', '')                                           # no number: town centroid
    assert q == 'city_centroid' and la == pytest.approx(np.median([v[0] for z, v in __import__('synthetic_tiger').ZIPS.items() if z not in ('80110', '80501')]))

def test_results_are_deterministic(geocoder):
    from cases import CASES
    a = [geocoder.geocode(*c) for c in CASES]; b = [geocoder.geocode(*c) for c in CASES]
    assert a == b
