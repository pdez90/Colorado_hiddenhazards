"""Stage B (geocoding -> sites -> inventory matching): invariants on the committed outputs, and on work/ when it is present.

Scripts covered: pipeline/tiger_geocode.py, run_geocode.py, export_geocoder_keys.py, frs_addr_geo.py, build_reg.py, build_sites.py,
finalize.py, export.py (sites side), validate_geocoding.py, validate_addresspoints.py, R/fix_direction_geocodes.R, app_inputs.py,
R/known_hidden_sensitivity.R.

Run:  STAGE_ROOT=/path/to/repo pytest test_stage_B_geocode_sites.py     (lives in tests/stages/; < 60 s)
Tests in the first half read committed files only. Tests marked `needs_work` skip when work/ (inventories, pickles, TIGER) is absent.
Nothing here re-asserts what tests/outputs/test_consistency.py (file-to-file agreement) or claims.yml (numbers quoted in the text)
already cover; these tests recompute a stage's output from the stage before it, or check a rule the stage is meant to enforce.
xfail(strict=True) tests document findings of the 12 Nov 2026 stage review (REPORT.md); remove the marker when the data are fixed.
"""
import glob
import json
import os
import pathlib
import re

import numpy as np
import pandas as pd
import pytest

ROOT = pathlib.Path(os.environ.get('STAGE_ROOT') or pathlib.Path(__file__).resolve().parents[2])
RES = ROOT / 'data' / 'results'
APP = ROOT / 'app' / 'data'
WORK = ROOT / 'work'

STREET = ['address', 'address_approx']
TIERS = ['cleanup', 'tri', 'rcra_handler', 'solid_waste', 'other_epa']                 # radar precedence, best first
RADIUS = dict(cleanup=75, tri=100, rcra_handler=40, solid_waste=75, other_epa=40)     # README "Inventory matching"; build_sites.RULES
LABEL = dict(cleanup='Cleanup / contamination list', tri='TRI reporter', rcra_handler='RCRA hazardous-waste handler',
             solid_waste='Solid waste facility', other_epa='Other EPA permit only')
HIDDEN = 'Not on any list'
SITE_M = 30.0
ELLS, BWAY = 39.7163, -104.9875        # Denver grid baselines: Ellsworth Ave (latitude), Broadway (longitude)
CO_BOX = dict(lat=(36.99, 41.01), lon=(-109.07, -102.03))


def hav(a, b, c, d):
    a, b, c, d = map(np.radians, (a, b, c, d))
    return 2 * 6371000 * np.arcsin(np.sqrt(np.sin((c - a) / 2) ** 2 + np.cos(a) * np.cos(c) * np.sin((d - b) / 2) ** 2))


def xyz(lat, lon):
    la, lo = np.radians(np.asarray(lat, float)), np.radians(np.asarray(lon, float))
    return 6371000.0 * np.c_[np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)]


def need(*paths):
    for p in paths:
        if not pathlib.Path(p).exists():
            pytest.skip(f'{pathlib.Path(p).relative_to(ROOT)} not present')


# ------------------------------------------------------------------------------------------------ committed inputs
@pytest.fixture(scope='module')
def listings():
    return pd.read_csv(RES / 'CO_directory_listings_1961-2002.csv', dtype={'zip': str, 'sic': str, 'est': str, 'size': str}, low_memory=False)


@pytest.fixture(scope='module')
def sites():
    return pd.read_csv(APP / 'sites.csv', dtype={'zip': str, 'GEOID': str, 'site_id': str})


@pytest.fixture(scope='module')
def geojson():
    g = json.load(open(RES / 'CO_historical_industrial_sites.geojson'))
    return pd.DataFrame([dict(f['properties'], lon=f['geometry']['coordinates'][0], lat=f['geometry']['coordinates'][1]) for f in g['features']])


@pytest.fixture(scope='module')
def keys():
    k = pd.read_csv(ROOT / 'data' / 'geocoder' / 'geocode_keys_with_python_results.csv', dtype=str, keep_default_na=False)
    for c in ('lat_py', 'lon_py'):
        k[c] = pd.to_numeric(k[c], errors='coerce')
    return k


@pytest.fixture(scope='module')
def evidence(sites):
    e = pd.read_csv(RES / 'known_hidden' / 'site_match_evidence.csv', dtype={'site_id': str})
    for t in TIERS:
        e[f'{t}_basis'] = e[f'{t}_basis'].fillna('')
    E = sites.merge(e, on='site_id', how='left', validate='one_to_one')
    assert E.spread_m.notna().all(), 'a site in app/data/sites.csv has no row in site_match_evidence.csv'
    return E


@pytest.fixture(scope='module')
def located_points(listings):
    """One row per distinct (point, printed street) among street-level listings, with its site."""
    loc = listings[listings.geo_level.isin(STREET)]
    return loc.drop_duplicates(['lat', 'lon', 'street'])[['lat', 'lon', 'street', 'site_id']].reset_index(drop=True)


@pytest.fixture(scope='module')
def pairs30(located_points):
    from scipy.spatial import cKDTree
    return cKDTree(xyz(located_points.lat, located_points.lon)).query_pairs(SITE_M, output_type='ndarray')


# =============================================================================== geocoder output (run_geocode, export_geocoder_keys)
def test_geocoder_key_file_is_keyed_and_complete(keys):
    """Catches duplicate address keys (a merge on geo_key would duplicate listings) and results without coordinates."""
    assert keys.geo_key.is_unique
    assert (keys.geo_key == keys.street + '|' + keys.city + '|' + keys.zip).all()
    assert (keys.lat_py.isna() == (keys.quality_py == 'none')).all() and (keys.lon_py.isna() == keys.lat_py.isna()).all()


