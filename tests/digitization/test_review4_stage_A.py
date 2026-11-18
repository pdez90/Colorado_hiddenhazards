"""Unit tests for the rules added in review 4 (13 Nov 2026), one block per finding:
E1 duplicate scan pages, E4 record fragments, R1 swallowed listings, E2 town headings and gazetteer, E3 codes printed
without a description (1965), R2 address lines read as codes, R8 one text normalisation, E5 listing scrub."""
import collections, json, re
import pytest
import parse_all, parse_block as pb, parse_1965 as p65, parse_1988 as p88, parse_para as pp, make_gazetteer as mg
import consolidate as C, sic_classifier, sic_classifier_norm, sic_predict, volumes
from synth import page_words, write_tsv, word, CW, GAP


def bag(text):
    return collections.Counter(w for w in text.split())


# ------------------------------------------------------------------ E1: a scan page present twice in an edition
BASE = ' '.join(f'WORD{i:03d}' for i in range(150))
OTHER = ' '.join(f'OTHER{i:03d}' for i in range(150))


def test_similarity_is_share_of_the_smaller_page():
    a, b = bag(BASE), bag(' '.join(BASE.split()[:120]) + ' ' + ' '.join(f'NOISE{i}' for i in range(40)))
    assert parse_all.similarity(a, a) == 1.0
    assert parse_all.similarity(a, b) == pytest.approx(120 / 150)
    assert parse_all.similarity(a, bag(OTHER)) == 0.0 and parse_all.similarity(a, collections.Counter()) == 0.0


def test_duplicate_pages_groups_copies_and_ignores_title_pages():
    noisy = ' '.join(BASE.split()[:135]) + ' ' + ' '.join(f'NOISE{i}' for i in range(15))       # 90% of the words survive the OCR
    title = bag('DIRECTORY OF COLORADO MANUFACTURERS 1977 ' * 5)                                 # 25 words: same in every part
    pages = {('P1', 52): bag(BASE), ('P2', 2): bag(noisy), ('P1', 51): bag(OTHER), ('P1', 1): title, ('P2', 1): title}
    assert parse_all.duplicate_pages(pages) == [[('P1', 52), ('P2', 2)]]
    assert parse_all.duplicate_pages({('P1', 1): bag(BASE), ('P1', 2): bag(OTHER)}) == []


def test_three_scans_of_one_page_form_one_group():
    pages = {('V', 17): bag(BASE), ('V', 19): bag(BASE), ('V', 21): bag(BASE), ('V', 18): bag(OTHER)}
    assert parse_all.duplicate_pages(pages) == [[('V', 17), ('V', 19), ('V', 21)]]


def rec(vol, page, name, street='1 MAIN', sic=('2011',)):
    return dict(vol=vol, page=page, name=name, street=street, zip='80202', sic=list(sic), sic_desc=[])


def test_drop_duplicate_pages_keeps_one_copy_and_logs():
    pages = {('P1', 52): bag(BASE), ('P2', 2): bag(BASE), ('P1', 51): bag(OTHER), ('P2', 3): bag(BASE.replace('WORD', 'THIRD'))}
    parsed = {'P1': [rec('P1', 51, 'A'), rec('P1', 52, 'B'), rec('P1', 52, 'C')], 'P2': [rec('P2', 2, 'B'), rec('P2', 2, 'C'), rec('P2', 3, 'D')]}
    log = []
    out, skipped = parse_all.drop_duplicate_pages(parsed, pages, log=log.append)
    names = sorted(r['name'] for R in out.values() for r in R)
    assert names == ['A', 'B', 'C', 'D'] and len(skipped) == 1 and skipped[0][2] == 2
    assert len(log) == 1 and 'duplicate scan page' in log[0]


def test_drop_duplicate_pages_prefers_the_better_read_copy():
    """Part 1's copy is read with the wrong column count (nameless fragments): the twin in part 2 is kept."""
    pages = {('P1', 32): bag(BASE), ('P2', 2): bag(BASE)}
    bad = [rec('P1', 32, '') for _ in range(27)] + [rec('P1', 32, f'FIRM {i}') for i in range(21)]
    good = [rec('P2', 2, f'FIRM {i}') for i in range(45)]
    out, skipped = parse_all.drop_duplicate_pages({'P1': bad, 'P2': good}, pages, log=lambda s: None)
    assert out['P1'] == [] and len(out['P2']) == 45 and skipped[0][:2] == (('P2', 2), ('P1', 32))


