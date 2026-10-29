"""Consistency of the committed outputs (app/data, data/results, data/by_year, data/full_inventory).

Fast, offline: every test reads files that are in the repository. A failure here means two
published files disagree with each other, not that a model is wrong.

Known inconsistencies in the current commit are marked ``xfail(strict=True)`` with the reason
in the marker, so they are documented and the marker must be removed once the data are fixed.
"""
import json
import os
import re
import subprocess
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from outputs_helpers import (APP_DATA, REPO, RESULTS, WORK, all_files, fisher_exact_p, gj_features, listings, load,
                      rel, sites)

# --------------------------------------------------------------------------------------------
# 1. app/data copies are byte-identical to data/results
# --------------------------------------------------------------------------------------------

# app/data file-name prefix -> data/results folder holding the original
PREFIX_MAP = {
    "rezoning_": "rezoning",
    "sanborn1903_": "sanborn_1903",
    "ownership_": "ownership",
    "conditions_": "housing_conditions",
}
# app/data files that exist under data/results with the same name but are allowed to differ
# (none for text formats; the 20 m land-use .tif rasters are binary and are compared by size only)
KNOWN_DIFFERENT = set()
TEXT_EXTS = {".csv", ".geojson", ".md"}


def _results_index():
    idx = {}
    for p in all_files(RESULTS):
        idx.setdefault(p.name, []).append(p)
    return idx


def _result_counterparts(app_file: Path, idx):
    """data/results files that app/data/<name> is a copy of."""
    out = list(idx.get(app_file.name, []))
    for pre, folder in PREFIX_MAP.items():
        if app_file.name.startswith(pre):
            cand = RESULTS / folder / app_file.name[len(pre):]
            if cand.exists():
                out.append(cand)
    return out


def _app_data_text_files():
    return [p for p in all_files(APP_DATA, TEXT_EXTS)]


@pytest.mark.parametrize("app_file", _app_data_text_files(), ids=lambda p: str(p.relative_to(APP_DATA)))
def test_app_data_copy_is_byte_identical(app_file):
    idx = _results_index()
    counterparts = _result_counterparts(app_file, idx)
    if not counterparts:
        pytest.skip("no copy under data/results")
    if app_file.name in KNOWN_DIFFERENT:
        pytest.skip("listed in KNOWN_DIFFERENT")
    a = app_file.read_bytes()
    for q in counterparts:
        assert a == q.read_bytes(), f"{app_file.relative_to(REPO)} differs from {q.relative_to(REPO)}"


def test_app_data_has_copies_of_results_tables():
    """Sanity: the copy check above is not vacuous."""
    idx = _results_index()
    n = sum(1 for p in _app_data_text_files() if _result_counterparts(p, idx))
    assert n >= 100, n


def test_landuse_rasters_same_size():
    for y in (1937, 1957, 1977, 1997):
        a, b = APP_DATA / f"landuse_{y}_20m.tif", RESULTS / "landuse" / f"landuse_{y}_20m.tif"
        assert a.exists() and b.exists()
        assert a.stat().st_size == b.stat().st_size, f"{a.name}: {a.stat().st_size} vs {b.stat().st_size} bytes"


def test_by_year_editions_identical_to_data_by_year():
    app_by = REPO / "app" / "data" / "by_year"
    src_by = REPO / "data" / "by_year"
    files = sorted(p.name for p in src_by.glob("*.csv"))
    assert len(files) == 13, files
    for f in files:
        assert (app_by / f).exists(), f"app/data/by_year lacks {f}"
        assert (app_by / f).read_bytes() == (src_by / f).read_bytes(), f


def test_by_year_rows_equal_listings_file():
    L = listings()
    by = pd.concat([pd.read_csv(p, dtype=str, keep_default_na=False, low_memory=False)
                    for p in sorted((REPO / "data" / "by_year").glob("*.csv"))])
    assert len(by) == len(L) == 41987
    assert set(L.estab_id) == set(by.establishment_id)
    assert set(L.site_id) == set(by.site_id)
    assert sorted(L.year.unique()) == sorted(by.edition_year.unique())


# --------------------------------------------------------------------------------------------
# 2. sites.csv, the geojson, the workbook and the full inventory agree
# --------------------------------------------------------------------------------------------

SITE_COLS = ["first_year", "last_year", "hazard_years", "radar", "confidence", "address", "geo_level"]


def _bool(s):
    return s.astype(str).str.upper().isin(["TRUE", "1", "1.0"])