def test_geocoder_quality_vocabulary(keys):
    """Catches a new quality suffix that build_sites.geo_level() would silently class as exact ('address')."""
    known = {'range_interp', 'street_nearest', 'zip_centroid', 'city_centroid', 'none'}
    suffix = {'fuzzy', 'sufloose', 'dirambig', 'dirzip', 'dirtype', 'dirsplit', 'cityzips', 'nearzips', 'trim', 'dirloose'}
    for q in keys.quality_py.unique():
        rest = q
        for b in known:
            rest = rest.replace(b, '')
        assert set(t for t in rest.split('_') if t) <= suffix, q
        assert sum(b in q for b in known) == 1, q


def test_geocoder_points_inside_colorado(keys):
    """Catches swapped or sign-flipped coordinates and matches outside the state."""
    k = keys[keys.lat_py.notna()]
    assert k.lat_py.between(*CO_BOX['lat']).all() and k.lon_py.between(*CO_BOX['lon']).all()


def test_listing_level_decides_coordinates_and_site(listings):
    """Catches a site id on a listing that is not street-located, or a street-located listing left out of the sites."""
    L = listings
    assert set(L.geo_level) <= {'address', 'address_approx', 'zip_centroid', 'city_centroid', 'none'}
    st = L.geo_level.isin(STREET)
    assert (L.site_id.notna() == st).all()
    assert L.lat[L.geo_level == 'none'].isna().all() and L.lat[L.geo_level != 'none'].notna().all()
    assert L.lat[st].between(*CO_BOX['lat']).all() and L.lon[st].between(*CO_BOX['lon']).all()


def test_street_level_listing_points_are_geocoder_results(listings, keys):
    """Referential integrity to the geocoding stage: a street-level listing's point must be a street-level, non-ambiguous geocoder
    result; catches listings built from a stale tiger_results.csv or a 'dirambig' point counted as placed."""
    q = keys.quality_py
    ok = keys[q.str.contains('range_interp|street_nearest') & ~q.str.contains('dirambig')]
    have = set(zip(ok.lat_py.round(6), ok.lon_py.round(6)))
    loc = listings[listings.geo_level.isin(STREET)]
    miss = [(a, b) not in have for a, b in zip(loc.lat.round(6), loc.lon.round(6))]
    assert sum(miss) == 0, f'{sum(miss)} street-level listings have a point that is not a street-level geocoder result'


def test_fallback_listing_points_are_centroid_or_ambiguous_results(listings, keys):
    """Catches a street-level geocode demoted to 'zip_centroid' for any reason other than the direction-ambiguity rule."""
    q = keys.quality_py
    ok = keys[q.isin(['zip_centroid', 'city_centroid']) | q.str.contains('dirambig')]
    have = set(zip(ok.lat_py.round(6), ok.lon_py.round(6)))
    o = listings[listings.geo_level.isin(['zip_centroid', 'city_centroid'])]
    assert all((a, b) in have for a, b in zip(o.lat.round(6), o.lon.round(6)))


def test_coverage_by_year_recomputes_from_listings(listings):
    """Catches a geocoding_coverage_by_year.csv left over from an earlier run (README quotes its 22-65% range)."""
    cov = pd.read_csv(RES / 'geocoding_coverage_by_year.csv').set_index('year')
    mine = listings.groupby('year').geo_level.value_counts(normalize=True).unstack(fill_value=0)
    assert list(cov.index) == list(mine.index)
    assert (cov.listings == listings.groupby('year').size()).all()
    for c in mine.columns:
        assert np.allclose(cov[c], mine[c], atol=0.00051), c
    assert np.allclose(cov.drop(columns='listings').sum(axis=1), 1, atol=0.003)


def test_no_denver_listing_on_the_wrong_side_of_the_grid(listings):
    """The Ellsworth/Broadway rule (README step 5; R/fix_direction_geocodes.R): a Denver address printed with S/N/E/W must not be
    placed more than ~500 m on the other side of the baseline. Catches the '4000 S KALAMATH on north Kalamath St' error."""
    L = listings[listings.geo_level.isin(STREET) & (listings.city.fillna('').str.upper().str.strip() == 'DENVER')]
    d = L.street.fillna('').str.upper().str.strip().str.extract(r'^[0-9]+[A-Z]?\s+(SOUTH|NORTH|EAST|WEST|SO|NO|S|N|E|W)\.?\s')[0].str[:1].fillna('')
    tol = 0.005
    bad = ((d == 'S') & (L.lat > ELLS + tol)) | ((d == 'N') & (L.lat < ELLS - tol)) | ((d == 'W') & (L.lon > BWAY + tol)) | ((d == 'E') & (L.lon < BWAY - tol))
    assert (d != '').sum() > 1000, 'the direction parser found too few prefixed Denver addresses to make this a test'
    assert int(bad.sum()) == 0


def test_street_level_points_near_their_stated_town(listings):
    """Catches a geocoder that drops its 15 km town check: at most 1% of street-level listings may lie more than 15 km from the
    GNIS point of the stated town (today 0.3%, big towns' outskirts) and at most 0.1% more than 60 km (today 8 listings: one Colorado
    Springs listing with a Denver ZIP, and Stratton, whose GNIS row in the repo is a namesake in Teller County)."""
    need(ROOT / 'data' / 'historical' / 'gnis_places_co.csv')
    G = pd.read_csv(ROOT / 'data' / 'historical' / 'gnis_places_co.csv')
    G = G[G.feature_class == 'Populated Place'].copy()
    G['name'] = G.name.str.upper()
    G = G[~G.name.duplicated(keep=False)]                       # a town name used twice in the state cannot say which is meant
    L = listings[listings.geo_level.isin(STREET)].assign(c=lambda x: x.city.fillna('').str.upper().str.strip())
    m = L.merge(G[['name', 'lat', 'lon']], left_on='c', right_on='name', suffixes=('', '_g'))
    assert len(m) > 0.8 * len(L)
    km = hav(m.lat, m.lon, m.lat_g, m.lon_g) / 1000
    assert (km > 15).mean() < 0.01 and (km > 60).mean() < 0.001


