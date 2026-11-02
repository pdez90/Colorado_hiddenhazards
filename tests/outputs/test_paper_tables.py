"""The manuscript's tables against the committed data (paper/make_tables.py).

Fast, offline. ``make_tables.py`` rebuilds each of the 23 tables of the manuscript from data/results;
this test imports it (no subprocess) and checks that every generated data row appears verbatim as a
line of paper/Before_and_After_the_Map_manuscript.md. A failure names the table and shows the first
generated row that is missing together with the closest line of the manuscript, so the stale row can
be pasted into the Doc. Fix the data or the manuscript, never the test or the generator's formatting,
when a row differs.
"""
import difflib
import importlib.util
import sys

import pytest

from outputs_helpers import REPO

MANUSCRIPT = REPO / "paper" / "Before_and_After_the_Map_manuscript.md"
N_TABLES = 23


def _load_make_tables():
    spec = importlib.util.spec_from_file_location("make_tables", REPO / "paper" / "make_tables.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules.setdefault("make_tables", mod)
    spec.loader.exec_module(mod)
    return mod


make_tables = _load_make_tables()


@pytest.fixture(scope="module")
def manuscript_lines():
    return MANUSCRIPT.read_text(encoding="utf-8").splitlines()


@pytest.fixture(scope="module")
def manuscript_table_lines(manuscript_lines):
    """Lines of the manuscript that are table rows (start with '|')."""
    return [ln for ln in manuscript_lines if ln.startswith("|")]


def _manuscript_tables(lines):
    """Index of each header line that is followed by a '| --- |' separator."""
    return [i for i in range(len(lines) - 1)
            if lines[i].startswith("|") and lines[i + 1].startswith("|")
            and set(lines[i + 1].replace("|", "").replace("-", "").strip()) == set()
            and "---" in lines[i + 1]]


def test_manuscript_has_23_tables(manuscript_lines):
    heads = _manuscript_tables(manuscript_lines)
    assert len(heads) == N_TABLES, [h + 1 for h in heads]


def test_generator_builds_23_tables():
    assert len(make_tables.TABLES) == N_TABLES


@pytest.mark.parametrize("builder", make_tables.TABLES, ids=lambda f: f.__name__)
def test_table_rows_in_manuscript(builder, manuscript_table_lines):
    table = builder()
    assert table.rows, f"{table.id}: generator produced no rows"
    present = set(manuscript_table_lines)
    missing = [r for r in table.rows if r not in present]
    if missing:
        first = missing[0]
        close = difflib.get_close_matches(first, manuscript_table_lines, n=1, cutoff=0.0)
        closest = close[0] if close else "(no similar line)"
        pytest.fail(
            f"{table.id}: {len(missing)} of {len(table.rows)} generated rows are not in the manuscript "
            f"(source: {table.source}).\n  generated:  {first}\n  manuscript: {closest}"
        )


@pytest.mark.parametrize("builder", make_tables.TABLES, ids=lambda f: f.__name__)
def test_table_header_in_manuscript(builder, manuscript_table_lines):
    table = builder()
    assert table.header in manuscript_table_lines, f"{table.id}: header not in manuscript\n  generated: {table.header}"