def _geojson_sites():
    g = load("data/results/CO_historical_industrial_sites.geojson", as_str=True)
    return g


def test_geojson_site_ids_cover_sites_csv():
    s, g = sites(), _geojson_sites()
    assert s.site_id.is_unique and g.site_id.is_unique
    missing = set(s.site_id) - set(g.site_id)
    assert not missing, f"{len(missing)} sites.csv ids not in the geojson: {sorted(missing)[:10]}"
    # the geojson holds every located site (hazardous or not); sites.csv is the hazardous subset
    hz = g[_bool(g.fe_hazard) | _bool(g.ext_hazard)]
    assert set(hz.site_id) == set(s.site_id)


def test_geojson_and_sites_csv_fields_agree():
    s, g = sites(), _geojson_sites()
    m = g.merge(s, on="site_id", suffixes=("_g", "_s"))
    assert len(m) == len(s)
    for c in SITE_COLS:
        bad = m[m[c + "_g"] != m[c + "_s"]]
        assert bad.empty, f"{c}: {len(bad)} differences, e.g. {bad[['site_id', c + '_g', c + '_s']].head(3).values.tolist()}"
    for c in ("fe_hazard", "ext_hazard"):
        assert (_bool(m[c + "_g"]) == _bool(m[c + "_s"])).all(), c
    for c in ("lat", "lon"):
        d = (m[c + "_g"].astype(float) - m[c + "_s"].astype(float)).abs()
        assert d.max() < 1e-6, f"{c}: max difference {d.max()}"


@pytest.mark.parametrize("sheet,selector", [
    ("All F&E hazardous sites", lambda s: _bool(s.fe_hazard)),
    ("Hidden sites", lambda s: _bool(s.fe_hazard) & (s.radar == "Not on any list")),
    ("Extended-sector sites", lambda s: ~_bool(s.fe_hazard) & _bool(s.ext_hazard)),
])
def test_workbook_sheet_agrees_with_sites_csv(sheet, selector):
    s = sites()
    x = load("data/results/CO_hazardous_sites_1961-2002.xlsx", sheet=sheet, as_str=True)
    assert set(x.site_id) == set(s[selector(s)].site_id), sheet
    m = x.merge(s, on="site_id", suffixes=("_x", "_s"))
    for c in ["first_year", "last_year", "hazard_years", "radar", "confidence"]:
        bad = m[m[c + "_x"].astype(str) != m[c + "_s"].astype(str)]
        assert bad.empty, f"{sheet} {c}: {bad[['site_id', c + '_x', c + '_s']].head(3).values.tolist()}"
    for c in ("lat", "lon"):
        assert (m[c + "_x"].astype(float) - m[c + "_s"].astype(float)).abs().max() < 1e-6, c


def test_workbook_coverage_sheet_matches_listings():
    L = listings()
    cov = load("data/results/CO_hazardous_sites_1961-2002.xlsx", sheet="Coverage by edition")
    cov = cov.dropna(subset=["year"])
    assert sorted(cov.year.astype(int)) == sorted(L.year.astype(int).unique())
    per_year = L.groupby(L.year.astype(int)).size()
    for _, r in cov.iterrows():
        assert int(r.listings) == int(per_year[int(r.year)]), int(r.year)
    fe = L[_bool(L.fe_hazard)].groupby(L.year.astype(int)).size()
    for _, r in cov.iterrows():
        assert int(r.fe_hazard_listings) == int(fe.get(int(r.year), 0)), int(r.year)


def test_full_inventory_internally_consistent():
    """data/full_inventory is the all-25-edition run; its own tables must agree with each other.

    Its site ids are a different numbering from app/data/sites.csv (different run), so only
    within-folder agreement is tested.
    """
    fi = REPO / "data" / "full_inventory"
    s = pd.read_csv(fi / "sites.csv", dtype=str, keep_default_na=False)
    f = pd.read_csv(fi / "site_firms.csv", dtype=str, keep_default_na=False)
    L = pd.read_csv(fi / "CO_directory_listings_1961-2002.csv", dtype=str, keep_default_na=False, low_memory=False)
    assert s.site_id.is_unique
    assert set(f.site_id) <= set(s.site_id)
    assert set(zip(f.site_id, f.estab_id)) <= set(zip(L.site_id, L.estab_id))
    assert list(s.columns) == list(sites().columns), "full-inventory sites.csv columns differ from app/data/sites.csv"
    yrs = L[L.site_id != ""].groupby("site_id").year.agg(lambda v: (min(map(int, v)), max(map(int, v))))
    m = s.set_index("site_id")
    bad = [sid for sid, (mn, mx) in yrs.items() if sid in m.index and (int(m.at[sid, "first_year"]), int(m.at[sid, "last_year"])) != (mn, mx)]
    assert not bad, bad[:5]
    assert not ((s.fe_hazard == "FALSE") & (s.ext_hazard == "FALSE")).any()
    assert len(L) == 68368
    by = sorted((fi / "by_year").glob("*.csv"))
    assert len(by) == 25


