"""parse_block.py: ORG-line anchors, ZIP parsing, house-number digit map, mining-code street rejection, and a full
synthetic three-column page (1966-1986 block format) parsed to the expected records."""
import pytest
import parse_block as pb
from synth import page_words, write_tsv


# ---- ORG line (listing anchor) -------------------------------------------------------------------------------------
@pytest.mark.parametrize('line', [
    'CORP EST-1920 NTL 20-49',                 # classic: organisation, founding year, market, size
    'PART EST-1955 LOC EMP-10 TO 19',
    'S.PROP EST- STATE EMP-1 TO 9',           # blank founding year
    'SePROP EST- LOC EMP-1 TO 9',             # OCR 'SePROP' for S.PROP, blank year
    'EST- STATE EMP-1 TO 9',                  # organisation word lost, blank year
    'EMP-20 TO 49',                           # only the size survives, written EMP-a TO b
    'EMP 1000 OR MORE',
    'CORP 80201 826-1145',                    # 1970 layout: org word with ZIP and phone
    'SEPROP EST-1961 LOC 1-9',
])
def test_is_org_anchors(line):
    assert pb.is_org(line)


@pytest.mark.parametrize('line', [
    'ACME WIDGET CO',                          # a name
    '1234 BLAKE ST 80202 534-1234',            # a street line
    '3041 PLASTIC HOSE',                       # a SIC line
    'JOHN SMITH PRES',                         # an officer
    'ESTES PARK',                              # a city heading starting with EST
    'WESTERN ESTATES LAND CO',
])
def test_is_org_rejects_other_lines(line):
    assert not pb.is_org(line)


def test_parse_org_fields():
    d = pb.parse_org('SePROP EST- LOC EMP-1 TO 9')
    assert 'est' not in d and d['org'] == 'SEPROP' and d['market'] == 'LOC' and d['size'] == '1-9'
    d = pb.parse_org('CORP EST-1946 NTL EMP-20 TO 49')
    assert d['est'] == 1946 and d['org'] == 'CORP' and d['market'] == 'NTL' and d['size'] == '20-49'
    assert pb.parse_org('CORP EST-1S61 REG 1OO-249')['est'] == 1961      # OCR digits in the year
    assert pb.parse_org('CORP EST-1S61 REG 1OO-249')['size'] == '100-249'


# ---- ZIP ------------------------------------------------------------------------------------------------------------
@pytest.mark.parametrize('line,zip_', [
    ('4556 TENNYSON 8O22O 455-4705', '80220'),        # letters for digits are normalised
    ('2390 S DELAWARE 60223 744-0552', '80223'),       # a leading 6 is a misread 8
    ('707 & SOTH 80216 825-7645', '80216'),
    ('1234 BLAKE ST B0202 534-1234', '80202'),
    ('1377 S JASON 80209 777-3300', '80209'),
    ('P O BOX 1234 80201', '80201'),
    ('3631 TENNYSON 80002 429-1515', '80002'),
])
def test_parse_zip_accepts_colorado_zips(line, zip_):
    z = pb.parse_zip(line)
    assert z and z[0] == zip_
    assert line[z[1]:z[2]].strip() and z[1] > 0


@pytest.mark.parametrize('line', [
    '10401 W 120TH AVE',               # a 5-digit house number is not ZIP 80401
    '50303',
    'NEW YORK, NY 10036',              # out-of-state ZIPs are not forced to 80xxx
    'DES MOINES, IA 50303',
    'KANSAS CITY, MO 64108',
    'ACME WIDGET CO',
])
def test_parse_zip_rejects_house_numbers_and_other_states(line):
    assert pb.parse_zip(line) is None


def test_parse_zip_takes_the_last_zip_on_the_line():
    z = pb.parse_zip('10401 W 120TH AVE 80020 466-1822')
    assert z[0] == '80020' and z[1] == 18


# ---- house numbers ----------------------------------------------------------------------------------------------------
@pytest.mark.parametrize('street,fixed', [
    ('$12 ELIZABETH ST', '512 ELIZABETH ST'),     # $ and S in a house number are 5, not 9
    ('S065 W 38TH AVE', '5065 W 38TH AVE'),
    ('S20 ELIZABETH ST', '520 ELIZABETH ST'),
    ('E20 ELIZABETH', '120 ELIZABETH'),           # E is 1
    ('1S20 S WAZEE', '1520 S WAZEE'),
    ('1O1 S BROADWAY', '101 S BROADWAY'),
    ('805 W LITH AVE', '805 W 11TH AVE'),         # ordinal street numbers
    ('4377 PACKING HOUSE', '4377 PACKING HOUSE'),
    ('1331 CANNON', '1331 CANNON'),
])
def test_fix_street_house_number_map(street, fixed):
    assert pb.fix_street(street) == fixed


