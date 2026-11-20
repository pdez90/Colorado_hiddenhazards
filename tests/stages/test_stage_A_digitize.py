"""Stage A (digitization of the 1961-2002 Directory of Colorado Manufacturers): parse -> consolidate -> geo_prep -> link ->
export listings / by_year.  Invariant checks written for review 4 (12 Nov 2026).  Lives in tests/stages/.
Reads committed files only; tests that need work/ skip when it is absent.  STAGE_ROOT overrides the repository root."""
import os, re, json, glob, pathlib, collections
import pandas as pd, numpy as np, pytest

ROOT = pathlib.Path(os.environ.get('STAGE_ROOT') or pathlib.Path(__file__).resolve().parents[2])
RES = ROOT / 'data' / 'results' / 'CO_directory_listings_1961-2002.csv'
FULL = ROOT / 'data' / 'full_inventory' / 'CO_directory_listings_1961-2002.csv'
WORK = ROOT / 'work'
FE = {'28': 'Chemicals', '29': 'Petroleum refining', '30': 'Rubber & plastics', '33': 'Primary metals',
      '34': 'Fabricated metals', '35': 'Industrial machinery', '37': 'Transportation equipment'}
EXT4 = {'2491', '3111', '3671', '3672', '3674', '3679', '3691', '3692', '3861'}
T = lambda s: s.astype(str).str.upper().isin(['TRUE', '1'])


def _csv(p):
    return pd.read_csv(p, dtype=str, keep_default_na=False, low_memory=False)


@pytest.fixture(scope='module')
def L():
    return _csv(RES)


@pytest.fixture(scope='module')
def BY():
    return pd.concat([_csv(p) for p in sorted((ROOT / 'data' / 'by_year').glob('CO_DCM_*_geocoded.csv'))], ignore_index=True)


@pytest.fixture(scope='module')
def CFG():
    return json.load(open(ROOT / 'config' / 'editions.json'))


def _volumes():
    """(volume, year) pairs read from pipeline/volumes.py as text (no import)."""
    src = (ROOT / 'pipeline' / 'volumes.py').read_text()
    return [(v, int(y)) for v, y in re.findall(r"'(DCM_[^']+)':\s*\((\d{4}),", src)]


def _need(*rel):
    for r in rel:
        if not (WORK / r).exists():
            pytest.skip(f'work/{r} not present')


# ------------------------------------------------------------------ editions
def test_edition_config_partitions_the_volume_table(CFG):
    """Catches an edition added to volumes.py but missing from (or listed twice in) config/editions.json."""
    years = {y for _, y in _volumes()}
    c, p = set(CFG['complete_editions']), set(CFG['partial_editions'])
    assert not (c & p) and (c | p) == years and len(c) == 13 and len(p) == 12


def test_readme_names_the_configured_editions(CFG):
    """Catches README's lists of complete / partial editions drifting from config/editions.json."""
    txt = (ROOT / 'README.md').read_text()
    m = re.search(r"\*\*13 complete editions\*\* only — ([\d, \n]+)\. The other twelve \(([\d, \n]+)\)", txt)
    assert m, 'README scope sentence not found'
    ints = lambda s: sorted(int(x) for x in re.findall(r'\d{4}', s))
    assert ints(m.group(1)) == sorted(CFG['complete_editions']) and ints(m.group(2)) == sorted(CFG['partial_editions'])


def test_published_files_hold_exactly_the_complete_editions(L, BY, CFG):
    """Catches a partial edition leaking into data/results or data/by_year (or a complete one dropped)."""
    want = sorted(CFG['complete_editions'])
    assert sorted(L.year.astype(int).unique()) == want
    files = sorted(int(re.search(r'CO_DCM_(\d{4})_', p.name).group(1)) for p in (ROOT / 'data' / 'by_year').glob('*.csv'))
    assert files == want
    for p in (ROOT / 'data' / 'by_year').glob('*.csv'):          # every file holds only its own year
        y = re.search(r'CO_DCM_(\d{4})_', p.name).group(1)
        assert set(_csv(p).edition_year) == {y}, p.name


