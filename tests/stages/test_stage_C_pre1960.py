"""Stage tests for the pre-1960 layer (pipeline/historical/run_hist.py, geocode_hist.py incl. apply_review, link_hist.py,
app_hist.py, pipeline/app_radium.py, R/fetch_gnis_historical.R). Review 4, 12 Nov 2026, reviewer C_pre1960; brought up to date
on 13 Nov 2026 for the no-town review (notown_review.csv), the homonym overrides (town_homonyms.csv) and the new merge and link
rules of link_hist.py.

Reads committed files only; tests that need work/hist skip when it is absent. Run:
    STAGE_ROOT=/home/claude/audit pytest test_stage_C_pre1960.py
Not duplicated here (already in tests/geocoding/test_hist.py and tests/outputs/claims.yml): unit behaviour of apply_review,
street_ok, hist_street, street_level, main() on small frames; README totals (listings / firm-locations / street level / links /
later sites); town-review verdict counts; radium counts.
"""
import os, re, pathlib
import numpy as np, pandas as pd, pytest

ROOT = pathlib.Path(os.environ.get('STAGE_ROOT') or pathlib.Path(__file__).resolve().parents[2])
HIST = ROOT / 'data' / 'historical'
APP = ROOT / 'app' / 'data'
WORK = ROOT / 'work' / 'hist'
KEY = ['year', 'town', 'nkey', 'sector']
README_PENDING = 'README not yet reconciled (pending the full rerun)'
STOP = r"\b(THE|CO|COMPANY|INC|CORP|CORPORATION|MFG|MANUFACTURING|WORKS|AND|OF|LTD|BROS|SONS?)\b"   # legal-form words (link_hist.py)
FE = {'Chemicals': '28', 'Paint & varnish': '28', 'Soap': '28', 'Explosives': '28', 'Fertilizer & rendering': '28',
      'Petroleum refining & asphalt': '29', 'Rubber': '30', 'Plastics': '30', 'Smelting & refining': '33', 'Foundry': '33',
      'Iron & steel works': '33', 'Metal working': '34', 'Machine shop / machinery': '35', 'Transportation equipment': '37'}
EXT = {'Assay office', 'Ore milling & sampling', 'Manufactured gas', 'Tannery', 'Wood preserving', 'Coke works', 'Batteries',
       'Radium & uranium', 'Asbestos products'}
EDITIONS = [1871, 1875, 1877, 1878, 1879, 1880, 1881, 1882, 1883, 1884, 1885, 1887, 1888, 1891, 1892, 1910, 1911, 1912, 1913, 1914,
            1915, 1916, 1917, 1920, 1927, 1929, 1932, 1933, 1935, 1939, 1941, 1943, 1950, 1956]
BIGCITY = {'PUEBLO', 'COLORADO SPRINGS', 'BOULDER', 'GRAND JUNCTION', 'TRINIDAD', 'GREELEY', 'FORT COLLINS', 'CANON CITY', 'LOVELAND',
           'LONGMONT', 'DURANGO', 'GOLDEN', 'ENGLEWOOD', 'LITTLETON', 'LEADVILLE', 'STERLING', 'LA JUNTA', 'ROCKY FORD'}


def _csv(p, **kw):
    if not p.exists(): pytest.skip(f'{p} not present')
    return pd.read_csv(p, **kw)


@pytest.fixture(scope='module')
def L(): return _csv(HIST / 'CO_pre1960_hazardous_listings.csv', dtype={'street': str})
@pytest.fixture(scope='module')
def S(): return _csv(HIST / 'CO_pre1960_hazardous_sites.csv')
@pytest.fixture(scope='module')
def SR():
    d = _csv(HIST / 'street_review.csv', dtype=str).fillna(''); d['year'] = d.year.astype(int); return d
@pytest.fixture(scope='module')
def TR():
    d = _csv(HIST / 'town_review.csv', dtype=str).fillna(''); d['year'] = d.year.astype(int); return d
@pytest.fixture(scope='module')
def NV():
    """The no-town review; its rows are keyed with town = '' (the file's town column is empty)."""
    d = _csv(HIST / 'notown_review.csv', dtype=str).fillna(''); d['year'] = d.year.astype(int); return d
@pytest.fixture(scope='module')
def HOM():
    d = _csv(HIST / 'town_homonyms.csv', dtype={'town': str, 'county': str, 'note': str}); return d
@pytest.fixture(scope='module')
def TC():
    """Town -> (lat, lon, county), built the way geocode_hist.py documents it (populated place first, then aliases)."""
    g = _csv(HIST / 'gnis_places_co.csv')
    h = HIST / 'gnis_places_co_historical.csv'
    if h.exists(): g = pd.concat([g, pd.read_csv(h).assign(feature_class='Populated Place')], ignore_index=True)
    g['rank'] = g.feature_class.map({'Populated Place': 0, 'Census': 1, 'Civil': 2})
    g = g.sort_values('rank', kind='stable').drop_duplicates('name')
    tc = {r.name: (r.lat, r.lon, r.county_name) for r in g.itertuples()}
    a = HIST / 'town_aliases.csv'
    if a.exists():
        for v, n in pd.read_csv(a, dtype=str).dropna().values:
            if n in tc and v not in tc: tc[v] = tc[n]
    return tc
@pytest.fixture(scope='module')
def E():
    d = _csv(WORK / 'hist_hazard_entries.csv', dtype={'street': str}); d['town'] = d.town.fillna(''); d['nkey'] = d.nkey.fillna(''); return d
@pytest.fixture(scope='module')
def G():
    d = _csv(WORK / 'hist_hazard_geocoded.csv', dtype={'street': str}); d['town'] = d.town.fillna(''); d['nkey'] = d.nkey.fillna(''); return d


def _dist_m(la1, lo1, la2, lo2):
    return 6371000 * np.hypot(np.radians(la2 - la1), np.radians(lo2 - lo1) * np.cos(np.radians(la1)))


