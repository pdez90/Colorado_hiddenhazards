#!/usr/bin/env python3
"""Rebuild the 23 tables of the manuscript (Before and After the Map) from the committed result files.

Run from the repository root:

    python3 paper/make_tables.py

Writes paper/tables_generated.md. Each table is preceded by a comment line
``<!-- table: <id> ; source: <files> -->`` and is formatted exactly as the manuscript's Markdown
export formats it (same header, column order, rounding, thousands separators, Unicode minus and
en dashes, escaped significance stars ``\\*``, ``—`` for missing cells).

The module is also importable: ``TABLES`` is the ordered list of builders; each returns a
``Table`` (id, source, header line, separator line, data rows). tests/outputs/test_paper_tables.py
calls them in-process and checks every data row against the manuscript.

Only pandas is required. Nothing under work/ is read.
"""
from __future__ import annotations

import math
import sys
from collections import namedtuple
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import pandas as pd

REPO = Path(__file__).resolve().parents[1]
RESULTS = REPO / "data" / "results"
OUT = REPO / "paper" / "tables_generated.md"

MINUS = "−"  # Unicode minus, as the manuscript export uses
DASH = "—"
EN = "–"

Table = namedtuple("Table", "id source header sep rows")


# ----------------------------------------------------------------------------------------------
# formatting helpers
# ----------------------------------------------------------------------------------------------

def _isnan(v):
    try:
        return v is None or (isinstance(v, float) and math.isnan(v)) or pd.isna(v)
    except (TypeError, ValueError):
        return False


def num(v, d=1, sign=False, thousands=False, pct=False, half_up=False):
    """Format a number with d decimals; Unicode minus; '+' when sign=True; a zero never carries a sign.

    By default the rounding is C's printf rounding of the binary double (what R's sprintf/format and Python
    give), which reproduces the manuscript's rows. ``half_up=True`` rounds the decimal text of the CSV value
    half away from zero instead; two tables (Table 23 and the first-arrival table) were formatted that way.
    """
    if _isnan(v):
        return DASH
    if half_up:
        q = Decimal(str(v)).quantize(Decimal(1).scaleb(-d), rounding=ROUND_HALF_UP)
        s = f"{abs(q):,.{d}f}" if thousands else f"{abs(q):.{d}f}"
        is_zero = q == 0
        neg = q < 0
    else:
        v = float(v)
        s = f"{abs(v):,.{d}f}" if thousands else f"{abs(v):.{d}f}"
        is_zero = float(s.replace(",", "")) == 0.0
        neg = v < 0
    if is_zero:
        out = s
    elif neg:
        out = MINUS + s
    else:
        out = ("+" if sign else "") + s
    return out + ("%" if pct else "")


def stars(p, levels=(0.05, 0.01, 0.001)):
    """Escaped significance stars as in the Markdown export: \\* p<0.05, \\*\\* p<0.01, \\*\\*\\* p<0.001.

    ``levels`` can be shortened to two entries for tables that only use \\* and \\*\\*.
    """
    if _isnan(p):
        return ""
    n = sum(1 for lv in levels if p < lv)
    return "\\*" * n


def coef(b, p, d=1, sign=True, levels=(0.05, 0.01, 0.001)):
    if _isnan(b):
        return DASH
    return num(b, d, sign=sign) + stars(p, levels)


def ci(est, lo, hi, d, half_up=False):
    """'est (lo to hi)' as in Tables 22 and 23."""
    return f"{num(est, d, half_up=half_up)} ({num(lo, d, half_up=half_up)} to {num(hi, d, half_up=half_up)})"


def rr(est, lo, hi, d=3):
    """'rr (lo–hi)' as in the block mortality table."""
    return f"{num(est, d)} ({num(lo, d)}{EN}{num(hi, d)})"


def pval(p):
    """Conley p as the boundary table prints it: <0.001; three decimals under 0.1; else two."""
    if _isnan(p):
        return DASH
    if p < 0.001:
        return "<0.001"
    if p < 0.1:
        return f"{p:.3f}"
    return f"{p:.2f}"


def en(s):
    """Replace ASCII hyphen between digits by an en dash (1891-1905 -> 1891–1905)."""
    return str(s).replace("-", EN)


def row(cells):
    return "| " + " | ".join(str(c) for c in cells) + " |"


def sep(n):
    return "| " + " | ".join(["---"] * n) + " |"


def make(tid, source, header, rows):
    return Table(tid, source, row(header), sep(len(header)), [row(r) for r in rows])


def read(rel, **kw):
    return pd.read_csv(RESULTS / rel, **kw)


# ----------------------------------------------------------------------------------------------
# Section 3: enumeration districts 1880–1940
# ----------------------------------------------------------------------------------------------