def test_full_inventory_restricted_to_complete_editions_is_the_published_listing_file(L, CFG):
    """Row conservation of the edition filter: the only rows dropped between the all-editions run and the published
    listings are those of the partial editions, and the industry coding / establishment ids of the kept rows are unchanged."""
    A = _csv(FULL)
    assert sorted(A.year.astype(int).unique()) == sorted(CFG['complete_editions'] + CFG['partial_editions'])
    Ac = A[A.year.astype(int).isin(CFG['complete_editions'])].reset_index(drop=True)
    assert len(Ac) == len(L)
    for c in ['year', 'source_volume', 'page', 'name', 'street', 'city', 'zip', 'sic', 'sic_source', 'naics', 'fe_sectors', 'ext_sectors', 'estab_id']:
        assert (Ac[c].values == L[c].values).all(), c
    assert (T(Ac.fe_hazard).values == T(L.fe_hazard).values).all() and (T(Ac.ext_hazard).values == T(L.ext_hazard).values).all()


def test_every_volume_of_a_complete_edition_contributes_listings(L, CFG):
    """Catches a volume that parsed to nothing (lost part of an edition) and volumes filed under the wrong year."""
    got = set(zip(L.source_volume, L.year.astype(int)))
    want = {(v, y) for v, y in _volumes() if y in CFG['complete_editions']}
    assert got == want
    assert L.groupby('source_volume').size().min() >= 300


# ------------------------------------------------------------------ listings <-> by_year
KEYMAP = {'year': 'edition_year', 'source_volume': 'source_volume', 'page': 'source_page', 'city': 'city', 'zip': 'zip',
          'sic': 'sic_codes', 'sic_source': 'industry_code_source', 'naics': 'naics_codes', 'fe_hazard': 'fe_hazardous_sector',
          'fe_sectors': 'fe_sectors', 'ext_hazard': 'extended_hazard_sector', 'ext_sectors': 'extended_sectors',
          'estab_id': 'establishment_id', 'site_id': 'site_id', 'geo_level': 'geocode_level'}
_scrub = lambda s: s.str.replace(r'^[=+@\-\s]+', '', regex=True)


def _multiset(df, cols):
    return collections.Counter(map(tuple, df[cols].itertuples(index=False, name=None)))


def test_by_year_rows_are_the_listing_rows_field_by_field(L, BY):
    """Catches a join in export_by_year.py that duplicates, drops or alters listings (the existing test compares only
    the row count and the id sets): the two files must hold the same multiset of rows over 15 shared fields + name."""
    a = L[list(KEYMAP)].copy(); a['name'] = _scrub(L.name)
    b = BY[list(KEYMAP.values())].copy(); b.columns = list(KEYMAP); b['name'] = _scrub(BY.firm_name)
    assert _multiset(a, list(a.columns)) == _multiset(b, list(a.columns))


def test_listing_csv_has_no_formula_leading_cells_and_same_names_as_by_year(L, BY):
    """Catches the spreadsheet-injection scrub being applied to one published listing file but not the other."""
    assert not L.name.str.match(r'^[=+@]').any()
    assert collections.Counter(L.name) == collections.Counter(BY.firm_name)