# --------------------------------------------------------------------------------------------
# 3. site_years, site_firms and the listings
# --------------------------------------------------------------------------------------------

def _hazard_listings(L):
    return L[(L.site_id != "") & (_bool(L.fe_hazard) | _bool(L.ext_hazard))]


def test_site_years_ids_subset_of_sites():
    sy = load("app/data/site_years.csv", as_str=True)
    assert set(sy.site_id) <= set(sites().site_id)
    assert not sy.duplicated(["site_id", "year"]).any()


def test_site_years_equal_hazardous_listing_years():
    sy = load("app/data/site_years.csv", as_str=True)
    H = _hazard_listings(listings())
    assert set(zip(sy.site_id, sy.year)) == set(zip(H.site_id, H.year))


def test_site_firms_ids_subset_of_sites_and_pairs_in_listings():
    sf = load("app/data/site_firms.csv", as_str=True)
    L = listings()
    assert set(sf.site_id) <= set(sites().site_id)
    pairs = set(zip(sf.site_id, sf.estab_id))
    assert pairs <= set(zip(L.site_id, L.estab_id)), "site_firms (site, estab) pair not in the listings"
    assert not sf.duplicated(["site_id", "estab_id"]).any()
    # hazardous firms in site_firms are exactly the hazardous (site, estab) pairs of the listings
    H = _hazard_listings(L)
    assert set(zip(sf[_bool(sf.hazardous)].site_id, sf[_bool(sf.hazardous)].estab_id)) == set(zip(H.site_id, H.estab_id))
    # and every establishment ever listed at a hazardous site is in site_firms
    at_sites = L[L.site_id.isin(sites().site_id)]
    assert set(zip(at_sites.site_id, at_sites.estab_id)) == pairs


def test_site_firm_years_match_listings():
    sf = load("app/data/site_firms.csv", as_str=True)
    L = listings()
    # editions = distinct years the establishment was listed at the site (an edition can list a firm twice)
    yrs = L.groupby(["site_id", "estab_id"]).year.agg(lambda v: (min(map(int, v)), max(map(int, v)), len(set(v))))
    bad = []
    for r in sf.itertuples():
        mn, mx, n = yrs[(r.site_id, r.estab_id)]
        if (int(r.first_year), int(r.last_year), int(r.editions)) != (mn, mx, n):
            bad.append((r.site_id, r.estab_id, r.first_year, r.last_year, r.editions, mn, mx, n))
    assert not bad, bad[:5]


def test_site_first_last_year_equal_listing_min_max():
    s, L = sites(), listings()
    yrs = L[L.site_id != ""].groupby("site_id").year.agg(lambda v: (min(map(int, v)), max(map(int, v))))
    missing = set(s.site_id) - set(yrs.index)
    assert not missing, f"sites with no listing: {sorted(missing)[:5]}"
    bad = [sid for sid, fy, ly in zip(s.site_id, s.first_year, s.last_year) if (int(fy), int(ly)) != yrs[sid]]
    assert not bad, bad[:5]


def test_hazard_years_subset_of_listing_years():
    s, L = sites(), listings()
    ly = L[L.site_id != ""].groupby("site_id").year.apply(set)
    hy = L[(L.site_id != "") & (_bool(L.fe_hazard) | _bool(L.ext_hazard))].groupby("site_id").year.apply(set)
    bad_sub, bad_eq = [], []
    for sid, h in zip(s.site_id, s.hazard_years):
        hs = {x.strip() for x in str(h).split(";") if x.strip()}
        assert hs, f"{sid}: empty hazard_years"
        if not hs <= ly[sid]:
            bad_sub.append(sid)
        if hs != hy[sid]:
            bad_eq.append(sid)
    assert not bad_sub, bad_sub[:5]
    assert not bad_eq, f"hazard_years != years of hazardous listings: {bad_eq[:5]}"


def test_no_site_without_a_hazard_flag():
    s = sites()
    assert not (~_bool(s.fe_hazard) & ~_bool(s.ext_hazard)).any()
    assert int(_bool(s.fe_hazard).sum()) == 3169