def t01_composition():
    src = "data/results/denver_eds/ed_year_groups.csv"
    d = read("denver_eds/ed_year_groups.csv")
    header = ["census", "group", "EDs", "population", "% Black", "% foreign born", "% Hispanic", "% laborers",
              "% owner households", "% boarders and lodgers"]
    rows = []
    for census in sorted(d.census.unique()):
        for grp, label in (("EDs with hazardous firms", "with hazardous firms"), ("EDs without", "without")):
            r = d[(d.census == census) & (d.group == grp)].iloc[0]
            rows.append([census, label, int(r.EDs), num(r.population, 0, thousands=True), num(r.pct_black, 2),
                         num(r.pct_fb, 1), num(r.pct_hisp, 2), num(r.pct_laborers, 1), num(r.pct_owner_hh, 1),
                         num(r.pct_boarders, 1)])
    return make("s3_composition", src, header, rows)


ED_OUTCOMES = [("% White", "pct_white"), ("% Black", "pct_black"), ("% Hispanic", "pct_hisp"),
               ("% foreign born", "pct_fb"), ("% laborers", "pct_laborers"), ("% owner households", "pct_owner_hh"),
               ("mean SEI", "mean_sei"), ("% boarders and lodgers", "pct_boarders"),
               ("% in hazardous industries (workers)", "pct_haz_industry")]


def t02_ed_gradients():
    src = "data/results/denver_eds/ed_distance_models.csv"
    d = read("denver_eds/ed_distance_models.csv")
    years = [1880, 1900, 1910, 1920, 1930, 1940]
    header = ["outcome (percentage points per log m)"] + [str(y) for y in years] + ["pooled", "pooled, downtown controlled"]
    rows = []
    for label, oc in ED_OUTCOMES:
        cells = [label]
        for y in years:
            r = d[(d.census == y) & (d.outcome == oc)]
            cells.append(DASH if r.empty or _isnan(r.iloc[0].b_per_log_m) else coef(r.iloc[0].b_per_log_m, r.iloc[0].p, 2))
        pooled = d[(d.census == 0) & (d.outcome == oc)].iloc[0]
        cells.append(coef(pooled.b_per_log_m, pooled.p, 2))
        cells.append(coef(pooled.b_cbd_ctrl, pooled.p_cbd_ctrl, 2))
        rows.append(cells)
    return make("s3_ed_gradients", src, header, rows)


def t03_segregation():
    src = "data/results/denver_eds/ed_dissimilarity_fixed_grid.csv"
    d = read("denver_eds/ed_dissimilarity_fixed_grid.csv")
    header = ["census", "EDs", "dissimilarity on that census's EDs", "fixed grid, 1880 city (53 cells)",
              "fixed grid, 1900 city (310 cells)"]
    rows = []
    for census in sorted(d.census.unique()):
        s = d[d.census == census]
        g53 = s[s.cells == 53]
        g310 = s[s.cells == 310]
        rows.append([census, int(s.iloc[0].EDs), num(s.iloc[0].dissimilarity_on_EDs, 2),
                     num(g53.iloc[0].dissimilarity_black_vs_nonblack, 2) if len(g53) else DASH,
                     num(g310.iloc[0].dissimilarity_black_vs_nonblack, 2) if len(g310) else DASH])
    return make("s3_segregation", src, header, rows)


# ----------------------------------------------------------------------------------------------
# Section 4: HOLC
# ----------------------------------------------------------------------------------------------

def _density(v):
    return "0" if float(v) == 0 else f"{float(v):.3f}"


def t04_density_by_grade():
    src = "data/results/holc/holc_industry_periods.csv"
    d = read("holc/holc_industry_periods.csv")
    header = ["period", "source", "editions", "A", "B", "C", "D", "D/C"]
    rows = []
    for period in d.period.drop_duplicates():
        s = d[d.period == period].set_index("grade")
        source = "business directory" if "Business Directory" in s.loc["D", "source"] else "manufacturers' directory"
        rows.append([en(period), source, int(s.loc["D", "editions"])] + [_density(s.loc[g, "per_km2_per_edition"]) for g in "ABCD"]
                    + [num(s.loc["D", "dc_ratio_within_period"], 1)])
    return make("s4_density_by_grade", src, header, rows)


def t05_zoning_by_grade():
    src = "data/results/holc/holc_zoning_by_grade.csv"
    d = read("holc/holc_zoning_by_grade.csv")
    header = ["HOLC grade (1938)", "areas", "on the 1929 sheet", "km² on the sheet", "% zoned industrial, 1929",
              "% zoned commercial, 1929"]
    rows = [[r.grade, int(r.areas), int(r.areas_on_map), num(r.km2_on_map, 1), num(r.pct_industrial_1929, 1),
             num(r.pct_commercial_1929, 1)] for r in d.itertuples()]
    return make("s4_zoning_by_grade", src, header, rows)


BOUNDARY_COLS = [(1900, "districts"), (1910, "districts"), (1920, "districts"), (1930, "districts"), (1940, "districts"),
                 (1940, "2010 tracts"), (1950, "2010 tracts"), (1960, "2010 tracts"), (1970, "2010 tracts"),
                 (1980, "2010 tracts"), (1990, "2010 tracts"), (2000, "2010 tracts"), (2010, "2010 tracts"),
                 (2020, "2010 tracts")]