def _point(TC, HOM, town, year):
    """(lat, lon, county) of a town in a year: the homonym override whose years contain the year (blank coordinates: nan, the
    listing stays unplaced), otherwise the gazetteer / alias point; None when the town has neither."""
    for t, a, b, la, lo, c in zip(HOM.town.values, HOM.year_from.values, HOM.year_to.values, HOM.lat.values, HOM.lon.values, HOM.county.values):
        if t == town and a <= year <= b: return (float(la), float(lo), c)
    return TC.get(town)


def _placed(TC, HOM, town, year):
    p = _point(TC, HOM, town, year)
    return p is not None and not np.isnan(p[0])


def _final_keys(rv):
    """The key a kept review row gives its listing: town_fix, the key of name_fix, sector_fix (each only when filled)."""
    nk = [re.sub(r'[^A-Z0-9]', '', n.upper()) if n else k for n, k in zip(rv.name_fix, rv.nkey)]
    return list(zip(rv.year, rv.town_fix.where(rv.town_fix != '', rv.town), nk, rv.sector_fix.where(rv.sector_fix != '', rv.sector)))


def _replay(E, rv, town_level):
    """Independent (merge-based) replay of the documented apply_review rules; returns kept rows and a log of dropped rows."""
    rv = rv.copy()
    for c in ('street_fix', 'town_fix', 'name_fix', 'sector_fix'):
        if c not in rv: rv[c] = ''
    m = E.merge(rv[KEY + ['verdict', 'street_fix', 'town_fix', 'name_fix', 'sector_fix']], on=KEY, how='left', validate='1:1', indicator=True)
    hit = (m._merge == 'both').values
    m.loc[hit, 'review'] = m.verdict[hit]
    if town_level:
        m.loc[hit, 'town_only'] = True
        m.loc[hit & (m.town_fix.fillna('') != '') & (m.town_fix != m.town), 'street'] = ''
    nw = hit & (m.verdict == 'not_works').values
    k = m[~nw].copy(); h = (k._merge == 'both').values
    sfx = h & ((k.verdict == 'fix_address') | (k.street_fix.fillna('') != '')).values
    k.loc[sfx, 'street'] = k.street_fix[sfx].replace('none', '')
    nf = h & (k.name_fix.fillna('') != '').values
    k.loc[nf, 'name'] = k.name_fix[nf]; k.loc[nf, 'nkey'] = k.name_fix[nf].map(lambda s: re.sub(r'[^A-Z0-9]', '', s.upper()))
    tf = h & (k.town_fix.fillna('') != '').values
    k.loc[tf, 'town'] = k.town_fix[tf]
    sf = h & (k.sector_fix.fillna('') != '').values
    k.loc[sf, 'sector'] = k.sector_fix[sf]; k.loc[sf, 'fe_group'] = k.sector_fix[sf].map(lambda x: FE.get(x, 'EXT'))
    dup = k.duplicated(KEY).values
    drop = ['verdict', 'street_fix', 'town_fix', 'name_fix', 'sector_fix', '_merge']
    out = k[~dup].drop(columns=drop)
    return out, dict(matched=int(hit.sum()), not_works=int(nw.sum()), dedup=int(dup.sum()), copies=k[dup].drop(columns=drop))


@pytest.fixture(scope='module')
def replayed(E, SR, TR, NV):
    """Street review, town review, then the no-town review (rows keyed town = '') on the frame stably sorted so that entries
    that had a town come first: a no-town entry that becomes a copy of a listing already reviewed is the one dropped. Entries
    still without a town afterwards are dropped. Returns the kept rows (with `_src`: 'town' / 'notown' = how the entry came out
    of the parser), the three logs and the rows left without a town."""
    d = E.copy(); d['review'] = ''; d['town_only'] = False; d['_src'] = np.where(d.town == '', 'notown', 'town')
    d1, l1 = _replay(d, SR, False)
    d2, l2 = _replay(d1, TR, True)
    d2 = d2.assign(_nt=(d2.town == '')).sort_values('_nt', kind='stable').drop(columns='_nt')
    d3, l3 = _replay(d2, NV.assign(town=''), False)
    return d3[d3.town != ''], l1, l2, l3, d3[d3.town == '']


# ------------------------------------------------------------------ review files
def test_review_files_have_unique_keys_and_known_verdicts(SR, TR):
    """A duplicated review key or a misspelt verdict would be applied silently (last one wins / treated as 'keep')."""
    assert not SR.duplicated(KEY).any() and not TR.duplicated(KEY).any()
    assert set(SR.verdict) <= {'ok', 'fix_address', 'fix_name', 'not_works', 'other_town', 'doubtful'}
    assert set(TR.verdict) <= {'ok', 'not_works', 'other_town', 'other_sector', 'doubtful'}
    assert not (set(map(tuple, SR[KEY].values)) & set(map(tuple, TR[KEY].values))), 'a listing reviewed in both files'


def test_review_fix_columns_agree_with_verdicts(SR, TR):
    """other_town without a new town, other_sector without a sector, or a sector_fix outside the vocabulary changes nothing or
    creates an unmapped sector (fe_group would silently become EXT)."""
    for rv in (SR, TR):
        ot = rv[rv.verdict == 'other_town']
        assert (ot.town_fix != '').all() and (ot.town_fix != ot.town).all()
    assert (TR[TR.verdict == 'other_sector'].sector_fix != '').all()
    assert set(TR.sector_fix) - {''} <= set(FE) | EXT
    assert (SR[SR.verdict == 'fix_name'].name_fix != '').all()


def test_readme_street_review_counts(SR):
    """README: 667 street-level listings reviewed; 122 dropped, 88 addresses and 58 names corrected, 20 moved, 41 doubtful."""
    c = SR.verdict.value_counts()
    assert [len(SR), c['not_works'], c['fix_address'], c['fix_name'], c['other_town'], c['doubtful']] == [667, 122, 88, 58, 20, 41]