# ------------------------------------------------------------------ industry codes and hazard flags
def test_fe_sector_definition_same_in_readme_code_and_workbook_text():
    """Catches the Frickel-Elliott sector list drifting between README, consolidate.py and export.py's read-me sheet."""
    readme = (ROOT / 'README.md').read_text()
    m = re.search(r"Frickel & Elliott's seven: SIC (.+?)\(NAICS ([\d, ]+)\)", readme, re.S)
    assert m
    assert sorted(re.findall(r'\b(\d{2}) [a-z]', m.group(1))) == sorted(FE)
    cons = (ROOT / 'pipeline' / 'consolidate.py').read_text()
    fe_code = dict(re.findall(r"'(\d{2})':'([^']+)'", re.search(r"FE_MAJOR = \{(.+?)\}", cons).group(1)))
    assert fe_code == FE
    naics = dict(re.findall(r"'(\d{3})':'(\d{2})'", re.search(r"NAICS_FE = \{(.+?)\}", cons).group(1)))
    assert sorted(naics) == sorted(re.findall(r'\d{3}', m.group(2))) and sorted(naics.values()) == sorted(FE)
    exp = (ROOT / 'pipeline' / 'export.py').read_text()
    assert 'SIC 28 chemicals, 29 petroleum refining, 30 rubber & plastics, 33 primary metals, 34 fabricated metals, 35 industrial machinery, 37 transportation equipment' in exp


@pytest.mark.parametrize('which', ['results', 'full_inventory'])
def test_hazard_flags_recomputed_from_the_published_codes(which):
    """Catches flags that no longer follow from the listing's own SIC codes (stale flags after a code fix, wrong sector map)."""
    D = _csv(RES if which == 'results' else FULL)
    codes = D.sic.apply(lambda s: [c for c in s.split(';') if c])
    assert all(re.fullmatch(r'\d{4}', c) for cs in codes for c in cs)
    # the 1957 SIC of the 1965-1968 editions files ordnance under major group 19; from 1972 it is 348x, so 19xx counts as 34
    m2 = lambda c: '34' if c[:2] == '19' else c[:2]
    fe = codes.apply(lambda cs: any(m2(c) in FE for c in cs))
    ext = codes.apply(lambda cs: any(c in EXT4 or c[:2] == '10' for c in cs)) & ~fe
    assert (fe.values == T(D.fe_hazard).values).all() and (ext.values == T(D.ext_hazard).values).all()
    sect = codes.apply(lambda cs: '; '.join(FE[k] for k in sorted({m2(c) for c in cs}) if k in FE))
    assert (sect == D.fe_sectors).all()
    assert not (T(D.fe_hazard) & T(D.ext_hazard)).any()            # the extended set is defined as "not F&E"
    assert ((D.ext_sectors != '') >= T(D.ext_hazard)).all()


def test_code_source_vocabulary_and_presence(L, BY):
    """Catches a listing with codes but no source (or the reverse), NAICS-derived codes in a SIC-era edition, and the
    by_year code/description columns disagreeing with the listing file."""
    assert set(L.sic_source) <= {'', 'directory', 'predicted', 'keyword', 'name_keyword', 'naics'}
    assert ((L.sic != '') == (L.sic_source != '')).all() or (L[(L.sic == '') & (L.sic_source != '')].sic_source.isin(['directory', 'predicted']).all()
                                                               and not ((L.sic != '') & (L.sic_source == '')).any())
    assert not (L.sic_source == 'naics').any()                                # 1965-1992 print SIC
    # 1965 prints one code per listing and no text. Since the fix of finding E3 (13 Nov 2026) a printed code counts as
    # 'directory' only when it is a code the directory uses (consolidate.validate_bare_codes); a listing whose code is
    # unreadable gets its industry from the firm's name ('name_keyword', 'predicted') or none, never 'directory'.
    # (Before the fix this line read: every 1965 listing is 'directory'.)
    s65 = L[L.year == '1965'].sic_source
    assert set(s65) <= {'directory', 'name_keyword', 'predicted', ''} and (s65 == 'directory').mean() >= 0.80


def test_edition_without_printed_codes_has_no_directory_codes(L):
    """Catches address lines parsed as printed SIC codes in the edition that prints product descriptions only."""
    assert not ((L.year == '1966') & (L.sic_source == 'directory')).any()


def test_no_naics_codes_in_sic_era_editions(L):
    """Catches house numbers / ZIPs read as NAICS codes in editions that print SIC codes only."""
    assert (L.naics == '').all()