def t06_boundary():
    src = "data/results/holc/holc_boundary.csv"
    d = read("holc/holc_boundary.csv")
    header = ["pair", "outcome", "1900", "1910", "1920", "1930", "1940 (districts)", "1940 (tracts)", "1950", "1960",
              "1970", "1980", "1990", "2000", "2010", "2020"]
    two = (0.05, 0.01)  # this table uses \* and \*\* only

    def series(pair, outcome, kind):
        out = []
        for census, basis in BOUNDARY_COLS:
            r = d[(d.pair == pair) & (d.outcome == outcome) & (d.census == census) & (d.basis == basis)]
            if r.empty:
                out.append(DASH)
                continue
            r = r.iloc[0]
            if kind == "raw":
                out.append(coef(r.gap, r.p, 1, levels=two))
            elif kind == "rail":
                out.append(coef(r.gap_rail, r.p_rail, 1, levels=two))
            elif kind == "zone":
                out.append(coef(r.gap_zone, r.p_zone, 1, levels=two))
            elif kind == "conley":
                out.append(pval(r.p_conley2km))
        return out

    rows = [
        ["D–C", "% Black"] + series("D-C", "p_black", "raw"),
        ["D–C, rail-adjusted", "% Black"] + series("D-C", "p_black", "rail"),
        ["D–C, rail- and zoning-adjusted", "% Black"] + series("D-C", "p_black", "zone"),
        ["D–C, Conley p", "% Black"] + series("D-C", "p_black", "conley"),
        ["D–C", "% Hispanic"] + series("D-C", "p_hisp", "raw"),
        ["D–C, rail- and zoning-adjusted", "% Hispanic"] + series("D-C", "p_hisp", "zone"),
        ["D–C, Conley p", "% Hispanic"] + series("D-C", "p_hisp", "conley"),
        ["C–B", "% Black"] + series("C-B", "p_black", "raw"),
        ["C–B, rail- and zoning-adjusted", "% Black"] + series("C-B", "p_black", "zone"),
    ]
    return make("s4_boundary", src, header, rows)


XU_ROWS = [("% Hispanic", "p_hisp", "1970-1980", 1), ("% Hispanic", "p_hisp", "1980-2010", 1),
           ("% Hispanic", "p_hisp", "1970-2010", 1), ("% Black (1940 nonwhite)", "p_black", "1940-2010", 1),
           ("% below poverty (first measured 1970)", "p_pov", "1970-2010", 1), ("% owner-occupied", "p_owner", "1940-2010", 1),
           ("log median home value", "lmval", "1940-1980", 2), ("log median home value", "lmval", "1940-2010", 2)]


def t07_xu():
    src = "data/results/holc/holc_tract_models.csv"
    d = read("holc/holc_tract_models.csv")
    header = ["change relative to A tracts", "period", "B", "C", "D"]
    rows = []
    for label, oc, period, dec in XU_ROWS:
        s = d[(d.outcome == oc) & (d.period == period)].set_index("grade")
        rows.append([label, en(period)] + [coef(s.loc[g, "b"], s.loc[g, "p"], dec) for g in "BCD"])
    return make("s4_xu_change_by_grade", src, header, rows)


GRID_LQ_ROWS = [("future A", "1938 class: A"), ("future B", "1938 class: B"), ("future C", "1938 class: C"),
                ("future D", "1938 class: D"), ("future ungraded industrial", "1938 class: ungraded industrial"),
                ("zoned industrial in 1929", "1929: zoned industrial (>=25% of cell)"),
                ("not zoned industrial in 1929", "1929: not zoned industrial")]


def t08_grid_lq():
    src = "data/results/descriptive/grid_location_quotients_1900_1940.csv"
    d = read("descriptive/grid_location_quotients_1900_1940.csv")
    years = [1900, 1910, 1920, 1930, 1940]
    header = ["future class or 1929 zoning", "cells", "Black LQ 1900", "1910", "1920", "1930", "1940",
              "Hispanic LQ 1900", "1910", "1920", "1930", "1940"]
    rows = []
    for label, grp in GRID_LQ_ROWS:
        s = d[d.group == grp].set_index("census")
        rows.append([label, int(s.loc[1900, "cells"])] + [num(s.loc[y, "lq_black"], 2) for y in years]
                    + [num(s.loc[y, "lq_hisp"], 2) for y in years])
    return make("s4_grid_lq", src, header, rows)


GRID_ZONING_ROWS = [("future D, not zoned industrial", "D", False), ("future D, zoned industrial", "D", True),
                    ("future ungraded industrial, zoned industrial", "ungraded industrial", True),
                    ("future C, not zoned industrial", "C", False)]


