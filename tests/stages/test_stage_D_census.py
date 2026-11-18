"""Stage checks for the census stages (review 4, id D_census).

Scripts covered: R/denver_1880.R, R/denver_eds_analysis.R (+ R/grf_eds.R), R/county_panel_1880_1940.R, R/ej_panel.R,
R/app_census_layers.R, R/denver_tracts_1950_2020.R, R/descriptive_sequences.R, R/statewide.R, R/fetch_census.R, R/benchmarks.R.

Everything here reads only committed files (app/data, data/results, data/historical, data/full_inventory, README.md); the
person-level Brown / IPUMS inputs are never needed.  Most tests recompute a published table a second way from the committed
district / tract level files, so they do not freeze numbers: they fail when a table and the files it was built from drift apart.

Run:  STAGE_ROOT=/path/to/repo pytest test_stage_D_census.py      (in the repository it lives in tests/stages/)
Known defects are kept as xfail(strict=True) with the finding number of REPORT.md.
"""
import functools
import json
import os
import pathlib
import re

import numpy as np
import pandas as pd
import pytest

ROOT = pathlib.Path(os.environ["STAGE_ROOT"]) if os.environ.get("STAGE_ROOT") else pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / "app" / "data"
RES = ROOT / "data" / "results"
UTM = 26913
CBD = (500250.0, 4399500.0)                      # the downtown point every R script uses
ED_YEARS = (1880, 1900, 1910, 1920, 1930, 1940)
EXT_1880 = ["Assay office", "Ore milling & sampling", "Manufactured gas", "Coke works", "Tannery", "Wood preserving", "Batteries",
            "Radium & uranium"]                  # sectors denver_eds_analysis.R drops from the 1878-85 firms (not Frickel & Elliott)
ED_MEAS = {"pct_black": ("black", "pop"), "pct_fb": ("fb", "pop"), "pct_fb_mexico": ("fb_mexico", "pop"), "pct_hisp": ("hisp", "pop"),
           "pct_laborers": ("laborers", "pop"), "pct_white": ("white", "pop"), "pct_owner_hh": ("owner_hh", "tenure_hh"),
           "pct_haz_industry": ("haz_industry", "employed"), "pct_recent_immig": ("recent_immig", "pop"),
           "pct_movers": ("movers", "mover_universe"), "pct_illiterate": ("illiterate", "lit_universe"), "pct_boarders": ("boarders", "pop")}
ED_AVG = ("mean_sei", "median_rent")
TRACT_WIN = {1950: (1941, 1950), 1960: (1951, 1960), 1970: (1961, 1970), 1980: (1971, 1980), 1990: (1981, 1990),
             2000: (1983, 1992), 2010: (1983, 1992), 2020: (1983, 1992)}
PANEL_WIN = {1940: (1931, 1940), **TRACT_WIN}
TRACT_MEAS = ["p_white", "p_black", "p_hisp", "p_fb", "p_pov", "p_owner", "mval_2020", "mrent_2020"]
COMPLETE_EDITIONS = [1965, 1966, 1967, 1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992]


# ------------------------------------------------------------------------------------------------ helpers
def gpd():
    return pytest.importorskip("geopandas")


def need(*paths):
    for p in paths:
        if not pathlib.Path(p).exists():
            pytest.skip(f"missing {p}")


def csv(path, **kw):
    need(path)
    return pd.read_csv(path, low_memory=False, **kw)


def years_of(s):
    return [int(x) for x in re.findall(r"\d{4}", str(s))]


def wls(y, X, w, cluster=None):
    """Weighted least squares with HC1 (or cluster-robust, sandwich::vcovCL defaults) standard errors -> (beta, se)."""
    y = np.asarray(y, float); X = np.asarray(X, float); w = np.asarray(w, float)
    n, k = X.shape
    bread = np.linalg.inv(X.T @ (X * w[:, None]))
    beta = bread @ (X.T @ (w * y))
    u = (X * (w * (y - X @ beta))[:, None])                                   # score contributions
    if cluster is None:
        meat = u.T @ u * n / (n - k)
    else:
        g = pd.Series(cluster).reset_index(drop=True)
        s = pd.DataFrame(u).groupby(g.values).sum().values
        G = s.shape[0]
        meat = s.T @ s * G / (G - 1) * (n - 1) / (n - k)
    return beta, np.sqrt(np.diag(bread @ meat @ bread))


def dummies(s):
    d = pd.get_dummies(pd.Series(s).reset_index(drop=True), drop_first=True).astype(float)
    return d.values


def nearest(px, py, fx, fy):
    return np.sqrt(((np.asarray(px)[:, None] - np.asarray(fx)[None, :]) ** 2 + (np.asarray(py)[:, None] - np.asarray(fy)[None, :]) ** 2).min(axis=1))


def points(df, lon="lon", lat="lat"):
    g = gpd()
    return g.GeoDataFrame(df.copy(), geometry=g.points_from_xy(df[lon], df[lat]), crs=4326).to_crs(UTM)


@functools.lru_cache(maxsize=None)
def hist_sites():
    return csv(APP / "historical_sites.csv")


def hist_fe_street(denver=False):
    h = hist_sites()
    h = h[(h.precision != "town") & h.lat.notna() & (h.fe_hazard == True)]    # noqa: E712
    return h[h.town == "DENVER"] if denver else h


@functools.lru_cache(maxsize=None)
def firms_1880():
    f = csv(RES / "denver_1880" / "firms_1878_1885_placed.csv")
    return f[(f.how != "street only") & ~f.sector.isin(EXT_1880)]


@functools.lru_cache(maxsize=None)
def ed_layer(yr):
    """One census's districts (population > 0) in UTM with the measures, firm counts and distances recomputed here."""
    g = gpd()
    f = RES / "denver_eds" / f"denver_eds_{yr}.geojson"
    need(f)
    E = g.read_file(f).to_crs(UTM)
    E = E[E["pop"].notna() & (E["pop"] > 0)].reset_index(drop=True)
    for k in set(sum(map(list, ED_MEAS.values()), [])) | set(ED_AVG):
        E[k] = pd.to_numeric(E[k], errors="coerce").astype(float)
    for m, (n, d) in ED_MEAS.items():
        v = 100 * E[n] / E[d]
        v[~np.isfinite(v) | (E[d] < 20)] = np.nan
        E[m] = v
    if yr == 1880:
        f80 = firms_1880()
        F = g.GeoDataFrame(f80.copy(), geometry=g.points_from_xy(f80.x, f80.y), crs=UTM)
    else:
        h = hist_fe_street(denver=True)
        F = points(h[(h.first_year <= yr) & (h.last_year >= yr - 9)])
    j = g.sjoin(F[["geometry"]], E[["geometry"]], predicate="within", how="inner")
    E["firms"] = j.groupby("index_right").size().reindex(E.index).fillna(0).astype(int).values
    c = E.geometry.centroid
    E["dist_m"] = nearest(c.x, c.y, F.geometry.x, F.geometry.y)
    E["dist_cbd"] = np.maximum(np.hypot(c.x - CBD[0], c.y - CBD[1]), 100)
    E["census"] = yr
    return E, F


@functools.lru_cache(maxsize=None)
def tracts():
    g = gpd()
    need(APP / "co_tracts_2010.geojson")
    T = g.read_file(APP / "co_tracts_2010.geojson").to_crs(UTM)
    T["geometry"] = T.geometry.make_valid()
    T["core"] = T.core.astype(str).str.upper() == "TRUE"
    return T


@functools.lru_cache(maxsize=None)
def panel():
    return csv(APP / "tract_panel.csv", dtype={"GEOID": str})


@functools.lru_cache(maxsize=None)
def sites():
    return csv(APP / "sites.csv", dtype={"GEOID": str})


@functools.lru_cache(maxsize=None)
def tract_firms(y):
    """Firms of the decade as R/denver_tracts_1950_2020.R selects them (statewide points, UTM): pre-1960 firm-locations whose listings
    span the window; from 1970 the sites with a Frickel-Elliott-sector listing inside the window (from the listings file)."""
    a, b = TRACT_WIN[y]
    if y <= 1960:
        s = hist_fe_street()
        return points(s[(s.first_year <= b) & (s.last_year >= a)])
    s = sites(); s = s[s.lat.notna() & (s.fe_hazard == True)]                 # noqa: E712
    L = csv(RES / "CO_directory_listings_1961-2002.csv", usecols=["site_id", "year", "fe_hazard"])
    sy = L[(L.fe_hazard == True) & L.site_id.notna()]                         # noqa: E712  (F&E-sector listings only, as the R script reads them)
    return points(s[s.site_id.isin(sy[sy.year.between(a, b)].site_id)])


@functools.lru_cache(maxsize=None)
def tract_layer(y):
    g = gpd()
    T = tracts(); T = T[T.core][["GEOID", "geometry"]].reset_index(drop=True)
    F = tract_firms(y)
    j = g.sjoin(F[["geometry"]], T[["geometry"]], predicate="intersects", how="inner").sort_values("index_right")
    j = j[~j.index.duplicated()]                                              # a firm on a shared edge counts once, in the first tract of the file
    T["firms"] = j.groupby("index_right").size().reindex(T.index).fillna(0).astype(int).values
    c = T.geometry.centroid
    T["dist_m"] = nearest(c.x, c.y, F.geometry.x, F.geometry.y)
    T["dist_cbd"] = np.maximum(np.hypot(c.x - CBD[0], c.y - CBD[1]), 100)
    p = panel()
    d = p[p.census == y].merge(pd.DataFrame(T.drop(columns="geometry")), on="GEOID")
    return d[d["pop"].notna() & (d["pop"] >= 200)].reset_index(drop=True), F, T