def test_geoid_eleven_digits_or_blank():
    s = sites()
    ok = s.GEOID.str.fullmatch(r"\d{11}") | (s.GEOID == "")
    assert ok.all(), s[~ok][["site_id", "GEOID"]].head().values.tolist()
    assert (s.GEOID == "").sum() < 50, "too many sites without a tract"


def test_n_hazard_establishments_matches_site_firms():
    s = sites()
    sf = load("app/data/site_firms.csv", as_str=True)
    n = sf[_bool(sf.hazardous)].groupby("site_id").size()
    bad = [sid for sid, k in zip(s.site_id, s.n_hazard_establishments) if int(k) != int(n.get(sid, 0))]
    assert not bad, bad[:5]


@pytest.mark.xfail(strict=True, reason="known: 4 non-hazardous site ids used in the listings (S00002, S00010, S00413, S03310) "
                                      "are missing from CO_historical_industrial_sites.geojson")
def test_every_listing_site_id_is_in_geojson():
    L, g = listings(), _geojson_sites()
    missing = set(L[L.site_id != ""].site_id) - set(g.site_id)
    assert not missing, sorted(missing)


# --------------------------------------------------------------------------------------------
# 4. tract panel
# --------------------------------------------------------------------------------------------

# Decennial census totals for the City and County of Denver (US Census Bureau).
DENVER_PUBLISHED = {1940: 322412, 1950: 415786, 1960: 493887, 1970: 514678, 1980: 492365,
                    1990: 467610, 2000: 554636, 2010: 600158, 2020: 715522}
# The panel is on 2010 tract boundaries; the 1960 and 1970 values are area-weighted from each
# census's own tracts and the county's 2010 footprint includes land annexed after 1960
# (Montbello, Green Valley Ranch), so those two years are held to a wider band.
DENVER_TOL = {1960: 0.05, 1970: 0.05}


def _panel():
    return pd.read_csv(APP_DATA / "tract_panel.csv", dtype={"GEOID": str}, low_memory=False)


def test_tract_panel_shape():
    t = _panel()
    assert t.GEOID.str.fullmatch(r"\d{11}").all()
    assert sorted(t.census.unique()) == [1940, 1950, 1960, 1970, 1980, 1990, 2000, 2010, 2020]
    assert t.GEOID.nunique() == 1249
    assert not t.duplicated(["GEOID", "census"]).any()


def test_tract_panel_no_measure_below_200_residents():
    t = _panel()
    meas = [c for c in t.columns if c.startswith("p_")] + ["mval_2020", "mrent_2020"]
    small = t[t["pop"] < 200]
    leaks = {c: int(small[c].notna().sum()) for c in meas if small[c].notna().any()}
    assert not leaks, leaks


def test_tract_panel_percentages_in_range():
    t = _panel()
    for c in [c for c in t.columns if c.startswith("p_")]:
        v = t[c].dropna()
        assert v.between(0, 100).all(), f"{c}: {v.min()}..{v.max()}"


def test_tract_panel_population_non_negative():
    t = _panel()
    assert (t["pop"].dropna() >= 0).all()


@pytest.mark.xfail(strict=True, reason="known: mval_2020 is 0 instead of NA in 3 tract-years with (almost) no owner-occupied "
                                      "housing: 08001008545 1980 (mrent_2020 also 0), 08041004402 1980 and 2000")
def test_tract_panel_values_positive_or_na():
    t = _panel()
    for c in ("mval_2020", "mrent_2020"):
        v = t[c].dropna()
        bad = t.loc[v[v <= 0].index, ["GEOID", "census", c]]
        assert bad.empty, f"{c}: non-positive values {bad.values.tolist()}"


def test_tract_panel_denver_2010_total():
    t = _panel()
    s = t[(t.GEOID.str.startswith("08031")) & (t.census == 2010)]["pop"].sum()
    assert abs(s - 600158) / 600158 < 0.005, s


@pytest.mark.parametrize("census", sorted(DENVER_PUBLISHED))
def test_tract_panel_denver_totals_match_published(census):
    t = _panel()
    s = t[(t.GEOID.str.startswith("08031")) & (t.census == census)]["pop"].sum()
    pub = DENVER_PUBLISHED[census]
    tol = DENVER_TOL.get(census, 0.01)
    assert abs(s - pub) / pub < tol, f"{census}: panel {s:,.0f} vs published {pub:,} ({100*(s-pub)/pub:+.2f}%)"