def t09_zoning_within_class():
    src = "data/results/descriptive/grid_zoning_1920_1940.csv"
    d = read("descriptive/grid_zoning_1920_1940.csv")
    header = ["1929 zoning within the future class", "cells", "% Black 1920", "1930", "1940", "% Hispanic 1920", "1930",
              "1940", "population change 1920–40"]
    rows = []
    for label, cls, zoned in GRID_ZONING_ROWS:
        r = d[(d.future_class == cls) & (d.zoned_industrial_1929 == zoned)].iloc[0]
        rows.append([label, int(r.cells), num(r.black_1920, 2), num(r.black_1930, 2), num(r.black_1940, 2),
                     num(r.hisp_1920, 2), num(r.hisp_1930, 2), num(r.hisp_1940, 2),
                     num(r.pop_change_1920_40_pct, 0, sign=True, pct=True)])
    return make("s4_zoning_within_class", src, header, rows)


def t10_first_arrival():
    src = ("data/results/descriptive/grid_first_arrival_1900_1940.csv; "
           "data/results/descriptive/tract_first_arrival_1965_1992.csv")
    g = read("descriptive/grid_first_arrival_1900_1940.csv")
    t = read("descriptive/tract_first_arrival_1965_1992.csv")
    header = ["places", "decade", "places (n)", "% Black at start", "% foreign born at start", "% owner-occupied at start",
              "change in % Black", "change in % Hispanic", "change in % owner-occupied"]
    rows = []
    for frm, to in ((1910, 1920), (1930, 1940)):
        for label, grp in (("grid cells, first trade arrives", "first hazardous trade arrives in the next decade"),
                           ("grid cells, no trade", "no hazardous trade by the next census")):
            r = g[(g["from"] == frm) & (g.to == to) & (g.group == grp)].iloc[0]
            # this table rounds ties in the CSV's last digit away from zero (38.55 -> 38.6)
            rows.append([label, f"{frm}{EN}{to}", int(r.cells), num(r.pct_black_before, 2), num(r.pct_fb_before, 1),
                         num(r.pct_owner_before, 1, half_up=True), num(r.chg_black, 2, sign=True),
                         num(r.chg_hisp, 2, sign=True), num(r.chg_owner, 2, sign=True)])
    for label, grp in (("tracts, first hazardous manufacturer listed 1973–80", "first listed 1973-80 (arrival)"),
                       ("tracts, none listed 1965–92", "none listed 1965-92"),
                       ("tracts, listed 1965–70", "hazardous manufacturer listed 1965-70")):
        r = t[t.group == grp].iloc[0]
        rows.append([label, f"1970{EN}1990", int(r.tracts), num(r.pct_black_1970, 2), DASH, num(r.pct_owner_1970, 1),
                     num(r.chg_black_1970_90, 2, sign=True), num(r.chg_hisp_1970_90, 2, sign=True),
                     num(r.chg_owner_1970_90, 2, sign=True)])
    return make("s4_first_arrival", src, header, rows)


TRACT_LQ_ROWS = [("D", "Black LQ", "lq_black"), ("D", "Hispanic LQ", "lq_hisp"), ("D", "poverty LQ", "lq_poverty"),
                 ("ungraded industrial", "Hispanic LQ", "lq_hisp"), ("ungraded industrial", "poverty LQ", "lq_poverty"),
                 ("B", "Black LQ", "lq_black"), ("C", "Black LQ", "lq_black")]


def t11_tract_lq():
    src = "data/results/descriptive/tract_location_quotients_1940_2020.csv"
    d = read("descriptive/tract_location_quotients_1940_2020.csv")
    years = list(range(1940, 2021, 10))
    header = ["dominant 1938 class (tracts)", "measure"] + [str(y) for y in years]
    rows = []
    for cls, measure, col in TRACT_LQ_ROWS:
        s = d[d.cls == cls].set_index("census")
        rows.append([f"{cls} ({int(s.tracts.iloc[0])})", measure] + [num(s.loc[y, col], 2) for y in years])
    return make("s4_tract_lq", src, header, rows)


# ----------------------------------------------------------------------------------------------
# Section 5: tracts 1950–2020
# ----------------------------------------------------------------------------------------------

TRACT_YEARS = list(range(1950, 2021, 10))
TRACT_GRADIENT_ROWS = [("% Hispanic", "p_hisp", False, 1), ("% Hispanic, downtown controlled", "p_hisp", True, 1),
                       ("% White", "p_white", False, 1), ("% White, downtown controlled", "p_white", True, 1),
                       ("% Black", "p_black", False, 1), ("% foreign born", "p_fb", False, 1),
                       ("% below poverty", "p_pov", False, 1), ("% below poverty, downtown controlled", "p_pov", True, 1),
                       ("% owner-occupied", "p_owner", False, 1), ("% owner-occupied, downtown controlled", "p_owner", True, 1),
                       ("log median home value", "log_mval_2020", False, 2)]


def t12_tract_gradients():
    src = "data/results/denver_tracts/denver_tracts_models.csv"
    d = read("denver_tracts/denver_tracts_models.csv")
    header = ["change per log m of distance from the nearest hazardous firm"] + [str(y) for y in TRACT_YEARS]
    rows = []
    for label, oc, cbd, dec in TRACT_GRADIENT_ROWS:
        cells = [label]
        for y in TRACT_YEARS:
            r = d[(d.census == y) & (d.outcome == oc)]
            if r.empty:
                cells.append(DASH)
            elif cbd:
                cells.append(coef(r.iloc[0].b_cbd_ctrl, r.iloc[0].p_cbd_ctrl, dec))
            else:
                cells.append(coef(r.iloc[0].b_per_log_m, r.iloc[0].p, dec))
        rows.append(cells)
    return make("s5_tract_gradients", src, header, rows)