# ================================================================================================ Denver 1880
def test_1880_placed_firms_file_counts():
    """Catches a firms_1878_1885_placed.csv that no longer matches the summary, the app copy or the ED table built from it."""
    f = csv(RES / "denver_1880" / "firms_1878_1885_placed.csv")
    assert set(f.how) <= {"building", "nearest number on street", "street only"}
    assert not f.duplicated(["x", "y", "sector"]).any(), "one point per firm-site and sector"
    assert f.year.between(1878, 1885).all()
    ed = csv(RES / "denver_1880" / "ed_composition_vs_firms.csv")
    assert ed.firms.sum() <= (f.how != "street only").sum()                   # firms inside Brown's EDs <= building-level placements
    a = csv(APP / "denver_1880_firms.csv")
    assert len(a) == len(f) and (a.how.value_counts() == f.how.value_counts()).all()
    md = (RES / "denver_1880" / "denver_1880_summary.md").read_text()
    m = re.search(r"(\d+) were placed on the 1880 map \((\d+) at the building or within a few house numbers, (\d+) at the street only\)", md)
    assert m and [int(x) for x in m.groups()] == [len(f), (f.how != "street only").sum(), (f.how == "street only").sum()]


def test_1880_placed_coordinates_inside_1880_denver():
    """Catches firm points in the wrong CRS or outside the 1880 city (the reconstructed 1880 districts + 300 m)."""
    E, _ = ed_layer(1880)
    g = gpd()
    f = csv(RES / "denver_1880" / "firms_1878_1885_placed.csv")
    P = g.GeoSeries(g.points_from_xy(f.x, f.y), crs=UTM)
    assert P.within(E.geometry.union_all().buffer(300)).all()


def test_1880_listing_window_and_street_count():
    """Catches a change of the 1878-1885 Denver listing window: the summary's 'N firms with a street' must equal the listings file."""
    L = csv(ROOT / "data" / "historical" / "CO_pre1960_hazardous_listings.csv")
    d = L[(L.town == "DENVER") & L.year.between(1878, 1885)]
    n_street = (d.street.fillna("") != "").sum()
    md = (RES / "denver_1880" / "denver_1880_summary.md").read_text()
    m = re.search(r"list (\d+) hazardous-trade firms in Denver with a street", md)
    assert m and int(m.group(1)) == n_street


def test_readme_1880_firm_count_matches_listings():
    """Catches a README count of the 1878-1885 Denver hazardous-trade firms that no committed file supports."""
    L = csv(ROOT / "data" / "historical" / "CO_pre1960_hazardous_listings.csv")
    d = L[(L.town == "DENVER") & L.year.between(1878, 1885)]
    ok = {len(d), d.hfirm.nunique(), int((d.street.fillna("") != "").sum())}
    m = re.search(r"places the (\d+) hazardous-trade firms of the 1878.1885 business directories", (ROOT / "README.md").read_text())
    assert m and int(m.group(1)) in ok


@pytest.mark.xfail(strict=True, reason="FINDING 5: 3 of the 1878-79 firms carry their own address in the name (404 Lawrence, 377 Larimer, 433 Blake) "
                                       "but are placed at a neighbouring entry's address (443 Holl, 491 Champa, 486 Larimer)")
def test_1880_firm_placed_at_its_own_printed_address():
    """Catches a firm whose name still carries its printed address but whose street field (used for placement) is another entry's."""
    f = csv(RES / "denver_1880" / "firms_1878_1885_placed.csv")
    bad = []
    for r in f.itertuples():
        m = re.search(r",\s*(\d{2,4})\s+([A-Z][a-z]+)\.?$", str(r.name))
        if m and not str(r.street).startswith(m.group(1)):
            bad.append((r.name, r.street))
    assert not bad, bad


def test_1880_ed_groups_recompute_and_distance_bands():
    """Catches ed_groups_1880.csv going stale against ed_composition_vs_firms.csv, and band totals that differ from the model n."""
    c = csv(RES / "denver_1880" / "ed_composition_vs_firms.csv"); g = csv(RES / "denver_1880" / "ed_groups_1880.csv").set_index("group")
    assert c.ED.is_unique and len(c) == 17
    for name, d in (("EDs with hazardous firms", c[c.firms > 0]), ("EDs without", c[c.firms == 0])):
        assert g.EDs[name] == len(d) and g.population[name] == d["pop"].sum()
        for v in ("pct_fb", "pct_black", "pct_german", "pct_irish", "mean_sei"):
            assert g[v][name] == pytest.approx(np.average(d[v], weights=d["pop"]), rel=1e-9)
    r = csv(RES / "denver_1880" / "residents_by_distance.csv"); m = csv(RES / "denver_1880" / "person_models.csv")
    assert list(r.band) == ["< 100 m", "100-250 m", "250-500 m", "> 500 m"]
    assert r.residents.sum() == m.n.max()                                    # every geocoded resident falls in one band
    assert (m[m.outcome.isin(["laborer", "sei (employed adults, linear)"])].n < m.n.max()).all()
    assert r.residents.sum() <= c["pop"].sum()                               # geocoded residents <= Brown's ED totals


def test_1880_person_models_p_consistent_with_estimate_and_se():
    """Catches a p-value that does not belong to its odds ratio / SE (z test on the log odds; t test for the linear SEI row)."""
    stats = pytest.importorskip("scipy.stats")
    m = csv(RES / "denver_1880" / "person_models.csv")
    lin = m.outcome.str.startswith("sei")
    z = np.where(lin, m.odds_ratio_per_log_m, np.log(m.odds_ratio_per_log_m.abs())) / m.se
    p = 2 * stats.norm.sf(np.abs(z))
    assert np.allclose(p, m.p, rtol=0.02, atol=1e-12)
    assert (m[~lin].odds_ratio_per_log_m > 0).all()


# ================================================================================================ enumeration districts 1880-1940
def test_ed_polygons_unique_labels_no_overlap_and_inside_denver():
    """Catches pooled / duplicated ED labels, overlapping districts (double counting in area weighting) and a wrong CRS."""
    for yr in ED_YEARS:
        E, _ = ed_layer(yr)
        assert E.ED.is_unique, yr
        u = E.geometry.union_all()
        assert abs(E.area.sum() - u.area) / u.area < 1e-3, yr                 # space-filling, not overlapping
        b = E.to_crs(4326).total_bounds
        assert -105.15 < b[0] and b[2] < -104.80 and 39.60 < b[1] and b[3] < 39.85, (yr, b)
        assert (E["pop"] >= E[["black", "fb", "hisp", "laborers"]].max(axis=1)).all(), yr


def test_ed_counts_agree_across_files():
    """Catches the district count of a census differing between the polygons, the groups table, the model table and the geocoding log."""
    M = csv(RES / "denver_eds" / "ed_distance_models.csv"); G = csv(RES / "denver_eds" / "ed_year_groups.csv")
    FD = csv(RES / "denver_eds" / "ed_dissimilarity_fixed_grid.csv"); LOG = csv(RES / "denver_eds" / "ed_geocoding_R.csv").set_index("year")
    tot = 0
    for yr in ED_YEARS:
        E, _ = ed_layer(yr); n = len(E); tot += n
        g = G[G.census == yr].set_index("group")
        assert g.EDs["dissimilarity (all mapped EDs)"] == n
        assert g.EDs["EDs with hazardous firms"] + g.EDs["EDs without"] == n
        assert g.population["EDs with hazardous firms"] + g.population["EDs without"] == g.population["dissimilarity (all mapped EDs)"] == E["pop"].sum()
        m = M[M.census == yr]
        assert (m.EDs <= n).all() and m.EDs[m.outcome == "pct_black"].iloc[0] == n      # EDs is each model's n; every district has a Black share
        assert (FD[FD.census == yr].EDs == n).all()
        if yr in LOG.index:
            assert LOG.eds[yr] >= n and LOG.geocoded[yr] <= LOG.addresses[yr] and LOG.used[yr] <= LOG.geocoded[yr]
    full = M[(M.census == 0) & M.outcome.isin(["pct_black", "pct_fb", "pct_laborers"])]
    assert (full.EDs == tot).all(), "pooled n = sum of the censuses for measures every census has"


def test_ed_mapped_population_within_city_full_count():
    """Catches ED labels pooled across counties or lost districts: mapped population must be 98-100% of the city's full count."""
    city = csv(APP / "denver_city_1880_1940.csv").set_index("census")
    for yr in ED_YEARS:
        E, _ = ed_layer(yr)
        share = E["pop"].sum() / city["pop"][yr]
        assert 0.98 <= share <= 1.0005, (yr, share)
        assert len(E) <= city.EDs[yr]


def test_ed_firm_counts_match_site_file_and_app_layer():
    """Catches the per-census firm count drifting from the pre-1960 sites file ([year-9, year] window) or from the app's firm layer.
    The app layer holds every firm of the window; the model table's firms column counts those inside a populated district."""
    M = csv(RES / "denver_eds" / "ed_distance_models.csv"); A = csv(APP / "denver_eds_firms.csv")
    G = csv(RES / "denver_eds" / "ed_year_groups.csv")
    for yr in ED_YEARS:
        E, F = ed_layer(yr)
        assert set(M[M.census == yr].firms) == {int(E.firms.sum())}, yr
        assert len(F) == int(E.firms.sum()), yr   # every firm-location of the window lies inside a reconstructed district (18 Nov rebuild)
        assert (A.census == yr).sum() == len(F), yr
        assert G[(G.census == yr) & (G.group == "EDs with hazardous firms")].EDs.iloc[0] == (E.firms > 0).sum(), yr


def test_ed_firm_shares_count_firms_inside_districts():
    """Catches ed_firm_shares.csv 'firms' no longer being the firms that fall inside a populated district."""
    S = csv(RES / "denver_eds" / "ed_firm_shares.csv")
    for yr in ED_YEARS:
        E, _ = ed_layer(yr)
        assert set(S[S.census == yr].firms) == {int(E.firms.sum())}, yr