# ------------------------------------------------------------------ row conservation: entries -> reviews -> geocoded -> published
def test_replay_of_reviews_reproduces_the_geocoded_file(replayed, G):
    """The review files applied by an independent implementation of the documented rules must give exactly the rows, names,
    streets, sectors and verdicts in work/hist/hist_hazard_geocoded.csv (catches a changed apply_review or a stale rerun)."""
    d, _, _, _, _ = replayed
    m = G.merge(d, on=KEY, how='outer', suffixes=('', '_r'), indicator=True)
    assert (m._merge == 'both').all(), m._merge.value_counts().to_dict()
    for c in ('name', 'street', 'review', 'fe_group', 'page', 'vol'):
        assert (m[c].fillna('').astype(str) == m[c + '_r'].fillna('').astype(str)).all(), c
    assert (m.town_only.astype(bool) == m.town_only_r.astype(bool)).all()
    assert (G[KEY].values == d[KEY].values).all(), 'row order: listings that had a town first, then the no-town entries'


def test_every_dropped_entry_has_a_named_reason(E, G, L, replayed, TC, HOM):
    """All 10,387 extracted entries are accounted for: published, or dropped as not works / as a copy collapsed by a correction in
    one of the three reviews, or left without a town, or reviewed to a town that has no point; nothing else may vanish."""
    d, l1, l2, l3, left = replayed
    placed = np.array([_placed(TC, HOM, t, y) for t, y in zip(d.town, d.year)])
    why = {'street review: not works': l1['not_works'], 'street review: copy': l1['dedup'],
           'town review: not works': l2['not_works'], 'town review: copy': l2['dedup'],
           'no-town review: not works': l3['not_works'], 'no-town review: copy of a listing of the edition': l3['dedup'],
           'still without a town': len(left), 'town has no point': int((~placed).sum()), 'published': len(L)}
    assert sum(why.values()) == len(E) == 10387, why
    assert why == {'street review: not works': 83, 'street review: copy': 4, 'town review: not works': 2320, 'town review: copy': 214,
                   'no-town review: not works': 1366, 'no-town review: copy of a listing of the edition': 258,
                   'still without a town': 0, 'town has no point': 104, 'published': 6038}
    assert len(d) == len(G)
    pub = set(map(tuple, L.assign(town=L.town.fillna(''))[KEY].values))
    assert pub == set(map(tuple, d[placed][KEY].values))
    assert set(map(tuple, G[G.precision == 'none'][KEY].values)) == set(map(tuple, d[~placed][KEY].values))
    assert set(left.review) <= {'', 'doubtful'}, 'only an unreviewed entry or a doubtful one without town_fix may stay without a town'


def test_no_extracted_entry_is_dropped_without_a_verdict(replayed):
    """'Every listing was hand-reviewed' must hold for what the parser extracted, not only for what could be placed (FINDING 1 of
    12 Nov, 2,860 entries without a town and without a verdict: closed by notown_review.csv)."""
    d, _, _, _, left = replayed
    assert (d.review.fillna('') != '').all(), int((d.review.fillna('') == '').sum())
    assert (left.review.fillna('') != '').all(), len(left)


@pytest.mark.xfail(strict=True, reason="FINDING 8: 48 street_review.csv rows (39 not_works, 6 doubtful, 3 ok) match no entry of the current "
                                       "parse and are skipped silently by apply_review (`if i is None: continue`)")
def test_every_review_row_matches_an_entry(E, SR, TR):
    """A review row whose key no longer exists (parser changed after the review) is ignored without notice: its verdict is lost."""
    ek = set(map(tuple, E[KEY].values))
    assert all(tuple(k) in ek for k in SR[KEY].values)


def test_every_town_review_row_matches_an_entry_after_the_street_review(replayed, TR):
    """All 6,908 town-review rows must find their listing (the larger review must not be partly ignored)."""
    _, _, l2, _, _ = replayed
    assert l2['matched'] == len(TR) == 6908


# ------------------------------------------------------------------ no-town review (notown_review.csv, 13 Nov 2026)
def test_notown_review_covers_every_entry_without_a_town_once(E, NV, replayed):
    """Every extracted entry without a town has exactly one review row and every review row an entry (same volume, page and
    name), so no entry is dropped silently and no verdict is lost."""
    nt = E[E.town == '']
    assert len(nt) == len(NV) == 2860 and (NV.town == '').all()
    assert not NV.duplicated(['year', 'nkey', 'sector']).any()
    m = nt.merge(NV, on=['year', 'nkey', 'sector'], how='outer', suffixes=('', '_r'), indicator=True, validate='1:1')
    assert (m._merge == 'both').all(), m._merge.value_counts().to_dict()
    assert (m.vol == m.vol_r).all() and (m.page.astype(int) == m.page_r.astype(int)).all() and (m.name.fillna('') == m.name_r).all()
    assert replayed[3]['matched'] == len(NV)


def test_notown_review_vocabulary_and_required_fields(NV, TR, SR):
    """A kept row must say where the firm was (town_fix, and street_fix: an address or 'none'); other_sector must name a known
    sector; a not_works row carries no correction; a misspelt verdict would be applied as 'keep' without a town and vanish."""
    assert set(NV.verdict) <= {'ok', 'other_sector', 'doubtful', 'not_works'}
    kept = NV[NV.verdict.isin(['ok', 'other_sector'])]
    assert (kept.town_fix != '').all() and (kept.street_fix != '').all()
    os_ = NV[NV.verdict == 'other_sector']
    assert (os_.sector_fix != '').all() and (os_.sector_fix != os_.sector).all()
    assert set(NV.sector_fix) - {''} <= set(FE) | EXT and (NV[NV.verdict != 'other_sector'].sector_fix == '').all()
    nw = NV[NV.verdict == 'not_works']
    assert (nw[['town_fix', 'street_fix', 'sector_fix', 'name_fix']] == '').all().all()
    d = NV[NV.verdict == 'doubtful']
    assert ((d.town_fix != '') == (d.street_fix != '')).all()
    assert (NV.town_fix == NV.town_fix.str.upper().str.strip()).all()
    assert (NV.name_fix.map(lambda s: re.sub(r'[^A-Z0-9]', '', s.upper()) != '') | (NV.name_fix == '')).all()
    assert (NV.note != '').all() and (NV.vol != '').all() and NV.page.str.fullmatch(r'\d+').all()
    assert set(NV.sector) <= set(FE) | EXT