QUARTILE_ROWS = [("% Hispanic", "p_hisp"), ("% below poverty", "p_pov"), ("% Black", "p_black"),
                 ("% foreign born", "p_fb"), ("% White", "p_white"), ("% owner-occupied", "p_owner")]


def t13_quartile_shares():
    src = "data/results/denver_tracts/denver_tracts_shares.csv"
    d = read("denver_tracts/denver_tracts_shares.csv")
    header = ["measure"] + [str(y) for y in TRACT_YEARS]
    rows = []
    for label, m in QUARTILE_ROWS:
        cells = [label]
        for y in TRACT_YEARS:
            r = d[(d.census == y) & (d.measure == m)]
            cells.append(DASH if r.empty else num(r.iloc[0].share_firms_top_quartile, 1))
        rows.append(cells)
    return make("s5_quartile_shares", src, header, rows)


# (label, outcome, decimals of the panel/cross-section columns, decimals of the reverse column)
PANEL_ROWS = [("% Hispanic", "p_hisp", 2, 3), ("% White", "p_white", 2, 3), ("% Black", "p_black", 2, 3),
              ("% foreign born", "p_fb", 2, 3), ("% below poverty", "ppov", 2, 3), ("% owner-occupied", "p_owner", 2, 3),
              ("log median home value", "lmval", 2, 2)]


def t14_panel():
    src = ("data/results/ej_panel_models.csv; data/results/ej_panel_legacy_sites.csv; "
           "data/results/ej_panel_reverse.csv")
    m = read("ej_panel_models.csv")
    leg = read("ej_panel_legacy_sites.csv")
    rev = read("ej_panel_reverse.csv").set_index("predictor")
    header = ["outcome", "within tracts", "between tracts", "between, spatial-error",
              "legacy firms (gone before the census), between", "2000", "2010", "2020",
              "reverse: composition → change in hazardous firms"]
    rows = []
    for label, oc, dec, rdec in PANEL_ROWS:
        hyb = m[(m.outcome == oc) & (m.model == "hybrid panel, tract-clustered SE")].set_index("term")
        spa = m[(m.outcome == oc) & m.model.str.startswith("between tracts, spatial error")].set_index("term")
        lg = leg[leg.outcome == oc].set_index("census")
        cells = [label, coef(hyb.loc["act_w", "b"], hyb.loc["act_w", "p"], dec),
                 coef(hyb.loc["act_b", "b"], hyb.loc["act_b", "p"], dec),
                 coef(spa.loc["act_b", "b"], spa.loc["act_b", "p"], dec),
                 coef(hyb.loc["leg_b", "b"], hyb.loc["leg_b", "p"], dec)]
        cells += [coef(lg.loc[y, "b"], lg.loc[y, "p"], dec) for y in (2000, 2010, 2020)]
        cells.append(coef(rev.loc[oc, "b"], rev.loc[oc, "p"], rdec))
        rows.append(cells)
    return make("s5_panel", src, header, rows)


def t15_landuse_freeways():
    src = "data/results/landuse/landuse_by_holc_grade.csv; data/results/highways/highways_by_holc_grade.csv"
    lu = read("landuse/landuse_by_holc_grade.csv")
    hw = read("highways/highways_by_holc_grade.csv").set_index("grade")
    header = ["", "A", "B", "C", "D"]

    def lu_pct(grade, year, group):
        r = lu[(lu.grade == grade) & (lu.year == year) & (lu.group == group)]
        return 0.0 if r.empty else float(r.iloc[0].pct)  # a class absent from a grade-year has no land in it

    rows = [
        ["industrial land use, 1937 (% of grade)"] + [num(lu_pct(g, 1937, "Industrial"), 1) for g in "ABCD"],
        ["industrial land use, 1977 (% of grade)"] + [num(lu_pct(g, 1977, "Industrial"), 1) for g in "ABCD"],
        ["single-family residential, 1937 (% of grade)"] + [num(lu_pct(g, 1937, "Residential, single family"), 1) for g in "ABCD"],
        ["freeway built 1950–1979 (km per km²)"] + [num(hw.loc[g, "km_per_km2"], 2) for g in "ABCD"],
        ["land within 250 m of such a freeway (%)"] + [num(hw.loc[g, "pct_within_250m"], 1) for g in "ABCD"],
    ]
    return make("s5_landuse_freeways", src, header, rows)


# ----------------------------------------------------------------------------------------------
# Section 6: site fate and zoning
# ----------------------------------------------------------------------------------------------

USE_ROWS = ["Industrial / utility", "Commercial / office", "Residential", "Vacant", "Civic / school / health",
            "Park / open space"]