def test_fe_listings_are_either_sited_or_in_the_not_located_file(listings):
    """Row conservation at the export: every F&E listing is in a site or in CO_hazardous_listings_not_street_located.csv."""
    U = pd.read_csv(RES / 'CO_hazardous_listings_not_street_located.csv', dtype=str)
    fe = listings[listings.fe_hazard.astype(str).str.lower() == 'true']
    assert len(U) == int(fe.site_id.isna().sum())
    assert len(U) + int(fe.site_id.notna().sum()) == len(fe)
    assert 'site_id' not in U or U.site_id.isna().all()


# ================================================================================================== site clustering (build_sites)
def test_points_within_30m_share_a_site_unless_across_the_street(located_points, pairs30):
    """The 30 m rule recomputed from listing coordinates: two street-level points within 30 m are one site, except a pair with house
    numbers of opposite parity (the across-the-street rule). Catches a changed radius, a stale site_id column, or a broken merge."""
    P = located_points
    sid = P.site_id.values
    num = pd.to_numeric(P.street.fillna('').str.upper().str.translate(str.maketrans('OQDCILSBZG', '0000115826')).str.extract(r'^\s*(\d+)')[0], errors='coerce').values
    diff = sid[pairs30[:, 0]] != sid[pairs30[:, 1]]
    a, b = num[pairs30[diff, 0]], num[pairs30[diff, 1]]
    assert len(pairs30) > 5000
    assert int(np.sum(~((a - b) % 2 == 1))) == 0, 'points within 30 m in different sites whose house numbers are not of opposite parity'


def test_every_site_is_connected_at_30m(located_points, pairs30):
    """A site is a connected component: linking only same-site pairs within 30 m must give exactly one component per site. Catches
    sites merged by something other than proximity (e.g. by address string) and site ids reused across a rebuild."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    P = located_points
    sid = P.site_id.values
    same = pairs30[sid[pairs30[:, 0]] == sid[pairs30[:, 1]]]
    n = len(P)
    nc, lab = connected_components(coo_matrix((np.ones(len(same)), (same[:, 0], same[:, 1])), shape=(n, n)), directed=False)
    assert nc == P.site_id.nunique()
    assert int((pd.Series(lab).groupby(sid).nunique() > 1).sum()) == 0


def test_site_count_bracketed_by_clustering_without_the_parity_rule(located_points, pairs30, geojson):
    """Second route to the site count: plain 30 m components are a lower bound (the parity rule only splits), distinct points an upper."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    P = located_points.drop_duplicates(['lat', 'lon']).reset_index(drop=True)
    from scipy.spatial import cKDTree
    pr = cKDTree(xyz(P.lat, P.lon)).query_pairs(SITE_M, output_type='ndarray')
    nc, _ = connected_components(coo_matrix((np.ones(len(pr)), (pr[:, 0], pr[:, 1])), shape=(len(P), len(P))), directed=False)
    assert nc <= len(geojson) <= len(P)
    assert len(geojson) <= 1.08 * nc, 'the parity rule splits far more sites than it did (4% in Nov 2026)'


def test_site_point_is_the_mean_of_its_listing_points(listings, geojson):
    """Catches site coordinates that no longer follow from the listings (e.g. after R/fix_direction_geocodes.R removed a listing)."""
    loc = listings[listings.site_id.notna()]
    m = loc.groupby('site_id').agg(lat=('lat', 'mean'), lon=('lon', 'mean'))
    g = geojson.set_index('site_id')
    assert set(g.index) == set(m.index)
    d = hav(g.lat, g.lon, m.lat.reindex(g.index), m.lon.reindex(g.index))
    assert d.max() < 0.5, f'largest gap {d.max():.1f} m'


def test_site_extent_is_bounded(listings, evidence):
    """A chain of 30 m links should stay a lot, not a street: no member point further than 150 m from the site point (today 81 m), and
    the published spread_m equals the recomputed one for hazardous sites."""
    loc = listings[listings.site_id.notna()]
    c = loc.groupby('site_id')[['lat', 'lon']].transform('mean')
    dm = 6371000 * np.hypot(np.radians(loc.lat - c.lat), np.radians(loc.lon - c.lon) * np.cos(np.radians(c.lat)))
    sp = dm.groupby(loc.site_id).max()
    assert sp.max() < 150
    e = evidence.set_index('site_id').spread_m
    assert np.allclose(e, sp.reindex(e.index), atol=0.01)


def test_site_hazard_flags_follow_from_listings(listings, sites):
    """Catches a site flagged F&E-hazardous without an F&E listing at it (or the reverse), i.e. a wrong headline site count."""
    L = listings[listings.site_id.notna()]
    tf = lambda s: s.astype(str).str.lower() == 'true'
    fe = tf(L.fe_hazard).groupby(L.site_id).any()
    ext = tf(L.ext_hazard).groupby(L.site_id).any()
    s = sites.set_index('site_id')
    assert set(s.index) == set(fe.index[fe | ext])
    assert (s.fe_hazard == fe.reindex(s.index)).all() and (s.ext_hazard == ext.reindex(s.index)).all()