def test_notown_kept_rows_are_published_unless_their_town_has_no_point(NV, G, L, replayed, TC, HOM):
    """Each kept no-town row ends as a listing under its corrected key (its own row, or the listing of the same edition it is a
    copy of); that listing is published unless the town has no gazetteer point and no override - the only reason allowed."""
    d, _, _, l3, left = replayed
    kept = NV[(NV.verdict != 'not_works') & (NV.town_fix != '')]
    assert len(kept) + len(left) == len(NV) - l3['not_works']
    keys = _final_keys(kept)
    g = {tuple(k): p for k, p in zip(G[KEY].values, G.precision)}
    assert all(k in g for k in keys)
    assert len(set(keys)) == len(kept) - l3['dedup'] + len(set(keys) & set(map(tuple, d[d._src == 'town'][KEY].values)))
    pub = set(map(tuple, L[KEY].values))
    out = [k for k in keys if k not in pub]
    assert all(g[k] == 'none' and not _placed(TC, HOM, k[1], k[0]) for k in out)
    own = d[d._src == 'notown']
    placed = np.array([_placed(TC, HOM, t, y) for t, y in zip(own.town, own.year)])
    assert [len(own), int(placed.sum()), int((~placed).sum())] == [1236, 1209, 27]
    assert sorted(set(own.town[~placed])) == ['ARGO', 'AUGUSTA', 'BLUMENAU', 'CEMENT CREEK', 'CHAFFEE CITY', 'CHRYSTAL CITY', 'DECATUR', 'DORA',
                                              'HIGHO', 'HORTENSE', 'NEWMIRE', 'PARROT CITY', 'PINE', 'PINKHAMPTON', 'ROBINSON', 'SPARKILL']


def test_notown_copies_are_copies_of_a_kept_listing(replayed, G):
    """A no-town row dropped as a copy must leave its twin in the layer, and where the twin is a listing that had a town, that
    reviewed listing (not the no-town row) is the one kept."""
    d, _, _, l3, _ = replayed
    c = l3['copies']
    assert (c._src == 'notown').all(), 'a listing that had a town was dropped in favour of a no-town entry'
    src = {tuple(k): s for k, s in zip(d[KEY].values, d._src)}
    assert all(tuple(k) in src for k in c[KEY].values)
    assert sum(src[tuple(k)] == 'town' for k in c[KEY].values) == 212


def test_notown_check_agreement_stays_above_the_13_nov_values(NV):
    """Independent reader's sample of 120 no-town entries (notown_check_2026-11-13.csv) against the review. Values on 13 Nov:
    same verdict 100/120; same keep-or-drop 102/120 (all 18 differences: the check keeps a repeated advertisement that the review
    drops because the firm has a listing in the edition; the review keeps nothing the check drops); of the 53 kept by both, same
    town 49, same address level (street vs town) 51, same address 47. A later edit of the review must not fall below these."""
    C = _csv(HIST / 'notown_check_2026-11-13.csv', dtype=str).fillna(''); C['year'] = C.year.astype(int)
    assert len(C) == 120 and not C.duplicated(['year', 'nkey', 'sector']).any()
    m = C.merge(NV, on=['year', 'nkey', 'sector'], how='left', suffixes=('_c', '_r'), indicator=True, validate='1:1')
    assert (m._merge == 'both').all() and (m.vol_c == m.vol_r).all() and (m.page_c == m.page_r).all()
    kc, kr = m.verdict_c != 'not_works', m.verdict_r != 'not_works'
    b = m[kc & kr]
    norm = lambda s: s.str.upper().str.replace(r'[^A-Z0-9 ]', '', regex=True).str.replace(r'\s+', ' ', regex=True).str.strip()
    assert int((m.verdict_c == m.verdict_r).sum()) >= 100
    assert int((kc == kr).sum()) >= 102 and int((~kc & kr).sum()) == 0
    assert len(b) >= 53
    assert (b.town_fix_c == b.town_fix_r).mean() >= 49 / 53
    assert ((b.street_fix_c == 'none') == (b.street_fix_r == 'none')).mean() >= 51 / 53
    assert (norm(b.street_fix_c) == norm(b.street_fix_r)).mean() >= 47 / 53


# ------------------------------------------------------------------ published listings
def test_listings_key_unique_and_every_listing_has_a_keep_verdict(L):
    """Duplicate listings inflate counts; a listing without a verdict, or with not_works, should not be published."""
    assert not L.duplicated(KEY).any()
    assert set(L.review.fillna('')) <= {'ok', 'fix_address', 'fix_name', 'other_town', 'other_sector', 'doubtful'}
    assert not L.is_person.astype(bool).any()


def test_editions_are_the_34_listed_in_the_readme(L):
    """An edition lost (file not parsed) or a year misread from a file name changes the series silently."""
    assert sorted(L.year.unique()) == EDITIONS
    readme = (ROOT / 'README.md').read_text(encoding='utf-8')
    m = re.search(r"\(34 editions: 1871 Rocky Mountain Directory, ([0-9, ]+)\)", readme)
    assert m and [1871] + [int(x) for x in m.group(1).split(',')] == EDITIONS