def test_ed_firm_count_same_in_models_and_shares():
    """Catches two published tables giving different firm counts for one census."""
    M = csv(RES / "denver_eds" / "ed_distance_models.csv"); S = csv(RES / "denver_eds" / "ed_firm_shares.csv")
    m = M[M.census > 0].groupby("census").firms.first(); s = S.groupby("census").firms.first()
    assert (m.reindex(s.index) == s).all(), {y: (int(m[y]), int(s[y])) for y in s.index if m[y] != s[y]}


class ManuscriptWordingPending(AssertionError):
    """Raised only by the wording check below, so that the xfail cannot hide a failure of the span-rule checks."""


SPAN_RULE = "first_year <= yr & hp$last_year >= yr - 9"
MS_DECADE_WORDING = r"list(?:ed|ings) (?:in|of) the ten years ending at"
# firms of each census (all, without a listing inside [census-9, census]) under the span rule, recomputed in the test below
SPAN_DENVER = {1900: (34, 1), 1910: (22, 2), 1920: (149, 0), 1930: (52, 9), 1940: (83, 2)}        # street-level Denver firms (district analysis)
SPAN_STATE = {1900: (120, 5), 1910: (82, 9), 1920: (790, 0), 1930: (250, 23), 1940: (383, 10)}     # all placed firms (county panel)


def _ms_says_listed_in_the_decade():
    f = ROOT / "paper" / "Before_and_After_the_Map_manuscript.md"
    return f.exists() and re.search(MS_DECADE_WORDING, f.read_text(encoding="utf-8")) is not None


@pytest.mark.xfail(_ms_says_listed_in_the_decade(), strict=True, raises=ManuscriptWordingPending,
                   reason="manuscript wording pending: the pre-1960 firms of a census are those whose first and last listings span the ten "
                          "years ending at it (editions are sparse), not those 'listed in the ten years ending at the census'")
def test_ed_firms_of_the_decade_are_listed_in_the_decade():
    """Catches (a) the two pre-1960 scripts applying different rules for the firms of a census, (b) a change in how many firms the span
    rule carries without a listing inside the ten years, and (c) a manuscript that still describes them as listed in those ten years."""
    for f in ("denver_eds_analysis.R", "county_panel_1880_1940.R"):                                  # (a) one rule in both scripts
        src = (ROOT / "R" / f).read_text(encoding="utf-8")
        assert src.count(SPAN_RULE) == 1 and len(re.findall(r"first_year\s*[<>]=?", src)) == 1, f
    f80 = firms_1880()                                                                               # 1880: the 1878-1885 listings
    assert f80.year.between(1878, 1885).all() and len(f80) == 38
    inside = lambda h, yr: h.years.map(lambda s: any(yr - 9 <= y <= yr for y in years_of(s)))        # noqa: E731
    h = hist_fe_street(denver=True); a = hist_sites(); a = a[a.lat.notna() & (a.fe_hazard == True)]  # noqa: E712
    for src, pin in ((h, SPAN_DENVER), (a, SPAN_STATE)):                                             # (b) pinned counts
        got = {}
        for yr in ED_YEARS[1:]:
            w = src[(src.first_year <= yr) & (src.last_year >= yr - 9)]
            assert (w.years.map(lambda s: min(years_of(s))) == w.first_year).all() and (w.years.map(lambda s: max(years_of(s))) == w.last_year).all(), yr
            got[yr] = (len(w), int((~inside(w, yr)).sum()))
        assert got == pin, got
    if _ms_says_listed_in_the_decade():                                                              # (c)
        raise ManuscriptWordingPending("the manuscript still says the decade's firms are those listed in the ten years ending at the census")


def test_ed_model_n_is_the_number_of_districts_in_the_model():
    """Catches a reported n that is larger than the number of districts with a value for the outcome."""
    M = csv(RES / "denver_eds" / "ed_distance_models.csv"); bad = []
    for r in M[M.census > 0].itertuples():
        E, _ = ed_layer(r.census)
        n = int(E[r.outcome].notna().sum())
        if n != r.EDs:
            bad.append((r.census, r.outcome, r.EDs, n))
    assert not bad, bad


def test_ed_distance_models_recompute():
    """Catches any change in distances, weights, the +50 m offset, the downtown control or HC1 that the published coefficients do not reflect."""
    M = csv(RES / "denver_eds" / "ed_distance_models.csv"); D = []
    for yr in ED_YEARS:
        E, _ = ed_layer(yr); D.append(pd.DataFrame(E.drop(columns="geometry")))
        for r in M[M.census == yr].itertuples():
            d = E[E[r.outcome].notna()]
            X = np.column_stack([np.ones(len(d)), np.log(d.dist_m + 50)])
            b, se = wls(d[r.outcome], X, d["pop"])
            b2, se2 = wls(d[r.outcome], np.column_stack([X, np.log(d.dist_cbd)]), d["pop"])
            assert [b[1], se[1], b2[1], se2[1]] == pytest.approx([r.b_per_log_m, r.se, r.b_cbd_ctrl, r.se_cbd_ctrl], rel=5e-3, abs=1e-5), (yr, r.outcome)
    D = pd.concat(D, ignore_index=True)
    for r in M[M.census == 0].itertuples():
        d = D[D[r.outcome].notna() & D.dist_m.notna()]
        assert len(d) == r.EDs, r.outcome                                    # pooled n really is the number of districts used
        X = np.column_stack([np.ones(len(d)), np.log(d.dist_m + 50)])
        if d.census.nunique() > 1:
            X = np.column_stack([X, dummies(d.census)])
        b, se = wls(d[r.outcome], X, d["pop"])
        b2, se2 = wls(d[r.outcome], np.column_stack([X[:, :2], np.log(d.dist_cbd), X[:, 2:]]), d["pop"])
        assert [b[1], se[1], b2[1], se2[1]] == pytest.approx([r.b_per_log_m, r.se, r.b_cbd_ctrl, r.se_cbd_ctrl], rel=5e-3, abs=1e-5), r.outcome


def test_ed_single_census_pooled_rows_equal_that_census():
    """Catches a 'pooled' row of a measure only one census provides that differs from that census's own row."""
    M = csv(RES / "denver_eds" / "ed_distance_models.csv")
    for oc in ("pct_movers", "median_rent"):
        a = M[(M.census == 1940) & (M.outcome == oc)].iloc[0]; b = M[(M.census == 0) & (M.outcome == oc)].iloc[0]
        assert a.b_per_log_m == pytest.approx(b.b_per_log_m, rel=1e-9) and a.se == pytest.approx(b.se, rel=1e-9)
    pooled = M[M.census == 0].set_index("outcome"); per = M[M.census > 0]
    for oc, r in pooled.iterrows():                                          # a pooled slope lies inside the range of the per-census slopes
        x = per[per.outcome == oc].b_per_log_m
        assert x.min() - 1e-9 <= r.b_per_log_m <= x.max() + 1e-9, oc


def test_ed_models_p_consistent_with_b_and_se():
    """Catches p-values that do not belong to b / se (t test, residual df from the EDs column; 3 df slack for the n overstatement)."""
    stats = pytest.importorskip("scipy.stats")
    M = csv(RES / "denver_eds" / "ed_distance_models.csv")
    for b, se, p, k in (("b_per_log_m", "se", "p", 2), ("b_cbd_ctrl", "se_cbd_ctrl", "p_cbd_ctrl", 3)):
        df = np.where(M.census > 0, M.EDs - k, M.EDs - k - 5)
        pp = 2 * stats.t.sf(np.abs(M[b] / M[se]), df)
        assert np.allclose(pp, M[p], rtol=0.05, atol=1e-12), (b, np.abs(pp - M[p]).max())


def test_ed_groups_and_quartile_shares_recompute():
    """Catches the with/without composition, the dissimilarity index or the quartile shares drifting from the district files."""
    G = csv(RES / "denver_eds" / "ed_year_groups.csv"); S = csv(RES / "denver_eds" / "ed_firm_shares.csv")
    assert S.share_firms_top_quartile.between(0, 100).all() and S.share_firms_bottom_quartile.between(0, 100).all()
    assert (S.share_firms_top_quartile + S.share_firms_bottom_quartile <= 100.05).all()       # the two quartiles are disjoint sets
    for yr in ED_YEARS:
        E, _ = ed_layer(yr)
        for name, d in (("EDs with hazardous firms", E[E.firms > 0]), ("EDs without", E[E.firms == 0])):
            g = G[(G.census == yr) & (G.group == name)].iloc[0]
            for v in ("pct_black", "pct_fb", "pct_hisp", "pct_laborers", "pct_owner_hh"):
                ok = d[v].notna()
                if ok.any():
                    assert g[v] == pytest.approx(np.average(d[v][ok], weights=d["pop"][ok]), rel=1e-6), (yr, name, v)
        dis = lambda a, b: 0.5 * np.abs(a / a.sum() - b / b.sum()).sum()     # noqa: E731
        g = G[(G.census == yr) & G.group.str.startswith("dissim")].iloc[0]
        assert g.pct_black == pytest.approx(dis(E.black, E["pop"] - E.black), rel=1e-6) and 0 <= g.pct_black <= 1
        for r in S[S.census == yr].itertuples():
            o = E[E[r.measure].notna()].sort_values(r.measure, ascending=False, kind="stable")
            cum = o["pop"].cumsum() / o["pop"].sum()
            top = o[(cum <= 0.25) | (np.arange(len(o)) == 0)]
            ro = o.iloc[::-1]; bot = ro[(ro["pop"].cumsum() / o["pop"].sum()) <= 0.25]
            assert r.share_pop_top_quartile == pytest.approx(100 * top["pop"].sum() / E["pop"].sum(), abs=0.06), (yr, r.measure)
            assert r.share_pop_top_quartile <= 25.05 or len(top) == 1
            assert r.share_firms_top_quartile == pytest.approx(100 * top.firms.sum() / E.firms.sum(), abs=0.06), (yr, r.measure)
            assert r.share_firms_bottom_quartile == pytest.approx(100 * bot.firms.sum() / E.firms.sum(), abs=0.06), (yr, r.measure)