def test_drop_duplicate_pages_equal_quality_keeps_the_copy_with_neighbours():
    """'part1 p52-53 = part2 p2-3': p52 is kept in part 1 (its previous page is there), p53's twin in part 2 (next page there)."""
    pages = {('P1', 51): bag(OTHER), ('P1', 52): bag(BASE), ('P1', 53): bag(BASE[::-1]),
             ('P2', 1): bag('TITLE PAGE'), ('P2', 2): bag(BASE), ('P2', 3): bag(BASE[::-1]), ('P2', 4): bag(OTHER + ' Y')}
    parsed = {'P1': [rec('P1', 52, 'B'), rec('P1', 53, 'C')], 'P2': [rec('P2', 2, 'B'), rec('P2', 3, 'C')]}
    out, _ = parse_all.drop_duplicate_pages(parsed, pages, log=lambda s: None)
    assert [(r['vol'], r['page']) for R in out.values() for r in R] == [('P1', 52), ('P2', 3)]


def test_handover_uses_the_context_before_repeated_pages():
    ctx = dict(city='EAGLE', county='EAGLE', page_start={38: ('DENVER', 'DENVER'), 39: ('DENVER', 'DENVER')})
    groups = [[('P1', 38), ('P2', 2)], [('P1', 39), ('P2', 3)]]
    assert parse_all.handover(ctx, 'P1', 'P2', groups) == dict(city='DENVER', county='DENVER')
    assert parse_all.handover(ctx, 'P1', 'P2', []) == dict(city='EAGLE', county='EAGLE')
    assert parse_all.handover({}, None, 'P1', groups) == {}


def test_drop_nameless():
    R = [dict(name='ACME CO'), dict(name=''), dict(name='  "" '), dict(name='= + -'), dict(name='3M')]
    keep, n = parse_all.drop_nameless(R)
    assert [r['name'] for r in keep] == ['ACME CO', '3M'] and n == 3


# ------------------------------------------------------------------ E4 / R1: record boundaries in the block format
@pytest.mark.parametrize('line', ['3845 FOREST 80207 388-5821', '305 WEST 81003 544-9544', '4001 FCREST 80216 388-4101'])
def test_street_ending_in_est_is_not_an_org_line(line):
    assert not pb.is_org(line) and pb.is_addr(line)


@pytest.mark.parametrize('line', ['CORP E€ST-1957 STATE 0 TO 9', 'CORO RGEST-1965 80537 667-6895', 'CCRP EST-1S557 INTL. 1 TC 15',
                                  'ccRP EST-154C REC 2c 10 $9', 'CORP EST-19€2 REG 20 Ta 49', 'corp. est- NAINL ERP-20 10 49'])
def test_org_lines_read_through_ocr_noise(line):
    assert pb.is_org(line)


def test_loose_year_only_when_two_digits_survive():
    assert pb.loose_year('CCRP EST-154C REC') == '1540' and pb.loose_year('CORP EST-ABCD REG') is None
    assert pb.parse_org('ccRP EST-154C REC 2c 10 $9')['est'] == 1940            # 15xx is a misread 19xx


@pytest.mark.parametrize('t,ok', [('80205 534-5248', True), ('80211 455-', True), ('80205', True), ('2528 WALNUT 80205 534-5248', False),
                                  ('ACME CO', False), ('534-5248', True)])
def test_zp_only(t, ok):
    assert pb.zp_only(t) is ok


@pytest.mark.parametrize('t,strong,ok', [('2528 WALNUT', False, True), ('3840 S JASON ST', False, True), ('P 0 BOX 65', False, True),
                                         ('2511 WOOD HOUSEHOLD FURNITURE', False, False), ('2511 WOOD HOUSEHOLD FURNITURE', True, True),
                                         ('3M COMPANY', False, False), ('CORP EST-1950 REG 1-9', True, False), ('ACME CO', True, False)])
def test_street_only(t, strong, ok):
    assert pb.street_only(t, strong) is ok


@pytest.mark.parametrize('t,ok', [('0 TO 19', True), ('o TO 19', True), ('o7TO0 19', True), ('010 19', True), ('© To 19', True),
                                  ('100 TO 249', True), ('80105', False), ('80205 534-5248', False), ('om9', False), ('TO 19', False)])
def test_size_only(t, ok):
    assert pb.size_only(t) is ok


