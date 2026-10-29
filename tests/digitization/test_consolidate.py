"""consolidate.py rules on small frames: OCR-corrected SIC codes, hazardous codes dropped as software or bled in from a
neighbouring entry (and the printing-ink protection), hazard flags and the NAICS->SIC map."""
import pandas as pd
import pytest
import consolidate as C


def frame(rows):
    base = dict(vol='T', year=1977, page=1, col=0, name='', street='', zip='', city_ctx='', county_ctx='', sic=[], sic_desc=[], extra=[])
    return C.prepare(pd.DataFrame([{**base, **r} for r in rows]))


def stub_predict(code='0000', score=0.0):
    """A classifier that never agrees with anything: isolates the one-digit-neighbour rule of fix_ocr_codes."""
    return lambda texts: [(code, score, '') for _ in texts]


@pytest.fixture
def no_classifier(monkeypatch):
    monkeypatch.setattr(C, 'predict', stub_predict())


# ---- sic_ocr_fix ------------------------------------------------------------------------------------------------------
def test_ocr_fix_moves_meat_packing_from_2911_to_2011(no_classifier):
    rows = [dict(name=f'PACKER {i}', sic=['2011'], sic_desc=['MEAT PACKING PLANTS']) for i in range(25)]
    rows += [dict(name=f'REFINER {i}', sic=['2911'], sic_desc=['PETROLEUM REFINING']) for i in range(25)]
    rows += [dict(name='PLAT PACKING CO', sic=['2911'], sic_desc=['MEAT PACKING PLANTS'])]  # misread 2011
    rows += [dict(name='A JEWELER', sic=['3011'], sic_desc=['JEWELRY, PRECIOUS METAL'])]    # 3011 (tires) is not common here: no fix
    df = frame(rows)
    C.assign_sic(df)
    title = C.fix_ocr_codes(df)
    assert title['2011'] == 'meat packing plants' and title['2911'] == 'petroleum refining'
    plat = df[df.name == 'PLAT PACKING CO'].iloc[0]
    assert plat.sic == ['2011'] and plat.sic_ocr_fix == '2911->2011'
    assert (df[df.name.str.startswith('REFINER')].sic_ocr_fix == '').all()
    assert (df[df.name.str.startswith('PACKER')].sic_ocr_fix == '').all()
    assert df[df.name == 'A JEWELER'].iloc[0].sic == ['3011']


def test_ocr_fix_trusts_the_classifier_when_it_names_a_neighbour(monkeypatch):
    """The printed description's predicted code, when one digit away and fitting that code's usual title, is used
    even if it is not a different major group (the neighbour fallback is only for cross-group misreads)."""
    rows = [dict(name=f'S{i}', sic=['3591'], sic_desc=['MACHINE SHOPS, JOBBING + REPAIR']) for i in range(25)]
    rows += [dict(name='ACME MACHINE', sic=['3291'], sic_desc=['MACHINE SHOPS, JOBBING'])]
    rows += [dict(name=f'G{i}', sic=['3291'], sic_desc=['ABRASIVE PRODUCTS']) for i in range(25)]
    monkeypatch.setattr(C, 'predict', lambda texts: [('3591' if 'MACHINE' in t else '3291', 0.9, '') for t in texts])
    df = frame(rows)
    C.assign_sic(df)
    C.fix_ocr_codes(df)
    assert df[df.name == 'ACME MACHINE'].iloc[0].sic == ['3591']
    assert df[df.name == 'ACME MACHINE'].iloc[0].sic_ocr_fix == '3291->3591'
    assert (df[df.name.str.startswith('G')].sic_ocr_fix == '').all()