def test_fixed_grid_dissimilarity_table_is_coherent():
    """Catches a fixed-grid segregation table whose cell sets change between censuses or whose ED column disagrees with the groups table."""
    FD = csv(RES / "denver_eds" / "ed_dissimilarity_fixed_grid.csv"); G = csv(RES / "denver_eds" / "ed_year_groups.csv")
    assert (FD.groupby("extent").cells.nunique() == 1).all()                  # one fixed set of cells per extent
    assert FD.dissimilarity_black_vs_nonblack.between(0, 1).all() and FD.black_share_pct.between(0, 100).all()
    g = G[G.group.str.startswith("dissim")].set_index("census").pct_black.round(3)
    assert (FD.dissimilarity_on_EDs == FD.census.map(g)).all()
    assert (FD.dissimilarity_black_vs_nonblack <= FD.dissimilarity_on_EDs + 1e-9).all()        # coarser, smoothed units cannot be more segregated
    assert not FD.duplicated(["census", "extent"]).any()
    assert set(FD[FD.extent.str.contains("1900 city")].census) == {1900, 1910, 1920, 1930, 1940}


# ================================================================================================ descriptive sequences: 500 m grid
@functools.lru_cache(maxsize=None)
def grid_1900():
    """The 500 m grid of descriptive_sequences.R (area mapped in every census 1900-1940) with each census's counts area-weighted onto it."""
    g = gpd(); from shapely.geometry import box
    CNT = ["pop", "black", "hisp", "fb", "laborers"]
    Es = {}
    for y in ED_YEARS[1:]:
        E, _ = ed_layer(y); e = E[CNT + ["geometry"]].copy(); e["geometry"] = e.geometry.make_valid(); Es[y] = e
    com = functools.reduce(lambda a, b: a.intersection(b), [e.geometry.union_all() for e in Es.values()])
    x0, y0, x1, y1 = com.bounds
    cells = g.GeoDataFrame(geometry=[box(x, y, x + 500, y + 500) for x in np.arange(x0, x1, 500) for y in np.arange(y0, y1, 500)], crs=UTM)
    cells["geometry"] = cells.intersection(com); cells = cells[cells.area >= 0.5 * 500 ** 2].reset_index(drop=True); cells["cid"] = cells.index
    out = {}
    for y, e in Es.items():
        e = e.copy(); e["src_a"] = e.area
        x = g.overlay(e, cells, how="intersection", keep_geom_type=True)
        w = x.area / x.src_a
        for k in CNT:
            x[k] = x[k] * w
        out[y] = x.groupby("cid")[CNT].sum().reindex(cells.cid)
    h = points(hist_fe_street(denver=True))
    j = g.sjoin(h[["first_year", "last_year", "geometry"]], cells, predicate="within", how="inner")
    return cells, out, j


def test_grid_area_weighting_conserves_and_reproduces_fixed_grid_and_first_arrival():
    """Catches an area-weighting error (weights not area(piece)/area(district)), a changed grid, or first-arrival cells/decades that moved."""
    cells, G, j = grid_1900()
    FD = csv(RES / "denver_eds" / "ed_dissimilarity_fixed_grid.csv"); FD = FD[FD.extent.str.contains("1900 city")].set_index("census")
    assert set(FD.cells) == {len(cells)}
    for y, d in G.items():
        E, _ = ed_layer(y)
        assert d["pop"].sum() <= E["pop"].sum() * 1.0001                       # weights sum to <= 1 per district: nobody is created
        b = d.black; o = d["pop"] - d.black
        assert FD.dissimilarity_black_vs_nonblack[y] == pytest.approx(0.5 * np.abs(b / b.sum() - o / o.sum()).sum(), abs=2e-3), y
        assert FD.black_share_pct[y] == pytest.approx(100 * b.sum() / d["pop"].sum(), abs=0.02), y
    A2 = csv(RES / "descriptive" / "grid_first_arrival_1900_1940.csv")
    first = j.groupby("cid").first_year.min()
    for t in (1900, 1910, 1920, 1930):
        ever = j[j.first_year <= t].cid.unique()
        a = G[t][~G[t].index.isin(ever)]
        arr = a.index.map(lambda c: c in first.index and t < first[c] <= t + 10)
        for flag, lab in ((True, "first hazardous trade arrives in the next decade"), (False, "no hazardous trade by the next census")):
            r = A2[(A2["from"] == t) & (A2.group == lab)].iloc[0]; d = a[arr == flag]
            assert r.to == t + 10 and r.cells == len(d), (t, lab)
            assert r["pop"] == pytest.approx(d["pop"].sum(), abs=1.5), (t, lab)
            assert r.pct_black_before == pytest.approx(100 * d.black.sum() / d["pop"].sum(), abs=0.011), (t, lab)
        assert A2[A2["from"] == t].cells.sum() == len(a)                      # the two groups partition the cells with no trade by t


def test_grid_location_quotients_are_coherent():
    """Catches location quotients not centred on the city share, class groups that do not partition the grid, and firm counts that drift."""
    cells, G, j = grid_1900()
    A1 = csv(RES / "descriptive" / "grid_location_quotients_1900_1940.csv")
    cls = A1[A1.group.str.startswith("1938 class")]; zon = A1[A1.group.str.startswith("1929")]
    for y, d in cls.groupby("census"):
        assert d.cells.sum() == len(cells), y                                 # every cell has exactly one future class
        assert d["pop"].sum() == pytest.approx(G[y]["pop"].sum(), abs=len(d))
        city_b = (d.pct_black * d["pop"]).sum() / d["pop"].sum()
        assert ((d.pct_black / city_b).round(2) - d.lq_black).abs().max() <= 0.02, y    # LQ = class share / city share
        assert (d.lq_black * d["pop"]).sum() / d["pop"].sum() == pytest.approx(1, abs=0.01), y
        n = len(j[(j.first_year <= y) & (j.last_year >= y - 9)])
        assert d.firms.sum() == n, (y, d.firms.sum(), n)                      # the decade's firms inside the grid
        assert d.cells_ever_firm.sum() == j[j.first_year <= y].cid.nunique(), y
        assert (d.cells_with_firm <= d.cells_ever_firm).all() and (d.cells_ever_firm <= d.cells).all()
    for y, d in zon.groupby("census"):
        assert d.cells.sum() <= len(cells) and len(d) == 2                    # cells off the 1929 sheet are left out
    ev = cls.groupby(["group", "census"]).cells_ever_firm.first().unstack()
    assert (ev.diff(axis=1).iloc[:, 1:] >= 0).all().all(), "cells that ever had a firm can only grow"


# ================================================================================================ tract panel (app_census_layers.R)
def test_tract_panel_firm_columns_are_coherent():
    """Catches firm columns that break their own definitions (hazardous <= all, no all-firm count before 1970, 2000-2020 reuse 1983-92)."""
    p = panel()
    assert not p.duplicated(["GEOID", "census"]).any()
    late = p[p.census >= 1970]
    assert (late.firms_haz <= late.firms_all).all() and late.firms_all.notna().all()
    assert p[p.census <= 1960].firms_all.isna().all()
    assert (p[["firms_haz", "legacy_haz"]] >= 0).all().all() and p[["firms_haz", "legacy_haz"]].notna().all().all()
    w = p[p.census >= 2000].pivot(index="GEOID", columns="census", values=["firms_haz", "firms_all", "legacy_haz"])
    for v in ("firms_haz", "firms_all", "legacy_haz"):
        assert (w[v][2000] == w[v][2010]).all() and (w[v][2010] == w[v][2020]).all(), v
    leg = p[p.census.between(1970, 1990)].pivot(index="GEOID", columns="census", values="legacy_haz")
    assert (leg.diff(axis=1).iloc[:, 1:] >= 0).all().all(), "legacy firms accumulate"


def test_tract_panel_geography_matches_tract_layer():
    """Catches the core flag, distance to downtown or area in the panel disagreeing with the tract layer or with the 10 km rule."""
    p = panel(); T = tracts().set_index("GEOID")
    one = p.drop_duplicates("GEOID").set_index("GEOID")
    assert set(one.index) == set(T.index)
    assert (one.core == (one.dist_km <= 10)).all()
    assert (one.core == T.core.reindex(one.index)).all()
    assert np.allclose(one.dist_km, T.dist_km.reindex(one.index)) and np.allclose(one.area_km2, T.area_km2.reindex(one.index))
    c = T[T.core].geometry.centroid                                           # simplified polygons: centroid within 150 m of the original
    d = np.hypot(c.x - CBD[0], c.y - CBD[1]) / 1000
    assert (np.abs(d - T[T.core].dist_km) < 0.15).all()
    assert (p.groupby("GEOID")[["dist_km", "area_km2", "core"]].nunique() == 1).all().all()


