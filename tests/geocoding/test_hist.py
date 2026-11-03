"""Pre-1960 layer: hist_parse.ADDR, run_hist's NEXT cut / own_listing / is_person on the audited entry patterns, and geocode_hist's
street normalisation and street-level rule."""
import pandas as pd, pytest
import hist_parse as hp, run_hist as rh, geocode_hist as gh

def row(entry, trade, name):
    a = hp.ADDR.search(entry)
    return pd.Series(dict(entry=entry, trade=trade, name=name, street=(a.group(1) + ' ' + a.group(2)) if a else ''))

# the eleven audited entry patterns: (entry text, trade word found, firm name, expected street after own_listing, expected own, expected is_person)
AUDITED = [
    ("Copenhaver Geo C, wagon maker, Cooper Geo H, florist, 833 15th", 'wagon maker', 'Copenhaver Geo C', '', True, False),   # 833 15th is the florist's
    ("Goldhammer S, phys, 312 17th. GOODRICH RUBBER CO, 1550 Broadway", 'rubber co', 'Goldhammer S', '', False, False),       # trade belongs to the next listing
    ("Pueblo Foundry Co, foundry, 125-7 S Weber", 'foundry', 'Pueblo Foundry Co', '125 S Weber', True, False),                  # hyphenated range -> 125
    ("Denver Fire Clay Co, chemical works, 1742 Champa. Stearns J B, machinist, 1800 Blake", 'chemical works', 'Denver Fire Clay Co', '1742 Champa', True, False),
    ("Western Chemical Mfg Co, chemicals, 1950 W Colfax av", 'chemicals', 'Western Chemical Mfg Co', '1950 W Colfax av', True, False),
    ("Hendrie & Bolthoff Mfg Co, mining machinery, 1621-1649 17th", 'mining machinery', 'Hendrie & Bolthoff Mfg Co', '1621 17th', True, False),
    ("Globe Smelting & Refining Co, smelters, 1721 Holladay", 'smelting', 'Globe Smelting & Refining Co', '1721 Holladay', True, False),  # trade word inside the name
    ("Jones W H, sheet iron work Gartman C E, machinist, 1450 Blake", 'sheet iron', 'Jones W H', '', True, False),            # next listing without punctuation
    ("Linquist Peter, lab, Globe smelter, r. 1234 Washington", 'smelter', 'Linquist Peter', '1234 Washington', True, True),   # a worker at his residence
    ("Cain Patrick, stoker, Denver Gas Co, 1700 Wazee", 'gas co', 'Cain Patrick', '1700 Wazee', True, True),                  # occupation between name and employer
    ("Denver Gas Co, gas works, 1700 Wazee", 'gas works', 'Denver Gas Co', '1700 Wazee', True, False),                        # the works itself
    # (second audit, 1 Nov) the trade word inside the name must not pick up the preceding listing's address
    ("Axelrood Mrs V, dry goods, 1325 24th. Atlas Wire & Iron Works, 1733 Wazee", 'iron works', 'Atlas Wire & Iron Works', '1733 Wazee', True, False),
    ("Axelrood Mrs V, dry goods, 1325 24th. Atlas Wire & Iron Works", 'iron works', 'Atlas Wire & Iron Works', '', True, False),
    ("Groves Bros, groc, 800 19th av. Gutta Percha & Rubber Mfg Co", 'rubber', 'Gutta Percha & Rubber Mfg Co', '', True, False),
]

@pytest.mark.parametrize('entry,trade,name,street,own,person', AUDITED)
def test_audited_entries(entry, trade, name, street, own, person):
    r = row(entry, trade, name)
    got_own, got_street = rh.own_listing(r)
    assert (bool(got_own), got_street) == (own, street)
    assert rh.is_person(r) is person

def test_copenhaver_does_not_get_the_florists_address():
    r = row("Copenhaver Geo C, wagon maker, Cooper Geo H, florist, 833 15th", 'wagon maker', 'Copenhaver Geo C')
    assert r.street == '833 15th'                        # the raw ADDR scan finds it ...
    assert rh.own_listing(r)[1] == ''                    # ... own_listing cuts at 'Cooper Geo H,' and leaves no street