@pytest.mark.parametrize('street,fixed', [
    ('3250 Drennan Ind Loop', '3250 Drennan Ind Loop'),     # 'Ind' (industrial) is not '1ND'
    ('ROYAL GORGE IND PARK', 'ROYAL GORGE IND PARK'),
    ('5078 List Dr', '5078 List Dr'),                       # List Dr, Colorado Springs, not '11ST DR'
    ('17708 WELD CORD 78', '17708 WELD CORD 78'),           # county road, not '00RD'
    ('RED BIRD FARMS', 'RED BIRD FARMS'),
    ('6440 E BOTH AVE', '6440 E 80TH AVE'),                 # ... but 'BOTH' really is E 80th Ave (Commerce City)
    ('1050 LOTH', '1050 10TH'),
    ('714 S 61H ST', '714 S 6TH ST'),
])
def test_fix_street_keeps_street_words_that_look_like_ordinals(street, fixed):
    """The ordinal repair ('LITH' -> '11TH') must not rewrite real street words made of eight-like letters."""
    assert pb.fix_street(street) == fixed


def test_house_map_does_not_change_the_zip_and_sic_digit_map():
    assert pb.norm_digits('S0216') == '90216'        # DIGMAP still reads S as 9 ...
    assert pb.parse_zip('1234 BLAKE ST S0216 534-1234')[0] == '80216'   # ... and parse_zip forces the first digit to 8
    assert pb.parse_sic('3S99 MACHINE SHOPS')[0] == '3999'


# ---- SIC lines and mining codes ---------------------------------------------------------------------------------------
@pytest.mark.parametrize('desc', ['W 12TH AVE', 'FORD ST', 'ithaca Dr', 'S BROADWAY', 'BOX 123', 'E 56TH AVE', 'xx'])
def test_street_like(desc):
    assert pb.street_like(desc)


@pytest.mark.parametrize('desc', ['URANIUM-RADIUM-VANADIUM ORES', 'IRON ORES', 'COPPER ORES', 'GOLD + SILVER ORE MILLING'])
def test_not_street_like(desc):
    assert not pb.street_like(desc)


@pytest.mark.parametrize('line', ['1080 FORD ST', '1015 W 12TH AVE', '1145 ithaca Dr', '1400 W 44TH AVE'])
def test_parse_sic_rejects_mining_code_streets(line):
    assert pb.parse_sic(line) is None


@pytest.mark.parametrize('line,code', [
    ('1094 URANIUM-RADIUM-VANADIUM ORES', '1094'), ('1011 IRON ORES', '1011'), ('2011 MEAT PACKING PLANTS', '2011'),
    ('3011 TIRES + INNER TUBES', '3011'), ('7372 PREPACKAGED SOFTWARE', '7372'), ('28S1 PAINTS + VARNISHES', '2891'),
])
def test_parse_sic_accepts_codes(line, code):
    assert pb.parse_sic(line)[0] == code


@pytest.mark.parametrize('line', ['1234 BLAKE ST 80202 534-1234', '4000 WIDGETS 555-1234', '1800 SQ FT', '2011 ab'])
def test_parse_sic_rejects_addresses(line):
    assert pb.parse_sic(line) is None


# ---- a full synthetic page ----------------------------------------------------------------------------------------------
PAGE = [
    ['DENVER 23',                                  # page header: city + page number
     'ACME METAL PRODUCTS INC',
     '1234 BLAKE ST 80202 534-1234',
     'CORP EST-1946 NTL EMP-20 TO 49',
     'JOHN SMITH PRES',
     '3444 SHEET METAL WORK',
     '3469 METAL STAMPINGS',
     'BAKER PRINTING CO',
     '$12 ELIZABETH ST 80218 322-9876',
     'SePROP EST- LOC EMP-1 TO 9',                 # blank year, OCR'd organisation word: must still start a record
     '2752 COMMERCIAL PRINTING, LITHOGRAPHIC',
     'WESTERN CHEMICAL CO',
     '4556 TENNYSON 8O22O 455-4705',
     'CORP EST-1955 REG 10-19',
     '2899 CHEMICALS + CHEMICAL PREPS NEC'],
    ['',
     'FRONT RANGE FOUNDRY',
     '10401 W 120TH AVE 80020 466-1822',
     'PART EST-1961 LOC EMP-10 TO 19',
     '3369 NONFERROUS FOUNDRIES NEC',
     'ROCKY MTN SOFTWARE INC',
     '1500 S BROADWAY 80210 777-1000',
     'CORP EST-1975 NTL 1-9',
     '3573 PREPACKAGED SOFTWARE',
     'MILE HIGH MINING SUPPLY',
     '1080 FORD ST 80204 623-5555',
     'CORP EST-1920 NTL 20-49',
     '1080 FORD ST',                               # mailing line: a house number in the mining-code range, not SIC 1080
     '3532 MINING MACHINERY'],
    ['',
     'PLATTE VALLEY PACKING',
     '707 & 50TH 80216 825-7645',
     'CORP EST-1930 REG 100-249',
     '2011 MEAT PACKING PLANTS',
     'GARDEN STATE PLASTICS',
     '2200 W ALAMEDA AVE 80223 935-2485',
     'GRBLD XXXX ZZZ',                             # ORG line garbled beyond recognition: street+phone starts the record
     '3079 MISC PLASTICS PRODUCTS',
     '3089 PLASTICS PRODUCTS NEC',
     'LAST WIDGET CO',
     '999 SANTA FE DR 80204 555-1212',
     'CORP EST-1950 LOC 1-9',
     '3999 MANUFACTURING INDUSTRIES NEC'],
]


