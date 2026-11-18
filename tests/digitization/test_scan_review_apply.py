"""apply_scan_review (pipeline/consolidate.py): the hand review of hazardous listings against the scans changes exactly the fields
it names (14 Nov 2026)."""
import os, sys
import pandas as pd
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'pipeline'))
import consolidate as C


def _df():
    return pd.DataFrame(dict(vol=['DCM_1988_part3'] * 4 + ['DCM_1966_part2'], page=[30, 30, 31, 31, 2],
                             name=['RUBBER RQGKY MIN', 'COUNTED THREAD', 'HEADING', 'OK FIRM', 'RUBBER STAMP CO'],
                             street=['375 S RARITAN', '1285 S JASON ST', None, '1 MAIN', '12 W COLORADO AVE'],
                             city_ctx=['ENGLEWOOD', 'DENVER', 'DENVER', 'DENVER', 'COLORADO SPRINGS'],
                             sic=[['3069', '2732'], ['3305'], ['3441'], ['3441'], ['3069', '2741']], sic_desc=[[], [], [], [], []],
                             sic_source=['directory'] * 4 + ['name_keyword']))


def _review(tmp_path):
    R = pd.DataFrame([
        dict(year='1988', vol='DCM_1988_part3', page='30', name='RUBBER RQGKY MIN', street='375 S RARITAN', verdict='fix',
             name_fix='ROCKY MTN RUBBER MFG CO', street_fix='2375 S RARITAN', city_fix='', sic_printed='3069', hazardous='yes', note='x'),
        dict(year='1988', vol='DCM_1988_part3', page='30', name='COUNTED THREAD', street='1285 S JASON ST', verdict='ok', name_fix='',
             street_fix='', city_fix='', sic_printed='2721', hazardous='no', note='publisher'),
        dict(year='1988', vol='DCM_1988_part3', page='31', name='HEADING', street='', verdict='not_listing', name_fix='',
             street_fix='', city_fix='', sic_printed='', hazardous='', note='heading'),
        dict(year='1966', vol='DCM_1966_part2', page='2', name='RUBBER STAMP CO', street='12 W COLORADO AVE', verdict='fix',
             name_fix='AAA RUBBER STAMP CO', street_fix='2802 1/2 W COLORADO AVE', city_fix='', sic_printed='', hazardous='no',
             note='pens, pencils, office mat')])
    p = tmp_path / 'r.csv'; R.to_csv(p, index=False); return str(p)


def test_fields_named_by_the_review_are_replaced_and_nothing_else(tmp_path):
    d = C.apply_scan_review(_df(), _review(tmp_path))
    assert list(d.name) == ['ROCKY MTN RUBBER MFG CO', 'COUNTED THREAD', 'OK FIRM', 'AAA RUBBER STAMP CO']       # heading dropped
    assert list(d.street) == ['2375 S RARITAN', '1285 S JASON ST', '1 MAIN', '2802 1/2 W COLORADO AVE']
    assert list(d.sic) == [['3069'], ['2721'], ['3441'], ['2741']]
    # codes read from the page are printed codes: they keep the source 'directory' (so the site counts as printed evidence);
    # a 'no' on an edition without printed codes only removes the hazardous codes
    assert list(d.sic_source) == ['directory', 'directory', 'directory', 'name_keyword']
    C.hazard_flags(d)
    assert list(d.fe_hazard) == [True, False, True, False]


def test_missing_review_file_changes_nothing(tmp_path):
    a = _df(); b = C.apply_scan_review(_df(), str(tmp_path / 'none.csv'))
    assert a.equals(b.drop(columns='name_parsed')) and (b.name_parsed == b['name']).all()      # only the as-parsed copy of the name is added