def test_next_cut_patterns():
    assert rh.NEXT.search(', Cooper Geo H, florist')                   # spelled-out given name + initial
    assert rh.NEXT.search('. Stearns J B, machinist')                 # initials after punctuation
    assert rh.NEXT.search(' work Gartman C E, machinist')             # no punctuation, lowercase trade follows
    assert rh.NEXT.search(' Smith John, tinner')
    assert not rh.NEXT.search(' & Refining Co, smelters, 1721 Holladay')   # the firm's own name
    assert not rh.NEXT.search(' Iron Works, machinists, 1234 Blake')
    assert not rh.NEXT.search(', 1742 Champa')
    assert not rh.NEXT.search(' Co, 1550 Broadway')

@pytest.mark.parametrize('text,street', [
    ('125-7 S Weber', '125 S Weber'), ('1621-1649 17th', '1621 17th'), ('833 15th', '833 15th'), ('1950 W Colfax av', '1950 W Colfax av'),
    ('312 17th.', '312 17th'), ('cor 33d and Wynkoop', None), ('r. 1234 Washington', '1234 Washington'),
    ('1742 Champa. Stearns', '1742 Champa'), ('301 22d', '301 22d'), ('Room 4, 1721 Holladay', '1721 Holladay'), ('no number here', None),
])
def test_addr_regex(text, street):
    a = hp.ADDR.search(text)
    assert ((a.group(1) + ' ' + a.group(2)) if a else None) == street

def test_entries_split():
    assert hp.entries("Pueblo Foundry Co, foundry, 125-7 S Weber. Brown J, tinner, 456 Elm. Smith & Co, machinists, 1 Main st.") == \
           ['Pueblo Foundry Co, foundry, 125-7 S Weber.', 'Brown J, tinner, 456 Elm.', 'Smith & Co, machinists, 1 Main st.']

def test_is_person_rules():
    assert rh.is_person(row("Smith John, foreman, Omaha & Grant smelter, bds 1200 Larimer", 'smelter', 'Smith John'))
    assert not rh.is_person(row("Omaha & Grant Smelting Co, smelters, Globeville", 'smelting', 'Omaha & Grant Smelting Co'))
    assert rh.is_person(row("Brown Wm, lab, Globe Smelting Co", 'smelting', 'Brown Wm'))

def test_clean_name():
    assert rh.clean_name('DEN Globe Smelting Co.,') == 'Globe Smelting Co'
    assert rh.clean_name('Goldhammer S, phys. Goodrich Rubber Co') == 'Goodrich Rubber Co'

# ---- geocode_hist
@pytest.mark.parametrize('street,entry,exp', [
    ('1721 Holladay', '', '1721 MARKET'), ('125 S Weber', '', '125 S WEBER'), ('1950 W Colfax av', '', '1950 W COLFAX AV'),
    ('301 22d', '', '301 22ND'), ('1234 3d', '', '1234 3RD'), ('100 12d', '', '100 12TH'), ('100 11d', '', '100 11TH'), ('100 21d', '', '100 21ST'),
    ('1550 Bdwy', '', '1550 BROADWAY'), ('1800 Wash', '', '1800 WASHINGTON'), ('1200 Santa Fe', '', '1200 SANTA FE'), ('1200 Santa', '', '1200 SANTA FE'),
    ('1721 Holladay', 'Globe Smelting Co, office 1721 Holladay blk', ''), ('1721 Holladay', 'Globe Smelting Co, 1721 Holladay, works Globeville', '1721 MARKET'),
])
def test_hist_street(street, entry, exp):
    assert gh.hist_street(street, entry) == exp

