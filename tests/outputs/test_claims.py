"""Claims registry: every number quoted in the write-ups must still be what the data say.

``claims.yml`` holds one entry per claim:

    - id: sites_total                       # unique name
      file: README.md                       # text file the claim appears in (repo-relative)
      text: "**3,169 hazardous-sector sites**"   # exact substring that must occur in that file
      check: "len(fe_sites())"              # Python expression over the data files
      expect: 3169                          # number or list of numbers the expression must give
      tol: 0.5                              # optional absolute tolerance (default: half the last printed decimal)
      stale: "reason"                       # optional: the text is known to be out of date (strict xfail)

Two things are asserted for each claim: the text is present in the named file, and the
expression evaluates to the quoted value(s). Either failing means a rerun changed a number
(update the text and the claim), or the text was edited (update the claim).

Expressions can use: load(path[, sheet]), text(path), listings(), sites(), fe_sites(),
hidden_sites(), fisher_exact_p(a, b, c, d), mh_conditional_or(strata), num(s), pd, np, re, math, REPO (the repository path).
"""
import math
import re
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import yaml

import outputs_helpers as C

HERE = Path(__file__).resolve().parent
CLAIMS = yaml.safe_load((HERE / "claims.yml").read_text(encoding="utf-8"))

NAMESPACE = {
    "load": C.load, "text": C.text, "listings": C.listings, "sites": C.sites, "fe_sites": C.fe_sites,
    "hidden_sites": C.hidden_sites, "fisher_exact_p": C.fisher_exact_p, "mh_conditional_or": C.mh_conditional_or,
    "num": C.num, "pd": pd, "np": np, "re": re, "math": math, "len": len, "abs": abs, "round": round,
    "sum": sum, "min": min, "max": max, "int": int, "float": float, "list": list, "sorted": sorted, "set": set,
    "zip": zip, "range": range, "str": str, "bool": bool, "REPO": C.REPO,
}


def _as_list(x):
    if isinstance(x, (list, tuple, np.ndarray, pd.Series)):
        return [float(v) for v in x]
    return [float(x)]


def _default_tol(v):
    """Half a unit of the last decimal place as the number is written in claims.yml."""
    if isinstance(v, bool):
        return 0.5
    if isinstance(v, int):
        return 0.5
    s = repr(float(v))
    if "e" in s or "E" in s:
        return abs(float(v)) * 0.005 + 1e-12
    dec = len(s.split(".")[1]) if "." in s else 0
    return 0.5 * 10 ** (-dec) + 1e-12


def test_registry_is_well_formed():
    ids = [c["id"] for c in CLAIMS]
    assert len(ids) == len(set(ids)), "duplicate claim ids"
    assert len(CLAIMS) >= 40
    for c in CLAIMS:
        assert {"id", "file", "text", "check", "expect"} <= set(c), c.get("id")
        assert C.rel(c["file"]).exists(), c["file"]


def _param(c):
    marks = []
    if c.get("stale"):
        marks.append(pytest.mark.xfail(strict=True, reason="known stale text: " + str(c["stale"])))
    return pytest.param(c, id=c["id"], marks=marks)


@pytest.mark.parametrize("claim", [_param(c) for c in CLAIMS])
def test_claim(claim):
    body = C.text(claim["file"])
    assert claim["text"] in body, f"text not found in {claim['file']}: {claim['text']!r}"
    try:
        # one namespace for globals so that names resolve inside lambdas and comprehensions too
        got = eval(claim["check"], dict(NAMESPACE, __builtins__={}))
    except Exception as e:  # noqa: BLE001
        pytest.fail(f"check raised {type(e).__name__}: {e}\n  check: {claim['check']}")
    got_l = _as_list(got)
    exp_raw = claim["expect"] if isinstance(claim["expect"], list) else [claim["expect"]]
    exp_l = [float(v) for v in exp_raw]
    assert len(got_l) == len(exp_l), f"check gave {len(got_l)} value(s) {got_l}, expected {len(exp_l)} {exp_l}"
    tol = claim.get("tol")
    tols = (tol if isinstance(tol, list) else [tol] * len(exp_l)) if tol is not None else [_default_tol(v) for v in exp_raw]
    bad = [(e, g, t) for e, g, t in zip(exp_l, got_l, tols) if not (abs(e - g) <= t)]
    assert not bad, f"{claim['id']}: data give {got_l}, text says {exp_l} (tolerances {tols}); mismatches {bad}"
