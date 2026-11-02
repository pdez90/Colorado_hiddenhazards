"""The Supplementary Information is what the data say.

paper/si/make_si.py builds paper/si/si_blocks.json (every SI paragraph and table) from the committed result files and asserts,
inside the script, that each hard-coded figure still matches its source. This test runs the builder in a temporary copy and
checks that it (a) runs without an assertion failing and (b) reproduces the committed si_blocks.json exactly, so a rerun that
moves an SI number fails until paper/si/si_blocks.json and the .docx are rebuilt (python3 paper/si/make_si.py; node paper/si/build_si.js).
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def test_si_blocks_reproduce():
    with tempfile.TemporaryDirectory() as td:
        si = Path(td) / "si"
        shutil.copytree(REPO / "paper" / "si", si, ignore=shutil.ignore_patterns("node_modules", "__pycache__"))
        script = (si / "make_si.py").read_text(encoding="utf-8")
        # point the temporary copy at the repository's result files but write beside itself
        script = script.replace("A = os.path.abspath(os.path.join(HERE, '..', '..')) + '/'", "A = %r + '/'" % str(REPO))
        (si / "make_si.py").write_text(script, encoding="utf-8")
        r = subprocess.run([sys.executable, "-I", str(si / "make_si.py")], capture_output=True, text=True, cwd=str(REPO))
        assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]
        new = json.load(open(si / "si_blocks.json", encoding="utf-8"))
    old = json.load(open(REPO / "paper" / "si" / "si_blocks.json", encoding="utf-8"))
    assert len(new) == len(old)
    for i, (a, b) in enumerate(zip(old, new)):
        assert a == b, f"SI block {i} ({a.get('type')}: {a.get('text', a.get('caption', ''))[:60]!r}) differs from a fresh build"