@pytest.fixture(scope='module')
def page_records(tmp_path_factory):
    d = tmp_path_factory.mktemp('tsv')
    (d / 'SYN_1977').mkdir()
    write_tsv(d / 'SYN_1977' / 'p023.tsv', page_words(PAGE))
    return pb.parse_volume('SYN_1977', str(d), 1977)


def test_synthetic_page_record_count_and_order(page_records):
    names = [r['name'] for r in page_records]
    assert names == ['ACME METAL PRODUCTS INC', 'BAKER PRINTING CO', 'WESTERN CHEMICAL CO',
                     'FRONT RANGE FOUNDRY', 'ROCKY MTN SOFTWARE INC', 'MILE HIGH MINING SUPPLY',
                     'PLATTE VALLEY PACKING', 'GARDEN STATE PLASTICS', 'LAST WIDGET CO']
    assert all(r['page'] == 23 and r['vol'] == 'SYN_1977' and r['year'] == 1977 for r in page_records)
    assert [r['col'] for r in page_records] == [0, 0, 0, 1, 1, 1, 2, 2, 2]


def by_name(recs, name):
    return next(r for r in recs if r['name'] == name)


def test_synthetic_page_fields(page_records):
    acme = by_name(page_records, 'ACME METAL PRODUCTS INC')
    assert (acme['street'], acme['zip'], acme['sic'], acme['est'], acme['size'], acme['org'], acme['market']) == \
           ('1234 BLAKE ST', '80202', ['3444', '3469'], 1946, '20-49', 'CORP', 'NTL')
    assert acme['sic_desc'] == ['SHEET METAL WORK', 'METAL STAMPINGS']
    assert acme['extra'] == ['JOHN SMITH PRES']
    assert acme['city_ctx'] == 'DENVER' and acme['county_ctx'] == 'DENVER'   # from the page header
    baker = by_name(page_records, 'BAKER PRINTING CO')
    assert (baker['street'], baker['zip'], baker['sic'], baker.get('est'), baker['size']) == ('512 ELIZABETH ST', '80218', ['2752'], None, '1-9')
    western = by_name(page_records, 'WESTERN CHEMICAL CO')
    assert (western['street'], western['zip'], western['sic']) == ('4556 TENNYSON', '80220', ['2899'])
    front = by_name(page_records, 'FRONT RANGE FOUNDRY')
    assert (front['street'], front['zip'], front['sic'], front['est']) == ('10401 W 120TH AVE', '80020', ['3369'], 1961)
    mile = by_name(page_records, 'MILE HIGH MINING SUPPLY')
    assert mile['sic'] == ['3532'] and '1080 FORD ST' in mile['extra']
    platte = by_name(page_records, 'PLATTE VALLEY PACKING')
    assert (platte['street'], platte['zip'], platte['sic'], platte['size']) == ('707 & 50TH', '80216', ['2011'], '100-249')
    garden = by_name(page_records, 'GARDEN STATE PLASTICS')
    assert (garden['street'], garden['zip'], garden['sic']) == ('2200 W ALAMEDA AVE', '80223', ['3079', '3089'])
    assert garden['org_raw'] == '' and 'GRBLD XXXX ZZZ' in garden['extra']
    last = by_name(page_records, 'LAST WIDGET CO')
    assert (last['street'], last['zip'], last['sic'], last['est']) == ('999 SANTA FE DR', '80204', ['3999'], 1950)


def test_synthetic_page_no_code_leaks_between_records(page_records):
    codes = [c for r in page_records for c in r['sic']]
    assert sorted(codes) == sorted(['3444', '3469', '2752', '2899', '3369', '3573', '3532', '2011', '3079', '3089', '3999'])
    assert all(r['zip'].startswith('80') for r in page_records)


def test_join_wrapped():
    """1970 layout: an indented continuation line is glued to the line above (unless it is a ZIP, phone or SIC line)."""
    pl = [dict(col=0, y=100, x=60, text='285 RIO GRANDE'), dict(col=0, y=120, x=130, text='BLVD'),
          dict(col=0, y=150, x=60, text='CORP EST-1920 80002 421-5123'), dict(col=0, y=170, x=130, text='2011 MEAT PACKING'),
          dict(col=0, y=200, x=60, text='A'), dict(col=0, y=230, x=60, text='B'), dict(col=0, y=260, x=60, text='C')]
    out = pb.join_wrapped(pl)
    assert [l['text'] for l in out] == ['285 RIO GRANDE BLVD', 'CORP EST-1920 80002 421-5123', '2011 MEAT PACKING', 'A', 'B', 'C']