def test_county_agrees_with_tract(sites):
    """County comes from the 2020 tract the point lies in: one county name per county FIPS and Denver = 08031 (the '1,112 Denver
    sites'). Catches a fall back to ZIP-based counties."""
    f = sites.GEOID.str[:5]
    assert sites.GEOID.str.match(r'^08\d{9}$').all()
    assert sites.groupby(f).county.nunique().max() == 1 and sites.groupby('county').GEOID.apply(lambda v: v.str[:5].nunique()).max() == 1
    assert ((sites.county == 'Denver') == (f == '08031')).all()


def test_site_geo_level_and_confidence_rule(listings, sites):
    """geo_level = 'address' when any listing at the site is exact; confidence high = exact AND printed code, low = neither."""
    best = listings[listings.site_id.notna()].groupby('site_id').geo_level.agg(lambda v: 'address' if (v == 'address').any() else 'address_approx')
    s = sites.set_index('site_id')
    assert (s.geo_level == best.reindex(s.index)).all()
    exp = np.select([(s.geo_level == 'address') & (s.industry_evidence == 'printed'), (s.geo_level == 'address') | (s.industry_evidence == 'printed')],
                    ['high', 'medium'], 'low')
    assert (s.confidence.values == exp).all()


# ============================================================================== known / hidden classification (build_sites, app_inputs)
def test_radar_is_the_best_tier_with_evidence(evidence):
    """Catches a status that does not follow from the per-tier evidence: radar = first of cleanup > TRI > RCRA > solid waste > other
    EPA with any basis, else 'Not on any list'."""
    E = evidence
    exp = np.select([E[f'{t}_basis'] != '' for t in TIERS], [LABEL[t] for t in TIERS], HIDDEN)
    assert (E.radar.values == exp).all()
    assert set(np.unique(np.concatenate([E[f'{t}_basis'].unique() for t in TIERS]))) <= {'', 'entity', 'boundary', 'prox'}
    assert (E.loc[E.cleanup_basis != 'boundary', 'cleanup_basis'].isin(['', 'entity', 'prox'])).all()
    for t in TIERS[1:]:
        assert not (E[f'{t}_basis'] == 'boundary').any(), 'only the cleanup tier has boundaries'


def test_match_basis_is_the_strongest_evidence(evidence):
    """match_basis = same entity > inside a cleanup boundary > nearby record only > none, over all tiers."""
    E = evidence
    B = np.array([E[f'{t}_basis'].values for t in TIERS])
    ent, bnd, prx = (B == 'entity').any(0), (B == 'boundary').any(0), (B == 'prox').any(0)
    # a tier's basis column keeps only its strongest evidence, so 'nearby record only' requires that no tier is entity/boundary
    assert ((E.match_basis == 'same entity (name or address)') == ent).all()
    assert ((E.match_basis == 'inside a cleanup boundary') == (~ent & bnd)).all()
    assert ((E.match_basis == 'none') == (E.radar == HIDDEN)).all()
    assert (E.match_basis[~ent & ~bnd & prx] == 'nearby record only').all()


def test_hidden_sites_have_no_record_inside_any_tier_radius(evidence):
    """The headline 'on no inventory' count checked a second way: for a hidden site the nearest record of every tier (within 250 m)
    must lie beyond that tier's radius + the site's spread. Catches radii changed in one place only, or a stale evidence file."""
    H = evidence[evidence.radar == HIDDEN]
    assert len(H) > 0
    for t in TIERS:
        r = np.minimum(250, RADIUS[t] + H.spread_m)
        near = H[f'{t}_nearest_m']
        assert int((near.notna() & (near < r - 0.5)).sum()) == 0, t
        assert H[f'{t}_prox_m'].isna().all(), t


def test_proximity_distances_respect_the_radius(evidence):
    """A recorded proximity hit lies within the tier radius + spread (<= 250 m), and the nearest record is never further than it."""
    E = evidence
    for t in TIERS:
        d = E[f'{t}_prox_m']
        lim = np.minimum(250, RADIUS[t] + E.spread_m) + 0.5
        lim = np.where(t == 'cleanup', np.maximum(lim, 40.5), lim)          # a cleanup boundary within 40 m counts at its distance
        assert int((d.notna() & (d > lim)).sum()) == 0, t
        assert ((E[f'{t}_basis'] == 'prox') <= d.notna()).all(), t
        if t != 'cleanup':
            assert int((d.notna() & (E[f'{t}_nearest_m'] > d)).sum()) == 0, t
        assert (E[f'{t}_nearest_m'].dropna() <= 250).all()


def test_known_match_text_only_for_known_sites(sites):
    """Catches a popup that names an inventory record for a site published as 'Not on any list' (and the reverse)."""
    assert ((sites.known_match.fillna('') != '') == (sites.radar != HIDDEN)).all()


