"""Interpolation along a segment, the 12 m side offset, side/parity choice, the far() sanity check and the Denver-grid baselines."""
import numpy as np, pytest
import tiger_geocode
from tiger_geocode import interp
ELLS, BWAY = getattr(tiger_geocode, "ELLS", 39.7163), getattr(tiger_geocode, "BWAY", -104.9875)
OFFSET_M = getattr(tiger_geocode, 'OFFSET_M', 12.0); grid_info = getattr(tiger_geocode, 'grid_info', None)   # absent in the pre-review geocoder
from geotest import make_geocoder
import synthetic_tiger as st

def deg_lon(m, lat): return m / (111320.0 * np.cos(np.radians(lat)))
def deg_lat(m): return m / 111320.0
def dist_m(a, b): return 6371000 * np.hypot(np.radians(a[1] - b[1]), np.radians(a[0] - b[0]) * np.cos(np.radians(a[1])))

def test_interp_centreline_fraction():
    seg = np.array([[-105.0, 39.72], [-105.0, 39.7215]])
    assert np.allclose(interp(seg, 0.0), seg[0]) and np.allclose(interp(seg, 1.0), seg[1])
    assert np.allclose(interp(seg, 0.5), [-105.0, 39.72075])

def test_interp_left_right_offset_northbound():
    """Travelling north, left is west: the L point is 12 m west of the centre-line, the R point 12 m east."""
    seg = np.array([[-105.0, 39.72], [-105.0, 39.7215]])
    c = interp(seg, 0.5); L = interp(seg, 0.5, 'L'); R = interp(seg, 0.5, 'R')
    assert L[1] == pytest.approx(c[1]) and R[1] == pytest.approx(c[1])
    assert L[0] == pytest.approx(-105.0 - deg_lon(OFFSET_M, 39.72), abs=1e-9)
    assert R[0] == pytest.approx(-105.0 + deg_lon(OFFSET_M, 39.72), abs=1e-9)
    assert dist_m(L, c) == pytest.approx(OFFSET_M, abs=0.05) and dist_m(L, R) == pytest.approx(2 * OFFSET_M, abs=0.1)   # 111320 m/deg vs the 6371 km sphere

def test_interp_left_right_offset_westbound():
    """Travelling west, left is south."""
    seg = np.array([[-104.99, 39.725], [-104.995, 39.725]])
    L = interp(seg, 0.25, 'L'); R = interp(seg, 0.25, 'R')
    assert L[1] == pytest.approx(39.725 - deg_lat(OFFSET_M), abs=1e-9) and R[1] == pytest.approx(39.725 + deg_lat(OFFSET_M), abs=1e-9)
    assert L[0] == pytest.approx(-104.99125) and R[0] == pytest.approx(-104.99125)

def test_interp_multi_vertex_uses_cos_scaled_lengths():
    """Fraction t is measured along the metre-scaled length (lon steps times cos lat), across vertices."""
    seg = np.array([[-104.9900, 39.7250], [-104.9925, 39.7250], [-104.9950, 39.7252]])
    c = np.cos(np.radians(39.725))
    d1 = 0.0025 * c; d2 = np.hypot(0.0025 * c, 0.0002)
    x = 0.75 * (d1 + d2); f = (x - d1) / d2
    exp = seg[1] + f * (seg[2] - seg[1])
    assert np.allclose(interp(seg, 0.75), exp)
    # the offset on the second piece is perpendicular to that piece
    p = interp(seg, 0.75, 'L'); ex, ey = -0.0025 * c, 0.0002
    assert np.dot([(p[0] - exp[0]) * c, p[1] - exp[1]], [ex, ey]) == pytest.approx(0, abs=1e-12)
    assert dist_m(p, exp) == pytest.approx(OFFSET_M, abs=0.05)

def test_interp_degenerate_segment():
    seg = np.array([[-105.0, 39.72], [-105.0, 39.72]])
    assert np.allclose(interp(seg, 0.3, 'L'), seg[0])

def test_place_side_parity_and_hand_computed_point(geocoder):
    """450 on Kalamath St (L 400-498 even, R 401-499 odd): both sides hold 450; the even side (L) wins and the point is 12 m west of the
    centre-line at t = 50/98; 451 goes to the R side, 12 m east, at t = 50/98 as well."""
    la, lo, q = geocoder.geocode('450 KALAMATH', 'DENVER', '80204')
    t = 50 / 98; assert q == 'range_interp_dirzip'
    assert la == pytest.approx(39.72 + t * 0.0015, abs=1e-9) and lo == pytest.approx(-105.0 - deg_lon(OFFSET_M, 39.72), abs=1e-9)
    la2, lo2, q2 = geocoder.geocode('451 KALAMATH', 'DENVER', '80204')
    assert la2 == pytest.approx(39.72 + 50 / 98 * 0.0015, abs=1e-9) and lo2 == pytest.approx(-105.0 + deg_lon(OFFSET_M, 39.72), abs=1e-9)
    assert dist_m((lo, la), (lo2, la2)) == pytest.approx(2 * OFFSET_M, abs=0.05)

def test_place_one_sided_range(geocoder):
    """600-698 exists only on the left side: 650 (even, parity ok) and 651 (odd, parity penalty but no alternative) both land on it."""
    la, lo, q = geocoder.geocode('650 KALAMATH', 'DENVER', '80204'); assert q == 'range_interp'
    assert lo == pytest.approx(-105.0 - deg_lon(OFFSET_M, 39.723), abs=1e-9) and la == pytest.approx(39.723 + 50 / 98 * 0.0015, abs=1e-9)
    la2, lo2, q2 = geocoder.geocode('651 KALAMATH', 'DENVER', '80204'); assert q2 == 'range_interp'
    assert lo2 == pytest.approx(lo) and la2 == pytest.approx(39.723 + 51 / 98 * 0.0015, abs=1e-9)

