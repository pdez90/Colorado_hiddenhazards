"""Shared helpers for the output-consistency and claims tests (tests/outputs).

Kept out of conftest.py so that `import outputs_helpers` is unambiguous when several test
directories, each with its own conftest.py, are collected in one pytest run.

Everything here reads the committed files only (app/data, data/results, data/by_year,
data/full_inventory); nothing touches the network or work/.
"""
import json
import os
import re
from functools import lru_cache
from pathlib import Path

import pandas as pd

REPO = Path(__file__).resolve().parents[2]
APP_DATA = REPO / "app" / "data"
RESULTS = REPO / "data" / "results"
WORK = REPO / "work"


def rel(path):
    """Absolute path for a repo-relative string."""
    p = Path(path)
    return p if p.is_absolute() else REPO / p


@lru_cache(maxsize=None)
def _load_cached(path, sheet, as_str):
    p = rel(path)
    if not p.exists():
        raise FileNotFoundError(str(p))
    suf = p.suffix.lower()
    if suf == ".csv":
        if as_str:
            return pd.read_csv(p, dtype=str, keep_default_na=False, low_memory=False)
        return pd.read_csv(p, low_memory=False)
    if suf == ".geojson":
        with open(p, encoding="utf-8") as fh:
            gj = json.load(fh)
        rows = []
        for f in gj["features"]:
            d = dict(f.get("properties") or {})
            g = f.get("geometry")
            if g and g.get("type") == "Point":
                d["lon"], d["lat"] = g["coordinates"][0], g["coordinates"][1]
            d["_geometry_type"] = g["type"] if g else None
            rows.append(d)
        df = pd.DataFrame(rows)
        return df.astype(str) if as_str else df
    if suf in (".xlsx", ".xlsm"):
        return pd.read_excel(p, sheet_name=sheet or 0, dtype=str if as_str else None)
    raise ValueError(f"load(): unsupported file type {suf} ({p})")


def load(path, sheet=None, as_str=False):
    """Return a DataFrame for a repo-relative CSV, GeoJSON (feature properties + lon/lat) or xlsx sheet.

    The result is cached and must not be mutated in place; use .copy() if you need to.
    """
    return _load_cached(str(path), sheet, bool(as_str)).copy()


def text(path):
    """Return a text file's content."""
    return rel(path).read_text(encoding="utf-8")


def gj_features(path):
    with open(rel(path), encoding="utf-8") as fh:
        return json.load(fh)["features"]


def listings():
    """The committed listings of the 13 complete editions (one row per directory listing)."""
    return load("data/results/CO_directory_listings_1961-2002.csv", as_str=True)


def sites():
    return load("app/data/sites.csv", as_str=True)


def fisher_exact_p(a, b, c, d):
    """Two-sided Fisher exact p for the 2x2 table [[a, b], [c, d]] (sum of tables at most as probable)."""
    import math

    n = a + b + c + d
    r1, c1 = a + b, a + c

    def pr(x):
        return math.comb(r1, x) * math.comb(n - r1, c1 - x) / math.comb(n, c1)

    po = pr(a)
    lo, hi = max(0, c1 - (n - r1)), min(r1, c1)
    return sum(pr(x) for x in range(lo, hi + 1) if pr(x) <= po * (1 + 1e-9))


def mh_conditional_or(strata, lo=1e-4, hi=1e4):
    """Exact conditional MLE of the common odds ratio over 2x2 strata [(a, b, c, d), ...]
    (what R's mantelhaen.test(exact = TRUE) reports)."""
    import math

    def expected(psi):
        tot = 0.0
        for a, b, c, d in strata:
            r1, c1, n = a + b, a + c, a + b + c + d
            xs = range(max(0, c1 - (n - r1)), min(r1, c1) + 1)
            w = [math.comb(r1, x) * math.comb(n - r1, c1 - x) * psi ** x for x in xs]
            tot += sum(x * wi for x, wi in zip(xs, w)) / sum(w)
        return tot

    obs = sum(s[0] for s in strata)
    for _ in range(300):
        mid = (lo * hi) ** 0.5
        if expected(mid) < obs:
            lo = mid
        else:
            hi = mid
    return mid


def fe_sites():
    """Frickel & Elliott hazardous-sector sites (fe_hazard TRUE) from app/data/sites.csv."""
    s = sites()
    return s[s.fe_hazard.str.upper() == "TRUE"]


def hidden_sites():
    f = fe_sites()
    return f[f.radar == "Not on any list"]


def all_files(root, exts=None):
    out = []
    for dirpath, _, files in os.walk(rel(root)):
        for f in files:
            p = Path(dirpath) / f
            if exts is None or p.suffix.lower() in exts:
                out.append(p)
    return sorted(out)


def num(s):
    """Parse a printed number ('3,169', '29%', '−0.22') to float."""
    s = str(s).replace(",", "").replace("%", "").replace("−", "-").strip()
    return float(s)


_ = re  # re is re-exported for claim expressions