def test_ocr_fix_singleton_code_is_compared_with_its_neighbours_title(no_classifier):
    """A code printed once has no 'usual' description of its own; it must not vouch for itself. '2986 BOTTLED AND CANNED
    SOFT DRINKS' at a bottler is a misread 2086 (and would otherwise count as petroleum refining, major group 29)."""
    rows = [dict(name=f'BOTTLER {i}', sic=['2086'], sic_desc=['BOTTLED AND CANNED SOFT DRINKS']) for i in range(25)]
    rows += [dict(name='COCA-COLA BOTTLING CO', sic=['2986'], sic_desc=['BOTTLED AND CANNED SOFT DRINKS'])]
    rows += [dict(name=f'MILL {i}', sic=['3299'], sic_desc=['NONMETALLIC MINERAL PRODUCTS NEC']) for i in range(25)]
    rows += [dict(name='ROCK WOOL CO', sic=['3296'], sic_desc=['MINERAL WOOL'])]       # a correct rare code: no neighbour fits
    df = frame(rows)
    C.assign_sic(df)
    title = C.fix_ocr_codes(df)
    assert '2986' not in title and '3296' not in title and title['2086'] == 'bottled and canned soft drinks'
    coke = df[df.name == 'COCA-COLA BOTTLING CO'].iloc[0]
    assert coke.sic == ['2086'] and coke.sic_ocr_fix == '2986->2086'
    assert df[df.name == 'ROCK WOOL CO'].iloc[0].sic == ['3296']
    C.hazard_flags(df)
    assert not df[df.name == 'COCA-COLA BOTTLING CO'].iloc[0].fe_hazard


def test_ocr_fix_needs_a_common_target(no_classifier):
    """A neighbour seen fewer than 20 times is not a safe target."""
    rows = [dict(name=f'P{i}', sic=['2011'], sic_desc=['MEAT PACKING PLANTS']) for i in range(10)]
    rows += [dict(name='PLAT PACKING CO', sic=['2911'], sic_desc=['MEAT PACKING'])]
    df = frame(rows)
    C.assign_sic(df); C.fix_ocr_codes(df)
    assert df[df.name == 'PLAT PACKING CO'].iloc[0].sic == ['2911']


# ---- sic_dropped -------------------------------------------------------------------------------------------------------
def run_drop(rows, title=None):
    df = frame(rows)
    df['sic_source'] = df.sic.apply(lambda x: 'directory' if x else '')
    df['sic_pred_score'] = None
    df['naics'] = [[] for _ in range(len(df))]
    C.drop_bad_hazard(df, title or {})
    return df


def test_printing_ink_maker_keeps_its_chemical_code():
    """'CRAWFORD PRINTING INK' is a chemical maker (2893 printing ink), not a printer: the bakery/printer bled-in rule
    must not take the 'PRINTING' in its name as evidence against the code."""
    df = run_drop([dict(name='CRAWFORD PRINTING INK CO', sic=['2893'], sic_desc=['PRINTING INK'])])
    r = df.iloc[0]
    assert r.sic == ['2893'] and r.sic_dropped == ''


def test_printer_with_bled_in_hazard_code_still_loses_it():
    # a street line read as a SIC line ('3441 S LIPAN'): its text neither names a hazardous activity nor fits the title
    df = run_drop([dict(name='BAKER PRINTING CO', sic=['2752', '3441'], sic_desc=['COMMERCIAL PRINTING', 'S LIPAN'])],
                  title={'3441': 'fabricated structural steel'})
    r = df.iloc[0]
    assert r.sic == ['2752'] and r.sic_dropped == '3441' and r.sic_desc == ['COMMERCIAL PRINTING']
    # a hazardous code without any description (the descriptions did not pair up) is dropped as well
    df = run_drop([dict(name='MILE HI PRINTERS', sic=['2751', '3441'], sic_desc=['COM*L PRINTING EXCEPT LITHOGRAPHIC'])])
    assert df.iloc[0].sic == ['2751'] and df.iloc[0].sic_dropped == '3441'


def test_printer_keeps_a_hazard_code_its_own_description_confirms():
    """A printer that also runs injection moulding keeps 3079 when the printed description names the activity."""
    df = run_drop([dict(name='BAKER PRINTING CO', sic=['2752', '3079'], sic_desc=['COMMERCIAL PRINTING', 'INJECTION MOLDED PLASTIC PARTS'])])
    r = df.iloc[0]
    assert r.sic == ['2752', '3079'] and r.sic_dropped == ''