# --------------------------------------------------------------------------------------------
# 5. rezoning
# --------------------------------------------------------------------------------------------

def _changes():
    return load("data/results/rezoning/changes.csv")


def _period(y):
    return "1925-1945" if y <= 1945 else ("1946-1954" if y <= 1954 else "1955-1956 (new code)")


def test_rezoning_by_dir_sums_to_changes():
    c, bd = _changes(), load("app/data/rezoning_by_dir.csv")
    per = [k for k in bd.columns if k != "direction"]
    assert bd[per].to_numpy().sum() == len(c) == 288
    c["period"] = c.year.map(_period)
    tab = c.groupby(["direction", "period"]).size().unstack(fill_value=0)
    for _, r in bd.iterrows():
        for p in per:
            assert int(r[p]) == int(tab.loc[r.direction].get(p, 0)), (r.direction, p)


def test_rezoning_by_holc_equals_by_holc_period_sums():
    bh, bp = load("app/data/rezoning_by_holc.csv"), load("app/data/rezoning_by_holc_period.csv")
    sums = bp.groupby("holc").changes.sum()
    for r in bh.itertuples(index=False):
        assert int(r.changes) == int(sums[r.holc]), r.holc
    rtb = bp.groupby("holc").res_to_business_or_industrial.sum()
    tores = bp.groupby("holc").to_residential.sum()
    for r in bh.itertuples(index=False):
        assert abs(100 * rtb[r.holc] / r.changes - r.pct_res_to_business_or_industrial) < 0.06, r.holc
        assert abs(100 * tores[r.holc] / r.changes - r.pct_to_residential) < 0.06, r.holc


def test_rezoning_by_holc_recomputed_from_changes():
    c, bh = _changes(), load("app/data/rezoning_by_holc.csv")
    r = c[(~c.annexation.astype(bool)) & c.holc.notna()]
    rtb = r.direction.isin(["Residential to business", "Residential to industrial"])
    toind = r.direction.isin(["Residential to industrial", "Business to industrial"])
    tores = r.direction.isin(["Business or industrial to residential", "Within residential districts"])
    for row in bh.itertuples(index=False):
        sel = r.holc == row.holc
        assert int(sel.sum()) == int(row.changes), row.holc
        assert abs(100 * rtb[sel].mean() - row.pct_res_to_business_or_industrial) < 0.06, row.holc
        assert abs(100 * toind[sel].mean() - row.pct_to_industrial) < 0.06, row.holc
        assert abs(100 * tores[sel].mean() - row.pct_to_residential) < 0.06, row.holc


def test_rezoning_fisher_p_matches_test_csv():
    c, tst = _changes(), load("app/data/rezoning_test.csv")
    r = c[(~c.annexation.astype(bool)) & c.holc.notna()]
    rtb = r.direction.isin(["Residential to business", "Residential to industrial"])
    D, AB = r.holc == "D", r.holc.isin(["A", "B"])
    p = fisher_exact_p(int(rtb[D].sum()), int((~rtb[D]).sum()), int(rtb[AB].sum()), int((~rtb[AB]).sum()))
    quoted = float(tst.loc[tst.period == "1925-1956", "p_all_placed"].iloc[0])
    assert abs(p - quoted) < 1e-3, (p, quoted)
    r = r.assign(period=r.year.map(_period))
    for per in ["1925-1945", "1946-1954", "1955-1956 (new code)"]:
        q = r[r.period == per]
        rq = q.direction.isin(["Residential to business", "Residential to industrial"])
        D, AB = q.holc == "D", q.holc.isin(["A", "B"])
        p = fisher_exact_p(int(rq[D].sum()), int((~rq[D]).sum()), int(rq[AB].sum()), int((~rq[AB]).sum()))
        quoted = float(tst.loc[tst.period == per, "p_all_placed"].iloc[0])
        assert abs(p - quoted) < 1e-3, (per, p, quoted)


def test_rezoning_placed_sums_to_changes():
    c, pl = _changes(), load("app/data/rezoning_placed.csv")
    assert int(pl.changes.sum()) == len(c)
    counts = c.placed_by.value_counts()
    for r in pl.itertuples(index=False):
        assert int(r.changes) == int(counts.get(r.placed_by, 0)), r.placed_by
    assert abs(pl.pct.sum() - 100) < 0.3


def test_rezoning_geojson_matches_placed_changes():
    c = _changes()
    g = load("app/data/rezoning_1925_1956.geojson")
    placed = c[c.lon.notna()]
    assert len(g) == len(placed), (len(g), len(placed))