def test_tract_panel_firm_counts_recompute_from_sites():
    """Catches firm windows, the hazardous definition or the point-in-tract join changing without tract_panel.csv being rebuilt."""
    g = gpd(); p = panel(); T = tracts()[["GEOID", "geometry"]]
    s = sites(); f = csv(APP / "site_firms.csv")
    sp = g.sjoin(points(s[["site_id", "lon", "lat"]]), T, predicate="within", how="inner").drop_duplicates("site_id")
    FE = "Chemicals|Petroleum refining|Rubber & plastics|Primary metals|Fabricated metals|Industrial machinery|Transportation equipment"
    f = f.merge(sp[["site_id", "GEOID"]], on="site_id"); f["haz"] = f.sectors.fillna("").str.contains(FE)
    assert not (f.haz & ~(f.hazardous == True)).any()                         # noqa: E712  F&E sector firms are all flagged hazardous
    h = hist_fe_street()
    hp = g.sjoin(points(h[["hfirm", "first_year", "last_year", "lon", "lat"]]), T, predicate="within", how="inner").drop_duplicates("hfirm")
    for y, (a, b) in PANEL_WIN.items():
        pub = p[p.census == y].set_index("GEOID")
        if y <= 1960:
            mine = hp[(hp.first_year <= b) & (hp.last_year >= a)].groupby("GEOID").size()
        else:
            w = f[(f.first_year <= b) & (f.last_year >= a)]
            mine = w[w.haz].groupby("GEOID").size()
            tot = w.groupby("GEOID").size().reindex(pub.index).fillna(0)
            assert abs(tot.sum() - pub.firms_all.sum()) <= 0.01 * pub.firms_all.sum(), y
        mine = mine.reindex(pub.index).fillna(0)
        # the script places points in the original tract polygons, this test in the published simplified ones: allow edge cases
        assert abs(mine.sum() - pub.firms_haz.sum()) <= max(2, 0.01 * pub.firms_haz.sum()), (y, mine.sum(), pub.firms_haz.sum())
        assert (mine == pub.firms_haz).mean() >= 0.94, y


def test_tract_panel_state_totals_1990_2020():
    """Catches lost or duplicated tracts in the standardised 1990-2020 series: the panel must sum to Colorado's census counts."""
    p = panel().groupby("census")["pop"].sum()
    for y, n in {1990: 3294394, 2000: 4301261, 2010: 5029196, 2020: 5773714}.items():   # decennial census counts of Colorado
        assert abs(p[y] - n) <= 1e-4 * n, (y, p[y])
    assert p.is_monotonic_increasing                                          # the tracted area and the state both grow


def test_tract_panel_hispanic_measure_availability_by_census():
    """Catches a Hispanic / poverty series appearing in a census that did not publish one (1940-50: none; poverty from 1970)."""
    p = panel(); m = p[p["pop"] >= 200]
    assert m[m.census <= 1950].p_hisp.isna().all() and m[m.census <= 1960].p_pov.isna().all()
    for y in (1990, 2000, 2010, 2020):
        assert m[m.census == y][["p_hisp", "p_black", "p_white", "p_fb", "p_pov"]].notna().all().all(), y
    for y in (1960, 1970, 1980):
        assert m[m.census == y].p_hisp.notna().mean() > 0.99, y
    assert ((m.p_black + m.p_white).dropna() <= 100.6).all()                  # two race groups cannot exceed the population


# ================================================================================================ tracts 1950-2020 (denver_tracts_1950_2020.R)
def test_tract_groups_partition_the_core_tracts():
    """Catches with/without groups that do not add up to the tracts with 200+ residents, or populations that differ from the panel."""
    G = csv(RES / "denver_tracts" / "denver_tracts_groups.csv")
    for y in TRACT_WIN:
        d, _, _ = tract_layer(y); g = G[G.census == y].set_index("group")
        assert g.EDs["Tracts with hazardous firms"] + g.EDs["Tracts without"] == g.EDs["dissimilarity (all tracts)"] == len(d)
        assert g.population["dissimilarity (all tracts)"] == d["pop"].sum()
        assert g.EDs["Tracts with hazardous firms"] == (d.firms > 0).sum()
        assert g.population["Tracts with hazardous firms"] == d["pop"][d.firms > 0].sum()
        bl = d[d.p_black.notna()]; b = bl.p_black / 100 * bl["pop"]; o = bl["pop"] - b
        assert g.p_black["dissimilarity (all tracts)"] == pytest.approx(0.5 * np.abs(b / b.sum() - o / o.sum()).sum(), abs=0.006)
        w = d[d.firms > 0]
        for v in ("p_black", "p_hisp", "p_owner"):
            if w[v].notna().any():
                assert g[v]["Tracts with hazardous firms"] == pytest.approx(np.average(w[v][w[v].notna()], weights=w["pop"][w[v].notna()]), abs=0.006), (y, v)


def test_tract_distance_models_recompute():
    """Catches the tract gradients drifting from tract_panel.csv + the site files (weights, log distance, downtown control, HC1)."""
    M = csv(RES / "denver_tracts" / "denver_tracts_models.csv"); D = []
    for y in TRACT_WIN:
        d, _, _ = tract_layer(y); D.append(d)
        for r in M[M.census == y].itertuples():
            m = r.outcome.replace("log_", "")
            dd = d[d[m].notna() & (d.dist_m > 0)]
            yv = np.log(dd[m]) if r.outcome.startswith("log_") else dd[m]
            dd = dd[np.isfinite(yv)]; yv = yv[np.isfinite(yv)]
            assert len(dd) == r.EDs, (y, r.outcome)                           # here n is the model's n
            X = np.column_stack([np.ones(len(dd)), np.log(dd.dist_m)])
            b, se = wls(yv, X, dd["pop"]); b2, se2 = wls(yv, np.column_stack([X, np.log(dd.dist_cbd)]), dd["pop"])
            assert [b[1], se[1], b2[1], se2[1]] == pytest.approx([r.b_per_log_m, r.se, r.b_cbd_ctrl, r.se_cbd_ctrl], rel=0.02, abs=2e-3), (y, r.outcome)
    D = pd.concat(D, ignore_index=True)
    for r in M[M.census == 0].itertuples():
        m = r.outcome.replace("log_", ""); dd = D[D[m].notna() & (D.dist_m > 0)]
        yv = np.log(dd[m]) if r.outcome.startswith("log_") else dd[m]
        dd = dd[np.isfinite(yv)]; yv = yv[np.isfinite(yv)]
        assert len(dd) == r.EDs == M[(M.census > 0) & (M.outcome == r.outcome)].EDs.sum(), r.outcome
        b, se = wls(yv, np.column_stack([np.ones(len(dd)), np.log(dd.dist_m), dummies(dd.census)]), dd["pop"], cluster=dd.GEOID)   # clustered by tract
        assert [b[1], se[1]] == pytest.approx([r.b_per_log_m, r.se], rel=0.02, abs=2e-3), r.outcome


def test_tract_quartile_shares_recompute():
    """Catches quartile shares of the decade's firms drifting from the tract panel, and top 'quartiles' holding more than 25% of people."""
    S = csv(RES / "denver_tracts" / "denver_tracts_shares.csv")
    assert (S.share_pop_top_quartile <= 25.05).all() and S.share_firms_top_quartile.between(0, 100).all()
    for y in TRACT_WIN:
        d, _, _ = tract_layer(y)
        for r in S[S.census == y].itertuples():
            o = d[d[r.measure].notna()].sort_values(r.measure, ascending=False, kind="stable")
            top = (o["pop"].cumsum() / o["pop"].sum() <= 0.25) | (np.arange(len(o)) == 0)
            assert r.firms == o.firms.sum(), (y, r.measure)                   # each firm counted in one tract
            assert r.share_pop_top_quartile == pytest.approx(100 * o["pop"][top].sum() / o["pop"].sum(), abs=0.06), (y, r.measure)
            assert r.share_firms_top_quartile == pytest.approx(100 * o.firms[top].sum() / max(o.firms.sum(), 1), abs=1.5), (y, r.measure)


def test_tract_pooled_se_allows_for_repeated_tracts():
    """Catches a pooled standard error that treats repeated observations of one tract as independent."""
    M = csv(RES / "denver_tracts" / "denver_tracts_models.csv")
    D = pd.concat([tract_layer(y)[0] for y in TRACT_WIN], ignore_index=True); bad = {}
    for oc in ("p_hisp", "p_black", "p_pov", "p_owner"):
        dd = D[D[oc].notna()]
        X = np.column_stack([np.ones(len(dd)), np.log(dd.dist_m), dummies(dd.census)])
        _, sec = wls(dd[oc], X, dd["pop"], cluster=dd.GEOID)
        pub = M[(M.census == 0) & (M.outcome == oc)].se.iloc[0]
        if pub < 0.9 * sec[1]:
            bad[oc] = (round(pub, 3), round(sec[1], 3))
    assert not bad, bad


def test_tract_models_firm_count_is_the_study_area_count():
    """Catches a 'firms' column that counts firms outside the study area the model is about."""
    M = csv(RES / "denver_tracts" / "denver_tracts_models.csv"); bad = {}
    for y in TRACT_WIN:
        _, F, T = tract_layer(y)
        inside = int(F.within(T.geometry.union_all()).sum())
        pub = int(M[M.census == y].firms.iloc[0])
        if pub != inside:
            bad[y] = (pub, inside)
    assert not bad, bad


def _tract_decade_counts(y):
    """Study-area sites of the decade, three ways from the listings file (not site_years.csv): with an F&E or extended-sector listing
    in the window, with an F&E listing in it, and by the first/last-year span of all listings."""
    L = csv(RES / "CO_directory_listings_1961-2002.csv", usecols=["site_id", "year", "fe_hazard", "ext_hazard"])
    s = sites(); s = s[s.lat.notna() & (s.fe_hazard == True)]                 # noqa: E712
    U = tracts(); U = U[U.core].geometry.union_all()
    a, b = TRACT_WIN[y]; w = L[L.year.between(a, b)]
    n = lambda d: int(points(d).intersects(U).sum())                          # noqa: E731
    return (n(s[s.site_id.isin(w[(w.fe_hazard == True) | (w.ext_hazard == True)].site_id)]),   # noqa: E712
            n(s[s.site_id.isin(w[w.fe_hazard == True].site_id)]), n(s[(s.first_year <= b) & (s.last_year >= a)]))   # noqa: E712


