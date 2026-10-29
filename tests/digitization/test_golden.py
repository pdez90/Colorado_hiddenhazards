"""Golden-count regression on real OCR pages: four volumes (block 1967 and 1977, the 1965 list format, a 1992 paragraph
part) parsed from data/ocr, record counts and quality shares held to the post-review baseline, plus listings the review
checked by eye against the page images.

BASELINE values are what the current code produces with the gazetteer conftest builds from data/geocoder/zip_city.csv
(the post-review baseline, recorded 2026-10-26). The pre-review parser gave, for comparison, 1967_part1: 1522 records,
65% ZIP, 20% garbage names; 1977_part1: 1833 records, 70% ZIP, 25% garbage names; 1965: 2338; 1992_part3: 1249."""
import re
import pytest
import consolidate as C

BASELINE = {
    #                    records  zip   garbage  hazardous  with_sic  with_street
    'DCM_1967_part1': dict(records=1653, zip=1301, garbage=80, hazardous=634, with_sic=1572, with_street=1200),
    'DCM_1977_part1': dict(records=2018, zip=1843, garbage=98, hazardous=831, with_sic=1900, with_street=1607),
    'DCM_1965':       dict(records=2411, zip=0,    garbage=24, hazardous=687, with_sic=2411, with_street=1451),
    'DCM_1992_part3': dict(records=1385, zip=877,  garbage=0,  hazardous=441, with_sic=1197, with_street=831),
}
# consolidate over the same four volumes (classifier trained on 1967 + 1977): F&E / extended hazard flags per edition
BASELINE_FLAGS = {1965: dict(fe=651, ext=36), 1967: dict(fe=604, ext=36), 1977: dict(fe=820, ext=38), 1992: dict(fe=410, ext=30)}
BASELINE_OCR_FIXES = 44       # printed codes corrected by one digit (sic_ocr_fix)
BASELINE_DROPPED = 7          # records with a hazardous code dropped as software / bled in


def metrics(R):
    n = len(R)
    return dict(records=n,
                zip=sum(1 for r in R if re.match(r'^8[01]\d{3}$', r.get('zip') or '')),
                garbage=sum(1 for r in R if not re.search(r'[A-Za-z]{3}', r.get('name') or '')),
                hazardous=sum(1 for r in R if any(C.haz(c) for c in r['sic'])),
                with_sic=sum(1 for r in R if r['sic']),
                with_street=sum(1 for r in R if re.match(r'^\d+\s+\S', r.get('street') or '')))


def within(actual, expected, n, rel=0.01, abs_pts=0.5):
    """Counts within 1% of the baseline, or within half a percentage point of the baseline share of records."""
    return abs(actual - expected) <= max(rel * expected, abs_pts / 100 * n)


@pytest.mark.parametrize('vol', list(BASELINE))
def test_volume_counts(parsed, vol):
    m = metrics(parsed[vol])
    exp = BASELINE[vol]
    bad = {k: (m[k], exp[k]) for k in exp if not within(m[k], exp[k], exp['records'])}
    assert not bad, f'{vol}: (actual, baseline) out of bounds: {bad}'


@pytest.mark.parametrize('vol', list(BASELINE))
def test_record_shape(parsed, vol):
    for r in parsed[vol]:
        assert r['vol'] == vol and isinstance(r['page'], int) and r['page'] >= 1
        assert isinstance(r['sic'], list) and all(re.fullmatch(r'\d{4}', c) for c in r['sic'])
        assert r['zip'] == '' or re.fullmatch(r'8[01]\d{3}', r['zip'])
        for c, d in zip(r['sic'], r['sic_desc']):      # no street line read as a mining code
            if 1000 <= int(c) <= 1499:
                assert not re.search(r'\b(ST|AVE|DR|RD|BLVD|PL)\b', d, re.I), (vol, r['name'], c, d)


def test_hazard_flags_per_year(consolidated):
    g = consolidated.groupby('year').agg(fe=('fe_hazard', 'sum'), ext=('ext_hazard', 'sum'), n=('name', 'size'))
    for y, exp in BASELINE_FLAGS.items():
        assert within(g.at[y, 'fe'], exp['fe'], g.at[y, 'n']), (y, g.at[y, 'fe'], exp['fe'])
        assert within(g.at[y, 'ext'], exp['ext'], g.at[y, 'n'], rel=0.05), (y, g.at[y, 'ext'], exp['ext'])
    assert abs((consolidated.sic_ocr_fix != '').sum() - BASELINE_OCR_FIXES) <= 3
    assert abs((consolidated.sic_dropped != '').sum() - BASELINE_DROPPED) <= 2
    src = consolidated.sic_source.value_counts()
    assert src['directory'] > 7000 and src.get('predicted', 0) > 80