# --------------------------------------------------------------------------------------------
# 6. ownership and housing conditions
# --------------------------------------------------------------------------------------------

PARTITION_GROUPS = ["Owner family size (rental units in Denver)", "Owner type", "1938 HOLC grade"]


def test_owner_location_group_tables_sum_to_all_row():
    d = load("app/data/ownership_owner_location.csv")
    total = int(d.loc[d.group == "All private rental units", "rental_units"].iloc[0])
    assert total == 209345
    for grp in PARTITION_GROUPS:
        assert int(d.loc[d.group == grp, "rental_units"].sum()) == total, grp


def test_owner_location_rows_sum_to_100():
    d = load("app/data/ownership_owner_location.csv")
    cols = ["pct_lives_on_the_property", "pct_elsewhere_in_denver", "pct_denver_metro_within_40_km",
            "pct_elsewhere_in_colorado", "pct_another_state", "pct_unknown_or_abroad"]
    s = d[cols].sum(axis=1)
    bad = d[(s - 100).abs() > 0.2]
    assert bad.empty, bad[["group", "value"]].assign(sum=s[bad.index]).values.tolist()


def test_conditions_rates_group_tables_sum_to_all_row():
    d = load("app/data/conditions_rates.csv")
    allrow = d[d.group == "All rental buildings"].iloc[0]
    for grp in PARTITION_GROUPS + ["Owner location", "Building type"]:
        sub = d[d.group == grp]
        for c in ("buildings", "units", "rental_units"):
            assert int(sub[c].sum()) == int(allrow[c]), (grp, c, int(sub[c].sum()), int(allrow[c]))


def test_ownership_size_and_type_shares_sum_to_100():
    o = load("app/data/ownership_owner_size.csv")
    for grp, g in o.groupby("grouping"):
        assert abs(g.pct_rental_units.sum() - 100) < 0.3, grp
        assert abs(g.pct_owners.sum() - 100) < 0.3, grp
    t = load("app/data/ownership_owner_types.csv")
    assert abs(t.pct_rental_units.sum() - 100) < 0.3
    occ = load("app/data/ownership_occupancy_by_type.csv")
    assert int(t.rental_units.sum()) == int(occ.rental_units.sum()) == 232395
    assert int(occ.units.sum()) == 398200 and int(occ.parcels.sum()) == 216206


def test_ownership_by_holc_sums_to_all_of_denver():
    h = load("app/data/ownership_by_holc.csv")
    p = load("app/data/ownership_by_site_proximity.csv")
    allrow = p[p.area == "All of Denver"].iloc[0]
    for c in ("parcels", "units", "rental_units"):
        assert int(h[c].sum()) == int(allrow[c]), c


def test_ownership_concentration_consistent_with_linking_stages():
    c = load("app/data/ownership_concentration.csv")
    s = load("app/data/ownership_linking_stages.csv")
    fam = c[c.grouping == "Private owners, by family"].iloc[0]
    s4 = s[s.grouping.str.startswith("S4")].iloc[0]
    for col in ("owners", "rental_units", "top10_pct", "top100_pct", "owners_20plus_pct", "hhi"):
        assert fam[col] == s4[col], col


def test_eviction_terciles_sum_to_tract_total():
    e = load("app/data/conditions_evictions_by_large_owner_share.csv")
    t = load("app/data/ownership_by_tract.csv")
    assert int(e.tracts.sum()) == int((t.rental_units >= 50).sum()) == len(t)
    # filing rate = filings per 100 renter households
    for r in e.itertuples(index=False):
        assert abs(100 * r.filings_per_year / r.renter_households - r.filing_rate) < 0.01, r.large_owner_tercile


def _published_text_files():
    exts = {".csv", ".geojson", ".md", ".json", ".txt"}
    return all_files(APP_DATA, exts) + all_files(RESULTS, exts)


def test_no_owner_name_columns_published():
    bad = []
    pat = re.compile(r"owner[_ ]?name|OWNER_?NAME|mailing[_ ]?address|MAIL_?ADDR", re.I)
    for p in _published_text_files():
        if p.suffix == ".csv":
            with open(p, encoding="utf-8", errors="replace") as fh:
                header = fh.readline()
            if pat.search(header):
                bad.append(str(p.relative_to(REPO)))
        elif p.suffix == ".geojson":
            with open(p, encoding="utf-8", errors="replace") as fh:
                feats = json.load(fh)["features"]
            if feats and any(pat.search(k) for k in (feats[0].get("properties") or {})):
                bad.append(str(p.relative_to(REPO)))
    assert not bad, bad