def test_tract_firms_of_the_decade_have_a_hazardous_listing_in_the_decade():
    """Catches sites counted as hazardous firms of a decade in which they had no hazardous listing: the published study-area count must
    be the count of sites with a Frickel-Elliott-sector listing in the window, recomputed from the listings file, and below both the
    count that also takes extended-sector listings and the count the first/last-year span of all listings would give."""
    src = (ROOT / "R" / "denver_tracts_1950_2020.R").read_text(encoding="utf-8")
    assert "sites[site_id %in% SY[year >= a[1] & year <= a[2], site_id]" in src and "sites[first_year" not in src and "fe_hazard == TRUE" in src
    M = csv(RES / "denver_tracts" / "denver_tracts_models.csv")
    for y in (1970, 1980, 1990, 2000):
        any_haz, fe, span = _tract_decade_counts(y)
        pub = int(M[M.census == y].firms.iloc[0])
        assert pub == fe and pub <= any_haz < span, (y, pub, fe, any_haz, span)


def test_tract_firms_of_the_decade_have_an_fe_listing_in_the_decade():
    """Catches F&E hazardous firms of a decade that have no F&E-sector listing in that decade."""
    M = csv(RES / "denver_tracts" / "denver_tracts_models.csv"); bad = {}
    for y in (1970, 1980, 1990, 2000):
        _, fe, _ = _tract_decade_counts(y)
        pub = int(M[M.census == y].firms.iloc[0])
        if pub != fe:
            bad[y] = (pub, fe)
    assert not bad, bad


def test_tract_fixed_set_tables_are_coherent():
    """Catches fixed-set model rows whose n differs from the set named in the label, or a fixed set that is not nested in the earlier one."""
    MF = csv(RES / "denver_tracts" / "denver_tracts_models_fixed.csv"); SF = csv(RES / "denver_tracts" / "denver_tracts_shares_fixed.csv")
    sizes = {}
    for lab, d in MF.groupby("set"):
        m = re.match(r"fixed (\d{4})-2020 \((\d+) tracts\)", lab); y0, n = int(m.group(1)), int(m.group(2)); sizes[y0] = n
        per = d[(d.census > 0) & (d.outcome == "p_black")]
        assert (per.EDs == n).all() and per.census.min() == y0 and len(per) == len([y for y in TRACT_WIN if y >= y0]), lab
        assert (d[d.census > 0].EDs <= n).all()
        assert d[(d.census == 0) & (d.outcome == "p_black")].EDs.iloc[0] == n * len(per)
    assert sizes[1950] <= sizes[1960] <= sizes[1970] <= 147
    assert set(SF.set) == set(MF.set) and (SF.share_pop_top_quartile <= 25.05).all()
    p = panel(); p = p[p.core & (p.census >= 1960) & (p["pop"] >= 200) & p.p_black.notna()]
    assert sizes[1960] == (p.groupby("GEOID").size() == 7).sum()             # recomputed from the panel


# ================================================================================================ descriptive sequences: tracts
def test_tract_location_quotients_recompute():
    """Catches the 1940-2020 tract location quotients drifting from the panel, or class groups that do not partition the fixed set."""
    B1 = csv(RES / "descriptive" / "tract_location_quotients_1940_2020.csv")
    p = panel(); p = p[p.core]
    fix = p[(p.census >= 1960) & (p["pop"] >= 200)].groupby("GEOID").size(); fix = set(fix[fix == 7].index)
    per = B1.groupby("census").tracts.sum()
    assert per[per.index >= 1960].eq(len(fix)).all() and (per <= len(fix)).all()
    P = p[p.GEOID.isin(fix) & (p["pop"] > 0)]
    tot = P.groupby("census")["pop"].sum().round()
    assert (B1.groupby("census")["pop"].sum() - tot).abs().max() <= B1.cls.nunique()
    assert (B1.groupby("census").firms.sum() == P.groupby("census").firms_haz.sum()).all()
    for v, lq in (("pct_black", "lq_black"), ("pct_hisp", "lq_hisp"), ("pct_poverty", "lq_poverty")):
        d = B1[B1[lq].notna() & (B1.census >= 1990)]                          # complete measures: LQ = class share / pooled share
        city = (d[v] * d["pop"]).groupby(d.census).sum() / d["pop"].groupby(d.census).sum()
        assert ((d[v] / d.census.map(city)).round(2) - d[lq]).abs().max() <= 0.02, lq


def test_tract_first_arrival_groups_recompute():
    """Catches first-arrival groups (listed 1965-70 / first 1973-80 / first 1983-92 / never) that no longer follow from site_years.csv."""
    g = gpd(); B2 = csv(RES / "descriptive" / "tract_first_arrival_1965_1992.csv").set_index("group")
    p = panel(); p = p[p.core]
    fix = p[(p.census >= 1960) & (p["pop"] >= 200)].groupby("GEOID").size(); fix = set(fix[fix == 7].index)
    assert B2.tracts.sum() == len(fix)
    s = sites(); s = s[(s.fe_hazard == True) & s.lat.notna()]                 # noqa: E712
    j = g.sjoin_nearest(points(s[["site_id", "lon", "lat"]]), tracts()[["GEOID", "geometry"]], max_distance=100, how="inner").drop_duplicates("site_id")
    sy = csv(APP / "site_years.csv"); sy = sy[sy.year.isin(COMPLETE_EDITIONS)].merge(j[["site_id", "GEOID"]], on="site_id")
    first = sy.groupby("GEOID").year.min().reindex(sorted(fix))
    grp = np.where(first <= 1970, "hazardous manufacturer listed 1965-70", np.where(first <= 1980, "first listed 1973-80 (arrival)",
                   np.where(first.notna(), "first listed 1983-92", "none listed 1965-92")))
    mine = pd.Series(grp).value_counts()
    assert (mine.reindex(B2.index).fillna(0) - B2.tracts).abs().max() <= 1, mine.to_dict()
    w = p[p.GEOID.isin(fix) & (p.census == 1970)].set_index("GEOID").reindex(first.index)
    for name in B2.index:
        d = w[grp == name]
        assert B2.pct_hisp_1970[name] == pytest.approx(np.average(d.p_hisp, weights=d["pop"]), abs=0.5), name
    assert np.allclose(B2.chg_hisp_1970_90, B2.pct_hisp_1990 - B2.pct_hisp_1970)


# ================================================================================================ ej_panel.R
def test_ej_panel_file_is_coherent():
    """Catches panel rows below the population minimum, densities that are not counts / area, or hazardous counts above all-firm counts."""
    d = csv(RES / "ej_panel_denver.csv", dtype={"GEOID": str})
    assert not d.duplicated(["GEOID", "census"]).any() and set(d.census) == {1970, 1980, 1990}
    assert (d["pop"] >= 200).all() and d.GEOID.nunique() <= 147
    assert (d.active_haz <= d.active).all() and (d.legacy_haz <= d.legacy).all()
    assert np.allclose(d.active_d, d.active_haz / d.area_km2) and np.allclose(d.legacy_d, d.legacy_haz / d.area_km2)
    assert np.allclose(d.pop_d, d["pop"] / d.area_km2) and (d.dist_km <= 10).all()
    assert np.allclose(d.p_hisp, 100 * d.hisp / d["pop"]) and np.allclose(d.p_black, 100 * d.nhblk / d["pop"])
    p = panel(); core = set(p[p.core].GEOID)
    assert set(d.GEOID) <= core
    m = d.merge(p[["GEOID", "census", "pop", "p_hisp"]], on=["GEOID", "census"], suffixes=("", "_panel"))
    assert len(m) == len(d) and (m["pop"].round() == m.pop_panel).all()       # the same census counts as the app's tract panel
    assert np.allclose(m.p_hisp.clip(upper=100).round(1), m.p_hisp_panel, atol=0.051)


def test_ej_panel_active_counts_recompute_from_listings():
    """Catches the matched-edition establishment counts (1970, 1980, 1990) drifting from the listings file."""
    g = gpd(); d = csv(RES / "ej_panel_denver.csv", dtype={"GEOID": str})
    L = csv(RES / "CO_directory_listings_1961-2002.csv", usecols=["estab_id", "year", "lat", "lon", "geo_level", "fe_hazard"])
    L = L[L.geo_level.isin(["address", "address_approx"]) & L.lat.notna() & L.year.isin([1970, 1980, 1990])]
    T = tracts(); T = T[T.core][["GEOID", "geometry"]]
    j = g.sjoin(points(L), T, predicate="within", how="inner")
    j = j[~j.index.duplicated()]
    a = j.groupby(["GEOID", "year"]).estab_id.nunique(); h = j[j.fe_hazard == True].groupby(["GEOID", "year"]).estab_id.nunique()   # noqa: E712
    k = pd.MultiIndex.from_frame(d[["GEOID", "census"]])
    assert abs(a.reindex(k).fillna(0).sum() - d.active.sum()) <= 0.01 * d.active.sum()
    assert abs(h.reindex(k).fillna(0).sum() - d.active_haz.sum()) <= 0.01 * d.active_haz.sum()
    assert (h.reindex(k).fillna(0).values == d.active_haz.values).mean() >= 0.95