def test_sensitivity_counts_recompute_from_evidence(evidence):
    """Every row of known_hidden/sensitivity_counts.csv (six rules x four site groups) from sites.csv + site_match_evidence.csv."""
    E = evidence
    S = pd.read_csv(RES / 'known_hidden' / 'sensitivity_counts.csv')
    strong = E.match_basis.isin(['same entity (name or address)', 'inside a cleanup boundary']).values
    pw = lambda d: np.any([(E[f'{t}_prox_m'] <= d).values for t in TIERS], axis=0)
    pub = (E.radar != HIDDEN).values
    known = dict(published=pub, strict=strong, prox25=strong | pw(25), prox10=strong | pw(10),
                 cleanup_tri_prox=strong | (E.cleanup_basis == 'prox').values | (E.tri_basis == 'prox').values,
                 wider=pub | np.any([(E[f'{t}_nearest_m'] <= np.minimum(250, 2 * RADIUS[t] + E.spread_m)).values for t in TIERS], axis=0))
    fe = E.fe_hazard.values
    grp = {'F&E hazardous-sector sites (headline)': fe, 'All hazardous-sector sites (F&E + extended)': np.ones(len(E), bool),
           'F&E sites, high confidence': fe & (E.confidence == 'high').values, 'F&E sites in the City and County of Denver': fe & (E.county == 'Denver').values}
    assert set(S.rule) == set(known) and set(S.sites) == set(grp) and len(S) == 24
    for r in S.itertuples():
        g = grp[r.sites]
        assert r.n_sites == g.sum() and r.n_hidden == (g & ~known[r.rule]).sum(), (r.rule, r.sites)
        assert abs(r.pct_hidden - 100 * (g & ~known[r.rule]).sum() / g.sum()) < 0.051
    f = S[S.sites.str.startswith('F&E hazardous')].set_index('rule').n_hidden
    assert f['wider'] <= f['published'] <= f['prox25'] <= f['prox10'] <= f['strict'] and f['published'] <= f['cleanup_tri_prox'] <= f['strict']


def test_hidden_share_is_higher_for_approximate_geocodes_within_a_bound(sites):
    """Monitors FINDING 4: sites placed only approximately are 'hidden' far more often than exactly placed ones (55% vs 32% in Nov
    2026), i.e. part of the hidden count is location error. Fails if the gap grows beyond 30 points or the approximate share of
    hidden sites passes one third."""
    H = sites[sites.fe_hazard]
    hid = H.radar == HIDDEN
    gap = hid[H.geo_level == 'address_approx'].mean() - hid[H.geo_level == 'address'].mean()
    assert gap < 0.30
    assert (H.geo_level[hid] == 'address_approx').mean() < 1 / 3


# ======================================================================================= validation outputs (validate_geocoding etc.)
def test_frs_validation_table_is_coherent_and_matches_the_markdown():
    """Catches an edited or half-written validation table: ordered quantiles, nested shares, and the same numbers in the .md."""
    v = pd.read_csv(RES / 'geocoding_validation_frs.csv')
    assert list(v.geocode_level) == ['address', 'address_approx']
    assert (v.median_m <= v.p75_m).all() and (v.p75_m <= v.p90_m).all()
    assert (v.within_100m <= v.within_250m).all() and (v.within_250m + v.over_1km <= 1.0005).all()
    assert v.median_m.iloc[0] < v.median_m.iloc[1], 'approximate geocodes should not validate better than exact ones'
    md = open(RES / 'geocoding_validation.md').read()
    for r in v.itertuples():
        row = [x.strip() for x in next(line for line in md.splitlines() if line.startswith(f'| {r.geocode_level} ')).strip('|').split('|')]
        assert [float(x) for x in row[1:]] == [r.n, r.median_m, r.p75_m, r.p90_m, r.within_100m, r.within_250m, r.over_1km]
    assert pd.read_csv(APP / 'geocoding_validation_frs.csv').equals(v)


def test_addresspoint_sample_is_drawn_from_the_published_editions():
    """The address-point check must sample the sites it vouches for: every sampled listing year is a complete edition."""
    A = pd.read_csv(RES / 'geocoding_validation_addresspoints.csv')
    ed = set(json.load(open(ROOT / 'config' / 'editions.json'))['complete_editions'])
    assert A.year.isin(ed).all()


@pytest.mark.xfail(strict=True, reason='FINDING 5: site ids in geocoding_validation_addresspoints_recheck.csv are from an earlier build; 66 of 400 no '
                                       'longer exist and none of the other 334 is the same point today')
def test_addresspoint_recheck_site_ids_are_current(geojson):
    """A validation file keyed by site_id must refer to today's sites: same id, same point (within 5 m) for at least 95% of rows."""
    B = pd.read_csv(RES / 'geocoding_validation_addresspoints_recheck.csv')
    m = B.merge(geojson[['site_id', 'lat', 'lon']], on='site_id', how='left', suffixes=('', '_now'))
    same = m.lat_now.notna() & (hav(m.lat, m.lon, m.lat_now.fillna(0), m.lon_now.fillna(0)) < 5)
    assert same.mean() >= 0.95


def test_zip_centroids_agree_with_geocoded_addresses(keys):
    """ZIP centroids (medians of inventory coordinates, pipeline/frs_addr_geo.py) drive the geocoder's 15 km town check and the
    fallback points: where 10+ exact addresses were geocoded in a ZIP, its centroid must lie within 12 km of their median."""
    zc = pd.read_csv(ROOT / 'data' / 'geocoder' / 'zip_centroids.csv', dtype={'zip5': str})
    assert zc.zip5.is_unique and zc.zip5.str.match(r'^8[01]\d{3}$').all()
    k = keys[(keys.quality_py == 'range_interp') & keys.zip.str.match(r'^8[01]\d{3}$')]
    a = k.groupby('zip').agg(mlat=('lat_py', 'median'), mlon=('lon_py', 'median'), n=('lat_py', 'size'))
    m = zc.join(a, on='zip5')
    m = m[m.n >= 10]
    assert len(m) > 100
    assert (hav(m.zlat, m.zlon, m.mlat, m.mlon) / 1000).max() < 12


# ============================================================================================================== work/ (skipped if absent)
needs_work = pytest.mark.skipif(not (WORK / 'inv' / 'reg.pkl').exists(), reason='work/inv not present')


@pytest.fixture(scope='module')
def reg():
    need(WORK / 'inv' / 'reg.pkl')
    return pd.read_pickle(WORK / 'inv' / 'reg.pkl').reset_index(drop=True)


