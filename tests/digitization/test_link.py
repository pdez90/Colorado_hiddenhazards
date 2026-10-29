"""link.py: establishments across editions from synthetic listings (name_n / street_n / zip5 / city_g as geo_prep
leaves them)."""
import pandas as pd
import pytest
import link
from consolidate import norm_name, norm_street


def listings(rows):
    df = pd.DataFrame(rows, columns=['year', 'name', 'street', 'zip5', 'city_g'])
    df['name_n'] = df.name.apply(norm_name)
    df['street_n'] = df.street.apply(norm_street)
    return df


def groups(df):
    """estab_id -> set of (year, name)."""
    return {e: set(zip(g.year, g.name)) for e, g in df.groupby('estab_id')}


def same(df, a, b):
    ids = df.set_index('name').estab_id
    return ids[a] == ids[b]


@pytest.fixture(scope='module')
def linked():
    rows = [
        # the same firm, OCR variants of the name, across four editions at one address
        (1967, 'CRAWFORD CHRONICLE', '101 MAIN ST', '81415', 'CRAWFORD'),
        (1970, 'CRAWFCRD CHRONICLE', '101 MAIN ST', '81415', 'CRAWFORD'),
        (1977, 'CRAWFORD CHRONICLE INC', '101 MAIN', '81415', 'CRAWFORD'),
        (1983, 'CRAWF0RD CHRONICLE, THE', '101 MAIN STREET', '81415', 'CRAWFORD'),
        # the same firm that moved within the ZIP (names identical)
        (1967, 'PLAT PACKING CO', '707 E 50TH AVE', '80216', 'DENVER'),
        (1977, 'PLAT PACKING CO', '4800 YORK ST', '80216', 'DENVER'),
        # two different firms at one address, dissimilar names: must stay apart
        (1967, 'MID AMERICA PLATING INC', '4377 PACKING HOUSE RD', '80216', 'DENVER'),
        (1983, 'WESTERN PAPER CO', '4377 PACKING HOUSE RD', '80216', 'DENVER'),
        # a short name that is a token subset of a longer one at the same address: not the same establishment
        (1970, 'DIAMOND', '2000 W 8TH AVE', '80204', 'DENVER'),
        (1980, 'DIAMOND VOGEL PAINTS', '2000 W 8TH AVE', '80204', 'DENVER'),
        # a longer variant with two shared tokens at the same street number does link
        (1973, 'ACME METAL PRODUCTS', '1234 BLAKE ST', '80202', 'DENVER'),
        (1979, 'ACME METAL PRODUCTS OF COLORADO', '1234 BLAKE', '80202', 'DENVER'),
        # the same name in two different ZIPs is two establishments
        (1967, 'MOUNTAIN STEEL + SUPPLY', '3800 RACE ST', '80205', 'DENVER'),
        (1983, 'MOUNTAIN STEEL + SUPPLY', '600 W 48TH AVE', '80216', 'DENVER'),
        # 1961-65 listings have no ZIP: linked to the ZIP records of the same city by name
        (1965, 'PLAT PACKING CO', '707 E 50TH', '', 'DENVER'),
        (1965, 'ZENITH DAIRY', '100 ELM', '', 'DENVER'),
    ]
    return link.link(listings(rows))


def test_estab_ids_are_dense_labels(linked):
    assert linked.estab_id.str.fullmatch(r'E\d{6}').all()
    assert sorted(linked.estab_id.unique()) == ['E%06d' % i for i in range(linked.estab_id.nunique())]


def test_ocr_variants_of_one_firm_link(linked):
    g = groups(linked)
    crawford = next(s for s in g.values() if (1967, 'CRAWFORD CHRONICLE') in s)
    assert {n for _, n in crawford} == {'CRAWFORD CHRONICLE', 'CRAWFCRD CHRONICLE', 'CRAWFORD CHRONICLE INC', 'CRAWF0RD CHRONICLE, THE'}


def test_same_firm_moved_within_zip_links(linked):
    g = linked[linked.name == 'PLAT PACKING CO']
    assert g.estab_id.nunique() == 1 and len(g) == 3        # 1965 (no ZIP), 1967, 1977


def test_different_firms_at_one_address_stay_apart(linked):
    assert not same(linked, 'MID AMERICA PLATING INC', 'WESTERN PAPER CO')
    assert not same(linked, 'DIAMOND', 'DIAMOND VOGEL PAINTS')


def test_token_subset_with_shared_number_links(linked):
    assert same(linked, 'ACME METAL PRODUCTS', 'ACME METAL PRODUCTS OF COLORADO')


def test_same_name_in_two_zips_is_two_establishments(linked):
    assert linked[linked.name == 'MOUNTAIN STEEL + SUPPLY'].estab_id.nunique() == 2


def test_no_zip_record_without_a_match_stays_alone(linked):
    assert (linked.estab_id == linked[linked.name == 'ZENITH DAIRY'].estab_id.iloc[0]).sum() == 1


def test_blocking_key(linked):
    assert (linked[linked.zip5 != ''].blk == linked[linked.zip5 != ''].zip5).all()
    assert (linked[linked.zip5 == ''].blk == 'DENVER').all()


def test_empty_names_never_link():
    df = listings([(1967, '', '1 A ST', '80202', 'DENVER'), (1977, '', '1 A ST', '80202', 'DENVER'), (1983, 'X Y', '1 A ST', '80202', 'DENVER')])
    out = link.link(df)
    assert out.estab_id.nunique() == 3