def test_sector_and_fe_group_agree(L):
    """fe_group drives fe_hazard and the Denver hazardous-sector count: it must follow the sector, also after sector_fix."""
    assert set(L.sector) <= set(FE) | EXT
    assert (L.sector.map(lambda s: FE.get(s, 'EXT')) == L.fe_group.astype(str)).all()


def test_town_level_points_are_the_gazetteer_points(L, TC, HOM):
    """Every published town must have a point (the homonym override for the year, else the gazetteer row or its alias) and
    town-level listings must sit exactly on it; every listing carries that point's county."""
    pts = [_point(TC, HOM, t, y) for t, y in zip(L.town, L.year)]
    assert all(p is not None and not np.isnan(p[0]) for p in pts)
    tl = (L.precision == 'town').values
    exp = np.array([p[:2] for p in pts], dtype=float)
    assert np.allclose(L[['lat', 'lon']].values[tl], exp[tl], atol=1e-6)
    assert (L.county.fillna('') == pd.Series([p[2] for p in pts], index=L.index).fillna('')).all()
    assert L.lat.between(36.99, 41.01).all() and L.lon.between(-109.07, -102.04).all()
    assert set(L.precision) == {'town', 'street'}


def test_street_level_rules_and_distance_to_town(L, TC, HOM):
    """Street level only where today's numbering applies (Denver 1891+, larger cities 1910+), never for office or town-review rows,
    and never far from the town it is listed in (a geocode carried to another city)."""
    s = L[L.precision == 'street']
    assert ((s.town == 'DENVER') & (s.year >= 1891) | s.town.isin(BIGCITY) & (s.year >= 1910)).all()
    assert not s.office.astype(bool).any() and not s.town_only.astype(bool).any()
    assert s.street.fillna('').str.match(r'^\d+ ').all()
    d = np.array([_dist_m(r.lat, r.lon, *_point(TC, HOM, r.town, r.year)[:2]) for r in s.itertuples()])
    assert d.max() < 15000, f'{d.max():.0f} m from the town point'
    assert (d[(s.town != 'DENVER').values] < 8000).all()


def test_alias_table_is_consistent(TC):
    """An alias whose target is missing places nothing; an alias that shadows a real gazetteer name is ignored by the code."""
    g = set(pd.read_csv(HIST / 'gnis_places_co.csv').name) | set(_csv(HIST / 'gnis_places_co_historical.csv').name)
    a = _csv(HIST / 'town_aliases.csv', dtype=str)
    assert a.variant.is_unique and a.name.isin(g).all() and not a.variant.isin(g).any()


def test_homonym_towns_are_in_the_county_the_directory_names(L, G):
    """A town name that exists twice in Colorado must be placed in the county the directory page gives (FINDING 4 of 12 Nov,
    closed by town_homonyms.csv), or left unplaced - never at its namesake."""
    want = {('COLORADO CITY', 1900, 1917): 'El Paso', ('GOLD HILL', 1871, 1892): 'Boulder', ('ALPINE', 1871, 1892): 'Chaffee',
            ('COTTON CREEK', 1871, 1892): 'Saguache', ('LIBERTY', 1910, 1917): 'Saguache'}
    bad = {k: sorted(set(L[(L.town == k[0]) & L.year.between(k[1], k[2])].county) - {v}) for k, v in want.items()}
    assert not any(bad.values()), bad
    n = {k: int(((G.town == k[0]) & G.year.between(k[1], k[2])).sum()) for k in want}
    assert all(n.values()), f'no geocoded row left for {[k for k, v in n.items() if not v]}: the check above would be empty'


def test_homonym_file_is_well_formed(HOM, TC):
    """Per town the year ranges must not overlap (the first matching row would win silently); coordinates inside Colorado or both
    blank; a county on every row; each override must change something: another point or county than the gazetteer / alias row,
    a point for a town that has none, or (blank) the removal of a namesake's point."""
    assert (HOM.year_from <= HOM.year_to).all() and HOM.year_from.between(1871, 1956).all() and HOM.year_to.between(1871, 1956).all()
    for t, g in HOM.groupby('town'):
        g = g.sort_values('year_from')
        assert (g.year_from.values[1:] > g.year_to.values[:-1]).all(), t
    assert (HOM.lat.isna() == HOM.lon.isna()).all() and HOM.county.notna().all() and (HOM.county.str.strip() != '').all()
    c = HOM[HOM.lat.notna()]
    assert c.lat.between(36.99, 41.01).all() and c.lon.between(-109.07, -102.04).all()
    assert (HOM.town == HOM.town.str.upper().str.strip()).all()
    for h in HOM.itertuples():
        old = TC.get(h.town)
        if np.isnan(h.lat): assert old is not None, f'{h.town}: a blank override of a town that has no point anyway'
        elif old is not None:
            assert _dist_m(h.lat, h.lon, old[0], old[1]) > 1000 or h.county != old[2], f'{h.town}: override equals the gazetteer row'


def test_homonym_overrides_are_applied_by_year(HOM, L, G, TC):
    """Listings of an overridden town sit on the override point and county in the stated years and on the gazetteer point outside
    them; under a blank override they are unplaced (precision none) and not published."""
    n_in = n_blank = n_out = 0
    for h in HOM.itertuples():
        l = L[(L.town == h.town) & L.year.between(h.year_from, h.year_to)]
        g = G[(G.town == h.town) & G.year.between(h.year_from, h.year_to)]
        if np.isnan(h.lat):
            assert l.empty and (g.precision == 'none').all() and g.lat.isna().all() and (g.county == h.county).all(); n_blank += len(g)
        else:
            assert len(l) == len(g) and (l.county == h.county).all()
            tl = l[l.precision == 'town']
            assert np.allclose(tl[['lat', 'lon']].values, [h.lat, h.lon], atol=1e-6); n_in += len(l)
    covered = pd.Series([((HOM.town == t) & (HOM.year_from <= y) & (HOM.year_to >= y)).any() for t, y in zip(L.town, L.year)], index=L.index)
    o = L[L.town.isin(HOM.town) & ~covered & (L.precision == 'town')]
    assert np.allclose(o[['lat', 'lon']].values, np.array([TC[t][:2] for t in o.town]).reshape(-1, 2), atol=1e-6); n_out = len(o)
    assert [n_in, n_blank, n_out] == [50, 3, 3]