@pytest.fixture(scope='module')
def raw_inventories():
    """(FRS facility rows, TRI rows, CDPHE feature count without composting sites, CDPHE features with a street address and (0,0)
    or out-of-state coordinates)."""
    R = WORK / 'reg'
    need(R / 'CO_FACILITY_FILE.CSV', R / 'tri_facility_CO.csv', R / 'cdphe_hmwmd_layers.json')
    f = pd.read_csv(R / 'CO_FACILITY_FILE.CSV', dtype=str, usecols=['REGISTRY_ID', 'STATE_CODE', 'PGM_SYS_ACRNMS', 'LATITUDE83', 'LONGITUDE83', 'LOCATION_ADDRESS'])
    t = pd.read_csv(R / 'tri_facility_CO.csv', dtype=str)
    J = json.load(open(R / 'cdphe_hmwmd_layers.json'))
    return f, t, {k.split('__')[0]: v for k, v in J.items() if not k.startswith('Composting_Sites')}


def in_box(lat, lon):
    return lat.between(36.5, 41.5) & lon.between(-109.5, -101.5)


@needs_work
def test_reg_row_conservation(reg, raw_inventories):
    """Every raw inventory row is in work/inv/reg.pkl or was dropped for coordinates outside Colorado; nothing is duplicated by the
    concatenation. Catches a changed layer list or a join that multiplies rows."""
    f, t, J = raw_inventories
    n_raw = int((f.STATE_CODE == 'CO').sum()) + len(t) + sum(len(v) for v in J.values())
    assert len(reg) <= n_raw
    dropped = n_raw - len(reg)
    assert dropped < 0.005 * n_raw, f'{dropped} inventory rows dropped'
    fr = reg[reg.source == 'EPA_FRS']
    assert fr.src_id.is_unique and set(fr.src_id) <= set(f.REGISTRY_ID)
    assert reg[reg.source == 'EPA_TRI'].src_id.is_unique
    for svc, feats in J.items():
        assert (reg.source == 'CDPHE_' + svc).sum() <= len(feats), svc
    assert not reg.source.str.contains('Compost').any()


@needs_work
def test_reg_coordinates_and_tiers(reg, raw_inventories):
    """Coordinates are in Colorado or missing (never half-missing), tiers are the five known ones, and the FRS tier follows the
    programme list (cleanup programmes > TRIS > RCRAINFO > other). Catches a programme acronym moved between tiers."""
    f, _, _ = raw_inventories
    assert set(reg.tier) == set(TIERS)
    assert (reg.lat.isna() == reg.lon.isna()).all()
    c = reg.lat.notna()
    assert in_box(reg.lat[c], reg.lon[c]).all()
    clean = {'SEMS', 'ACRES', 'BRAC', 'FFEP', 'FFDOCKET', 'LUST-ARRA'}
    P = f.set_index('REGISTRY_ID').PGM_SYS_ACRNMS.fillna('').map(lambda s: {p.split(':')[0].strip() for p in s.split(',') if p.strip()})
    exp = P.map(lambda p: 'cleanup' if p & clean else 'tri' if 'TRIS' in p else 'rcra_handler' if 'RCRAINFO' in p else 'other_epa')
    fr = reg[reg.source == 'EPA_FRS'].set_index('src_id').tier
    assert (fr == exp.reindex(fr.index)).all()
    assert reg[reg.geom_wkt.notna()].tier.eq('cleanup').all(), 'only cleanup layers carry boundaries'
    assert reg[reg.source == 'EPA_TRI'].tier.eq('tri').all()


@needs_work
@pytest.mark.xfail(strict=True, reason='FINDING 2: build_reg.py drops 275 inventory records whose coordinates are (0,0) or outside Colorado '
                                       '(121 CDPHE voluntary-cleanup sites, 69 CDPHE RCRA handlers, 33 TRI facilities, 47 FRS, 5 solid waste) instead of '
                                       'keeping them without a point for the address match')
def test_no_inventory_record_is_dropped_for_bad_coordinates(reg, raw_inventories):
    """A record with unusable coordinates should stay in the inventory without a point (it can still match by address), as records
    with no coordinates do. Counts raw rows missing from reg.pkl."""
    f, t, J = raw_inventories
    n_raw = int((f.STATE_CODE == 'CO').sum()) + len(t) + sum(len(v) for v in J.values())
    assert n_raw - len(reg) == 0


@needs_work
def test_inventory_records_without_a_point_stay_a_bounded_share(reg):
    """Monitors FINDING 3: records without coordinates can only match by address, never by name or distance. Fails if the share grows
    (18.4% of all records, 16% of cleanup-tier and 12% of TRI-tier records in Nov 2026)."""
    nc = reg.lat.isna()
    assert nc.mean() < 0.20
    assert nc[reg.tier == 'cleanup'].mean() < 0.18 and nc[reg.tier == 'tri'].mean() < 0.14


@needs_work
def test_edition_filter_row_conservation(listings):
    """records_final = records_linked restricted to config/editions.json's complete editions, one row per listing, and the published
    listings file has the same rows. Catches a geocode merge that duplicates or drops listings."""
    need(WORK / 'inv' / 'records_linked.pkl', WORK / 'inv' / 'records_final.pkl')
    ed = json.load(open(ROOT / 'config' / 'editions.json'))
    rl = pd.read_pickle(WORK / 'inv' / 'records_linked.pkl')
    rf = pd.read_pickle(WORK / 'inv' / 'records_final.pkl')
    n = int(rl.year.isin(ed['complete_editions']).sum()) if ed.get('mode') == 'complete' else len(rl)
    assert len(rf) == n == len(listings)
    assert sorted(rf.year.unique()) == sorted(listings.year.unique())
    assert (rf.site_id.fillna('').values == listings.site_id.fillna('').values).all()
    assert (rf.geo_level.values == listings.geo_level.values).all()