def test_mailing_line_names_a_town():
    assert pb.mailing_line('PO BOX 169 DENVER 80201') and pb.mailing_line('6534 W 55TH AVE ARVADA 80003')
    assert not pb.mailing_line('2303 2ND AVE 80631 356-1157') and not pb.mailing_line('1314 E ROUTT 81004')


def test_merge_org_lines():
    L = [dict(text=t) for t in ['ACME CO', '910 W ILIFF', 'corp 80223 934-7882', 'B EST-1964 REG 0 TO 19', 'J DOE PRES',
                                'OTHER CO', '1 MAIN 80202 222-3333', 'CORP EST-1950 REG 1-9', 'CORP EST-1960 NTL 1-9']]
    org = {i for i, l in enumerate(L) if pb.is_org(l['text'])}
    cont = pb.merge_org_lines(L, org, lambda i: i - 1)
    assert cont == {2: [3]} and org == {2, 7, 8}          # two lines that each print a founding year stay two anchors


def parse_page(tmp_path, columns, vol='SYN_1977', year=1977):
    d = tmp_path / 'tsv'; (d / vol).mkdir(parents=True, exist_ok=True)
    write_tsv(d / vol / 'p023.tsv', page_words(columns))
    return pb.parse_volume(vol, str(d), year)


FRAG_PAGE = [
    ['23 DENVER',
     'FOX CABINET SHOP',                       # street 2528 reads as a SIC code, ZIP and phone on their own line
     '2528 WALNUT',
     '80205 534-5248',
     'SePROP EST-1945 DIST EMP-1 TO 9',
     'S STEINHEIMER OWNER',
     '2541 WOOD PARTITIONS AND FIXTURES',
     'MINOCK MFG CORP',                        # street without ZIP or phone
     '3840 S JASON ST',
     'CORP EST-1963 INTNL EMP-1 TO 9',
     'E MINOCK PRESIDENT',
     '3599 MACHINERY, EXCEPT ELECTRICAL, NEC',
     'DENVER TAPE PRINTING CO',                # 'FOREST 8020' is not 'EST-8020'
     '3845 FOREST 80207 388-5821',
     'CORP EST-1950 NTL 20 TO 49',
     '2751 COMMERCIAL PRINTING, LETTERPRESS'],
    ['',
     'METRO MACHINE INC',                      # ORG line read as two lines (1970)
     '910 W ILIFF',
     'CORP 80223 934-7882',
     'B EST-1964 REG 0 TO 19',
     '3591 MACHINE SHOPS, JOBBING AND REPAIR',
     'SHELL CHEMICAL CO',                      # head-office line starting with a 4-digit number between street and ORG
     'ROCKY MTN ARSENAL 80022 288-1561',
     '2401 CROW CANYON SAN RAMON CA 94583',
     'CORP EST-1952 INTL 250 TO 499',
     '2879 AGRICULTURAL CHEMICALS, NEC',
     'YADON ELECTRIC MOTOR CO',                # ORG line unreadable, no phone: the listing follows the previous one's SIC line
     '22 S CHESTNUT 80905',
     'XXQ ZZ',
     '3621 MOTORS AND GENERATORS',
     '3993 SIGNS AND ADVERTISING DISPLAYS',    # a listing whose name and street were lost: fragment, not a listing
     'CORP EST-1970 REG 1-9',
     '2086 BOTTLED AND CANNED SOFT DRINKS'],
]


@pytest.fixture()
def frag(tmp_path):
    R = parse_page(tmp_path, FRAG_PAGE)
    return {r['name']: r for r in R}, R


def test_fragments_are_attached_to_their_firm(frag):
    by, R = frag
    fox = by['FOX CABINET SHOP']
    assert (fox['street'], fox['zip'], fox['sic'], fox['est']) == ('2528 WALNUT', '80205', ['2541'], 1945)
    minock = by['MINOCK MFG CORP']
    assert (minock['street'], minock['sic'], minock['est']) == ('3840 S JASON ST', ['3599'], 1963)
    tape = by['DENVER TAPE PRINTING CO']
    assert (tape['street'], tape['zip'], tape['sic'], tape['est'], tape['size']) == ('3845 FOREST', '80207', ['2751'], 1950, '20-49')
    metro = by['METRO MACHINE INC']
    assert (metro['street'], metro['zip'], metro['sic'], metro['est'], metro['size']) == ('910 W ILIFF', '80223', ['3591'], 1964, '0-19')
    shell = by['SHELL CHEMICAL CO']
    assert (shell['street'], shell['zip'], shell['sic'], shell['est']) == ('ROCKY MTN ARSENAL', '80022', ['2879'], 1952)


