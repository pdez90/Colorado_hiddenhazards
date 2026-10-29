"""Test harness for the digitization stage (pipeline/segment.py, parse_*.py, consolidate.py, sic_classifier.py, link.py).

The pipeline modules read work/inv/co_cities.txt and work/inv/zip_city.csv relative to the current directory when they
are imported, and write work/parsed, work/inv when run. So this conftest builds a throw-away workspace, reconstructs
the gazetteer from data/geocoder/zip_city.csv (the FRS facility file it is normally built from is not in the repo),
chdirs into the workspace and puts pipeline/ on sys.path before any test module imports a pipeline module. OCR pages
are extracted from data/ocr/dcm_ocr_output.tar.gz on demand (only the volumes a test asks for).

Set DCM_PIPELINE=/path/to/other/pipeline to run the suite against another copy of the code (e.g. `git show HEAD:...`
exports) and DCM_KEEP_WS=1 to keep the workspace after the run."""
import os, sys, re, csv, json, shutil, tarfile, tempfile, pathlib, functools
import pytest

REPO = pathlib.Path(__file__).resolve().parents[2]
PIPELINE = pathlib.Path(os.environ.get('DCM_PIPELINE', REPO / 'pipeline')).resolve()
OCR_TAR = REPO / 'data' / 'ocr' / 'dcm_ocr_output.tar.gz'
ZIP_CITY = REPO / 'data' / 'geocoder' / 'zip_city.csv'

# volumes parsed by the golden-count tests and used to train the test classifier (1967 and 1977 are coded editions)
GOLDEN_VOLS = {'DCM_1967_part1': 1967, 'DCM_1977_part1': 1977, 'DCM_1965': 1965, 'DCM_1992_part3': 1992}

WS = pathlib.Path(tempfile.mkdtemp(prefix='dcm_digitization_tests_'))
for d in ('work/inv', 'work/tsv', 'work/parsed', 'work/coltxt'):
    (WS / d).mkdir(parents=True, exist_ok=True)


def build_gazetteer(ws=WS):
    """work/inv/co_cities.txt (city names of every Colorado ZIP) and work/inv/zip_city.csv from data/geocoder/zip_city.csv."""
    rows = list(csv.DictReader(open(ZIP_CITY)))
    cities = sorted({r['CITY_NAME'].upper().strip() for r in rows if re.match(r'^8[01]\d{3}$', r['z'])})
    (ws / 'work/inv/co_cities.txt').write_text('\n'.join(cities))
    shutil.copy(ZIP_CITY, ws / 'work/inv/zip_city.csv')
    return cities


build_gazetteer()
os.chdir(WS)
sys.path.insert(0, str(PIPELINE))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))   # synth.py helper


def pytest_sessionfinish(session, exitstatus):
    if not os.environ.get('DCM_KEEP_WS'):
        os.chdir(REPO)
        shutil.rmtree(WS, ignore_errors=True)


_extracted = set()


def extract_volumes(vols):
    """Extract the OCR pages (tsv/<vol>/p*.tsv) of the given volumes into the workspace; one pass over the tarball."""
    todo = [v for v in vols if v not in _extracted]
    if todo:
        prefixes = tuple(f'tsv/{v}/' for v in todo)
        with tarfile.open(OCR_TAR) as tf:
            members = [m for m in tf.getmembers() if m.name.startswith(prefixes)]
            tf.extractall(WS / 'work', members=members, filter='data')
        _extracted.update(todo)
    return WS / 'work' / 'tsv'


@functools.lru_cache(maxsize=None)
def ocr_members():
    """Names of every member of the OCR tarball (for the volume-table sanity test)."""
    with tarfile.open(OCR_TAR) as tf:
        return tf.getnames()


@pytest.fixture(scope='session')
def workspace():
    return WS


@pytest.fixture(scope='session')
def tsv_root():
    return extract_volumes(GOLDEN_VOLS)


@pytest.fixture(scope='session')
def parsed(tsv_root):
    """{volume: records} for GOLDEN_VOLS, parsed with the production dispatcher; also written to work/parsed/<vol>.jsonl."""
    import parse_all
    from volumes import VOLUMES
    out = {}
    for vol in GOLDEN_VOLS:
        year, parser, mode = VOLUMES[vol]
        R = parse_all.parse_vol(vol, year, parser, mode, T=str(tsv_root))
        with open(WS / 'work/parsed' / f'{vol}.jsonl', 'w') as f:
            for r in R: f.write(json.dumps(r) + '\n')
        out[vol] = R
    return out


@pytest.fixture(scope='session')
def classifier(parsed):
    """Description->SIC model trained on the coded golden volumes (1967, 1977); installed as the model sic_predict uses."""
    import sic_classifier, sic_predict, pickle
    model = sic_classifier.train(str(WS / 'work/parsed/*.jsonl'))
    pickle.dump(model, open(WS / 'work/inv/sic_clf.pkl', 'wb'))
    sic_predict.M = model
    return model


@pytest.fixture(scope='session')
def consolidated(parsed, classifier):
    """consolidate stages run over the golden volumes (the real classifier), as main() runs them."""
    import consolidate
    df = consolidate.load_parsed(str(WS / 'work/parsed/*.jsonl'))
    consolidate.assign_sic(df)
    title = consolidate.fix_ocr_codes(df)
    consolidate.drop_bad_hazard(df, title)
    consolidate.hazard_flags(df)
    return df