@needs_work
def test_geocode_results_cover_every_key_and_levels_recompute():
    """tiger_results.csv has one row per address key of records_linked, and records_final.geo_level follows from the quality code by
    the documented rule (dirambig -> zip level; any loosened match -> approximate)."""
    need(WORK / 'geo' / 'tiger_results.csv', WORK / 'inv' / 'records_linked.pkl', WORK / 'inv' / 'records_final.pkl')
    g = pd.read_csv(WORK / 'geo' / 'tiger_results.csv', dtype={'geo_key': str}, keep_default_na=False)
    rl = pd.read_pickle(WORK / 'inv' / 'records_linked.pkl')
    assert g.geo_key.is_unique and set(rl.geo_key) == set(g.geo_key)
    rf = pd.read_pickle(WORK / 'inv' / 'records_final.pkl')
    q = rf.geo_key.map(dict(zip(g.geo_key, g.geo_quality)))
    assert q.notna().all()

    def level(x):
        if 'dirambig' in x: return 'zip_centroid'
        if 'range_interp' in x and not re.search('fuzzy|nearzips|trim|dirloose|sufloose|dirsplit', x): return 'address'
        if 'range_interp' in x or 'street_nearest' in x: return 'address_approx'
        return x if x in ('zip_centroid', 'city_centroid') else 'none'
    assert (q.map(level).values == rf.geo_level.values).all()
    k = pd.read_csv(ROOT / 'data' / 'geocoder' / 'geocode_keys_with_python_results.csv', dtype=str, keep_default_na=False)
    assert set(k.geo_key) == set(g.geo_key) and (k.set_index('geo_key').quality_py.reindex(g.geo_key).values == g.geo_quality.values).all()


@needs_work
def test_frs_validation_recomputes_from_work():
    """geocoding_validation_frs.csv from records_final + frs_addr.pkl (identical street and ZIP), computed here independently."""
    need(WORK / 'inv' / 'records_final.pkl', WORK / 'inv' / 'frs_addr.pkl')
    rf = pd.read_pickle(WORK / 'inv' / 'records_final.pkl')
    fa = pd.read_pickle(WORK / 'inv' / 'frs_addr.pkl')
    assert not fa.duplicated(['street_n', 'zip5']).any()
    u = rf[rf.geo_level.isin(STREET)].drop_duplicates('geo_key')
    m = u.merge(fa, on=['street_n', 'zip5'], suffixes=('', '_f'))
    m['d'] = hav(m.lat, m.lon, m.lat_f, m.lon_f)
    v = pd.read_csv(RES / 'geocoding_validation_frs.csv').set_index('geocode_level')
    for lvl, g in m.groupby('geo_level'):
        assert v.n[lvl] == len(g) and v.median_m[lvl] == round(g.d.median())
        assert abs(v.within_250m[lvl] - (g.d <= 250).mean()) < 0.00051 and abs(v.over_1km[lvl] - (g.d > 1000).mean()) < 0.00051


@needs_work
def test_zip_centroid_files_agree():
    """data/geocoder/zip_centroids.csv is the table the geocoder used (work/inv/zip_centroids.pkl)."""
    need(WORK / 'inv' / 'zip_centroids.pkl')
    a = pd.read_pickle(WORK / 'inv' / 'zip_centroids.pkl').reset_index(drop=True)
    b = pd.read_csv(ROOT / 'data' / 'geocoder' / 'zip_centroids.csv', dtype={'zip5': str})
    assert list(a.zip5) == list(b.zip5) and np.allclose(a.zlat, b.zlat) and np.allclose(a.zlon, b.zlon)


@needs_work
@pytest.mark.xfail(strict=True, reason='FINDING 6: ZIP "centroids" are medians of inventory coordinates with no minimum count (103 rest on one record); '
                                       'several lie 50-460 km from the ZIP\'s own TIGER streets (81061, 81244, 80842, 80732, 80307, 81124, 80541, 81241)')
def test_zip_centroids_lie_in_their_zip():
    """A ZIP centroid must be within 50 km of the median of that ZIP's TIGER street segments (generous: rural ZIPs are large)."""
    shp = sorted(glob.glob(str(WORK / 'tiger' / '*_addrfeat.shp')))
    if not shp: pytest.skip('work/tiger not present')
    import warnings
    import geopandas as gpd
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        G = pd.concat([gpd.read_file(f, columns=['ZIPL', 'ZIPR']) for f in shp], ignore_index=True)
        c = G.geometry.centroid
    T = pd.concat([pd.DataFrame({'z': G.ZIPL, 'x': c.x, 'y': c.y}), pd.DataFrame({'z': G.ZIPR, 'x': c.x, 'y': c.y})]).dropna()
    tz = T.groupby('z').agg(tx=('x', 'median'), ty=('y', 'median'))
    zc = pd.read_csv(ROOT / 'data' / 'geocoder' / 'zip_centroids.csv', dtype={'zip5': str}).join(tz, on='zip5').dropna(subset=['tx'])
    assert len(zc) > 400
    assert int((hav(zc.zlat, zc.zlon, zc.ty, zc.tx) > 50000).sum()) == 0


@pytest.fixture(scope='module')
def site_table():
    need(WORK / 'inv' / 'sites_export.pkl')
    return pd.read_pickle(WORK / 'inv' / 'sites_export.pkl').reset_index(drop=True)