def test_gazetteer_file_is_sane():
    """The gazetteer gives every town-level coordinate: names unique (one point per name), inside Colorado, with a county."""
    g = _csv(HIST / 'gnis_places_co.csv')
    assert g.name.is_unique and (g.name == g.name.str.upper()).all()
    assert g.lat.between(36.6, 41.1).all() and g.lon.between(-109.1, -102.0).all() and g.county_name.notna().all()


def test_readme_unplaced_count(G):
    """The number of reviewed listings that cannot be placed must be the one the README states."""
    m = re.search(r"and ([\d,]+) listings reviewed to vanished", (ROOT / 'README.md').read_text(encoding='utf-8'))
    assert m and int(m.group(1).replace(',', '')) == int((G.precision == 'none').sum())


def test_unplaced_listings_are_not_published(G, L, TC, HOM):
    """Listings reviewed to a town without coordinates must be absent from the published file (not parked at another point):
    a row is unplaced exactly when its town has no point in its year, and no unplaced key is published."""
    u = G[G.precision == 'none']
    assert len(u) == 104 and (u.town != '').all() and u.lat.isna().all()
    pub = set(map(tuple, L[KEY].values))
    assert not any(tuple(k) in pub for k in u[KEY].values)
    assert not any(_placed(TC, HOM, t, y) for t, y in zip(u.town, u.year))
    assert all(_placed(TC, HOM, t, y) for t, y in zip(G[G.precision != 'none'].town, G[G.precision != 'none'].year))
    assert set(u.town) & set(L.town) <= set(HOM.town[HOM.lat.isna()]), 'a town both placed and unplaced without a dated blank override'


# ------------------------------------------------------------------ firm-locations (link_hist.py)
def test_sites_are_the_aggregate_of_the_listings(L, S):
    """Each firm-location row must be recomputable from its listings: years, editions, sectors, precision, hazard flag, one town."""
    assert S.hfirm.is_unique and set(S.hfirm) == set(L.hfirm)
    g = L.groupby('hfirm')
    a = pd.DataFrame(dict(first=g.year.min(), last=g.year.max(), ed=g.year.nunique(), nt=g.town.nunique(),
                          st=g.precision.apply(lambda s: (s == 'street').any()), fe=g.fe_group.apply(lambda s: (s.astype(str) != 'EXT').any()),
                          sec=g.sector.apply(lambda s: '; '.join(sorted(s.unique()))),
                          yrs=g.year.apply(lambda s: ' '.join(map(str, sorted(s.unique())))))).reindex(S.hfirm)
    assert (a.nt == 1).all()
    assert (a['first'].values == S.first_year.values).all() and (a['last'].values == S.last_year.values).all()
    assert (a.ed.values == S.editions.values).all() and (a.yrs.values == S.years.astype(str).values).all()
    assert (a.st.values == (S.precision == 'street').values).all() and (a.fe.values == S.fe_hazard.astype(bool).values).all()
    assert (a.sec.values == S.sectors.values).all()


def test_site_coordinates_come_from_one_of_its_listings(L, S):
    """A firm-location must sit on a point of its own listings (street point when it has one), not on a later directory address."""
    def near(r, g): return float(np.hypot(g.lat - r.lat, g.lon - r.lon).min()) < 1e-6
    by = dict(tuple(L.groupby('hfirm')))
    assert all(near(r, by[r.hfirm]) for r in S.itertuples())
    assert all(near(r, by[r.hfirm][by[r.hfirm].precision == 'street']) for r in S[S.precision == 'street'].itertuples())


def test_denver_street_level_counts(S):
    """Denver hazardous-sector street-level firm-locations and how many of them are doubtful (13 Nov 2026 run)."""
    d = S[(S.precision == 'street') & (S.town == 'DENVER') & S.fe_hazard.astype(bool)]
    assert [len(S), int((S.precision == 'street').sum()), len(d), int((d.review == 'doubtful').sum())] == [3417, 565, 366, 34]


def test_readme_denver_street_level_counts(S):
    """README: '(N Denver hazardous-sector firm-locations, M of them doubtful)' must be the numbers of the firm-location file."""
    d = S[(S.precision == 'street') & (S.town == 'DENVER') & S.fe_hazard.astype(bool)]
    m = re.search(r"\(([\d,]+) Denver hazardous-sector firm-locations, (\d+) of them doubtful\)", (ROOT / 'README.md').read_text(encoding='utf-8'))
    assert m and [int(m.group(1).replace(',', '')), int(m.group(2))] == [len(d), int((d.review == 'doubtful').sum())]


def test_identical_name_in_one_town_is_one_firm_location(L):
    """The same normalised name in the same town in different editions must be one firm-location, or counts and persistence are
    wrong (FINDING 3 of 12 Nov, 116 names split into 388 firm-locations: closed by the nkey and whole-name rules of link_hist.py)."""
    n = L.groupby(['town', 'nkey']).hfirm.nunique()
    assert (n == 1).all(), f'{int((n > 1).sum())} names split, {int((n - 1).sum())} excess firm-locations'


def _fkey(s):
    """The whole normalised name with legal-form words dropped (link_hist.fkey, written out again)."""
    s = re.sub(STOP, ' ', re.sub(r'[^A-Z0-9& ]', ' ', str(s).upper()))
    return re.sub(r'\s+', ' ', s.replace('&', ' ')).strip()