# listings the review checked against the page images (volume, page, name) -> (street, zip, city, sic codes)
VERIFIED = [
    ('DCM_1967_part1', 17, 'PYROCHEM CO.',                        '1331 CANNON',            '80027', 'LOUISVILLE',  ['3722', '2899']),
    ('DCM_1967_part1', 30, 'INTERCHEMICAL CORP PRINTING INK OLV', '805 W 11TH AVE',         '80204', 'DENVER',      ['2693']),
    ('DCM_1967_part1',  6, 'COOLEY GRAVEL CO',                    '3631 TENNYSON',          '80002', 'ARVADA',      ['3272']),
    ('DCM_1967_part1', 28, 'GRANT CHESTER*S IDEA PRESS',          '952 S FEDERAL BLVD',     '80219', 'DENVER',      ['2751']),
    ('DCM_1967_part1', 35, 'PLAT PACKING CO',                     '707 & 90TH',             '80216', 'DENVER',      ['2011']),
    ('DCM_1967_part1', 41, 'WESTERN PAPER Co',                    '1816 MARKET',            '80202', None,          ['2653']),   # name was 'PRES' before the review
    ('DCM_1967_part1', 41, 'WESTERN FASHIONS INC',                '1513 WAZEE',             '80262', None,          ['2385']),
    ('DCM_1965',       15, 'CRAWFCRD CHRONICLE',                  'CELTA',                  '',      'CRAWFORD',    ['2711']),
    ('DCM_1965',       43, 'CHERRY PRODUCTS, INC.',               'L.S. HWY. 34',           '',      'LOVELAND',    ['2037']),
    ('DCM_1965',       47, 'MCHRLAND BROTHERS MFG. CO.',          '',                       '',      'BRUSH',       ['2042']),
    ('DCM_1992_part3', 20, 'ALL-RITE PAVING & REDILMIX',          '200 Speculater Ave',     '81052', 'LAMAR',       ['3272', '2999']),
    ('DCM_1992_part3', 44, 'INTERSTATE PATTERN + MEG CO',         '3650 W 69TH PI',         '80030', 'WESTMINSTER', ['3363', '3469', '3869']),
    ('DCM_1992_part3', 17, 'MORRELL GRAPHICS COMM',               '111 Public Rd',          '80026', 'LAFAYETTE',   ['2759', '2761']),
    ('DCM_1992_part3', 24, 'DFM ENGINEERING INC',                 '1035 Delaware Ave No D', '80501', 'LONGMONT',    ['3829']),
]


@pytest.mark.parametrize('vol,page,name,street,zip_,city,sic', VERIFIED, ids=[v[2] for v in VERIFIED])
def test_verified_listing(parsed, vol, page, name, street, zip_, city, sic):
    hits = [r for r in parsed[vol] if r['page'] == page and r['name'] == name]
    assert len(hits) == 1, f'{name}: {len(hits)} records on page {page}'
    r = hits[0]
    assert (r['street'], r['zip'], r['sic']) == (street, zip_, sic)
    if city is not None:
        assert r['city_ctx'] == city


def test_verified_listings_specific_fields(parsed):
    r = next(r for r in parsed['DCM_1967_part1'] if r['name'] == 'COOLEY GRAVEL CO')
    assert r['est'] == 1925 and r['size'] == '20-99'
    r = next(r for r in parsed['DCM_1967_part1'] if r['name'] == 'PLAT PACKING CO')
    assert r['est'] == 1950 and r['size'] == '50-99' and r['sic_desc'] == ['MEAT PACKING PLANTS']
    r = next(r for r in parsed['DCM_1992_part3'] if r['name'] == 'DFM ENGINEERING INC')
    assert r['est'] == 1982 and r['sic_desc'] == ['astronomical instruments']
    r = next(r for r in parsed['DCM_1965'] if r['name'] == 'CHERRY PRODUCTS, INC.')
    assert r['size'] == '20-99'