def t16_parcel_use():
    src = "data/results/site_fate/site_fate_denver.csv; data/results/site_fate/site_fate_denver_pre1960.csv"
    later = read("site_fate/site_fate_denver.csv", low_memory=False)
    pre = read("site_fate/site_fate_denver_pre1960.csv", low_memory=False)
    pre = pre[pre.use_now != "No parcel match"]  # 407 of 408 have a parcel within 40 m
    header = ["current parcel use", f"manufacturers' directory sites 1965–1992 (n = {len(later):,} matched)",
              f"business-directory hazardous trades 1891–1956 (n = {len(pre):,} matched)"]

    def share(df, mask):
        return num(100.0 * mask.sum() / len(df), 1, pct=True)

    def truthy(s):
        return s.astype(str).str.upper().eq("TRUE")

    rows = [[u, share(later, later.use_now == u), share(pre, pre.use_now == u)] for u in USE_ROWS]
    rows.append(["Still zoned industrial (current zone district)", share(later, truthy(later.zone_industrial)),
                 share(pre, truthy(pre.zone_industrial))])
    rows.append(["Building newer than last listing", share(later, truthy(later.redeveloped)), share(pre, truthy(pre.redeveloped))])
    rows.append(["Median year built of present building", int(later.year_built.median()), int(pre.year_built.median())])
    return make("s6_parcel_use", src, header, rows)


def t17_fate_by_decade():
    src = "data/results/site_fate/site_fate_summary.csv"
    d = read("site_fate/site_fate_summary.csv")
    d = d[d.series == "Manufacturers' directory sites 1965-1992"]
    header = ["decade of last listing", "sites", "industrial / utility", "commercial / office", "residential", "vacant",
              "civic, school, park"]
    labels = {"1960s": "1960s", "1970s": "1970s", "1980s": "1980s", "1990s": "1990s (listed in 1990 or 1992)"}
    rows = []
    for dec in ("1960s", "1970s", "1980s", "1990s"):
        s = d[d.last_decade == dec].set_index("use_now")
        n = int(s.n.sum())  # all parcels of the cohort, including the few 'Other'

        def pct(uses):
            return num(100.0 * sum(int(s.n.get(u, 0)) for u in uses) / n, 1, pct=True)

        rows.append([labels[dec], n, pct(["Industrial / utility"]), pct(["Commercial / office"]), pct(["Residential"]),
                     pct(["Vacant"]), pct(["Civic / school / health", "Park / open space"])])
    return make("s6_fate_by_decade", src, header, rows)


Z23_ROWS = [("Industrial, housing not allowed", "Industrial (housing not allowed)"),
            ("Industrial mixed use, housing allowed (Denver I-MX)", "Industrial mixed use (housing allowed)"),
            ("Other mixed use with housing", "Mixed use with housing"), ("Residential", "Residential"),
            ("Commercial", "Commercial"), ("Open space, civic, other", "Open space, civic, other")]


def t18_zoning_2023():
    src = "data/results/zoning_2023/zoning_1929_to_2023.csv; data/results/zoning_2023/sites_by_zoning_2023.csv"
    land = read("zoning_2023/zoning_1929_to_2023.csv").set_index("zone1929")
    sites = read("zoning_2023/sites_by_zoning_2023.csv")
    mfg = sites[sites.series.str.startswith("Hazardous-sector manufacturers")]
    pre = sites[sites.series.str.startswith("Hazardous trades before 1960")]
    den = mfg[mfg["where"] == "Denver County"].iloc[0]
    sub = mfg[mfg["where"] == "Suburban study tracts"].iloc[0]
    pre_den = pre[pre["where"] == "Denver County"].iloc[0]
    header = ["2023 zoning", f"1929 Industrial A land ({num(land.loc['Industrial A', 'km2_1929'], 1)} km²)",
              f"1929 Industrial B land ({num(land.loc['Industrial B', 'km2_1929'], 1)} km²)",
              f"1965–92 sites, Denver County (n = {int(den.n):,})", f"1965–92 sites, suburban study tracts (n = {int(sub.n):,})",
              f"pre-1960 trades, Denver County (n = {int(pre_den.n):,})"]
    rows = [[label, num(land.loc["Industrial A", col], 1, pct=True), num(land.loc["Industrial B", col], 1, pct=True),
             num(den[col], 1, pct=True), num(sub[col], 1, pct=True), num(pre_den[col], 1, pct=True)] for label, col in Z23_ROWS]
    return make("s6_zoning_2023", src, header, rows)


def _short(v):
    """0 -> '0', else one decimal (for the A/B/C range row of the zoning-over-time table)."""
    return "0" if float(v) == 0 else f"{float(v):.1f}"


