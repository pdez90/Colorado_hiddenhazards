"""Addresses run through the synthetic fixture by both the Python geocoder (pytest) and the R port (testthat): (street, city, zip)."""
CASES = [
    # plain vs directional street holding the same number (450 Kalamath / 450 S Kalamath)
    ('450 KALAMATH', 'DENVER', '80223'),      # printed ZIP's own ranges hold only S Kalamath -> moved there, _dirzip (plain Kalamath's nearest end is not used)
    ('250 KALAMATH', 'DENVER', '80223'),      # no S segment holds 250: nearest end of the plain street
    ('450 KALAMATH', 'DENVER', '80204'),      # printed ZIP's own ranges hold only the plain street -> stays, _dirzip
    ('450 KALAMATH', 'DENVER', '80219'),      # ZIP holds neither; its half of the grid is S -> moved to S Kalamath, _dirzip
    ('450 KALAMATH', 'DENVER', '80211'),      # ZIP holds neither; its half is N -> stays on the plain street, _dirzip
    ('450 KALAMATH', 'DENVER', ''),           # no ZIP, Denver's ZIPs lie on both halves -> _dirambig (not placed)
    ('450 KALAMATH ST', 'DENVER', '80203'),   # downtown ZIP without a known half -> _dirambig
    ('450 KALAMATH', 'ENGLEWOOD', ''),        # found through a neighbouring ZIP of the town, no half -> _dirambig_nearzips
    ('450 KALAMATH', 'DENVER', '80501'),      # ZIP of another town (OCR), city decides the search -> _dirambig_cityzips
    # street type decides between two different streets
    ('2350 24TH ST', 'DENVER', '80205'), ('2350 24TH AVE', 'DENVER', '80205'), ('2350 24TH', 'DENVER', '80205'), ('2350 E 24TH AVE', 'DENVER', '80205'),
    # grid conflict: a prefixed address never lands on the unprefixed street on the wrong side of Ellsworth
    ('4000 S KALAMATH', 'DENVER', '80223'), ('4000 N KALAMATH', 'DENVER', '80223'),
    # directions written SO/NO, NO as a unit marker, glued letters
    ('450 SO KALAMATH', 'DENVER', '80223'), ('1050 SO BROADWAY', 'DENVER', '80210'), ('650 BROADWAY NO 5', 'DENVER', '80203'),
    ('450 SKALAMATH', 'DENVER', '80223'), ('450S KALAMATH', 'DENVER', '80223'), ('1731S KALAMATH', 'DENVER', '80223'),
    # junk token / trimming
    ('2150 5 KALAMATH', 'DENVER', '80204'), ('2150 W 5TH AVE', 'DENVER', '80204'), ('450 KALAMATH XYZ', 'DENVER', '80204'),
    # blank ZIP -> the town's ZIPs' neighbours
    ('3550 S BANNOCK', 'DENVER', ''), ('3550 S BANNOCK', 'DENVER', '80223'), ('3550 S BANNOCK ST', 'ENGLEWOOD', '80110'),
    # sides, parity, one-sided range, nearest end, type mismatch, fuzzy name
    ('450 KALAMATH', 'DENVER', '80204'), ('451 KALAMATH', 'DENVER', '80204'), ('452 KALAMATH', 'DENVER', '80204'), ('453 KALAMATH', 'DENVER', '80204'),
    ('650 KALAMATH', 'DENVER', '80204'), ('651 KALAMATH', 'DENVER', '80204'), ('620 S KALAMATH', 'DENVER', '80223'), ('950 S KALAMATH', 'DENVER', '80223'),
    ('450 KALAMETH ST', 'DENVER', '80223'), ('450 KALAMATH AVE', 'DENVER', '80204'), ('2150 W 5TH', 'DENVER', '80204'), ('2101 W 5TH AVE', 'DENVER', '80204'),
    # fallbacks
    ('123 NOSUCH ST', 'DENVER', '80204'), ('450 KALAMATH', 'LONGMONT', '80501'), ('450 KALAMATH', 'NOWHERE', ''), ('KALAMATH ST', 'DENVER', '80204'),
    ('l234 KALAMATH', 'DENVER', ''), ('5O1 KALAMATH', 'DENVER', '80204'), ('2150 1/2 W 5TH AVE', 'DENVER', '80204'), ('2150-60 W 5TH AVE', 'DENVER', '80204'),
]

# parse_addr inputs compared between the ports (expected values are asserted in test_parse.py)
PARSE_CASES = ['1934 S BROADWAY', '1934 SO BROADWAY', '400 NO 5TH ST', '650 BROADWAY NO 5', '1441 W 46TH AVE NO 21', '1234 MAIN ST STE 5', '1234 MAIN ST #5',
               '2505 W 2ND AVE 7', '1234 1/2 MAIN ST', '1234A MAIN ST', '123N MAIN', '450S KALAMATH', '1731S WADSWORTH BLVD', '123N S MAIN', '125-7 S WEBER',
               '1621-1649 17TH ST', 'l234 MAIN', '12O5 MAIN ST', '5O1 MAIN', '4505 KALAMATH', 'I70 FRONTAGE RD', 'MAIN ST', '1500 E 1 AVE', '2150 5 KALAMATH',
               '100 WEST 38TH AV', '100 W 38TH AVE N', '100 W 38TH 5T', '100 SANTA FE ORIVE', '3600 S HIGHWAY 85', '400 S', '1934 s. broadway,', '4200N WEBER EE EE']
# name pairs for the rapidfuzz vs R/fuzz.R comparison
FUZZ_PAIRS = [('CRYSTAL CHEMICAL', 'CRYSTAL'), ('ACME PLATING WORKS', 'ACME PLATING'), ('ACME PLATING WORKS', 'PLATING WORKS ACME'), ('ACME PLATNG WORKS', 'ACME PLATING WORKS'),
              ('ACME PLATING', 'ACME ELECTROPLATING'), ('ROCKY MOUNTAIN STEEL', 'ROCKY MOUNTAIN NEWS'), ('ROCKY MOUNTAIN STEEL', 'ROCKY MOUNTAIN STEEL MILLS'),
              ('KALAMATH', 'KALAMETH'), ('W 38TH', 'W 36TH'), ('GATES RUBBER', 'GATES'), ('A B C', 'C B A'), ('SAME', 'SAME'), ('X', 'Y'), ('SERUM LABORATORIES', 'SERUM LABS INTERNATIONAL')]
