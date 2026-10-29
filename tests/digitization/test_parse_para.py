"""parse_para.parse_text_record on 1990-1993 paragraph entries: the SIC scan must not read the firm's house number or its
employee count as an industry code (a 4-digit number followed by lower-case text is the pattern of a code line, but '3000 ist Ave'
is 3000 1st Ave with an OCR 'i', and '2000 employees' is the size)."""
import parse_para as pp


def rec(text, name='ACME INC', year=1992):
    return pp.parse_text_record(name, text, year, 'V', 1, 0)


def test_house_number_with_lowercase_street_is_not_a_sic_code():
    r = rec('John Doe, President. 3000 ist Ave, Denver 80219. (303) 555-1212 Denver County. Began in 1970. 1-9 employees. '
            'Private corporation. 2752 commercial printing, lithographic.')
    assert r['street'] == '3000 1ST Ave' and r['zip'] == '80219'
    assert r['sic'] == ['2752'] and r['sic_desc'] == ['commercial printing, lithographic']


def test_house_number_in_food_range_is_not_a_sic_code():
    r = rec('Joe Beydler, Owner. 2002 ist Ave, Greeley 80631. (303) 555-1212 Weld County. Began in 1970. 1-9 employees. '
            'Sole proprietorship. 2434 wood kitchen cabinets.', name='BEYDLER CABINET SHOP', year=1990)
    assert r['sic'] == ['2434'] and r['size'] == '1-9'


def test_employee_count_is_not_a_sic_code():
    r = rec('John Doe, President. 1145 ithaca Dr, Boulder 80303. Boulder County. Began in 1970. 2000 employees. 2752 commercial printing.')
    assert r['sic'] == ['2752'] and r['size'] == '2000' and r['street'] == '1145 ithaca Dr'


def test_real_codes_and_fields_still_parsed():
    r = rec('Jane Roe, Owner. 1234 Blake St, Denver 80202. (303) 555-1212 Denver County. Began in 1946. 20-49 employees. '
            'Private corporation. 3599 (region) machine shop. 3444 sheet metal work.')
    assert r['sic'] == ['3599', '3444'] and r['est'] == 1946 and r['size'] == '20-49' and r['org'] == 'Private corporation'
    assert r['city_ctx'] == 'DENVER' and r['county_ctx'] == 'DENVER'
