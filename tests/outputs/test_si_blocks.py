"""The Supplementary Information is what the data say.

paper/si/make_si.py builds paper/si/si_blocks.json (every SI paragraph and table) from the committed result files; its counts are
computed from those files and its chk(...) calls compare each with a second computation. This test runs the builder in a temporary copy and
checks that it (a) runs without an assertion failing and (b) reproduces the committed si_blocks.json exactly, so a rerun that
moves an SI number fails until paper/si/si_blocks.json and the .docx are rebuilt (python3 paper/si/make_si.py; node paper/si/build_si.js).
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pandas as pd
import pytest

REPO = Path(__file__).resolve().parents[2]


def test_si_blocks_reproduce():
    with tempfile.TemporaryDirectory() as td:
        si = Path(td) / "si"
        shutil.copytree(REPO / "paper" / "si", si, ignore=shutil.ignore_patterns("node_modules", "__pycache__"))
        script = (si / "make_si.py").read_text(encoding="utf-8")
        # point the temporary copy at the repository's result files but write beside itself
        script = script.replace("A = os.path.abspath(os.path.join(HERE, '..', '..')) + '/'", "A = %r + '/'" % str(REPO))
        (si / "make_si.py").write_text(script, encoding="utf-8")
        # -P (3.11+): the script's folder is not put on sys.path. Not -I, which would also hide a user-site pandas (pip --user)
        flags = ["-P"] if sys.version_info >= (3, 11) else []
        r = subprocess.run([sys.executable, *flags, str(si / "make_si.py")], capture_output=True, text=True, cwd=str(REPO))
        assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]
        new = json.load(open(si / "si_blocks.json", encoding="utf-8"))
    old = json.load(open(REPO / "paper" / "si" / "si_blocks.json", encoding="utf-8"))
    assert len(new) == len(old)
    for i, (a, b) in enumerate(zip(old, new)):
        assert a == b, f"SI block {i} ({a.get('type')}: {a.get('text', a.get('caption', ''))[:60]!r}) differs from a fresh build"


def _listings_by_edition():
    return pd.read_csv(REPO / "data" / "full_inventory" / "CO_directory_listings_1961-2002.csv", usecols=["year"]).year.value_counts().sort_index()


def test_edition_coverage_listing_counts_are_those_of_the_listing_file():
    ec = pd.read_csv(REPO / "data" / "results" / "edition_coverage.csv")
    ec = ec[ec.series == "Directory of Colorado Manufacturers"].set_index("year").listings
    now = _listings_by_edition()
    assert ec.to_dict() == now.to_dict(), {int(y): (int(ec[y]), int(now[y])) for y in now.index if ec.get(y) != now[y]}


def test_benchmark_table_is_built_on_the_current_listings():
    cb = pd.read_csv(REPO / "data" / "results" / "benchmarks" / "cbp_vs_directory_state.csv").dropna(subset=["listings"]).set_index("year").listings.astype(int)
    now = _listings_by_edition()
    assert cb.to_dict() == now[cb.index].to_dict(), {int(y): (int(cb[y]), int(now[y])) for y in cb.index if cb[y] != now[y]}