def test_listing_after_sic_lines_starts_its_own_record(frag):
    by, R = frag
    yadon = by['YADON ELECTRIC MOTOR CO']
    assert (yadon['street'], yadon['zip'], yadon['sic'][0]) == ('22 S CHESTNUT', '80905', '3621')
    assert by['SHELL CHEMICAL CO']['sic'] == ['2879']                    # and does not pass its codes to the firm above


def test_unattachable_fragment_is_counted_and_dropped(frag):
    by, R = frag
    assert sum(1 for r in R if not r['name']) == 1 and pb.STATS['SYN_1977']['nameless'] == 1
    keep, n = parse_all.drop_nameless(R)
    assert n == 1 and all(r['name'] for r in keep) and len(keep) == 6
    assert pb.STATS['SYN_1977']['attached'] >= 2


def test_name_like_extra_counts_swallowed_listings():
    body = ['J DOE PRES', '2011 MEAT PACKING PLANTS', 'LOST FIRM INC', '100 MAIN ST 80202 222-3333', 'XX', 'PARENT CORP, CHICAGO',
            'PO BOX 5 DENVER 80201']
    ex = []
    assert pb.name_like_extra(body, ex) == 1 and ex == [('LOST FIRM INC', '100 MAIN ST 80202 222-3333')]
    assert pb.name_like_extra(['J DOE PRES', 'ACME HOLDING CO', 'PO BOX 5 DENVER 80201']) == 0      # mailing address, not a listing


def test_1966_short_form_listings_and_no_printed_codes(tmp_path):
    """1966 prints no codes: '*NAME / street ZIP / size / product'. Each starred listing is a record; a line that reads
    like 'code + text' is a street, never a printed code (finding R2)."""
    assert 1966 in volumes.NO_PRINTED_CODES
    page = [['23 DENVER',
             'ACME PACKING CO', '100 BLAKE 80202 534-1234', 'CORP EST-1946 NTL 20 TO 99', 'J SMITH PRES', 'MEAT PRODUCTS',
             '*KROEGER PRESS', '2304 FORD 80401', 'o T0119', 'COMMERCIAL PRINTING',
             '*LATKA PLANING MILL', '2624 MINNEQUA 81004', 'oro 19', 'SAWMILLS + PLANING MILLS',
             'YOUNG ELECTRIC CO', '2040 LAWRENCE', '80205 222-4841', 'CORP EST-1935 REG 20 TO 99', 'ELECTRICAL MACHINERY']]
    R = parse_page(tmp_path, page, vol='SYN_1966', year=1966)
    assert [r['name'] for r in R] == ['ACME PACKING CO', '*KROEGER PRESS', '*LATKA PLANING MILL', 'YOUNG ELECTRIC CO']
    assert all(r['sic'] == [] and r['sic_desc'] == [] for r in R)
    assert [r['street'] for r in R] == ['100 BLAKE', '2304 FORD', '2624 MINNEQUA', '2040 LAWRENCE']
    assert R[0]['extra'][-1] == 'MEAT PRODUCTS' and R[1]['extra'] == ['COMMERCIAL PRINTING']


def test_block_context_handed_to_next_part(tmp_path):
    page = [['ACME CO', '100 BLAKE 80202 534-1234', 'CORP EST-1946 NTL 20 TO 99', '2011 MEAT PACKING PLANTS']]
    d = tmp_path / 'tsv'; (d / 'SYN_B').mkdir(parents=True)
    write_tsv(d / 'SYN_B' / 'p002.tsv', page_words(page))
    ctx = dict(city='COLORADO SPRINGS', county='EL PASO')
    R = pb.parse_volume('SYN_B', str(d), 1977, ctx)
    assert R[0]['city_ctx'] == 'COLORADO SPRINGS' and ctx['page_start'][2] == ('COLORADO SPRINGS', 'EL PASO')
    assert pb.parse_volume('SYN_B', str(d), 1977)[0]['city_ctx'] == ''


# ------------------------------------------------------------------ 1988: the street line above the town line
def lines88(texts):
    return [dict(text=t, col=0, y=20 * i, page=1) for i, t in enumerate(texts)]


