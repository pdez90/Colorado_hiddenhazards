"""The pipeline modules import without running anything: no files read beyond the gazetteer, nothing written."""
import os, subprocess, sys, shutil
import pytest
from conftest import PIPELINE, build_gazetteer

MODULES = ['segment', 'volumes', 'geoctx', 'parse_block', 'parse_1965', 'parse_1988', 'parse_2002', 'parse_para', 'parse_table',
           'parse_all', 'sic_classifier', 'sic_classifier_norm', 'sic_predict', 'consolidate', 'link', 'make_gazetteer']


def test_modules_import_without_side_effects(tmp_path):
    (tmp_path / 'work' / 'inv').mkdir(parents=True)
    build_gazetteer(tmp_path)
    before = sorted(str(p.relative_to(tmp_path)) for p in tmp_path.rglob('*'))
    code = 'import ' + ', '.join(MODULES) + '; print("ok")'
    r = subprocess.run([sys.executable, '-c', code], cwd=tmp_path, capture_output=True, text=True,
                       env={**os.environ, 'PYTHONPATH': str(PIPELINE), 'PYTHONDONTWRITEBYTECODE': '1'})
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == 'ok' and r.stderr == ''
    after = sorted(str(p.relative_to(tmp_path)) for p in tmp_path.rglob('*'))
    assert after == before, 'importing created files: ' + str(sorted(set(after) - set(before)))


def test_scripts_have_main_guards():
    for m in ['parse_all', 'sic_classifier', 'consolidate', 'link', 'make_gazetteer', 'parse_block', 'parse_1965', 'parse_1988',
              'parse_2002', 'parse_para', 'parse_table', 'segment']:
        src = (PIPELINE / f'{m}.py').read_text()
        assert "if __name__" in src, m


def test_parse_all_dispatch(tmp_path):
    import parse_all
    (tmp_path / 'EMPTY_VOL').mkdir()
    for parser in ['block', '1965', 'table', '1988', 'para']:
        assert parse_all.parse_vol('EMPTY_VOL', 1977, parser, 'tsv', T=str(tmp_path)) == []