def test_printed_codes_are_mining_or_manufacturing_codes(L):
    """Catches OCR-garbled printed codes: a printed SIC must be mining (10-14), manufacturing (20-39) or 73 (software), <=0.5% otherwise."""
    ok = {str(i) for i in list(range(10, 15)) + list(range(20, 40))} | {'73'}
    d = L[L.sic_source == 'directory']
    bad = {}
    for y, g in d.groupby('year'):
        cs = [c for s in g.sic for c in s.split(';') if c]
        share = np.mean([c[:2] not in ok for c in cs])
        if share > 0.005: bad[y] = round(float(share), 4)
    assert not bad, bad


def _pair_agreement(L, ya, yb, src_a, src_b=('directory',)):
    a = L[(L.year == ya) & (L.sic != '') & L.sic_source.isin(src_a)]; b = L[(L.year == yb) & (L.sic != '') & L.sic_source.isin(src_b)]
    a = a[~a.estab_id.duplicated(keep=False)]; b = b[~b.estab_id.duplicated(keep=False)]
    m = a.merge(b, on='estab_id', suffixes=('_a', '_b'))
    return len(m), float((T(m.fe_hazard_a) == T(m.fe_hazard_b)).mean())


def test_inferred_and_1965_flags_agree_with_the_next_printed_edition(L):
    """Catches a classifier or 1965-parser regression: for establishments listed in both editions, the F&E flag from
    inferred 1966 codes (and from 1965's printed codes) must agree with the flag from 1967's printed codes at least
    85% / 80% of the time (observed 89.9% of 1,009 and 85.4% of 418; printed-vs-printed editions agree 93-97%)."""
    n, p = _pair_agreement(L, '1966', '1967', ('predicted',)); assert n >= 500 and p >= 0.85, (n, p)
    n, p = _pair_agreement(L, '1965', '1967', ('directory',)); assert n >= 200 and p >= 0.80, (n, p)
    n, p = _pair_agreement(L, '1973', '1974', ('directory',)); assert n >= 1000 and p >= 0.95, (n, p)


def test_classifier_normalises_training_and_query_text_the_same_way():
    """Catches train/predict skew: sic_classifier.norm (training) and sic_classifier_norm.norm (prediction) must be one rule."""
    a = (ROOT / 'pipeline' / 'sic_classifier.py').read_text(); b = (ROOT / 'pipeline' / 'sic_classifier_norm.py').read_text()
    body = lambda s: [l.strip() for l in re.search(r"def norm\(t\):\n((?:    .+\n)+)", s).group(1).splitlines()]
    if 'from sic_classifier_norm import norm' in a: return
    assert body(a) == body(b)



# ------------------------------------------------------------------ duplicates, empty rows, towns
def test_no_listing_printed_in_two_volumes_of_one_edition(L):
    """Catches a scan page present in two part-volumes being counted twice (FINDING E1, fixed by the re-parse): the same name + street
    + ZIP + codes + year established must not occur in two different source volumes of one edition. Two 1990 firms (AT+T, Colorado
    Composite) are printed twice with different codes, sizes and founding years on non-overlapping pages: separate entries, not copies."""
    d = L[(L.name != '') & (L.street != '')].copy()
    d['k'] = (d.name.str.upper().str.replace(r'[^A-Z0-9]', '', regex=True) + '|' + d.street.str.upper().str.replace(r'[^A-Z0-9]', '', regex=True)
              + '|' + d.zip + '|' + d.sic + '|' + d.est)
    nv = d.groupby(['year', 'k']).source_volume.nunique()
    assert (nv > 1).sum() == 0, nv[nv > 1].groupby('year').size().to_dict()


def test_every_listing_has_a_firm_name(L):
    """Catches record fragments (code lines or address lines split from their firm) published as listings."""
    assert (L.name.str.strip() != '').all(), L[L.name.str.strip() == ''].groupby('year').size().to_dict()