@pytest.mark.skipif(not (WORK / "property" / "top_owners_private.csv").exists(),
                    reason="work/property/top_owners_private.csv not present (restricted)")
def test_no_private_owner_names_in_published_files():
    top = pd.read_csv(WORK / "property" / "top_owners_private.csv", dtype=str, keep_default_na=False)
    name_cols = [c for c in top.columns if re.search(r"name|owner", c, re.I)]
    names = {n.strip() for c in name_cols for n in top[c] if len(n.strip()) >= 6}
    names = {n for n in names if not re.fullmatch(r"[\d\W]+", n)}
    hits = []
    for p in _published_text_files():
        txt = p.read_text(encoding="utf-8", errors="replace").upper()
        for n in names:
            if n.upper() in txt:
                hits.append((str(p.relative_to(REPO)), n))
    assert not hits, hits[:10]


# --------------------------------------------------------------------------------------------
# 7. highways, Sanborn blocks
# --------------------------------------------------------------------------------------------

def test_highway_km_in_service_non_decreasing_unless_removed():
    h = load("app/data/highways_km_by_decade.csv").sort_values("decade").reset_index(drop=True)
    for i in range(1, len(h)):
        prev, cur = h.loc[i - 1], h.loc[i]
        if cur.km_removed == 0:
            assert cur.km_open_at_decade_end >= prev.km_open_at_decade_end - 1e-9, int(cur.decade)
        assert abs(cur.km_open_at_decade_end - (prev.km_open_at_decade_end + cur.km_opened - cur.km_removed)) < 0.15, int(cur.decade)
    assert abs(h.loc[0].km_open_at_decade_end - h.loc[0].km_opened) < 0.15


def test_highway_holc_table_consistent():
    g = load("app/data/highways_by_holc_grade.csv")
    assert set(g.grade) >= {"A", "B", "C", "D"}
    for r in g.itertuples(index=False):
        assert abs(r.km_through / r.area_km2 - r.km_per_km2) < 0.006, r.grade
        assert 0 <= r.pct_within_250m <= 100


def test_sanborn_blocks_have_no_street_label_starting_with_slash():
    feats = gj_features("app/data/sanborn_1903_blocks.geojson")
    bad = [f["properties"].get("streets") for f in feats if str(f["properties"].get("streets") or "").startswith("/")]
    assert not bad, bad[:5]
    assert len(feats) == 615


def test_sanborn_exposure_table_matches_blocks_geojson():
    b = load("app/data/sanborn_1903_blocks.geojson")
    e = load("app/data/sanborn1903_expo.csv")
    b["dwellings"] = pd.to_numeric(b.dwellings, errors="coerce")
    # expo.csv counts blocks with at least one dwelling
    by = b.groupby("exposure").agg(blocks=("dwellings", lambda v: int((v > 0).sum())), dwellings=("dwellings", "sum"))
    for r in e.itertuples(index=False):
        assert int(by.loc[r.exposure, "blocks"]) == int(r.blocks), r.exposure
        assert int(by.loc[r.exposure, "dwellings"]) == int(r.dwellings), r.exposure
    assert abs(e.pct_dwellings.sum() - 100) < 0.3


# --------------------------------------------------------------------------------------------
# 8. app manifest, .gitignore and the files app.R reads
# --------------------------------------------------------------------------------------------

def _manifest_files():
    return set(json.load(open(REPO / "app" / "manifest.json"))["files"])


def _app_disk_files():
    out = set()
    for p in all_files(REPO / "app"):
        r = str(p.relative_to(REPO / "app"))
        if r != "manifest.json":
            out.add(r)
    return out


def test_manifest_lists_no_missing_file():
    missing = sorted(f for f in _manifest_files() if not (REPO / "app" / f).exists())
    assert not missing, missing


@pytest.mark.xfail(strict=True, reason="known: app/data/mlp_exposure_windows.csv is on disk but not in app/manifest.json")
def test_manifest_lists_every_file_under_app():
    extra = sorted(_app_disk_files() - _manifest_files())
    assert not extra, extra


def test_manifest_covers_everything_app_R_reads():
    names = _app_literals()
    man = _manifest_files()
    missing = sorted(f for f in names if f"data/{f}" not in man and (APP_DATA / f).is_file())
    assert not missing, missing