def t19_zoning_over_time():
    src = ("data/results/zoning_over_time/zoning_land_by_year.csv; data/results/zoning_over_time/zoning_by_holc_grade_years.csv; "
           "data/results/zoning_over_time/zoning_sites_by_year.csv")
    land = read("zoning_over_time/zoning_land_by_year.csv")
    grade = read("zoning_over_time/zoning_by_holc_grade_years.csv")
    sites = read("zoning_over_time/zoning_sites_by_year.csv")
    years = ["1929", "1944", "1955", "2023", "today"]
    land["year"] = land.year.astype(str)
    grade["year"] = grade.year.astype(str)
    sites["year"] = sites.year.astype(str)
    header = ["zoned industrial (housing not allowed)"] + years
    total_km2 = land[land.year == "1929"].km2.sum()
    ind = land[land.cat == "Industrial"].set_index("year")
    d = grade[grade.grade == "D"].set_index("year")
    abc = grade[grade.grade.isin(list("ABC"))]
    abc_km2 = abc[abc.year == "1929"].grade_km2.sum()

    def abc_range(y):
        v = abc[abc.year == y].pct_industrial
        lo, hi = v.min(), v.max()
        return f"{_short(lo)}%" if lo == hi else f"{_short(lo)}{EN}{_short(hi)}%"

    mfg = sites[sites.series.str.startswith("Hazardous-sector")].set_index("year")
    pre = sites[sites.series.str.startswith("Hazardous trades")].set_index("year")
    rows = [
        [f"land mapped in 1929 and 1944 ({total_km2:.0f} km²)"] + [num(ind.loc[y, "pct"], 1, pct=True) for y in years],
        [f"HOLC D land ({num(d.loc['1929', 'grade_km2'], 1)} km²)"] + [num(d.loc[y, "pct_industrial"], 1, pct=True) for y in years],
        [f"HOLC A, B and C land ({abc_km2:.1f} km²)"] + [abc_range(y) for y in years],
        [f"hazardous-sector sites 1965–92 (n = {int(mfg.sites.iloc[0]):,})"] + [num(mfg.loc[y, "pct_industrial"], 1, pct=True) for y in years],
        [f"hazardous trades before 1960 (n = {int(pre.sites.iloc[0]):,})"] + [num(pre.loc[y, "pct_industrial"], 1, pct=True) for y in years],
    ]
    return make("s6_zoning_over_time", src, header, rows)


TRACT_PATH_ROWS = [("industrial in 1929 and today", "Industrial in 1929 and today"),
                   ("industrial in 1929, not today", "Industrial in 1929, not today"), ("neither", "Neither")]


def t20_rezoned_tracts():
    src = "data/results/zoning_over_time/zoning_tract_paths.csv"
    d = read("zoning_over_time/zoning_tract_paths.csv")
    header = ["tracts (2010)", "n", "census", "% Hispanic", "% Black", "% in poverty", "% owner-occupied"]
    rows = []
    for label, path in TRACT_PATH_ROWS:
        s = d[d.path == path].sort_values("census")
        # the manuscript prints one n per group (the 200-resident rule drops a tract in some censuses): the largest
        n = int(s.tracts.max())
        for i, r in enumerate(s.itertuples()):
            rows.append([label if i == 0 else "", n if i == 0 else "", int(r.census), num(r.pct_hispanic, 1),
                         num(r.pct_black, 1), num(r.pct_poverty, 1), num(r.pct_owner_occupied, 1)])
    return make("s6_rezoned_tracts", src, header, rows)


# ----------------------------------------------------------------------------------------------
# Section 7: mortality and CenSoc
# ----------------------------------------------------------------------------------------------

# (row label, model, term): known and hidden sites come from the model with both; the placebo row for known
# sites from the model that adds the placebo; the pre-1960 row from the model that adds the pre-1960 trades.
BLOCK_ROWS = [("known historical sites", "M4 + hidden", "known_hist"),
              ("known historical sites, placebo also in the model", "M4 + placebo", "known_hist"),
              ("hidden sites", "M4 + hidden", "hidden"),
              ("hidden sites, high-confidence only", "M4 hidden high-confidence", "hidden_hiconf"),
              ("pre-1960 hazardous trades", "M5 + pre-1960 trades", "pre1960"),
              ("placebo: non-hazardous manufacturers, alone", "Placebo: non-hazardous manufacturers", "placebo")]
BLOCK_COLS = [("Colorado, natural causes", "Colorado, all blocks with 100+ person-years", "natural causes"),
              ("Colorado, all causes", "Colorado, all blocks with 100+ person-years", "all causes"),
              ("Denver study area, natural causes", "Denver study area", "natural causes")]


def t21_block_mortality():
    src = "data/results/health/mortality_block_models.csv"
    d = read("health/mortality_block_models.csv")
    header = ["site exposure (per SD of kernel density)"] + [c[0] for c in BLOCK_COLS]
    rows = []
    for label, model, term in BLOCK_ROWS:
        cells = [label]
        for _, sample, outcome in BLOCK_COLS:
            r = d[(d["sample"] == sample) & (d.outcome == outcome) & (d.model == model) & (d.term == term)].iloc[0]
            cells.append(rr(r.rr, r.lo, r.hi, 3))
        rows.append(cells)
    return make("s7_block_mortality", src, header, rows)