def test_firm_locations_are_the_components_of_the_documented_merge_rules(L):
    """The partition of listings into firm-locations must be exactly the connected components of the four documented rules, within
    a town: distinctive keys (nk, 4+ characters) with token_sort_ratio >= 90; the identical printed-name key (nkey, 4+ characters);
    for names without a distinctive key the identical whole name (fk, 6+ characters); and whole names (6+ characters) with
    token_sort_ratio >= 85 on the same street-level point (coordinates rounded to 5 places)."""
    fuzz = pytest.importorskip('rapidfuzz.fuzz'); process = pytest.importorskip('rapidfuzz.process')
    sp = pytest.importorskip('scipy.sparse'); csg = pytest.importorskip('scipy.sparse.csgraph')
    d = L.reset_index(drop=True).copy()
    d['nk'] = d.nk.fillna(''); d['nkey'] = d.nkey.fillna('').astype(str); d['fk2'] = d.name.map(_fkey)
    assert (d.fk2 == d.fk.fillna('')).all(), 'the published fk column is not the whole normalised name'
    ed = [(i, i) for i in d.index]
    def pairs(g, col, cut):
        if len(g) > 1:
            a, b = np.nonzero(process.cdist(g[col].tolist(), g[col].tolist(), scorer=fuzz.token_sort_ratio, score_cutoff=cut))
            ed.extend(zip(g.index[a], g.index[b]))
    for _, g in d[d.nk.str.len() >= 4].groupby('town'): pairs(g, 'nk', 90)
    for _, g in d[d.nkey.str.len() >= 4].groupby(['town', 'nkey']): ed.extend((g.index[0], i) for i in g.index[1:])
    for _, g in d[(d.nk == '') & (d.fk2.str.len() >= 6)].groupby(['town', 'fk2']): ed.extend((g.index[0], i) for i in g.index[1:])
    st = d[(d.precision == 'street') & (d.fk2.str.len() >= 6)]
    for _, g in st.groupby(['town', st.lat.round(5), st.lon.round(5)]): pairs(g, 'fk2', 85)
    ed = np.array(ed)
    n, lab = csg.connected_components(sp.coo_matrix((np.ones(len(ed)), (ed[:, 0], ed[:, 1])), shape=(len(d), len(d))), directed=False)
    assert n == d.hfirm.nunique() == 3417
    assert d.groupby('hfirm').apply(lambda g: len(set(lab[g.index])), include_groups=False).eq(1).all()      # no firm-location spans two components
    assert pd.Series(d.hfirm.values).groupby(lab).nunique().eq(1).all()                                    # no component is split


def test_similar_names_on_one_street_point_are_one_firm_location(L):
    """The documented rule itself: two street-level listings of a town on the same point (5 decimal places) whose whole names
    (6+ characters) have token_sort_ratio >= 85 must be the same firm-location."""
    fuzz = pytest.importorskip('rapidfuzz.fuzz')
    st = L[L.precision == 'street'].assign(fk2=L.name.map(_fkey))
    st = st[st.fk2.str.len() >= 6]
    bad = []
    for _, g in st.groupby(['town', st.lat.round(5), st.lon.round(5)]):
        r = g.drop_duplicates('hfirm')
        bad += [(a.name, b.name, a.street) for i, a in enumerate(r.itertuples()) for b in list(r.itertuples())[i + 1:]
                if fuzz.token_sort_ratio(a.fk2, b.fk2) >= 85]
    assert not bad, bad[:5]


@pytest.mark.xfail(strict=True, reason="FINDING 3 (remaining, 56 -> 12): 12 street-level firm-locations still repeat another one with the same "
                                       "point and the same first 12 letters of the name, because the same-point rule compares whole names at "
                                       "token_sort_ratio >= 85 and the 1950/1956 editions print the proprietor after the firm: Reliable Sheet Metal "
                                       "/ 'Reliable Sheet Metal Robert J Oppelt' (2685 S High, both 1956), Denver Machine Shop at 1409 Blake (three "
                                       "firm-locations), Denver Metals Foundry at 1525 18th, General Chemical at 1271 W Bayaud, Dowdle Sheet Metal "
                                       "at 1804 S Pearl, Horton and Greeley Sheet Metal (Greeley), Richards Machine Shop (Pueblo), Maxwell Sheet "
                                       "Metal (Sterling)")
def test_same_name_at_the_same_point_is_one_firm_location(S):
    """Two street-level firm-locations with the same point and the same normalised name are one place counted twice."""
    s = S[S.precision == 'street'].copy()
    s['k'] = s.name.str.upper().str.replace(r'[^A-Z0-9]', '', regex=True).str[:12]
    assert not s.duplicated(['town', 'k', 'lat', 'lon']).any(), int(s.duplicated(['town', 'k', 'lat', 'lon']).sum())


@pytest.mark.xfail(strict=True, reason="NEW (13 Nov): the no-town review removes a copy only when the corrected key is letter-for-letter that of a "
                                       "listing of the edition; 62 kept no-town entries (classified sections, adverts) repeat a listing the same "
                                       "firm-location already has in that edition and sector under another spelling (1920 Vulcan Iron Works p.2433 "
                                       "next to Vulcan Iron Works Co p.937), so 62 of the 1,209 published no-town listings are second copies; "
                                       "firm-location counts are not affected")
def test_a_notown_entry_does_not_repeat_a_listing_of_its_firm_in_the_edition(L, replayed):
    """'Keep one per edition': a kept no-town entry must not stand beside another listing of the same firm-location, edition and sector."""
    d = replayed[0]
    src = {tuple(k): v for k, v in zip(d[KEY].values, d._src)}
    l = L.assign(src=[src[tuple(k)] for k in L[KEY].values])
    n = 0
    for _, g in l[l.duplicated(['hfirm', 'year', 'sector'], keep=False)].groupby(['hfirm', 'year', 'sector']):
        k = int((g.src == 'notown').sum())
        n += k if (g.src == 'town').any() else k - 1      # among no-town entries only, one of them is the listing
    assert n == 0, n