def test_software_house_filed_under_computer_equipment_becomes_7372():
    df = run_drop([dict(name='ROCKY MTN SOFTWARE INC', sic=['3573'], sic_desc=['PREPACKAGED SOFTWARE'])])
    r = df.iloc[0]
    assert r.sic == ['7372'] and r.sic_dropped == '3573'
    # a hardware maker with 'software' in a longer description keeps the equipment code
    df = run_drop([dict(name='ACME TERMINALS', sic=['3573'], sic_desc=['TERMINAL HARDWARE + SOFTWARE'])])
    assert df.iloc[0].sic == ['3573'] and df.iloc[0].sic_dropped == ''


def test_bakery_with_bled_in_code_loses_it():
    df = run_drop([dict(name='SUNRISE BAKERY', sic=['2051', '2800'], sic_desc=['BREAD + CAKES', 'MONACO PARKWAY 0207'])])
    assert df.iloc[0].sic == ['2051'] and df.iloc[0].sic_dropped == '2800'
    # a dairy with a lone misread code (2926 for 2026) that the OCR-fix could not reach (no common neighbour in a small run)
    df = run_drop([dict(name='VALLEY VIEW DAIRY', sic=['2926'], sic_desc=['FLUID MILK'])])
    assert df.iloc[0].sic == [] and df.iloc[0].sic_dropped == '2926'


def test_bakery_keeps_a_code_whose_description_fits_its_title():
    """Documented behaviour of the printed-description rule: a code whose own description matches the code's usual
    title is taken as the firm's (it could be a sideline), even next to a bakery name."""
    df = run_drop([dict(name='SUNRISE BAKERY', sic=['2051', '2951'], sic_desc=['BREAD + CAKES', 'ASPHALT PAVING MIXTURES'])],
                  title={'2951': 'asphalt paving mixtures and blocks'})
    assert df.iloc[0].sic == ['2051', '2951'] and df.iloc[0].sic_dropped == ''


def test_chemical_firm_untouched():
    df = run_drop([dict(name='WESTERN CHEMICAL CO', sic=['2899', '2851'], sic_desc=['CHEMICALS NEC', 'PAINTS'])])
    assert df.iloc[0].sic == ['2899', '2851'] and df.iloc[0].sic_dropped == ''


def test_predicted_hazard_code_on_a_winery_is_dropped():
    df = frame([dict(name='GRANDE RIVER WINERY', sic=[], sic_desc=['Winery'])])
    df['sic'] = [['3599']]; df['sic_source'] = ['predicted']; df['sic_pred_score'] = [0.5]; df['naics'] = [[]]
    C.drop_bad_hazard(df, {})
    assert df.iloc[0].sic == [] and df.iloc[0].sic_dropped == '3599'


# ---- hazard flags and NAICS ------------------------------------------------------------------------------------------
def flags(rows):
    df = frame(rows)
    df['sic_source'] = df.sic.apply(lambda x: 'directory' if x else '')
    return C.hazard_flags(df)


@pytest.mark.parametrize('sic,fe,ext,fe_sectors,ext_sectors', [
    (['2851'], True, False, 'Chemicals', ''),
    (['3444', '3469'], True, False, 'Fabricated metals', ''),
    (['2911'], True, False, 'Petroleum refining', ''),
    (['3079'], True, False, 'Rubber & plastics', ''),
    (['3369'], True, False, 'Primary metals', ''),
    (['3532'], True, False, 'Industrial machinery', ''),
    (['3714'], True, False, 'Transportation equipment', ''),
    (['3672'], False, True, '', 'Printed circuit boards'),
    (['2491'], False, True, '', 'Wood preserving'),
    (['1094'], False, True, '', 'Metal mining / ore milling'),
    (['2951'], True, False, 'Petroleum refining', 'Asphalt paving mixtures'),   # 29xx is an F&E major group
    (['2851', '3672'], True, False, 'Chemicals', 'Printed circuit boards'),   # ext is reported but ext_hazard excludes F&E firms
    (['2011'], False, False, '', ''),
    (['2752', '7372'], False, False, '', ''),
    ([], False, False, '', ''),
])
def test_hazard_flags(sic, fe, ext, fe_sectors, ext_sectors):
    r = flags([dict(name='X', sic=sic)]).iloc[0]
    assert (bool(r.fe_hazard), bool(r.ext_hazard), r.fe_sectors, r.ext_sectors) == (fe, ext, fe_sectors, ext_sectors)