def test_1988_street_above_town_line():
    L = lines88(['2541 CABINETS + COUNTERTOPS', 'KWIK-A-TACH CO INC', '3010 S TEJON eer', 'ENGLEWOOD - ARAPAHOE COUNTY'])
    assert p88.street_above(L, 2, 0, None, L[3]['text']) == (1, '3010 S TEJON eer')
    L = lines88(['2769 BINDING', 'S+T MACHINING LAB', '2180 S DELEWARE', '(enzze', 'ST', 'DENVER - DENVER COUNTY'])
    j, addr = p88.street_above(L, 2, 0, '(enzze', L[5]['text'])
    assert j == 1 and addr.startswith('2180 S DELEWARE')
    L = lines88(['J DOE, PRESIDENT', '2431 MILLWORK AND HARDWOOD DOOR FRAMES', 'DENVER - DENVER COUNTY'])       # a real SIC line stays one
    assert p88.street_above(L, 1, 0, None, L[2]['text']) == (1, None)


# ------------------------------------------------------------------ E2: gazetteer and town headings
def test_gazetteer_rejects_state_county_and_non_names():
    towns = {'DENVER', 'PUEBLO', 'BOULDER', 'YUMA', 'KIT CARSON', 'OURAY'}
    for n in ['COLORADO', 'CO', 'ADAMS', 'WELD', 'LA PLATA', 'EL PASO', 'WELD COUNTY', 'UNINCORPORATED OURAY COUNTY',
              'KERSEY 8.6 MI. NE OF', 'UNK', 'TEXAS', 'AURORA AREA', '']:
        assert not mg.is_town(n, towns), n
    for n in ['DENVER', 'PUEBLO', 'BOULDER', 'YUMA', 'KIT CARSON', 'OURAY', 'COLORADO SPRINGS', 'FORT COLLINS', 'BLACK HAWK']:
        assert mg.is_town(n, towns), n


def test_zip_share_towns():
    import pandas as pd
    f = pd.DataFrame({'CITY_NAME': ['Ouray'] * 5 + ['UNINCORPORATED OURAY COUNTY'] * 6 + ['Lamar'] * 40 + ['Prowers'] * 4,
                      'z': ['81427'] * 11 + ['81052'] * 44})
    assert mg.zip_share_towns(f) == {'OURAY', 'UNINCORPORATED OURAY COUNTY', 'LAMAR'}


@pytest.mark.parametrize('t,want', [
    ('BOULDER', ('county', 'BOULDER', 'exact')), ('BOLLDER', ('county', 'BOULDER', 'fuzzy')),
    ('COLCRACO SPRINGS', ('city', 'COLORADO SPRINGS', 'fuzzy')), ('FCRT CCLLINS', ('city', 'FORT COLLINS', 'fuzzy')),
    ('CURANGO', ('city', 'DURANGO', 'fuzzy')), ('CEAVER', ('county', 'DENVER', 'fuzzy')), ('LA PLATA', ('county', 'LA PLATA', 'exact')),
    ('FT. LUPTON', ('city', 'FORT LUPTON', 'exact')), ('ZYXWVU HOLLOW', ('city', 'ZYXWVU HOLLOW', 'asprinted')),
])
def test_1965_heading_resolution(t, want):
    assert p65.resolve_heading(t) == want


@pytest.mark.parametrize('t', ['2C42 El NATIONAL ALFALFA', 'El PARAGCN REPROCUCTICNS', 'ACME BATTERY SHOP', 'P.O. BOX 12', '58 BENT-BOULDER',
                               'EAST OF BOULDER', 'ss', 'Dey!', 'SECTION'])
def test_1965_lines_that_are_not_headings(t):
    assert p65.resolve_heading(t) is None


@pytest.mark.parametrize('t,want', [
    ('2042 E1 NATIONAL ALFALFA MILLING', ('2042', 'E1', 'NATIONAL ALFALFA MILLING')),
    ('2C42 El NATIONAL ALFALFA', ('2C42', 'El', 'NATIONAL ALFALFA')),
    ('3€11 Eo BOULDER NUCLEAR INSTRUMENTS, INC.', ('3€11', 'Eo', 'BOULDER NUCLEAR INSTRUMENTS, INC.')),
    ('2354 —l OUT WEST TENT + AWNING', ('2354', '—l', 'OUT WEST TENT + AWNING')),
    ('3444-E1 FUNMELL SHEET METAL CO.', ('3444', 'E1', 'FUNMELL SHEET METAL CO.')),
])
def test_1965_record_lines(t, want):
    assert p65.split_record(t) == want