def test_place_southbound_segment_sides(geocoder):
    """S Kalamath St runs south: L (401-499, odd) is east of the line, R (400-498, even) west."""
    la, lo, q = geocoder.geocode('450 S KALAMATH', 'DENVER', '80223'); assert q == 'range_interp'
    assert lo == pytest.approx(-105.0 - deg_lon(OFFSET_M, 39.712), abs=1e-9) and la == pytest.approx(39.712 - 50 / 98 * 0.0015, abs=1e-9)
    la2, lo2, _ = geocoder.geocode('451 S KALAMATH', 'DENVER', '80223')
    assert lo2 == pytest.approx(-105.0 + deg_lon(OFFSET_M, 39.712), abs=1e-9)

def test_avenue_sides(geocoder):
    """W 5th Ave is drawn westward: 2150 (L, even) is 12 m south of the line, 2151 (R) 12 m north."""
    la, lo, q = geocoder.geocode('2150 W 5TH AVE', 'DENVER', '80204'); assert q == 'range_interp'
    la2, lo2, _ = geocoder.geocode('2151 W 5TH AVE', 'DENVER', '80204')
    assert la < 39.725 < la2 and dist_m((lo, la), (lo2, la2)) == pytest.approx(2 * OFFSET_M, abs=0.1)

def test_street_nearest_and_300_limit(geocoder):
    la, lo, q = geocoder.geocode('620 S KALAMATH', 'DENVER', '80223')
    assert q == 'street_nearest' and la == pytest.approx(39.709, abs=1e-9)           # end of the 501-599 segment, 21 numbers away
    assert geocoder.geocode('950 S KALAMATH', 'DENVER', '80223')[2] == 'zip_centroid'  # 351 numbers away: not placed

def test_far_rejects_matches_beyond_max_km(synth_root):
    """The reference point is the stated town's ZIP centroids. Kalamath St (39.72) is 7.8 km from Englewood's ZIP centroid (39.65):
    accepted with the default 15 km, rejected (city centroid) with max_km=5."""
    g15 = make_geocoder(synth_root); g5 = make_geocoder(synth_root, max_km=5)
    assert g15.geocode('450 KALAMATH', 'ENGLEWOOD', '')[2] == 'range_interp_dirambig_nearzips'
    la, lo, q = g5.geocode('450 KALAMATH', 'ENGLEWOOD', '')
    assert q == 'city_centroid' and (la, lo) == (39.65, -104.99)
    # with no reference (unknown town, no ZIP) nothing is far, and nothing is found either
    assert g5.geocode('450 KALAMATH', 'NOWHERE', '')[2] == 'none'

def test_far_check_also_accepts_points_near_the_printed_zip(synth_root):
    """A big town's outer ZIPs lie more than max_km from the median of its ZIP centroids (Denver's 80249 is 25 km out), so a number
    found in the printed ZIP's own address ranges was rejected as 'far' and fell back to the ZIP centroid. A point within max_km of
    the printed ZIP's centroid is not far. Here max_km=2: the 4000 block of Kalamath St (39.771) is 4.5 km from the Denver median
    (39.73, -105.01) but 1.7 km from 80211's centroid (39.77, -105.02)."""
    g2 = make_geocoder(synth_root, max_km=2)
    la, lo, q = g2.geocode('4050 KALAMATH', 'DENVER', '80211')
    assert q == 'range_interp' and la == pytest.approx(39.7708, abs=1e-3)
    # without the ZIP the town median is the only reference and the match is still far
    assert g2.geocode('4050 KALAMATH', 'DENVER', '')[2] == 'city_centroid'
    # a printed ZIP does not rescue a match that is far from both the town and that ZIP: 450 S Kalamath (39.712) is 6 km from 80211
    assert g2.geocode('450 S KALAMATH', 'DENVER', '80211')[2] == 'zip_centroid'

def test_grid_info_baselines(geocoder):
    """Denver-grid ZIPs: >= 5 prefixed segments agreeing with the Ellsworth/Broadway baselines; halves need >= 50 segments, 80% on one side."""
    assert geocoder.gridzips == {'80204', '80211', '80223', '80219', '80205', '80210'}
    assert geocoder.half == {('80204', 'NS'): 'N', ('80204', 'EW'): 'W', ('80211', 'NS'): 'N', ('80211', 'EW'): 'W',
                             ('80223', 'NS'): 'S', ('80223', 'EW'): 'W', ('80219', 'NS'): 'S', ('80219', 'EW'): 'W',
                             ('80205', 'NS'): 'N', ('80205', 'EW'): 'E', ('80210', 'NS'): 'S', ('80210', 'EW'): 'E'}
    assert '80203' not in geocoder.gridzips and '80110' not in geocoder.gridzips      # too few prefixed segments to test

def test_grid_info_rejects_inconsistent_zip():
    """A ZIP whose 'S' streets lie north of Ellsworth is not on the grid."""
    import pandas as pd
    rows = []
    for i in range(10):
        rows.append(dict(pre='S', coords=np.array([[-105.0, 39.73 + 0.001 * i], [-105.0, 39.7305 + 0.001 * i]]), ZIPL='80999', ZIPR='80999'))
    gz, half = grid_info(pd.DataFrame(rows))
    assert gz == set() and half == {}
    rows = [dict(pre='S', coords=np.array([[-105.0, 39.70 - 0.001 * i], [-105.0, 39.7005 - 0.001 * i]]), ZIPL='80998', ZIPR=None) for i in range(10)]
    gz, half = grid_info(pd.DataFrame(rows))
    assert gz == {'80998'} and half == {}                                                   # on the grid, but < 50 segments: no half