def test_ej_panel_models_recompute():
    """Catches the hybrid panel and reverse models drifting from ej_panel_denver.csv (within/between terms, tract-clustered SE, n)."""
    d = csv(RES / "ej_panel_denver.csv", dtype={"GEOID": str}).sort_values(["GEOID", "census"]).reset_index(drop=True)
    M = csv(RES / "ej_panel_models.csv"); RV = csv(RES / "ej_panel_reverse.csv").set_index("predictor")
    g = d.groupby("GEOID")
    la = np.log1p(d.active_d); d["act_w"] = la - la.groupby(d.GEOID).transform("mean"); d["act_b"] = la.groupby(d.GEOID).transform("mean")
    d["leg_b"] = np.log1p(d.GEOID.map(d[d.census == g.census.transform("min")].set_index("GEOID").legacy_d))
    lp = np.log1p(d.pop_d); d["popd_w"] = lp - lp.groupby(d.GEOID).transform("mean")
    d["entry_next"] = g.active_haz.shift(-1) - d.active_haz
    assert ((g.census.shift(-1) - d.census).dropna() == 10).all()            # 'next census' is always ten years on
    H = M[M.model.str.startswith("hybrid")]
    assert (H.n <= len(d)).all() and (H.tracts <= d.GEOID.nunique()).all()
    for oc, pub in H.groupby("outcome"):
        x = d[d[oc].notna()]
        X = np.column_stack([np.ones(len(x)), x.act_w, x.act_b, x.leg_b, x.popd_w, x.dist_km, dummies(x.census)])
        b, se = wls(x[oc], X, np.ones(len(x)), cluster=x.GEOID)
        pub = pub.set_index("term")
        for i, t in enumerate(("act_w", "act_b", "leg_b"), start=1):
            assert [b[i], se[i], len(x)] == pytest.approx([pub.b[t], pub.se[t], pub.n[t]], rel=5e-3, abs=1e-6), (oc, t)
            assert pub.tracts[t] == x.GEOID.nunique(), (oc, t)
    for xv, r in RV.iterrows():
        x = d[d.entry_next.notna() & d[xv].notna()]
        X = np.column_stack([np.ones(len(x)), x[xv], np.log1p(x.active_d), x.popd_w, x.dist_km, dummies(x.census)])
        b, se = wls(x.entry_next, X, np.ones(len(x)), cluster=x.GEOID)
        assert [b[1], se[1], len(x)] == pytest.approx([r.b, r.se, r.n], rel=5e-3, abs=1e-6), xv


def test_ej_panel_tables_p_values_and_copies():
    """Catches p-values that do not belong to b / se in the four panel tables."""
    stats = pytest.importorskip("scipy.stats")
    for f, tol in (("ej_panel_models.csv", 2e-3), ("ej_panel_by_decade.csv", 5e-3), ("ej_panel_legacy_sites.csv", 5e-3), ("ej_panel_reverse.csv", 3e-3)):
        d = csv(RES / f)
        assert (d.se > 0).all()
        assert np.abs(2 * stats.norm.sf(np.abs(d.b / d.se)) - d.p).max() < tol, f      # t with 140+ df is within this of the normal
    L = csv(RES / "ej_panel_legacy_sites.csv")
    assert set(L.census) == {2000, 2010, 2020} and L.tracts.between(140, 147).all()


