"""validate_addresspoints.classify (the 'undecidable' rule) and validate_geocoding.hav on synthetic candidates."""
import numpy as np, pytest
import validate_addresspoints as va, validate_geocoding as vg

TOWN = (39.72, -105.0)
def c(lat, lon, predir=''): return (lat, lon, 'DENVER', predir)
def m2lat(m): return m / 111320.0

def test_found_single_candidate():
    r = va.classify([c(39.72, -105.0)], '', TOWN, 39.72 + m2lat(50), -105.0)
    assert r['status'] == 'found' and not r['ambiguous'] and r['n_candidates'] == 1 and r['n_plain'] == 1
    assert r['dmin'] == pytest.approx(50, rel=0.01) and r['dmax'] == r['dmin']

def test_not_found_without_candidates_or_town():
    assert va.classify([], '', TOWN, 39.72, -105.0)['status'] == 'not_found'
    assert va.classify([c(39.72, -105.0)], '', None, 39.72, -105.0)['status'] == 'not_found'       # no town point: nothing can be kept

def test_candidates_beyond_20km_of_town_dropped():
    assert va.classify([c(39.95, -105.0)], '', TOWN, 39.72, -105.0)['status'] == 'not_found'
    assert va.classify([c(39.85, -105.0)], '', TOWN, 39.72, -105.0)['status'] == 'found'

def test_undecidable_when_candidates_disagree_by_more_than_300m():
    """A direction-less address with the number on both the plain (north) and the S (south) street, 1 km apart: undecidable."""
    cands = [c(39.7208, -105.0), c(39.7112, -105.0, 'S')]
    r = va.classify(cands, '', TOWN, 39.7208, -105.0)
    assert r['status'] == 'undecidable' and r['ambiguous'] and r['n_candidates'] == 2 and r['n_plain'] == 1
    assert r['dmin'] == pytest.approx(0, abs=1) and r['dmax'] == pytest.approx(1067, rel=0.02)

def test_plain_points_are_not_preferred_for_a_directionless_address():
    """Before the review the plain candidates were kept alone whenever any existed, which agreed with the geocoder by construction."""
    cands = [c(39.7208, -105.0), c(39.7112, -105.0, 'S')]
    assert va.classify(cands, '', TOWN, 39.7208, -105.0)['n_candidates'] == 2

def test_two_close_candidates_are_found_not_undecidable():
    cands = [c(39.7208, -105.0), c(39.7208 + m2lat(200), -105.0, 'S')]
    r = va.classify(cands, '', TOWN, 39.7208, -105.0)
    assert r['status'] == 'found' and not r['ambiguous'] and r['dmax'] == pytest.approx(200, rel=0.01)

def test_printed_direction_filters_candidates():
    cands = [c(39.7208, -105.0), c(39.7112, -105.0, 'S'), c(39.80, -105.0, 'N')]
    r = va.classify(cands, 'S', TOWN, 39.7112, -105.0)
    assert r['status'] == 'found' and r['n_candidates'] == 1 and r['n_plain'] == 0 and r['dmin'] == pytest.approx(0, abs=1)
    r = va.classify(cands, 'N', TOWN, 39.7112, -105.0)
    assert r['n_candidates'] == 1 and r['dmin'] == pytest.approx(9876, rel=0.02)
    assert va.classify(cands, 'E', TOWN, 39.7112, -105.0)['status'] == 'not_found'
    assert va.classify(cands, 'SOUTH', TOWN, 39.7112, -105.0)['n_candidates'] == 1          # first letter only, as the service's PreDir

def test_hav_matches_equirectangular_at_short_range():
    assert vg.hav(39.72, -105.0, 39.72 + m2lat(100), -105.0) == pytest.approx(100, rel=0.002)
    assert vg.hav(39.72, -105.0, 39.72, -105.0) == 0
    assert vg.hav(39.72, -105.0, 39.7112, -105.0) == pytest.approx(va.dist(39.72, -105.0, 39.7112, -105.0), rel=0.002)