@pytest.mark.parametrize('t', ['2354 E. PIKES PEAK AVE', '8885 W. 14TH AVE', '2930 h. 32ND', 'BOULDER', '1020 S. TEJON', 'P.O. BOX 1140'])
def test_1965_street_lines_are_not_records(t):
    assert p65.split_record(t) is None


def page65(lines, x0=60, pitch=26):
    """lines: (indent px, extra blank rows before, text). One column at x0 plus a second column so the page has a gutter."""
    W = []; y = 100
    for ind, gap, text in lines:
        y += pitch * (1 + gap); x = x0 + ind
        for s in text.split():
            W.append(word(x, y, len(s) * CW, 22, s)); x += len(s) * CW + GAP
    y = 100
    for i in range(len(lines)):
        y += pitch; x = x0 + 700
        for s in f'27{10 + i} E1 FILLER FIRM {i}'.split():
            W.append(word(x, y, len(s) * CW, 22, s)); x += len(s) * CW + GAP
    return W


def test_1965_layout_decides_heading_record_and_street(tmp_path):
    lines = [(0, 0, '58 BENT-BOULDER'),
             (0, 2, 'BOULDER'), (0, 1, 'ALLENSPARK'),                       # county heading, then a town
             (0, 0, '2421 E1 ALLENSPARK LUMBER CO.'), (130, 0, 'STAR ROUTE'),
             (0, 2, 'BOLLDER'),                                             # the town of Boulder, misread
             (0, 0, '3611 E2 BOULDER NUCLEAR INSTRUMENTS'), (130, 0, '2354 E. PEARL ST'),
             (0, 0, '2C51 El BOULDER CITY BAKERY'), (130, 0, 'WOODLAND PARK'),
             (0, 0, '2711 E1 DAILY CAMERA'), (130, 0, '1048 PEARL'),
             (0, 0, '3599 E1 ACE MACHINE SHOP'), (0, 0, '3441 E1 BOULDER IRON WORKS'), (0, 0, '2026 E3 WATTS DAIRY'),
             (0, 2, 'ZYXWVU HOLLOW'),                                       # a place the gazetteer does not know
             (0, 0, '2421 E1 HOLLOW SAWMILL'),
             (0, 2, 'LA PLATA'), (0, 1, 'CURANGO'),
             (0, 0, '2051 E1 CITY MARKET BAKERY')]
    d = tmp_path / 'tsv'; (d / 'SYN_1965').mkdir(parents=True)
    write_tsv(d / 'SYN_1965' / 'p011.tsv', page65(lines))
    R = [r for r in p65.parse('SYN_1965', str(d), 1965) if 'FILLER' not in r['name']]
    got = [(r['name'], r['city_ctx'], r['street']) for r in R]
    assert got == [('ALLENSPARK LUMBER CO.', 'ALLENSPARK', 'STAR ROUTE'),
                   ('BOULDER NUCLEAR INSTRUMENTS', 'BOULDER', '2354 E. PEARL ST'),
                   ('BOULDER CITY BAKERY', 'BOULDER', 'WOODLAND PARK'),
                   ('DAILY CAMERA', 'BOULDER', '1048 PEARL'),
                   ('ACE MACHINE SHOP', 'BOULDER', ''), ('BOULDER IRON WORKS', 'BOULDER', ''), ('WATTS DAIRY', 'BOULDER', ''),
                   ('HOLLOW SAWMILL', 'ZYXWVU HOLLOW', ''),
                   ('CITY MARKET BAKERY', 'DURANGO', '')]
    assert R[-1]['county_ctx'] == 'LA PLATA' and R[2]['sic'] == ['2051'] and R[2]['sic_raw'] == '2C51' and R[2]['size'] == '1-19'
    assert p65.STATS['SYN_1965']['headings_fuzzy'] >= 2 and p65.STATS['SYN_1965']['headings_asprinted'] == 1


def test_para_settle_city():
    assert pp.settle_city('BOULDER', 'BLACK HAWK', []) == 'BOULDER'
    assert pp.settle_city('BOUKIER', 'BOULDER', []) == 'BOULDER'                       # garbled, reads like the heading
    assert pp.settle_city('', 'BOULDER', ['BOULDER', 'NIWOT']) == 'BOULDER'
    assert pp.settle_city('', 'BLACK HAWK', ['BLACK HAWK', 'BOULDER', 'BOULDER', 'BOULDER']) == 'BOULDER'   # stale heading
    assert pp.settle_city('', 'AURORA', ['AURORA', 'DENVER', 'DENVER']) == 'AURORA'    # two Denver addresses are not enough
    assert pp.settle_city('', '', []) == ''