def test_street_ok_rules():
    R = lambda **k: pd.Series(k)
    assert gh.street_ok(R(street='1721 Market', town='DENVER', year=1891, office=False))
    assert not gh.street_ok(R(street='1721 Market', town='DENVER', year=1887, office=False))      # before the renumbering
    assert not gh.street_ok(R(street='1721 Market', town='DENVER', year=1900, office=True))
    assert gh.street_ok(R(street='125 S Weber', town='COLORADO SPRINGS', year=1910, office=False))
    assert not gh.street_ok(R(street='125 S Weber', town='COLORADO SPRINGS', year=1905, office=False))
    assert not gh.street_ok(R(street='125 S Weber', town='SILVER PLUME', year=1930, office=False))
    assert not gh.street_ok(R(street='Main st', town='DENVER', year=1930, office=False))

def test_street_level_codes():
    assert gh.street_level('range_interp') and gh.street_level('range_interp_cityzips') and gh.street_level('range_interp_dirzip_cityzips') \
        and gh.street_level('range_interp_dirtype')
    assert not gh.street_level('range_interp_dirambig_cityzips') and not gh.street_level('fuzzy_range_interp') \
        and not gh.street_level('street_nearest') and not gh.street_level('zip_centroid') and not gh.street_level(None)
    # loosened matches never count as street level (README: 'only exact address-range match')
    assert not gh.street_level('range_interp_cityzips_dirloose') and not gh.street_level('range_interp_sufloose_dirloose') \
        and not gh.street_level('range_interp_cityzips_trim') and not gh.street_level('range_interp_nearzips')

def test_hist_street_through_the_geocoder(geocoder):
    """A pre-1960 Denver listing goes through the same geocoder with town only (no ZIP)."""
    la, lo, q = geocoder.geocode(gh.hist_street('450 S Kalamath'), 'DENVER', '')
    assert gh.street_level(q) and la == pytest.approx(39.712 - 50 / 98 * 0.0015, abs=1e-9)
    assert not gh.street_level(geocoder.geocode(gh.hist_street('450 Kalamath'), 'DENVER', '')[2])     # plain vs S: ambiguous without a ZIP


# ---- hand review of street placements (data/historical/street_review.csv, 3 Nov 2026)
def test_apply_review_verdicts():
    df = pd.DataFrame(dict(year=[1913] * 6, town=['DENVER'] * 6, nkey=list('ABCDEF'), sector=['Foundry'] * 6,
                           name=['A Co', 'B Co', 'C Xx', 'D Co', 'E Co', 'F Co'], town_src=[''] * 6,
                           street=['1 Blake', '2 Blake', '3 Blake', '4 Blake', '5 Blake', '6 Blake']))
    rv = pd.DataFrame(dict(year=[1913] * 5, town=['DENVER'] * 5, nkey=list('ABCDE'), sector=['Foundry'] * 5,
                           verdict=['ok', 'fix_address', 'fix_name', 'not_works', 'other_town'],
                           street_fix=['', '22 Wazee', '', '', ''], town_fix=['', '', '', '', 'GREELEY'], name_fix=['', '', 'C Co', '', '']))
    out = gh.apply_review(df, rv).set_index('nkey')
    assert 'D' not in out.index                                       # not a works: dropped
    assert out.loc['A', 'street'] == '1 Blake' and out.loc['A', 'review'] == 'ok'
    assert out.loc['B', 'street'] == '22 Wazee'
    assert out.loc['CCO', 'name'] == 'C Co'                          # the corrected name also gives the key
    assert out.loc['E', 'town'] == 'GREELEY' and out.loc['E', 'street'] == '5 Blake'
    assert out.loc['F', 'review'] == ''                               # no review row


def test_every_street_placement_was_reviewed():
    """A parser change that creates new street-level placements must be followed by a review of them (or the review file
    no longer matches the listings): every street-level listing in the committed layer carries a verdict."""
    import pathlib
    p = pathlib.Path(__file__).resolve().parents[2] / 'data/historical/CO_pre1960_hazardous_listings.csv'
    L = pd.read_csv(p, low_memory=False, dtype={'review': str})
    st = L[L.precision == 'street']
    assert 'review' in L.columns
    missing = st[st.review.fillna('') == '']
    assert missing.empty, f"{len(missing)} street-level listings have no review verdict, e.g. {missing[['year', 'town', 'name', 'street']].head(5).values.tolist()}"
    assert not st.review.eq('not_works').any()


