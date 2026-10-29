"""parse_addr / parse_name edge cases (pipeline/tiger_geocode.py)."""
import pytest
from tiger_geocode import parse_addr, parse_name, ordfix

@pytest.mark.parametrize('addr,expected', [
    ('1934 S BROADWAY', (1934, 'BROADWAY', 'S', '')),
    ('1934 SOUTH BROADWAY', (1934, 'BROADWAY', 'S', '')),
    ('1934 SO BROADWAY', (1934, 'BROADWAY', 'S', '')),            # 'So. Broadway' is a direction ...
    ('400 NO 5TH ST', (400, '5TH', 'N', 'ST')),                   # ... and so is 'No. 5th'
    ('650 BROADWAY NO 5', (650, 'BROADWAY', '', '')),             # 'NO' followed by a number is a unit
    ('1441 W 46TH AVE NO 21', (1441, '46TH', 'W', 'AVE')),
    ('400 NO 5TH', (400, '5TH', 'N', '')),
    ('1234 MAIN ST STE 5', (1234, 'MAIN', '', 'ST')),
    ('1234 MAIN ST #5', (1234, 'MAIN', '', 'ST')),
    ('1234 MAIN ST UNIT B', (1234, 'MAIN', '', 'ST')),
    ('2505 W 2ND AVE 7', (2505, '2ND', 'W', 'AVE')),              # bare number after the street type is a unit
    ('1234 1/2 MAIN ST', (1234, 'MAIN', '', 'ST')),               # half addresses
    ('1234A MAIN ST', (1234, 'MAIN', '', 'ST')),                  # a unit letter glued to the number
    ('123N MAIN', (123, 'MAIN', 'N', '')),                        # a direction letter glued to the number (40 real keys)
    ('450S KALAMATH', (450, 'KALAMATH', 'S', '')),                # ... also S, which the OCR fix used to read as a 5
    ('1731S WADSWORTH BLVD', (1731, 'WADSWORTH', 'S', 'BLVD')),
    ('123N S MAIN', (123, 'MAIN', 'S', '')),                      # an explicit direction wins over the glued letter
    ('125-7 S WEBER', (125, 'WEBER', 'S', '')),                   # hyphenated range -> first number
    ('1621-1649 17TH ST', (1621, '17TH', '', 'ST')),
    ('l234 MAIN', (1234, 'MAIN', '', '')),                        # OCR house numbers: l -> 1, O -> 0, S -> 5
    ('12O5 MAIN ST', (1205, 'MAIN', '', 'ST')),
    ('5O1 MAIN', (501, 'MAIN', '', '')),
    ('4505 KALAMATH', (4505, 'KALAMATH', '', '')),                # a real 5 stays a 5
    ('I70 FRONTAGE RD', (None, None, '', '')),                    # interstates are not house numbers
    ('MAIN ST', (None, None, '', '')),                            # no number
    ('1500 E 1ST AVE', (1500, '1ST', 'E', 'AVE')),
    ('1500 E FIRST AVE', (1500, '1ST', 'E', 'AVE')),
    ('1500 E 1 AVE', (1500, '1ST', 'E', 'AVE')),                  # bare ordinal number gets its suffix
    ('2150 5 KALAMATH', (2150, '5TH KALAMATH', '', '')),          # the S read as 5: kept as a token for the junk rule, not a direction
    ('100 W 38TH AVENUE', (100, '38TH', 'W', 'AVE')),
    ('100 WEST 38TH AV', (100, '38TH', 'W', 'AVE')),
    ('100 W 38TH AVE N', (100, '38TH', 'W', 'AVE')),              # post-direction dropped
    ('100 W 38TH 5T', (100, '38TH', 'W', 'ST')),                  # OCR street type
    ('100 WH 38TH AVF', (100, '38TH', 'W', 'AVE')),
    ('100 SANTA FE DR', (100, 'SANTA FE', '', 'DR')),
    ('100 SANTA FE ORIVE', (100, 'SANTA FE', '', 'DR')),
    ('3600 S HIGHWAY 85', (3600, 'HIGHWAY 85TH', 'S', '')),       # highway numbers are not units (the ordinal suffix is added to TIGER names too)
    ('400 S', (400, 'S', '', '')),                                 # a lone direction token is the street core, not a prefix
])
def test_parse_addr(addr, expected):
    assert parse_addr(addr) == expected

def test_parse_addr_lowercase_and_punctuation():
    assert parse_addr('1934 s. broadway,') == (1934, 'BROADWAY', 'S', '')

@pytest.mark.parametrize('name,expected', [
    ('S Kalamath St', ('S', 'KALAMATH', 'ST')), ('W 5th Ave', ('W', '5TH', 'AVE')), ('E 24th Ave', ('E', '24TH', 'AVE')),
    ('24th St', ('', '24TH', 'ST')), ('Kalamath St', ('', 'KALAMATH', 'ST')), ('Broadway', ('', 'BROADWAY', '')),
    ('N Fed Blvd', ('N', 'FED', 'BLVD')), ('E Colfax Ave', ('E', 'COLFAX', 'AVE')), ('Martin Luther King Jr Blvd', ('', 'MARTIN LUTHER KING JR', 'BLVD')),
])
def test_parse_name(name, expected):
    assert parse_name(name) == expected

def test_ordfix():
    assert [ordfix(t) for t in ['1', '2', '3', '4', '11', '12', '13', '21', '22', '101', 'FIRST', 'MAIN', '5TH']] == \
           ['1ST', '2ND', '3RD', '4TH', '11TH', '12TH', '13TH', '21ST', '22ND', '101ST', '1ST', 'MAIN', '5TH']