def test_sic2_and_normalised_keys():
    r = flags([dict(name='The Acme Mfg. Co., Inc.', street='1234 West Alameda Avenue', sic=['3444', '3469', '2851'])]).iloc[0]
    assert r.sic2 == ['28', '34']
    assert r.name_n == 'ACME' and r.street_n == '1234 W ALAMEDA AVE'


@pytest.mark.parametrize('naics,sic,fe,ext', [
    (['325510'], ['2800'], True, False),       # chemicals
    (['324110'], ['2900'], True, False),
    (['326199'], ['3000'], True, False),
    (['331524'], ['3300'], True, False),
    (['332710'], ['3400'], True, False),
    (['333120'], ['3500'], True, False),
    (['336211'], ['3700'], True, False),
    (['321114'], ['2491'], False, True),       # wood preserving
    (['334412'], ['3672'], False, True),
    (['335911'], ['3691'], False, True),
    (['212231'], ['1000'], False, True),       # metal ore mining
    (['311611'], [], False, False),            # meat processing: no SIC, no flag
    (['541511'], [], False, False),
])
def test_naics_mapping(naics, sic, fe, ext, no_classifier):
    df = frame([dict(name='X', year=1999, naics=naics)])
    C.assign_sic(df)
    r = df.iloc[0]
    assert r.sic == sic
    assert r.sic_source == 'naics'      # every record whose only code is a NAICS code, even when it maps to nothing
    C.hazard_flags(df)
    assert (bool(df.iloc[0].fe_hazard), bool(df.iloc[0].ext_hazard)) == (fe, ext)


def test_sic_from_naics_direct():
    assert C.sic_from_naics(['325992', '336999', '999999']) == ['3861', '3700']


def test_assign_sic_sources(monkeypatch):
    """Printed codes stay 'directory'; a description alone is predicted or keyword-matched; a bare name can be keyword-matched."""
    monkeypatch.setattr(C, 'predict', lambda texts: [('2752', 0.9, 'commercial printing') for _ in texts])
    df = frame([dict(name='A PRINTER', sic=['2752'], sic_desc=['COMMERCIAL PRINTING']),
                dict(name='B', sic=[], sic_desc=['OFFSET PRINTING']),
                dict(name='C', sic=[], sic_desc=['PETROLEUM REFINERY']),          # keyword beats a disagreeing prediction
                dict(name='DENVER SMELTING CO', sic=[], sic_desc=[]),               # name keyword
                dict(name='E', sic=[], sic_desc=[])])
    C.assign_sic(df)
    assert df.sic_source.tolist() == ['directory', 'predicted', 'keyword', 'name_keyword', '']
    assert df.sic.tolist() == [['2752'], ['2752'], ['2911'], ['3339'], []]
    assert df.sic_pred_score.tolist()[1] == 0.9


def test_kw_sic():
    assert C.kw_sic('CUSTOM ORE MILLING') == '1099'
    assert C.kw_sic('ELECTROPLATING') == '3471'
    assert C.kw_sic('bread') is None


def test_strip_quotes_removes_ocr_quote_noise():
    # data.table::fread misreads CSV fields that start or end with escaped quotes (five quotes + COX -> 4 quotes) and
    # each R rewrite doubles them (committed sites.csv: 16 quotes before COX, TOLBERT G). prepare() strips them.
    df = pd.DataFrame({'name': ['""COX, TOLBERT G, SHEET METAL', 'PLAIN CO'], 'street': ['500 GRANT ""', None],
                       'sic': [['3441'], None], 'sic_desc': [['SHEET "METAL" WORK'], None], 'n': [1, 2]})
    out = C.prepare(df)
    assert out.name.tolist() == ['COX, TOLBERT G, SHEET METAL', 'PLAIN CO']
    assert out.street.tolist()[0] == '500 GRANT' and pd.isna(out.street.tolist()[1])
    assert out.sic_desc.tolist() == [['SHEET METAL WORK'], []]
    assert out.n.tolist() == [1, 2]