def test_apply_review_sector_fix_and_second_pass_keeps_first_verdicts():
    df = pd.DataFrame(dict(year=[1880, 1880, 1880], town=['LEADVILLE'] * 3, nkey=['A', 'B', 'C'], sector=['Foundry', 'Assay office', 'Foundry'],
                           fe_group=['33', 'EXT', '33'], name=['A', 'B', 'C'], town_src=[''] * 3, street=[''] * 3))
    street = pd.DataFrame(dict(year=[1880], town=['LEADVILLE'], nkey=['A'], sector=['Foundry'], verdict=['ok'], street_fix=[''], town_fix=[''], name_fix=['']))
    town = pd.DataFrame(dict(year=[1880, 1880], town=['LEADVILLE'] * 2, nkey=['B', 'C'], sector=['Assay office', 'Foundry'], verdict=['other_sector', 'other_town'],
                             town_fix=['', 'DENVER'], sector_fix=['Smelting & refining', ''], name_fix=['', '']))
    out = gh.apply_review(gh.apply_review(df, street), town).set_index('nkey')
    assert out.loc['A', 'review'] == 'ok'                                       # the street verdict survives the town pass
    assert out.loc['B', 'sector'] == 'Smelting & refining' and out.loc['B', 'fe_group'] == '33'
    assert out.loc['C', 'town'] == 'DENVER' and out.loc['C', 'review'] == 'other_town'


def test_town_review_keeps_the_printed_address_but_never_places_at_it():
    df = pd.DataFrame(dict(year=[1880, 1880], town=['DENVER', 'LEADVILLE'], nkey=['A', 'B'], sector=['Foundry'] * 2, fe_group=['33'] * 2,
                           name=['A', 'B'], town_src=[''] * 2, street=['17 Blake', '5 Harrison']))
    town = pd.DataFrame(dict(year=[1880, 1880], town=['DENVER', 'LEADVILLE'], nkey=['A', 'B'], sector=['Foundry'] * 2, verdict=['ok', 'other_town'],
                             town_fix=['', 'DENVER'], sector_fix=[''] * 2, name_fix=[''] * 2))
    out = gh.apply_review(df, town, town_level=True).set_index('nkey')
    assert out.loc['A', 'street'] == '17 Blake' and out.loc['A', 'town_only']      # kept for R/denver_1880.R, not geocoded
    assert out.loc['B', 'street'] == '' and out.loc['B', 'town'] == 'DENVER'       # a moved listing loses the other town's address


def test_apply_review_drops_copies_created_by_a_correction():
    df = pd.DataFrame(dict(year=[1912, 1912], town=['DENVER', 'ARLINGTON'], nkey=['QUEENCITY', 'QUEENCITY'], sector=['Metal working'] * 2,
                           fe_group=['34'] * 2, name=['Queen City'] * 2, town_src=[''] * 2, street=[''] * 2))
    town = pd.DataFrame(dict(year=[1912], town=['ARLINGTON'], nkey=['QUEENCITY'], sector=['Metal working'], verdict=['other_town'],
                             town_fix=['DENVER'], sector_fix=[''], name_fix=['']))
    assert len(gh.apply_review(df, town)) == 1


def test_every_listing_was_reviewed_once_the_town_review_exists():
    """With data/historical/town_review.csv committed, every pre-1960 listing (street or town level) carries a verdict, and none is
    'not_works' (those are dropped)."""
    import pathlib
    root = pathlib.Path(__file__).resolve().parents[2]
    if not (root / 'data/historical/town_review.csv').exists():
        pytest.skip('town review not yet committed')
    L = pd.read_csv(root / 'data/historical/CO_pre1960_hazardous_listings.csv', low_memory=False, dtype={'review': str})
    missing = L[L.review.fillna('') == '']
    assert missing.empty, f"{len(missing)} listings have no review verdict, e.g. {missing[['year', 'town', 'name']].head(5).values.tolist()}"
    assert not L.review.eq('not_works').any()