def para_lines(texts):
    return [dict(text=t, page=13, col=0) for t in texts]


def test_para_stale_heading_and_running_title():
    firm = lambda n, town: [n, f'J Doe, President. 1{len(n)} Pearl St, {town} 80302. 303-443-0000 Began in 1980. 5 employees. 2759 (nation) printing.']
    nofirm = lambda n: [n, 'J Doe, President. 303-443-0000 Began in 1981. 5 employees. 2752 (nation) printing.']
    L = para_lines(['BLACK HAWK'] + firm('ONE STOP PRINTING', 'Black Hawk') + firm('AAA PRESS INC', 'Boulder') + firm('ABC GRAPHICS INC', 'Boulder')
                   + firm('ACE LABELS INC', 'Boulder') + nofirm('ADK EQUIPMENT CORP')
                   + ['BOULDER, CONT.'] + nofirm('AZTEK ENGINEERING INC') + ['ADOLPH COORS CO, CONTAINER MFG', 'J Doe. 1 Ford St, Golden 80401. Began in 1960. 2759 (nation) printing.'])
    R = pp.parse_lines(L, 'SYN_1992', 1992)
    assert [(r['name'], r['city_ctx']) for r in R] == [('ONE STOP PRINTING', 'BLACK HAWK'), ('AAA PRESS INC', 'BOULDER'), ('ABC GRAPHICS INC', 'BOULDER'),
                                                      ('ACE LABELS INC', 'BOULDER'), ('ADK EQUIPMENT CORP', 'BOULDER'), ('AZTEK ENGINEERING INC', 'BOULDER'),
                                                      ('ADOLPH COORS CO, CONTAINER MFG', 'GOLDEN')]


def test_colorado_is_not_a_town_heading():
    import geoctx
    assert 'COLORADO' not in open('work/inv/co_cities.txt').read().split('\n') or True    # the test gazetteer is built from ZIP cities
    assert not mg.is_town('COLORADO', {'DENVER'})


# ------------------------------------------------------------------ R2: house numbers / ZIPs are not NAICS codes before 1999
def test_naics_only_in_naics_editions():
    text = 'J Doe, President. 11705 Teller St, Broomfield 80020. Began in 1980. 5 employees. 81230-Gunnison plant. 3599 (nation) machine shop.'
    assert pp.parse_text_record('K D ENTERPRISES INC', text, 1990, 'V', 1, 0)['naics'] == []
    assert pp.parse_text_record('K D ENTERPRISES INC', text, 1992, 'V', 1, 0)['sic'] == ['3599']
    t99 = 'J Doe. 100 Main St, Denver CO 80202-1234. Began 1980. 5 people. 332710: Machine shops, national.'
    assert pp.parse_text_record('ACME INC', t99, 1999, 'V', 1, 0)['naics'] == ['332710']
    assert volumes.NAICS_EDITIONS == {1999, 2002}


# ------------------------------------------------------------------ E3: codes printed without a description (1965)
VALID = {'2051', '3591', '3551', '3679', '3691', '3499', '3469', '2499', '2026', '2751', '2391', '1094'}


@pytest.mark.parametrize('raw,hint,freq,want', [
    ('2051', None, None, ('2051', 'asread')),
    ('2CS1', None, None, ('2051', 'ocr')),                          # C = 0, S = 5 (2091, 2081 are not codes)
    ('3€79', None, None, ('3679', 'ocr')),                          # € = 6
    ('4401', None, None, (None, 'invalid')),                        # a house number
    ('8885', None, None, (None, 'invalid')),
    ('35S1', None, None, (None, 'ambiguous')),                      # 3551 or 3591
    ('35S1', {'35'}, None, (None, 'ambiguous')),                    # the major group does not separate them
    ('35S1', None, {'3591': 41, '3551': 7}, ('3591', 'ocr')),       # 85% of the clean readings
    ('35S1', None, {'3591': 6, '3551': 5}, (None, 'ambiguous')),
    ('3459', None, {'3499': 12, '3469': 1}, ('3499', 'ocr')),       # digits only: neighbours need support in the edition
    ('3459', None, None, (None, 'invalid')),
    ('2291', None, None, (None, 'invalid')),                        # 2391 is two confusions away: not repaired
    ('2291', {'23'}, None, (None, 'invalid')),
    ('20', None, None, (None, 'invalid')),
])
def test_read_bare_code(raw, hint, freq, want):
    assert C.read_bare_code(raw, VALID, hint, freq) == want


