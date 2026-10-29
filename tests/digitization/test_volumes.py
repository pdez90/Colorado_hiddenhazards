"""volumes.py: the volume -> (edition year, parser, OCR mode) table that parse_all and consolidate dispatch on."""
import re
import pytest
from volumes import VOLUMES
from conftest import ocr_members

PARSERS = {'table', '1965', 'block', '1988', 'para', '2002'}
# which parser handles which edition years
PARSER_YEARS = {'table': {1961, 1962}, '1965': {1965}, 'block': set(range(1966, 1987)), '1988': {1988},
                'para': {1990, 1992, 1993, 1999}, '2002': {2002}}


def test_table_shape():
    assert len(VOLUMES) == 43
    for vol, entry in VOLUMES.items():
        assert re.fullmatch(r'DCM_\d{4}(_part\d|_copy|_part1_SIC)?', vol), vol
        year, parser, mode = entry
        assert isinstance(year, int) and 1961 <= year <= 2002
        assert parser in PARSERS and mode in ('tsv', 'coltxt')
        assert year in PARSER_YEARS[parser], (vol, year, parser)


def test_file_year_matches_edition_year_except_documented_cases():
    for vol, (year, _, _) in VOLUMES.items():
        file_year = int(vol[4:8])
        if vol == 'DCM_1961_copy':
            assert year == 1984        # the scan labelled 1961 is the 1984 edition
        else:
            assert file_year == year, vol


def test_coltxt_only_for_1999():
    assert [v for v, (_, _, m) in VOLUMES.items() if m == 'coltxt'] == ['DCM_1999']


def test_every_edition_has_a_geographic_section():
    years = sorted({y for y, _, _ in VOLUMES.values()})
    assert years == [1961, 1962, 1965, 1966, 1967, 1968, 1970, 1971, 1973, 1974, 1976, 1977, 1979, 1980, 1982, 1983, 1984,
                     1985, 1986, 1988, 1990, 1992, 1993, 1999, 2002]


def test_sic_and_naics_index_volumes_excluded():
    assert not any(re.search(r'_SIC$|_NAICS$', v) and v != 'DCM_1962_part1_SIC' for v in VOLUMES)
    assert 'DCM_1968' not in VOLUMES          # duplicate of DCM_1968_part1


@pytest.fixture(scope='module')
def ocr_dirs():
    names = ocr_members()
    return {n.split('/')[1] for n in names if n.count('/') >= 2 and n.split('/')[0] in ('tsv', 'coltxt')}, \
           {(n.split('/')[0], n.split('/')[1]) for n in names if n.count('/') >= 2}


def test_every_volume_has_ocr_output(ocr_dirs):
    dirs, modes = ocr_dirs
    for vol, (_, _, mode) in VOLUMES.items():
        assert vol in dirs, f'{vol} missing from data/ocr'
        assert (mode, vol) in modes, f'{vol}: no {mode} output in data/ocr'


def test_ocr_pages_named_pNNN(ocr_dirs):
    names = [n for n in ocr_members() if n.endswith('.tsv')]
    assert names and all(re.fullmatch(r'tsv/[^/]+/p\d{3}\.tsv', n) for n in names)