@needs_work
def test_site_pickle_is_what_was_published(site_table, sites):
    """work/inv/sites_export.pkl and app/data/sites.csv describe the same build (ids, status, point); guards the tests below."""
    s = site_table[site_table.fe_hazard | site_table.ext_hazard].set_index('site_id')
    p = sites.set_index('site_id')
    assert set(s.index) == set(p.index)
    assert (s.radar.reindex(p.index) == p.radar).all() and np.allclose(s.lat.reindex(p.index), p.lat, atol=1e-6)


@needs_work
def test_known_hidden_geometry_recomputes_from_the_inventory(site_table, reg):
    """The proximity half of the classification recomputed from work/inv/reg.pkl with an independent search: no hidden F&E site has an
    inventory point within its tier radius + spread or lies in / within 40 m of a cleanup boundary; every 'nearby record only' site
    has one. Catches a status table that does not belong to this inventory."""
    from scipy.spatial import cKDTree
    from shapely import wkt
    from shapely.geometry import Point
    from shapely.ops import transform
    from pyproj import Transformer
    S = site_table[site_table.fe_hazard].reset_index(drop=True)
    R = reg[reg.lat.notna()].reset_index(drop=True)
    tree = cKDTree(xyz(R.lat, R.lon))
    nb = tree.query_ball_point(xyz(S.lat, S.lon), 251.0)
    tier = R.tier.values
    rad = np.array([RADIUS[t] for t in tier], float)
    to_utm = Transformer.from_crs('EPSG:4326', 'EPSG:26913', always_xy=True).transform
    import warnings
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        polys = [transform(to_utm, wkt.loads(w)) for w in reg.geom_wkt.dropna()]
    assert len(polys) > 300
    from shapely.strtree import STRtree
    pt = STRtree(polys)
    prox = np.zeros(len(S), bool); bnd = np.zeros(len(S), bool)
    for k, s in enumerate(S.itertuples()):
        ii = np.array(nb[k], dtype=int)
        if len(ii):
            d = hav(s.lat, s.lon, R.lat.values[ii], R.lon.values[ii])
            prox[k] = bool((d <= np.minimum(250, rad[ii] + s.spread_m)).any())
        p = Point(*to_utm(s.lon, s.lat))
        bnd[k] = any(polys[j].distance(p) <= 40 for j in pt.query(p.buffer(40)))
    hid = (S.radar == HIDDEN).values
    assert int((hid & (prox | bnd)).sum()) == 0, 'hidden sites with an inventory record inside the radius or a cleanup boundary'
    po = (S.match_basis == 'nearby record only').values
    assert int((po & ~(prox | bnd)).sum()) == 0, "'nearby record only' sites with no record nearby"
    # every site with nothing nearby that is still 'known' must be a same-entity match (name within 250 m, or address)
    assert (S.match_basis[~hid & ~(prox | bnd)] == 'same entity (name or address)').all()


@needs_work
@pytest.mark.xfail(strict=True, reason='FINDING 3: 9 hidden F&E sites have an inventory record of the same firm in the same town or ZIP that has no '
                                       'coordinates (528 FRS cleanup-tier and 197 TRI records have none), so the name match, which only searches within 250 m, cannot see it')
def test_no_hidden_site_has_a_same_name_record_without_coordinates(site_table, reg):
    """A site must not be 'on no inventory' only because the inventory record of the same firm has no point: for every hidden F&E
    site, no record without coordinates in the same town or ZIP carries a hazardous firm's name (the pipeline's two-informative-words
    rule, re-implemented here)."""
    from rapidfuzz import fuzz
    stop = (r"\b(GRAND JUNCTION|FORT COLLINS|COLORADO SPRINGS|THE|INC|CO|CORP|CORPORATION|COMPANY|LLC|LTD|MFG|MANUFACTURING|OF|AND|DIV|DIVISION|INCORPORATED"
            r"|INDUSTRIES|SYSTEMS|PRODUCTS|CASTINGS|PRECISION|ENTERPRISES|SERVICES|SUPPLY"
            r"|COLORADO|DENVER|AURORA|BOULDER|PUEBLO|MONTROSE|ENGLEWOOD|LITTLETON|GOLDEN|LAKEWOOD|ARVADA|WESTMINSTER|LONGMONT|LOVELAND|GREELEY)\b")
    norm = lambda s: re.sub(r'\s+', ' ', re.sub(stop, ' ', re.sub(r'[^A-Z0-9 ]', ' ', str(s).upper()))).strip()

    def same(a, b):
        if not a or not b: return False
        if fuzz.token_sort_ratio(a, b) >= 88: return True
        return fuzz.token_set_ratio(a, b) >= 88 and len(set(a.split()) & set(b.split())) >= 2
    nc = reg[reg.lat.isna()].copy()
    nc['nn'] = nc.name.map(norm)
    nc = nc[nc.nn != '']
    by_zip = nc.groupby(nc.zip.fillna('').astype(str).str[:5]).nn.agg(set).to_dict()
    by_city = nc.groupby(nc.city.fillna('').astype(str).str.upper().str.strip()).nn.agg(set).to_dict()
    H = site_table[site_table.fe_hazard & (site_table.radar == HIDDEN)]
    n = 0
    for s in H.itertuples():
        names = [norm(x) for x in s.names_n] if isinstance(s.names_n, (list, tuple, np.ndarray)) else []
        cand = (by_zip.get(str(s.zip or ''), set()) if s.zip else set()) | by_city.get(str(s.city or '').upper().strip(), set())
        if names and any(same(c, x) for c in cand for x in names):
            n += 1
    assert n == 0, f'{n} hidden sites have a same-name inventory record without coordinates in their town'