def test_no_town_holds_many_listings_in_one_edition_only(L):
    """Catches a town heading carried over pages that belong to another town (FINDING E2, fixed by the re-parse): a town with 30+
    listings in an edition must not exceed three times (+10) its largest count in any other edition; and no town with a median of
    60+ listings may be empty in an edition. The 1965 edition prints no ZIP codes and files Commerce City (incorporated 1962) firms
    under their Denver post office; they are placed in Commerce City by address, so 1965 has no COMMERCE CITY heading by design."""
    t = L[L.city != ''].groupby(['year', 'city']).size().unstack(fill_value=0)
    bad = {}
    for y in t.index:
        other = t.drop(index=y).max()
        f = t.loc[y][(t.loc[y] >= 30) & (t.loc[y] > 3 * other.clip(lower=1) + 10)]
        if len(f): bad[y] = f.to_dict()
    big = t.columns[t.median() >= 60]
    missing = {y: [c for c in big[t.loc[y, big] == 0] if (y, c) != ('1965', 'COMMERCE CITY')] for y in t.index}
    missing = {y: v for y, v in missing.items() if v}
    assert not bad and not missing, (bad, missing)


# ------------------------------------------------------------------ establishments (link.py)
def test_establishment_ids_well_formed_and_one_block(L):
    """Catches missing / malformed ids and links across ZIP codes, which link.py's blocking forbids (a ZIP-less record may
    bridge to one ZIP only): no establishment may hold more than two distinct valid ZIPs."""
    assert L.estab_id.str.fullmatch(r'E\d{6}').all()
    z = L[L.zip.str.fullmatch(r'8[01]\d{3}')].groupby('estab_id').zip.nunique()
    assert (z <= 2).all() and (z > 1).mean() < 0.005


def test_establishments_rarely_span_towns_or_repeat_within_an_edition(L):
    """Catches a linking change that chains firms of different towns (observed 7 of 7,863 multi-listing establishments)
    or merges many same-edition listings (observed 358 extra listings, 0.8%, mostly the duplicated scan pages)."""
    g = L.groupby('estab_id')
    multi = g.size() > 1
    towns = L[L.city != ''].groupby('estab_id').city.nunique()
    assert (towns > 1).sum() <= 0.005 * multi.sum()
    extra = (g.size() - g.year.nunique()).sum()
    assert extra <= 0.015 * len(L)
    assert g.size().max() <= 2 * L.year.nunique()


def test_founding_years_not_after_the_edition(L):
    """Catches OCR/parse errors in year_established and off-by-one edition years: a firm cannot be founded after the
    edition that lists it (observed 51 of 36,561, 0.14%)."""
    e = pd.to_numeric(L.est, errors='coerce'); y = L.year.astype(int)
    ok = e.between(1850, 2002)
    assert ((e > y) & ok).sum() <= 0.005 * ok.sum()


# ------------------------------------------------------------------ work/-dependent row conservation
def test_parsed_volumes_all_reach_records_pkl_in_order():
    """Row conservation parse -> consolidate: every parsed line of every volume is one row of records.pkl, same order, same name
    as parsed (name_parsed; the scan review may correct `name`), except the rows the scan review drops as not listings."""
    _need('parsed', 'inv/records.pkl')
    R = pd.read_pickle(WORK / 'inv' / 'records.pkl')
    rv = _csv(ROOT / 'data' / 'raw' / 'dcm_scan_review.csv')
    nl = rv[rv.verdict == 'not_listing']
    gone = {(v, int(float(p)), n.strip()) for v, p, n in zip(nl.vol, nl.page, nl['name'])}
    vols = dict(_volumes())
    assert {os.path.basename(f)[:-6] for f in glob.glob(str(WORK / 'parsed' / '*.jsonl'))} == set(vols)
    n = 0
    for f in sorted(glob.glob(str(WORK / 'parsed' / '*.jsonl'))):
        v = os.path.basename(f)[:-6]
        rows = [json.loads(l) for l in open(f)]
        rows = [r for r in rows if (v, int(r.get('page')), (r.get('name') or '').replace('"', '').strip()) not in gone]
        seg = R.iloc[n:n + len(rows)]
        assert (seg.vol == v).all() and (seg.year == vols[v]).all(), v
        assert [(r.get('name') or '').replace('"', '').strip() for r in rows] == seg.name_parsed.fillna('').tolist(), v
        assert [r.get('page') for r in rows] == seg.page.tolist(), v
        n += len(rows)
    assert n == len(R)