CENSOC_ROWS = [("1929 industrial district (vs residence or commercial)", "zone_ind"),
               ("industrial land within 250 m, 1937 (per 10 points)", "ind10"),
               ("hazardous trade listed by 1940 within 500 m", "haz_500"),
               ("hazardous trades listed by 1940, kernel (per SD)", "haz_kz"),
               ("placebo: commercial land within 250 m, 1937 (per 10 points)", "com10"),
               ("HOLC grade D (vs A or B)", "holc_D"),
               ("1965–92 sites on no inventory, kernel (per SD)", "hidden_kz"),
               ("1965–92 sites on an inventory, kernel (per SD)", "known_kz")]
CENSOC_COLS = [("men, deaths 1975–2020: birth year only", "DMF (men, deaths 1975 on)", "M1: birth year (and sex) only"),
               ("men, deaths 1975–2020: with 1940 controls", "DMF (men, deaths 1975 on)", "M2: + 1940 person and household controls"),
               ("men and women, deaths 1988–2005: birth year and sex only", "Numident (men and women, deaths 1988-2005)",
                "M1: birth year (and sex) only"),
               ("men and women, deaths 1988–2005: with 1940 controls", "Numident (men and women, deaths 1988-2005)",
                "M2: + 1940 person and household controls")]


def t22_censoc():
    # The committed file carries three decimals; the manuscript was formatted from the full-precision estimates, so a
    # value that is a tie at the third decimal (−1.575, DMF M1 industrial district) cannot be settled from the file:
    # the manuscript prints −1.58, printf rounding of the committed value gives −1.57.
    src = "data/results/censoc/censoc_models.csv"
    d = read("censoc/censoc_models.csv")
    header = ["exposure at the 1940 address"] + [c[0] for c in CENSOC_COLS]
    rows = []
    for label, term in CENSOC_ROWS:
        cells = [label]
        for _, file, model in CENSOC_COLS:
            r = d[(d.file == file) & (d.model == model) & (d.term == term)].iloc[0]
            cells.append(ci(r.years, r.lo, r.hi, 2))
        rows.append(cells)
    return make("s7_censoc_table22", src, header, rows)


ENLIST_ROWS = [("1929 industrial district", "1929 industrial district"),
               ("industrial land within 250 m, 1937 (per 10 points)", "Industrial land within 250 m, 1937 (per 10 points)"),
               ("hazardous trade listed by 1940 within 500 m", "Hazardous trade within 500 m (to 1940)"),
               ("HOLC grade D (vs A or B)", "HOLC grade D (vs A/B)"),
               ("major road open in 1940 within 100 m", "Major road open in 1940 within 100 m"),
               ("placebo: commercial land within 250 m (per 10 points)", "Placebo: commercial land within 250 m (per 10 points)")]
ENLIST_COLS = [("years of schooling", "Men born 1905-1927", "Years of schooling at enlistment", 2),
               ("height (inches)", "Men born 1905-1927", "Height (inches)", 2),
               ("weight (pounds)", "Men born 1905-1927", "Weight (pounds)", 1),
               ("years of schooling, boys aged 13–17 in 1940", "Boys aged 13-17 in 1940", "Years of schooling at enlistment", 2)]


def t23_enlistment():
    src = "data/results/censoc/enlistment_models.csv"
    d = read("censoc/enlistment_models.csv")
    header = ["exposure at the 1940 address"] + [c[0] for c in ENLIST_COLS]
    rows = []
    for label, exposure in ENLIST_ROWS:
        cells = [label]
        for _, sample, outcome, dec in ENLIST_COLS:
            r = d[(d["sample"] == sample) & (d.outcome == outcome) & (d.exposure == exposure)].iloc[0]
            cells.append(ci(r.estimate, r.lo, r.hi, dec, half_up=True))  # Table 23 rounds ties away from zero
        rows.append(cells)
    return make("s7_enlistment_table23", src, header, rows)


# ----------------------------------------------------------------------------------------------

TABLES = [t01_composition, t02_ed_gradients, t03_segregation, t04_density_by_grade, t05_zoning_by_grade, t06_boundary,
          t07_xu, t08_grid_lq, t09_zoning_within_class, t10_first_arrival, t11_tract_lq, t12_tract_gradients,
          t13_quartile_shares, t14_panel, t15_landuse_freeways, t16_parcel_use, t17_fate_by_decade, t18_zoning_2023,
          t19_zoning_over_time, t20_rezoned_tracts, t21_block_mortality, t22_censoc, t23_enlistment]


def build_all():
    return [f() for f in TABLES]


def render(tables):
    parts = ["<!-- generated by paper/make_tables.py from the committed data/results files; do not edit by hand -->", ""]
    for t in tables:
        parts.append(f"<!-- table: {t.id} ; source: {t.source} -->")
        parts.append(t.header)
        parts.append(t.sep)
        parts.extend(t.rows)
        parts.append("")
    return "\n".join(parts)


def main(out=OUT):
    tables = build_all()
    Path(out).write_text(render(tables), encoding="utf-8")
    print(f"wrote {len(tables)} tables to {Path(out).relative_to(REPO) if Path(out).is_relative_to(REPO) else out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