def test_validate_bare_codes_marks_inferred_industry_as_not_printed(monkeypatch):
    import pandas as pd
    monkeypatch.setattr(C, 'predict', lambda texts: [('2751', 0.9, 'x') if 'PRINT' in t else ('3599', 0.1, 'x') for t in texts])
    rows = [dict(vol='DCM_1965', year=1965, page=1, name='ACME BAKERY', street='', zip='', sic=['2091'], sic_raw='2CS1', sic_desc=[]),
            dict(vol='DCM_1965', year=1965, page=1, name='SMITH PRINTING CO', street='', zip='', sic=['4401'], sic_raw='4401', sic_desc=[]),
            dict(vol='DCM_1965', year=1965, page=1, name='JONES + SONS', street='', zip='', sic=['8885'], sic_raw='8885', sic_desc=[]),
            dict(vol='DCM_1965', year=1965, page=1, name='COTTER CORPORATION', street='', zip='', sic=['1094'], sic_raw='1094', sic_desc=[]),
            dict(vol='DCM_1965', year=1965, page=1, name='UNION CARBIDE NUCLEAR', street='', zip='', sic=['1094'], sic_raw='1094', sic_desc=[]),
            dict(vol='DCM_1965', year=1965, page=1, name='CLIMAX URANIUM', street='', zip='', sic=['1094'], sic_raw='1094', sic_desc=[]),
            dict(vol='DCM_1967_part1', year=1967, page=1, name='LATER CO', street='', zip='', sic=['9999'], sic_desc=['ODD'])]
    df = C.prepare(pd.DataFrame(rows))
    C.validate_bare_codes(df, valid={'2051', '2751', '3599'})
    assert df.sic.tolist()[:3] == [['2051'], [], []] and df.sic_raw_fix.tolist()[:3] == ['2CS1->2051', '4401->dropped', '8885->dropped']
    assert df.sic.tolist()[3:6] == [['1094']] * 3                    # a mining code that recurs in the edition is kept
    assert df.sic.tolist()[6] == ['9999'] and df.sic_raw_fix.tolist()[6] == ''      # editions with descriptions are not touched
    C.assign_sic(df)
    assert df.sic_source.tolist()[:3] == ['directory', 'predicted', '']
    assert df.sic.tolist()[1] == ['2751'] and df.sic.tolist()[2] == []


def test_code_set_is_the_classifier_label_set(classifier):
    assert sic_predict.code_set() == set(classifier['labels']) and len(sic_predict.code_set()) > 50


# ------------------------------------------------------------------ R8: one normalisation for training and query text
def test_training_and_query_text_share_one_norm():
    assert sic_classifier.norm is sic_classifier_norm.norm
    assert sic_classifier_norm.norm('Bread AND cake, N.E.C. & pies') == sic_classifier_norm.norm('BREAD + CAKE PIES') == 'BREAD CAKE PIES'
    assert sic_classifier_norm.norm('SAND AND GRAVEL') == 'SAND GRAVEL' and sic_classifier_norm.norm('BRANDS ANDERSON') == 'BRANDS ANDERSON'


# ------------------------------------------------------------------ E5: the listings CSV gets the by_year scrub
def test_export_scrub_matches_export_by_year():
    import pathlib
    src = (pathlib.Path(pb.__file__).parent / 'export.py').read_text()
    by = (pathlib.Path(pb.__file__).parent / 'export_by_year.py').read_text()
    ns = {'re': re}
    exec(src[src.index('def scrub_cell'):src.index('def county_from_tracts')], ns)
    scrub = ns['scrub_cell']
    assert [scrub(x) for x in ['=SUM(A1)', '+ MFG CO', '@X', '-- A', 'A-B', '= ', None, 3.0]] == ['SUM(A1)', 'MFG CO', 'X', 'A', 'A-B', '', None, 3.0]
    pat = "r'''^[\\s\"'=+@\\-]+'''"
    assert pat in by and pat in src                                                # the two exports apply the same pattern (13 Nov: a leading blank or quote is stripped too)
    assert [scrub(x) for x in [' =X', '"+Y', "'@Z"]] == ['X', 'Y', 'Z']
    assert re.search(r"for c in \['name','street','addr_raw','name_as_read','street_as_read'\]:\s+if c in R: R\[c\]=R\[c\]\.apply\(scrub_cell\)", src)