def test_gitignore_does_not_ignore_manifest_files(tmp_path):
    """Only the committed .gitignore counts (a throw-away git dir is used so that .git/info/exclude
    and the user's global excludes play no part)."""
    files = sorted(f"app/{f}" for f in _manifest_files() if (REPO / "app" / f).exists())
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True, capture_output=True)
    res = subprocess.run(["git", "--git-dir", str(tmp_path / ".git"), "--work-tree", str(REPO),
                          "-c", "core.excludesFile=/dev/null", "check-ignore", "--no-index", "--stdin"],
                         input="\n".join(files), text=True, capture_output=True, cwd=REPO)
    ignored = [l for l in res.stdout.splitlines() if l.strip()]
    assert not ignored, ignored


def _app_literals():
    """File names app.R reads: dd("…") and rd_opt("…") literals, the land-use rasters built with sprintf, the
    download-handler table DL_FILES, and the per-edition CSVs served from data/by_year."""
    src = (REPO / "app" / "app.R").read_text(encoding="utf-8")
    dd = re.findall(r'(?<![\w$.])dd\("([^"]+)"', src)
    ro = re.findall(r'(?<![\w$.])rd_opt\("([^"]+)"', src)
    tif = [f"landuse_{y}_20m.tif" for y in re.findall(r"\b(19\d\d)\b", re.search(r"LU_YEARS <- c\(([^)]*)\)", src).group(1))]
    dl = re.findall(r'dl_\w+ = "([^"]+)"', re.search(r"DL_FILES <- c\((.*?)\)\n", src, re.S).group(1))
    by_year = [f"by_year/{p.name}" for p in sorted((REPO / "data" / "by_year").glob("CO_DCM_*_geocoded.csv"))]
    assert len(tif) == 4 and len(dl) >= 9 and len(by_year) == 13
    return set(dd) | set(ro) | set(tif) | set(dl) | set(by_year)


def test_manifest_covers_app_www_assets():
    """Images referenced from app.R (src=/href=) must exist under app/www and be in the manifest."""
    src = (REPO / "app" / "app.R").read_text(encoding="utf-8")
    refs = set(re.findall(r'(?:src|href) = "([\w./-]+\.(?:jpg|png|svg|css|js))"', src))
    assert refs, "no www asset references found"
    man = _manifest_files()
    missing = sorted(r for r in refs if f"www/{r}" not in man or not (REPO / "app" / "www" / r).is_file())
    assert not missing, missing


def test_app_R_reads_only_existing_files():
    src = (REPO / "app" / "app.R").read_text(encoding="utf-8")
    guarded = set(re.findall(r'file\.exists\(dd\("([^"]+)"\)\)', src))
    required = {f for f in re.findall(r'(?<![\w$.])dd\("([^"]+)"', src)} - guarded
    optional = set(re.findall(r'(?<![\w$.])rd_opt\("([^"]+)"', src))
    assert len(required) > 10 and len(optional) > 50
    missing_req = sorted(f for f in required if not (APP_DATA / f).exists())  # dd("by_year") is a folder
    assert not missing_req, f"dd() literals without a file under app/data: {missing_req}"
    missing_opt = sorted(f for f in optional if not (APP_DATA / f).exists())
    assert not missing_opt, f"rd_opt() literals without a file under app/data: {missing_opt}"
    # the only file.exists()-guarded read may legitimately be absent; say which
    absent_guarded = sorted(f for f in guarded if not (APP_DATA / f).exists())
    assert absent_guarded in ([], ["denver_1880_eds.geojson"]), absent_guarded


@pytest.mark.xfail(strict=True, reason='stale: committed files predate consolidate.strip_quotes; OCR stray quotes in a few '
                   'firm names were doubled by fread/fwrite round trips (e.g. 16 quotes before "COX, TOLBERT G" in sites.csv). '
                   'Clears on the next full pipeline run.')
def test_no_quote_characters_in_published_text_fields():
    """data.table::fread misreads fields that begin/end with escaped quotes, so the pipeline strips '"' from all text."""
    bad = []
    for f in [APP_DATA / 'sites.csv', APP_DATA / 'site_firms.csv', RESULTS.parent / 'full_inventory' / 'sites.csv',
              *sorted((RESULTS.parent / 'by_year').glob('*.csv'))]:
        if not f.exists():
            continue
        d = pd.read_csv(f, dtype=str, keep_default_na=False)
        n = int(sum(d[c].str.contains('"').sum() for c in d.columns))
        if n:
            bad.append((f.name, n))
    assert not bad, bad