# ------------------------------------------------------------------ links to the 1961-2002 directory
def test_link_columns_are_coherent(S):
    """link, persists_to_1961plus and the dcm_* columns must describe the same set; score ranges follow the method (name >= 95, address <= 40 m)."""
    lk = S[S.link.notna()]
    assert (S.link.notna() == S.persists_to_1961plus.astype(bool)).all()
    assert set(lk.link) <= {'name', 'address'}
    assert S[S.link.isna()][['dcm_name', 'dcm_site', 'dcm_years']].isna().all().all()
    assert (lk[lk.link == 'name'].link_score >= 95).all() and lk[lk.link == 'address'].link_score.between(0, 40).all()
    assert (lk[lk.link == 'address'].precision == 'street').all() and lk[lk.link == 'address'].dcm_site.notna().all()


def test_address_links_recomputed_from_sites_csv(L, S):
    """An address link must name the app site nearest to any street-level point the firm-location was listed at, within 40 m
    (the score is that distance), and every firm-location with a street-level point within 40 m of a site must carry a link
    (recomputed from the listings and app/data/sites.csv)."""
    sites = _csv(APP / 'sites.csv')
    rows = []
    for f, g in L[L.precision == 'street'].groupby('hfirm'):
        p = g.drop_duplicates(['lat', 'lon'])
        d = np.min([_dist_m(la, lo, sites.lat.values, sites.lon.values) for la, lo in zip(p.lat, p.lon)], axis=0); j = int(np.argmin(d))
        rows.append((f, d[j], sites.site_id.iloc[j]))
    r = pd.DataFrame(rows, columns=['hfirm', 'd', 'sid']).merge(S, on='hfirm', validate='1:1')
    assert set(S[S.link == 'address'].hfirm) <= set(r.hfirm) and len(r) == int((S.precision == 'street').sum())
    a = r[r.link == 'address']
    assert len(a) == 253 and (a.d <= 40).all() and (a.sid == a.dcm_site).all() and (a.link_score == a.d.astype(int)).all()
    assert r.link.notna()[r.d <= 40].all()


def test_linked_sites_exist_in_the_published_site_file(S):
    """Every dcm_site (and every row of site_precursors.csv) must be a site of the published inventory (FINDING 6 of 12 Nov, four
    linked sites outside app/data/sites.csv: closed, a name link now names a site only when it is in that file)."""
    sites = _csv(APP / 'sites.csv')
    assert S.dcm_site.notna().sum() > 0 and S.dcm_site.dropna().isin(sites.site_id).all() and not (S.dcm_site == '').any()
    assert _csv(APP / 'site_precursors.csv').site_id.isin(sites.site_id).all()
    assert [int(S.link.notna().sum()), S.dcm_site.nunique()] == [314, 186]
    assert S[S.link == 'address'].dcm_site.notna().all()


# ------------------------------------------------------------------ app files
def test_app_listings_copy_matches_the_data_file(L):
    """app/data must carry the same listings as data/historical (a stale copy shows old numbers in the app)."""
    assert _csv(APP / 'pre1960_listings.csv', dtype={'street': str}).equals(L)


def test_app_copies_match_the_data_files(L, S):
    """app/data must carry the same firm-locations as data/historical (a stale copy shows old numbers in the app)."""
    H = _csv(APP / 'historical_sites.csv')
    assert H.hfirm.tolist() == S[S.lat.notna()].hfirm.tolist()
    for c in ('name', 'town', 'precision', 'sectors', 'first_year', 'last_year', 'editions'):
        assert (H[c].values == S[S.lat.notna()][c].values).all(), c
    assert np.allclose(H[['lat', 'lon']].values, S[S.lat.notna()][['lat', 'lon']].values)
    assert H.GEOID.notna().mean() > 0.99


def test_site_precursors_recomputed(S):
    """site_precursors.csv = one row per linked later site with the earliest pre-1960 year of the firm-locations linked to it."""
    P = _csv(APP / 'site_precursors.csv')
    exp = S[S.dcm_site.notna()].groupby('dcm_site').first_year.min()
    assert P.site_id.is_unique and set(P.site_id) == set(exp.index)
    assert (P.set_index('site_id').hist_first_year.reindex(exp.index) == exp).all()
    assert P.hist_first_year.between(1871, 1956).all()


def test_radium_firms_match_the_reviewed_layer():
    """The business-directory rows of radium_firms.csv must be exactly the radium firm-locations of historical_sites.csv
    (FINDING 2 of 12 Nov, a table older than the review: closed, pipeline/app_radium.py is rerun with the layer)."""
    R = _csv(APP / 'radium_firms.csv'); H = _csv(APP / 'historical_sites.csv')
    b = R[R.source == 'Colorado State Business Directory']
    h = H[H.sectors.fillna('').str.contains('Radium')]
    assert len(b) == len(h) > 0
    assert set(zip(b.city, b.first_year, b.last_year)) == set(zip(h.town, h.first_year, h.last_year))


def test_radium_firms_file_is_well_formed():
    """Coordinates inside Colorado, known precision and source labels, years in range, DCM rows carry a site or an address level."""
    R = _csv(APP / 'radium_firms.csv')
    assert R.lat.between(36.99, 41.01).all() and R.lon.between(-109.07, -102.04).all()
    assert set(R.precision) <= {'town', 'street'} and set(R.source) == {'Colorado State Business Directory', 'Directory of Colorado Manufacturers'}
    assert (R.first_year <= R.last_year).all() and R.first_year.between(1871, 2002).all()
    assert (R[R.source == 'Colorado State Business Directory'].last_year <= 1956).all()
    assert (R[R.source == 'Directory of Colorado Manufacturers'].first_year >= 1961).all()