def test_records_survive_geo_prep_link_and_edition_filter(CFG, L):
    """Row conservation consolidate -> geo_prep -> link -> build_sites -> export: no row added, lost or reordered; the
    only rows dropped are the partial editions'; codes, flags and establishment ids reach the CSV unchanged."""
    _need('inv/records.pkl', 'inv/records_geo.pkl', 'inv/records_linked.pkl', 'inv/records_final.pkl')
    R, G, K, F = (pd.read_pickle(WORK / 'inv' / f'{n}.pkl') for n in ['records', 'records_geo', 'records_linked', 'records_final'])
    assert len(R) == len(G) == len(K)
    for D in (G, K):       # clean_spelling.py respells `name` in the linked records and keeps the reading in name_as_read
        nm = D.name_as_read if 'name_as_read' in D.columns else D.name
        assert (D.vol.values == R.vol.values).all() and (D.page.values == R.page.values).all() and (nm.fillna('').values == R.name.fillna('').values).all()
        assert [tuple(x) for x in D.sic] == [tuple(x) for x in R.sic] and (D.fe_hazard.values == R.fe_hazard.values).all()
    Kc = K[K.year.isin(CFG['complete_editions'])]
    assert len(Kc) == len(F) == len(L)
    assert (Kc.estab_id.values == F.estab_id.values).all() and (Kc.name.fillna('').values == F.name.fillna('').values).all()
    assert (F.estab_id.values == L.estab_id.values).all() and (F.sic.apply(';'.join).values == L.sic.values).all()
    assert (F.fe_hazard.values == T(L.fe_hazard).values).all() and (F.year.astype(str).values == L.year.values).all()
    # geo_prep may only move a trailing ZIP out of the street: the street can only get shorter
    assert all(str(g or '') == str(r or '') or str(r or '').startswith(str(g or '')) for g, r in zip(G.street_n, R.street_n))


def test_readme_counts_of_code_corrections_match_the_log_columns():
    """Catches the README's sic_ocr_fix / sic_dropped counts going stale after a rerun of consolidate.py."""
    _need('inv/records.pkl')
    R = pd.read_pickle(WORK / 'inv' / 'records.pkl')
    txt = (ROOT / 'README.md').read_text()
    fixed = int(re.search(r"([\d,]+) codes, logged in `sic_ocr_fix`", txt).group(1).replace(',', ''))
    dropped = int(re.search(r"([\d,]+) listings, logged in `sic_dropped`", txt).group(1).replace(',', ''))
    assert fixed == int(R.sic_ocr_fix.str.split().str.len().sum()) and dropped == int((R.sic_dropped != '').sum())


def test_gazetteer_one_city_and_county_per_zip():
    """Catches duplicate ZIP keys in the gazetteer tables that geo_prep/export join on (a duplicate would multiply listings)."""
    for f, col in [('zip_city.csv', 'CITY_NAME'), ('zip_county.csv', 'COUNTY_NAME')]:
        p = ROOT / 'data' / 'geocoder' / f
        if not p.exists(): p = WORK / 'inv' / f
        if not p.exists(): pytest.skip(f'{f} not present')
        z = _csv(p)
        assert z.z.is_unique and (z[col] != '').all()