# ================================================================================================ counties 1880-1940, statewide
def test_county_panel_is_coherent():
    """Catches duplicated county-years, shares that are not count / population, and a Denver County that differs from the city file."""
    c = csv(RES / "county_panel_1880_1940.csv", dtype={"fips": str})
    assert not c.duplicated(["census", "icp"]).any() and set(c.census) == set(ED_YEARS)
    assert (c.fips == c.icp.map(lambda i: "08%03d" % (i // 10))).all()
    for v, n, k in (("pct_black", "black", 2), ("pct_fb", "fb", 1), ("pct_fb_mexico", "fb_mexico", 2), ("pct_hisp", "hisp", 2), ("pct_laborers", "laborers", 1)):
        assert np.allclose(c[v], (100 * c[n] / c["pop"]).round(k), atol=10 ** -k * 0.51, equal_nan=True), v
    assert (c[["black", "fb", "hisp", "laborers"]].max(axis=1) <= c["pop"]).all() and (c.fb_mexico + c.fb_europe + c.fb_asia <= c.fb).all()
    city = csv(APP / "denver_city_1880_1940.csv").set_index("census")
    den = c[c.icp == 310].set_index("census")
    assert set(den.index) == {1910, 1920, 1930, 1940}                        # Denver County exists from 1902
    assert (den["pop"] == city["pop"].reindex(den.index)).all() and (den.EDs == city.EDs.reindex(den.index)).all()
    for y in (1880, 1900):                                                    # before 1902 the city is part of Arapahoe (ICP 50)
        assert c[(c.icp == 50) & (c.census == y)]["pop"].iloc[0] >= city["pop"][y]
    st = c.groupby("census")["pop"].sum()
    for y, n in {1880: 194327, 1900: 539700, 1910: 799024, 1920: 939629, 1930: 1035791, 1940: 1123296}.items():   # published state totals
        assert abs(st[y] - n) <= 0.005 * n, (y, st[y])


def test_county_firm_counts_recompute_and_match_app_layer():
    """Catches county firm counts drifting from the pre-1960 sites file ([year-9, year], F&E trades, each census's own counties)."""
    g = gpd(); c = csv(RES / "county_panel_1880_1940.csv"); need(APP / "co_counties_1880_1940.geojson")
    S = g.read_file(APP / "co_counties_1880_1940.geojson")
    assert len(S) == len(c) and not S.duplicated(["census", "icp"]).any()
    assert (S.groupby("census").firms_haz.sum() == c.groupby("census").firms_haz.sum()).all()
    h = hist_sites(); h = h[h.lat.notna() & (h.fe_hazard == True)]            # noqa: E712
    hp = points(h[["hfirm", "first_year", "last_year", "lon", "lat"]]).to_crs(4326)
    for yr in ED_YEARS:
        w = hp[(hp.first_year <= yr) & (hp.last_year >= yr - 9)]
        j = g.sjoin(w, S[S.census == yr][["icp", "geometry"]], predicate="within", how="inner").drop_duplicates("hfirm")
        pub = c[c.census == yr].set_index("icp").firms_haz
        mine = j.groupby("icp").size().reindex(pub.index).fillna(0)
        assert abs(mine.sum() - pub.sum()) <= 2 and (mine == pub).mean() >= 0.95, (yr, mine.sum(), pub.sum())   # simplified county edges


def test_statewide_county_tables_recompute():
    """Catches regional shares that do not sum to 100 or the county correlations drifting from the county panel."""
    c = csv(RES / "county_panel_1880_1940.csv", dtype={"fips": str}); c = c[c["pop"].notna()]
    R1 = csv(RES / "statewide" / "county_regions_1880_1940.csv"); R1c = csv(RES / "statewide" / "county_correlations_1880_1940.csv").set_index("census")
    assert (R1.groupby("census").pct_trades.sum() - 100).abs().max() <= 0.25 and (R1.groupby("census").pct_pop.sum() - 100).abs().max() <= 0.25
    assert (R1.groupby("census").trades.sum() == c.groupby("census").firms_haz.sum()).all()
    assert (R1.groupby("census")["pop"].sum() == c.groupby("census")["pop"].sum()).all()
    den = R1[R1.region.str.startswith("Denver")].set_index("census")
    for y in ED_YEARS:
        icp = 50 if y <= 1900 else 310
        assert den.trades[y] == c[(c.census == y) & (c.icp == icp)].firms_haz.iloc[0], y
    for y, d in c[c["pop"] >= 1000].groupby("census"):
        x = np.log1p(1000 * d.firms_haz / d["pop"])
        assert R1c.counties[y] == len(d)
        for col, v in (("r_foreign_born", "pct_fb"), ("r_hispanic", "pct_hisp"), ("r_laborers", "pct_laborers"), ("r_black", "pct_black")):
            assert R1c[col][y] == pytest.approx(x.corr(d[v]), abs=0.0051), (y, col)


def test_statewide_regional_shares_recompute():
    """Catches regional shares of hazardous manufacturers that drift from sites.csv / site_years.csv or do not sum to 100."""
    R2 = csv(RES / "statewide" / "regional_shares_1965_1992.csv").set_index("region")
    assert [int(c) for c in R2.columns[:-1]] == COMPLETE_EDITIONS
    assert (R2.drop(columns="pct_pop_1990").sum() - 100).abs().max() <= 0.25 and abs(R2.pct_pop_1990.sum() - 100) <= 0.25
    reg = {"031": "Denver", "041": "Colorado Springs (El Paso)", "101": "Pueblo", "077": "Grand Junction (Mesa)"}
    reg.update({k: "Denver suburbs" for k in ("001", "005", "014", "035", "059")}); reg.update({k: "Boulder, Larimer, Weld" for k in ("013", "069", "123")})
    s = sites(); s = s[(s.fe_hazard == True) & s.lat.notna() & s.geo_level.isin(["address", "address_approx"])]   # noqa: E712
    assert s.GEOID.str.fullmatch(r"08\d{9}").all()                            # a blank GEOID would fall silently into 'rest of Colorado'
    sy = csv(APP / "site_years.csv"); sy = sy[sy.year.isin(COMPLETE_EDITIONS)].merge(s[["site_id", "GEOID"]], on="site_id")
    sy["region"] = sy.GEOID.str[2:5].map(reg).fillna("rest of Colorado")
    n = sy.groupby(["year", "region"]).site_id.nunique()
    pct = (100 * n / n.groupby("year").transform("sum")).round(1).unstack("year").fillna(0)
    assert np.abs(pct.reindex(R2.index).values - R2.drop(columns="pct_pop_1990").values).max() <= 0.051
    p = panel(); p = p[(p.census == 1990) & p["pop"].notna()]
    pop = p.groupby(p.GEOID.str[2:5].map(reg).fillna("rest of Colorado"))["pop"].sum()
    assert np.abs((100 * pop / pop.sum()).round(1).reindex(R2.index) - R2.pct_pop_1990).max() <= 0.051


def test_statewide_tract_associations_recompute():
    """Catches the statewide tract models drifting from tract_panel.csv (fixed sets, weights, county effects, HC1) or their n from the fixed sets."""
    R3 = csv(RES / "statewide" / "tract_associations_1980_2020.csv")
    p = panel(); P = p[p["pop"].notna() & (p["pop"] >= 200)].copy()
    n90 = P[P.census >= 1990].groupby("GEOID").size(); fix90 = set(n90[n90 == 4].index)
    n80 = P[P.census >= 1980].groupby("GEOID").size(); fix80 = set(n80[n80 == 5].index)
    co = R3[R3.region == "Colorado"]
    assert co[co.set.str.contains("1990-2020")].tracts.max() == len(fix90) and co[co.set.str.contains("1980-2020")].tracts.max() == len(fix80)
    assert (R3.se > 0).all() and R3.p.between(0, 1).all() and not R3.duplicated(["set", "region", "outcome", "census"]).any()
    P["lfirm"] = np.log1p(P.firms_haz / P.area_km2); P["ldens"] = np.log(P["pop"] / P.area_km2); P["cty"] = P.GEOID.str[2:5]
    OUT = {"% Hispanic": "p_hisp", "% below poverty": "p_pov", "% Black": "p_black"}
    for r in co[co.outcome.isin(OUT) & co.census.isin([1990, 2020])].itertuples():
        v = OUT[r.outcome]; d = P[P.GEOID.isin(fix90 if "1990-2020" in r.set else fix80) & (P.census == r.census) & P[v].notna()]
        X = np.column_stack([np.ones(len(d)), d.lfirm, d.ldens, dummies(d.cty)])
        keep = np.r_[True, True, True, np.abs(X[:, 3:]).sum(axis=0) > 0]
        b, se = wls(d[v], X[:, keep], d["pop"])
        assert [b[1], len(d)] == pytest.approx([r.b, r.tracts], rel=5e-3), (r.set, r.outcome, r.census)
        assert se[1] == pytest.approx(r.se, rel=0.03), (r.set, r.outcome, r.census)


def test_graded_cities_tables_are_coherent():
    """Catches graded-city tables with impossible values (negative densities, zero-area classes, location quotients without tracts)."""
    R4 = csv(RES / "statewide" / "graded_cities_firm_density.csv"); R5 = csv(RES / "statewide" / "graded_cities_tract_lq_1970_2020.csv")
    assert (R4.km2 > 0).all() and (R4[["1965-1980", "1981-1992"]] >= 0).all().all() and not R4.duplicated(["city", "step"]).any()
    assert set(R4.step) <= {"best", "middle", "worst", "business, industrial or fire district"}
    assert (R5.tracts >= 1).all() and not R5.duplicated(["city", "step", "census"]).any() and set(R5.census) <= {1970, 1980, 1990, 2000, 2010, 2020}
    assert R5[["pct_hisp", "pct_black", "pct_pov"]].stack().between(0, 100).all()
    one = R5.groupby(["city", "census"]).filter(lambda d: len(d) == 1)       # a city with one graded class has LQ 1 by construction
    assert np.allclose(one.lq_hisp.dropna(), 1, atol=0.011)


# ================================================================================================ benchmarks
def test_benchmark_tables_are_coherent():
    """Catches ratios that are not directory / CBP, hazardous counts above totals, and county rows that exceed the state row."""
    B = RES / "benchmarks"; s = csv(B / "cbp_vs_directory_state.csv"); c = csv(B / "cbp_vs_directory_county.csv", dtype={"county": str})
    assert list(s.year) == list(range(1975, 2003))
    ok = s.dir_all.notna()
    assert np.allclose(s.ratio_mfg[ok], (s.dir_mfg / s.cbp_mfg).round(2)[ok]) and np.allclose(s.ratio_haz[ok], (s.dir_haz / s.cbp_haz).round(2)[ok])
    assert (s.cbp_haz <= s.cbp_mfg).all() and (s.dir_haz[ok] <= s.dir_all[ok]).all() and (s.dir_mfg[ok] <= s.dir_all[ok]).all()
    assert (c.cbp_haz <= c.cbp_mfg).all() and (c.dir_haz <= c.dir_all).all() and (c.dir_street <= c.dir_all).all()
    assert set(c.year) == set(s.year[ok]) and not c.duplicated(["year", "county"]).any()
    cs = c.groupby("year")[["cbp_mfg", "cbp_haz", "dir_mfg", "dir_haz", "dir_all"]].sum(); m = s.set_index("year").loc[cs.index]
    assert (cs.cbp_mfg == m.cbp_mfg).all() and (cs.cbp_haz == m.cbp_haz).all()         # CBP: counties sum to the state
    assert (cs.dir_all <= m.dir_all).all() and (cs.dir_all >= 0.95 * m.dir_all).all()  # directory firms in counties CBP does not list
    for f in ("cbp_vs_directory_state.csv", "cbp_vs_directory_county.csv", "nhgis_mfg_vs_directory.csv"):
        assert (APP / f).read_bytes() == (B / f).read_bytes(), f


def test_benchmark_directory_side_recompute():
    """Catches the directory counts in the CBP comparison drifting from the all-editions listings (unique establishments per edition and county)."""
    g = gpd(); f = ROOT / "data" / "full_inventory" / "CO_directory_listings_1961-2002.csv"; need(APP / "enviroscreen_tracts.geojson")
    L = csv(f, usecols=["estab_id", "year", "lat", "lon", "sic", "naics", "fe_hazard"], dtype={"sic": str, "naics": str}); L = L[L.lat.notna()]
    s = csv(RES / "benchmarks" / "cbp_vs_directory_state.csv").set_index("year"); s = s[s.dir_all.notna()]
    T = g.read_file(APP / "enviroscreen_tracts.geojson")[["GEOID", "geometry"]]; T["geometry"] = T.geometry.make_valid()
    pts = L[["lat", "lon"]].drop_duplicates()
    j = g.sjoin(g.GeoDataFrame(pts, geometry=g.points_from_xy(pts.lon, pts.lat), crs=4326), T.to_crs(4326), predicate="intersects", how="inner")
    j = j[~j.index.duplicated()]; j["county"] = j.GEOID.str[2:5]
    L = L.merge(j[["lat", "lon", "county"]], on=["lat", "lon"])                # listings outside every tract have no county and drop out
    L["mfg"] = L.sic.fillna("").str.match(r"^[23][0-9]") | L.naics.fillna("").str.match(r"^3[123]")
    cnt = lambda d: d.groupby(["year", "county"]).estab_id.nunique().groupby("year").sum().reindex(s.index)   # noqa: E731
    for mine, pub in ((cnt(L), s.dir_all), (cnt(L[L.fe_hazard == True]), s.dir_haz), (cnt(L[L.mfg]), s.dir_mfg)):   # noqa: E712
        assert (mine - pub).abs().max() <= 2, (mine - pub).to_dict()
    n = csv(f, usecols=["year"]).groupby("year").size().reindex(s.index)       # the edition's listings column is a plain row count
    assert (n == s.listings).all(), (n - s.listings)[n != s.listings].to_dict()


def test_benchmark_county_ratios_are_finite():
    """Catches infinite ratios written to a published CSV."""
    c = csv(RES / "benchmarks" / "cbp_vs_directory_county.csv")
    assert np.isfinite(c.ratio_mfg.dropna()).all() and np.isfinite(c.ratio_haz.dropna()).all()


def test_nhgis_benchmark_is_coherent():
    """Catches census years without a directory edition within two years entering the 1880-1940 comparison, or ratios that do not recompute."""
    n = csv(RES / "benchmarks" / "nhgis_mfg_vs_directory.csv", dtype={"county": str})
    eds = sorted({y for s in hist_sites().years for y in years_of(s)})
    for cy in n.census.unique():
        assert any(abs(e - cy) <= 2 for e in eds), cy
    assert 1900 not in set(n.census) and 1910 not in set(n.census) or any(abs(e - 1910) <= 2 for e in eds)
    assert (n.mfg_estab >= 0).all()
    ok = n.dir_haz.notna() & (n.mfg_estab > 0)
    assert np.allclose(n.ratio_haz_to_census[ok], (n.dir_haz / n.mfg_estab)[ok].round(2), atol=0.006)
    assert (n.dir_street.fillna(0) <= n.dir_haz.fillna(0)).all()


def test_nhgis_benchmark_one_row_per_county_and_census():
    """Catches two NHGIS counties collapsing onto one county code (historical NHGIS codes that are not FIPS x 10)."""
    n = csv(RES / "benchmarks" / "nhgis_mfg_vs_directory.csv", dtype={"county": str})
    assert not n.duplicated(["census", "county"]).any()


# ================================================================================================ copies used by the app
def test_app_copies_of_census_tables_are_identical():
    """Catches an app copy of a census table that was not refreshed (pairs with different names are not covered by tests/outputs)."""
    pairs = {"denver_1880_distance.csv": RES / "denver_1880" / "residents_by_distance.csv", "denver_1880_models.csv": RES / "denver_1880" / "person_models.csv",
             "denver_1880_ed_groups.csv": RES / "denver_1880" / "ed_groups_1880.csv", "county_regions_1880_1940.csv": RES / "statewide" / "county_regions_1880_1940.csv",
             "ed_distance_models.csv": RES / "denver_eds" / "ed_distance_models.csv", "ed_firm_shares.csv": RES / "denver_eds" / "ed_firm_shares.csv",
             "denver_tracts_models.csv": RES / "denver_tracts" / "denver_tracts_models.csv", "grid_first_arrival_1900_1940.csv": RES / "descriptive" / "grid_first_arrival_1900_1940.csv"}
    for name, src in pairs.items():
        need(APP / name, src)
        assert (APP / name).read_bytes() == src.read_bytes(), name
    a = csv(APP / "denver_1880_eds.csv"); c = csv(RES / "denver_1880" / "ed_composition_vs_firms.csv")
    m = a.merge(c, on="ED", suffixes=("", "_res"))
    assert len(m) == 17 and (m.firms == m.firms_res).all() and (m["pop"] == m.pop_res).all()
    E, _ = ed_layer(1880)
    ip = E.assign(ED=E.ED.astype(int)).set_index("ED")["pop"]
    assert (a.set_index("ED").ipums_pop == ip.reindex(a.ED).values).all()    # the same IPUMS district totals in both 1880 layers
