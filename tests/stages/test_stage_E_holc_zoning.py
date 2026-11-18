"""Stage checks for the HOLC / zoning / rezoning / Sanborn / land-use / highways / corridors / context stages (review 4).

Reads only committed files (app/data, data/results, data/raw, R/, rerun_results.sh). Lives in tests/stages/; run from elsewhere with
    STAGE_ROOT=/path/to/repo pytest test_stage_E_holc_zoning.py
Every test recomputes a published table from the stage's own inputs (polygons, cells, site points) with independent code
(geopandas / numpy), or asserts an invariant between files. Known defects are strict xfails that name the finding in REPORT.md.
"""
import os
import pathlib
import re
import warnings

import numpy as np
import pandas as pd
import pytest

gpd = pytest.importorskip("geopandas")
import shapely  # noqa: E402
from shapely.geometry import Polygon  # noqa: E402

warnings.filterwarnings("ignore")
ROOT = pathlib.Path(os.environ["STAGE_ROOT"]) if os.environ.get("STAGE_ROOT") else pathlib.Path(__file__).resolve().parents[2]
A, RES, RAW = ROOT / "app" / "data", ROOT / "data" / "results", ROOT / "data" / "raw"
UTM = 26913
GR = list("ABCD")
ED_OK = [1965, 1966, 1967, 1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992]
_C = {}


def cached(fn):
    def w():
        if fn.__name__ not in _C:
            _C[fn.__name__] = fn()
        return _C[fn.__name__]
    return w


def csv(p, **k):
    return pd.read_csv(ROOT / p, low_memory=False, **k)


def pts(d):
    return gpd.GeoDataFrame(d.copy(), geometry=gpd.points_from_xy(d.lon, d.lat), crs=4326).to_crs(UTM)


@cached
def holc():
    h = gpd.read_file(A / "holc_denver.geojson").to_crs(UTM)
    h["geometry"] = shapely.make_valid(h.geometry.values)
    h["cls"] = np.where(h.grade.isin(GR), h.grade, np.where(h["cat"].str.contains("Industrial"), "Industrial",
                        np.where(h["cat"].str.contains("Commercial"), "Commercial", "other")))
    h["km2"] = h.area / 1e6
    return h


@cached
def hist_denver():
    h = csv("app/data/historical_sites.csv", dtype={"GEOID": str})
    h = h[(h.precision != "town") & h.lat.notna() & (h.town == "DENVER") & (h.fe_hazard == True)]  # noqa: E712
    g = pts(h)
    g["yl"] = [[int(x) for x in re.split(r"[^0-9]+", str(s)) if x] for s in g.years]
    j = gpd.sjoin(g, holc()[["area_id", "cls", "geometry"]], how="left", predicate="intersects")
    return j[~j.index.duplicated()]


@cached
def hist_street():
    h = csv("app/data/historical_sites.csv", dtype={"GEOID": str})
    return pts(h[(h.precision != "town") & h.lat.notna() & (h.fe_hazard == True)])  # noqa: E712


@cached
def sites_fe():
    s = csv("app/data/sites.csv", dtype={"GEOID": str})
    s = s[(s.fe_hazard == True) & s.lat.notna()]  # noqa: E712
    j = gpd.sjoin(pts(s), holc()[["cls", "geometry"]], how="left", predicate="intersects")
    return j[~j.index.duplicated()]


@cached
def site_years():
    return csv("app/data/site_years.csv")


@cached
def sites_addr():
    """1965-92 hazardous-sector sites as the zoning scripts select them."""
    s = sites_fe()
    ok = set(site_years()[site_years().year.isin(ED_OK)].site_id)
    return s[s.geo_level.isin(["address", "address_approx"]) & s.site_id.isin(ok)]


@cached
def tracts():
    t = gpd.read_file(A / "co_tracts_2010.geojson").to_crs(UTM)
    t["geometry"] = shapely.make_valid(t.geometry.values)
    return t


@cached
def tracts_raw():
    """The tract outlines as rezoning_denver.R reads them (no make_valid)."""
    return gpd.read_file(A / "co_tracts_2010.geojson").to_crs(UTM)


@cached
def den():
    t = tracts()
    return shapely.union_all(t[t.GEOID.str[:5] == "08031"].geometry.values)


@cached
def fit29():
    g = csv("data/results/zoning_1929/gcp_fit.csv")
    X = np.column_stack([np.ones(len(g)), g.px_x, g.px_y])
    return g, np.linalg.lstsq(X, g.X, rcond=None)[0], np.linalg.lstsq(X, g.Y, rcond=None)[0]


def rect29(x0, y0, x1, y1):
    _, cx, cy = fit29()
    P = lambda x, y: (cx[0] + cx[1] * x + cx[2] * y, cy[0] + cy[1] * x + cy[2] * y)  # noqa: E731
    return Polygon([P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)])


@cached
def cells():
    c29, c44 = csv("data/raw/zoning_1929/zone_cells_1929.csv"), csv("data/raw/zoning_1929/zone_cells_1944.csv")
    off = csv("data/raw/zoning_1929/cells_off_1944_sheet.csv")
    return c29, c44, off


def dissolve(c, pattern):
    r = c[c.zone.str.contains(pattern)]
    return shapely.union_all([rect29(*v) for v in r[["px_x0", "px_y0", "px_x1", "px_y1"]].values])


@cached
def layers():
    """Industrial land of each map and the land on both historical sheets within Denver County (the scripts' COMMON)."""
    c29, c44, off = cells()
    sheet = rect29(0, 0, 11849, 12000)
    offp = shapely.union_all([rect29(c * 32, r * 32, min(c * 32 + 32, 11849), min(r * 32 + 32, 12000)) for c, r in zip(off.col, off.row)])
    on_sheets = sheet.difference(offp)
    z55 = gpd.read_file(A / "zoning_1955.geojson").to_crs(UTM)
    out = dict(sheet=sheet, on_sheets=on_sheets, common=on_sheets.intersection(den()),
               i29=dissolve(c29, "Industrial"), c29=dissolve(c29, "Commercial"), i44=dissolve(c44, "Industrial"), c44=dissolve(c44, "Commercial"),
               i55=shapely.union_all(shapely.make_valid(z55.geometry.values)))
    for nm, f in (("today", "zoning_today_categories.geojson"), ("2023", "zoning_2023_categories.geojson")):
        z = gpd.read_file(A / f).to_crs(UTM)
        z["geometry"] = shapely.make_valid(z.geometry.values)
        out[nm] = z
    return out


def cat_geom(z, cats):
    return shapely.union_all(z[z["cat"].isin(cats)].geometry.values)


# ====================================================================== HOLC (R/holc_covenants.R)

def test_holc_polygons_valid_disjoint_and_areas_match_csv():
    """Catches a wrong CRS/units in the HOLC area calculation, overlapping areas (double-counted land) and a stale holc_areas.csv."""
    h, a = holc(), csv("data/results/holc/holc_areas.csv")
    assert len(h) == len(a) == 56 and h.area_id.is_unique
    assert h.total_bounds[0] > 4.8e5 and h.total_bounds[2] < 5.2e5 and 4.38e6 < h.total_bounds[1] < h.total_bounds[3] < 4.42e6
    m = h.merge(a[["area_id", "area_km2", "grade"]], on="area_id", suffixes=("", "_csv"))
    assert np.allclose(m.km2, m.area_km2_csv, rtol=1e-6)
    assert abs(h.km2.sum() - shapely.union_all(h.geometry.values).area / 1e6) < 0.01          # no overlap between areas
    geod = h.to_crs(4326).geometry.apply(lambda x: abs(__import__("pyproj").Geod(ellps="GRS80").geometry_area_perimeter(x)[0]) / 1e6)
    assert abs(h.km2.sum() / geod.sum() - 1) < 0.002                                         # planar UTM area within 0.2% of geodesic


def test_holc_by_grade_counts_recomputed_from_points_and_polygons():
    """Catches a changed firm filter, period window or point-in-polygon join in holc_by_grade.csv (areas, km2, firms before/after the map)."""
    h, p, g = holc(), hist_denver(), csv("data/results/holc/holc_by_grade.csv").set_index("grade")
    for gr in GR:
        d = p[p.cls == gr]
        assert g.areas[gr] == (h.grade == gr).sum()
        assert g.area_km2[gr] == round(h.km2[h.grade == gr].sum(), 1)
        assert g.firms_pre1938[gr] == (d.first_year <= 1937).sum()
        assert g.areas_with_firm_pre1938[gr] == d[d.first_year <= 1937].area_id.nunique()
        assert g.firms_1921_1937[gr] == ((d.first_year <= 1937) & (d.last_year >= 1921)).sum()
        assert g.firms_1938_1956[gr] == ((d.first_year <= 1956) & (d.last_year >= 1938)).sum()
    assert g.areas.sum() == 54 and g.areas_with_firm_pre1938["C"] <= g.areas["C"]


def test_holc_facility_shares_recomputed():
    """Catches drift between holc_facility_shares.csv and the site, TRI and cleanup points it counts (incl. the 146 pre-map trades)."""
    h, S = holc(), csv("data/results/holc/holc_facility_shares.csv").set_index("layer")
    CLS = GR + ["Industrial", "Commercial"]
    p, s = hist_denver(), sites_fe()

    def other(f):
        d = csv(f)
        j = gpd.sjoin(pts(d[d.lat.notna()]), h[["cls", "geometry"]], how="inner", predicate="intersects")
        return j[~j.index.duplicated()].cls

    exp = {"Hazardous trades before the map (1871-1937)": p[p.first_year <= 1937].cls,
           "Hazardous trades after the map (1938-1956)": p[(p.first_year <= 1956) & (p.last_year >= 1938)].cls,
           "Hazardous-sector manufacturers 1965-1992 (complete editions)": s.cls,
           "Hazardous-sector sites with no match in searched inventories (1965-1992)": s[s.radar == "Not on any list"].cls,
           "EPA TRI facilities (today)": other("app/data/tri_facilities.csv"),
           "Cleanup / contamination sites (today)": other("app/data/cleanup_sites.csv")}
    for layer, cls in exp.items():
        for c in CLS:
            assert S.loc[layer, c] == (cls == c).sum(), (layer, c)
    for c in CLS:
        assert abs(S.loc["Land area of HOLC areas", c] - h.km2[h.cls == c].sum()) < 1e-6
        assert S.loc["Population 1940", c] == round(h.pop_1940[h.cls == c].sum())
    assert np.allclose(S[CLS].sum(axis=1), S.total)
    assert (abs(S[[f"share_{c}" for c in CLS]].sum(axis=1) - 100) <= 0.31).all()
    assert np.allclose(S[[f"share_{c}" for c in CLS]].values, (100 * S[CLS].div(S.total, axis=0)).round(1).values, atol=0.051)


def _per_edition():
    """firms per edition by grade and period, recomputed from the site files (pre-1960: years listed; 1965-92: site_years)."""
    p, s, sy = hist_denver(), sites_fe(), site_years()
    eds_h = sorted({y for yl in p.yl for y in yl})
    rows = []
    for a, b in [(1891, 1905), (1906, 1920), (1921, 1937), (1938, 1956), (1965, 1980), (1981, 1992)]:
        eds = [y for y in (ED_OK if a >= 1960 else eds_h) if a <= y <= b]
        for gr in GR:
            if a >= 1960:
                n = sum(((s.cls == gr) & s.site_id.isin(set(sy[sy.year == y].site_id))).sum() for y in eds)
                firms = ((s.cls == gr) & (s.first_year <= b) & (s.last_year >= a)).sum()
            else:
                n = sum(((p.cls == gr) & p.yl.apply(lambda z: y in z)).sum() for y in eds)
                firms = ((p.cls == gr) & (p.first_year <= b) & (p.last_year >= a)).sum()
            rows.append(dict(period=f"{a}-{b}", grade=gr, firms2=firms, fpe2=n / len(eds), eds2=len(eds)))
    return pd.DataFrame(rows)


def test_holc_industry_periods_counts_recomputed():
    """Catches a wrong edition list, period window or grade join in holc_industry_periods.csv (firms and firms per edition)."""
    I = csv("data/results/holc/holc_industry_periods.csv").merge(_per_edition(), on=["period", "grade"])
    assert len(I) == 24
    assert (I.firms == I.firms2).all()
    assert np.allclose(I.firms_per_edition, I.fpe2)
    assert (I.editions.isna() | (I.editions == I.eds2)).all()
    km = holc().groupby("grade").km2.sum()
    assert (I.km2 == I.grade.map(km).round(1)).all()
    assert np.allclose(I.per_km2, (I.firms / I.grade.map(km)).round(2), atol=0.0051)


def test_holc_dc_ratio_and_density_use_unrounded_area():
    """Catches densities and D/C ratios computed from rounded areas (the script says the ratio comes from the unrounded densities)."""
    I = csv("data/results/holc/holc_industry_periods.csv")
    km = holc().groupby("grade").km2.sum()
    dens = I.firms_per_edition / I.grade.map(km)
    assert np.allclose(I.per_km2_per_edition, dens.round(3), atol=0.00051)
    for per, d in I.assign(dens=dens).groupby("period"):
        c, dd = d.dens[d.grade == "C"].iloc[0], d.dens[d.grade == "D"].iloc[0]
        if c > 0:
            assert d.dc_ratio_within_period.iloc[0] == round(dd / c, 1), per


def test_holc_dc_ratios_within_rounding_of_recomputed():
    """Catches a D/C ratio that no longer follows from the site files and polygons (3.8, 8.3, 2.7, 13.8/13.9, 18.2)."""
    I = csv("data/results/holc/holc_industry_periods.csv").merge(_per_edition(), on=["period", "grade"])
    km = holc().groupby("grade").km2.sum()
    for per, d in I.groupby("period"):
        c = (d.fpe2 / d.grade.map(km))[d.grade == "C"].iloc[0]
        dd = (d.fpe2 / d.grade.map(km))[d.grade == "D"].iloc[0]
        if c > 0:
            assert abs(d.dc_ratio_within_period.iloc[0] - dd / c) < 0.11, per
        else:
            assert d.dc_ratio_within_period.isna().all()


@cached
def tract_grades():
    """Dominant HOLC grade of each 2010 tract by area (the crosswalk's pct_tract), tracts >= 40% graded; and the 6-class version."""
    t, h = tracts(), holc()
    t = t[t.intersects(shapely.box(*h.total_bounds))][["GEOID", "geometry"]].copy()
    t["ta"] = t.area
    ov = gpd.overlay(t, h.assign(c6=np.where(h.grade.isin(GR), h.grade, h["cat"]))[["c6", "geometry"]], how="intersection", keep_geom_type=True)
    ov["sh"] = ov.area / ov.ta
    s = ov.groupby(["GEOID", "c6"]).sh.sum().reset_index()
    g4 = s[s.c6.isin(GR)]
    dom = g4.loc[g4.groupby("GEOID").sh.idxmax()].merge(g4.groupby("GEOID").sh.sum().rename("cov"), on="GEOID")
    dom = dom[dom["cov"] >= 0.4].rename(columns={"c6": "grade"})
    d6 = s.loc[s.groupby("GEOID").sh.idxmax()].merge(s.groupby("GEOID").sh.sum().rename("cov6"), on="GEOID")
    return dom[["GEOID", "grade", "cov"]].merge(d6[d6.cov6 >= 0.4][["GEOID", "c6"]], on="GEOID", how="left")


@cached
def holc_wide():
    pan = csv("app/data/tract_panel.csv", dtype={"GEOID": str}).merge(tract_grades(), on="GEOID")
    pan["lmval"] = np.log(pan.mval_2020.where(pan.mval_2020 > 0))
    W = pan.pivot(index=["GEOID", "grade", "c6"], columns="census", values=["p_black", "p_hisp", "p_pov", "firms_haz", "p_owner", "lmval"])
    W.columns = [f"{a}_{b}" for a, b in W.columns]
    W = W.reset_index()
    W["cls"] = W.c6.fillna(W.grade)
    cen = tracts().set_index("GEOID").centroid.to_crs(4326)
    W["lat"], W["lon"] = W.GEOID.map(cen.y), W.GEOID.map(cen.x)
    return pan, W


def _change_model(v, a, b):
    _, W = holc_wide()
    d = W.copy()
    d["base"], d["black40"], d["firms40"] = d[f"{v}_{a}"], d.p_black_1940, np.log1p(d.firms_haz_1940)
    d["dy"] = d[f"{v}_{b}"] - d.base
    d = d[np.isfinite(d.dy) & np.isfinite(d.base) & d.black40.notna() & np.isfinite(d.firms40)]
    vc = d.cls.value_counts()
    d = d[d.cls.isin(set(vc[vc >= 5].index) | {"A"})]
    lv = [g for g in ["B", "C", "D", "Industrial", "Commercial"] if (d.cls == g).any()]
    cols = [np.ones(len(d))] + [(d.cls == g).values for g in lv] + [d.base.values, d.firms40.values]
    if not np.allclose(d.base, d.black40):          # for % Black from 1940 the baseline IS the 1940 % Black control (R drops the alias)
        cols.append(d.black40.values)
    X, y = np.column_stack(cols).astype(float), d.dy.values
    bi = np.linalg.inv(X.T @ X)
    beta = bi @ X.T @ y
    e = y - X @ beta
    n, k = X.shape
    S = X * e[:, None]
    hc1 = np.sqrt(np.diag(bi @ (S.T @ S) @ bi) * n / (n - k))
    cl = np.sqrt(np.diag(bi) * (e @ e) / (n - k))
    la, lo = np.radians(d.lat.values), np.radians(d.lon.values)
    hav = 2 * 6371 * np.arcsin(np.sqrt(np.sin((la[:, None] - la[None, :]) / 2) ** 2 + np.cos(la[:, None]) * np.cos(la[None, :]) * np.sin((lo[:, None] - lo[None, :]) / 2) ** 2))
    conley = np.sqrt(np.abs(np.diag(bi @ (S.T @ (hav <= 2).astype(float) @ S) @ bi)) * n / (n - k))
    return {g: dict(b=beta[i + 1], se=hc1[i + 1], se_classical=cl[i + 1], conley=conley[i + 1], n=n, n_class=int((d.cls == g).sum()), n_ref=int((d.cls == "A").sum())) for i, g in enumerate(lv)}


def test_holc_trajectories_by_grade_recomputed_from_tract_panel():
    """Catches a changed tract-grade assignment (40% rule, dominant grade) or weighting in trajectories_by_grade.csv."""
    pan, _ = holc_wide()
    T = csv("data/results/holc/trajectories_by_grade.csv")
    assert tract_grades().grade.value_counts().to_dict() == {"C": 41, "D": 19, "B": 6, "A": 4}
    for r in T.itertuples():
        d = pan[(pan.census == r.census) & (pan.grade == r.grade) & (pan["pop"] > 0)]
        assert len(d) == r.tracts and d.firms_haz.sum() == r.firms_haz
        ok = d.p_black.notna()
        if ok.any():
            assert abs(np.average(d.p_black[ok], weights=d["pop"][ok]) - r.p_black) < 1e-6


def test_holc_tract_change_models_recomputed():
    """Catches any change to the Xu-style change models: coefficients, HC1 and classical SEs, sample and class sizes (D-vs-A and the rest)."""
    M = csv("data/results/holc/holc_tract_models.csv")
    assert len(M) == 45 and set(M.grade) == {"B", "C", "D"} and (M.n_ref == 4).all()
    for (v, per), d in M.groupby(["outcome", "period"]):
        a, b = map(int, per.split("-"))
        assert a == (1970 if v in ("p_pov", "p_hisp") else 1940) or a == 1980
        r = _change_model(v, a, b)
        for row in d.itertuples():
            q = r[row.grade]
            assert (row.n, row.n_class, row.n_ref) == (q["n"], q["n_class"], q["n_ref"])
            assert abs(row.b - q["b"]) < 1e-6 * max(1, abs(row.b))
            assert abs(row.se - q["se"]) < 1e-6 * max(1, row.se)
            assert abs(row.se_classical - q["se_classical"]) < 1e-6 * max(1, row.se_classical)
            assert 0 <= row.p <= 1 and 0 <= row.p_classical <= 1


def test_holc_conley_se_reproduced_for_well_conditioned_models():
    """Catches a wrong cutoff unit (km vs m), swapped lat/lon or a different sample in the Conley (2 km, uniform kernel) standard errors."""
    M = csv("data/results/holc/holc_tract_models.csv")
    for v, a, b in [("p_owner", 1940, 1980), ("p_owner", 1980, 2010), ("p_owner", 1940, 2010), ("lmval", 1940, 1980), ("lmval", 1940, 2010)]:
        r = _change_model(v, a, b)
        for row in M[(M.outcome == v) & (M.period == f"{a}-{b}")].itertuples():
            assert abs(row.se_conley2km / r[row.grade]["conley"] - 1) < 0.03, (v, a, b, row.grade)


# ====================================================================== zoning 1929 / 1944 / 1955 (R/zoning_19*.R)

def test_gcp_fit_1929_is_a_near_conformal_affine_with_small_residuals():
    """Catches a bad control point or a mirrored/sheared georeference of the 1929 scan (every later zoning area depends on it)."""
    g, cx, cy = fit29()
    X = np.column_stack([np.ones(len(g)), g.px_x, g.px_y])
    res = np.hypot(X @ cx - g.X, X @ cy - g.Y)
    assert len(g) >= 12 and np.abs(res - g.residual_m).max() < 0.1 and np.sqrt((res ** 2).mean()) < 25 and res.max() < 60
    sx, sy = np.hypot(cx[1], cy[1]), np.hypot(cx[2], cy[2])
    assert abs(sx / sy - 1) < 0.01 and 1.2 < sx < 1.4 and cy[2] < 0 < cx[1]             # square pixels of ~1.29 m, north up
    assert abs(np.degrees(np.arctan2(cy[1], cx[1]))) < 1


def test_zone_cells_1929_1944_grid_and_coverage():
    """Catches duplicate or off-grid cells, cells of 1944 lying where the 1944 sheet has no coverage, and unknown district names."""
    c29, c44, off = cells()
    offk = set(zip(off.col, off.row))
    for c in (c29, c44):
        assert not c.duplicated(["col", "row"]).any()
        assert ((c.px_x0 == c.col * 32) & (c.px_y0 == c.row * 32) & (c.px_x1 - c.px_x0 == 32) & (c.px_y1 - c.px_y0 == 32)).all()
        assert c.px_x1.max() <= 11849 + 32 and c.px_y1.max() <= 12000
        assert set(c.zone) == {"Industrial A", "Industrial B", "Commercial"}
    assert not any(k in offk for k in zip(c44.col, c44.row))
    assert not off.duplicated().any()


def test_zoning_1929_geojson_and_1944_table_follow_from_cells():
    """Catches a zoning_1929.geojson / zoning_1929_vs_1944.csv that no longer equals the classified cells placed with the control-point fit."""
    c29, c44, off = cells()
    z = gpd.read_file(A / "zoning_1929.geojson").to_crs(UTM).set_index("zone")
    for zn in ("Industrial A", "Industrial B", "Commercial"):
        mine = dissolve(c29, f"^{zn}$")
        assert mine.symmetric_difference(shapely.make_valid(z.geometry[zn])).area < 50      # m2
        assert z.km2[zn] == round(mine.area / 1e6, 2)
    offk = set(zip(off.col, off.row))
    c29on = c29[[k not in offk for k in zip(c29.col, c29.row)]]
    T = csv("data/results/zoning_1944/zoning_1929_vs_1944.csv").set_index("zone")
    for zn in T.index:
        assert T.km2_1929[zn] == round(dissolve(c29on, f"^{zn}$").area / 1e6, 2)
        assert T.km2_1944[zn] == round(dissolve(c44, f"^{zn}$").area / 1e6, 2)
        assert abs(T.change_km2[zn] - (T.km2_1944[zn] - T.km2_1929[zn])) < 0.006


def test_zoning_shares_holc_and_grade_table_recomputed():
    """Catches wrong 1929 zoning shares per HOLC area (CRS, sheet-extent rule) and a holc_zoning_by_grade.csv out of step with them."""
    L, h = layers(), holc()
    p = csv("data/results/zoning_1929/zoning_shares_holc.csv")
    assert list(p.area_id) == list(h.area_id)
    a = h.area.values
    inside = h.intersection(L["sheet"]).area.values / a
    si = np.where(inside < 0.5, np.nan, (h.intersection(L["i29"]).area.values / a).round(3))
    sc = np.where(inside < 0.5, np.nan, (h.intersection(L["c29"]).area.values / a).round(3))
    assert (np.isnan(si) == p.share_industrial_1929.isna().values).all()
    assert np.nanmax(np.abs(si - p.share_industrial_1929.values)) < 0.0011 and np.nanmax(np.abs(sc - p.share_commercial_1929.values)) < 0.0011
    assert (p.share_industrial_1929_strict.fillna(0) <= p.share_industrial_1929.fillna(0) + 1e-9).all()
    G = csv("data/results/holc/holc_zoning_by_grade.csv").set_index("grade")
    for g, d in p[p.grade.isin(GR)].groupby("grade"):
        o = d[d.share_industrial_1929.notna()]
        assert (G.areas[g], G.areas_on_map[g]) == (len(d), len(o))
        assert G.km2_on_map[g] == round(o.area_km2.sum(), 1)
        assert G.pct_industrial_1929[g] == round(100 * (o.share_industrial_1929 * o.area_km2).sum() / o.area_km2.sum(), 1)
        assert G.pct_commercial_1929[g] == round(100 * (o.share_commercial_1929 * o.area_km2).sum() / o.area_km2.sum(), 1)
    assert sorted(csv("app/data/zoning_shares_holc.csv").area_id) == sorted(p.area_id)


def test_zoning_1955_polygons_follow_from_cells_and_control_points():
    """Catches a zoning_1955.geojson that no longer equals the classified cell runs placed with the 23-point polynomial fit."""
    g, c = csv("data/raw/zoning_1955/gcps_1955.csv"), csv("data/raw/zoning_1955/zone_cells_1955.csv")
    D = lambda x, y: np.column_stack([np.ones(len(x)), x, y, x * x, x * y, y * y])  # noqa: E731
    X = D(g.px_x.values.astype(float), g.px_y.values.astype(float))
    bx, by = np.linalg.lstsq(X, g.X, rcond=None)[0], np.linalg.lstsq(X, g.Y, rcond=None)[0]

    def rect(r):
        n = max(2, r.col1 - r.col0 + 2)
        xs = np.linspace(r.col0 * 16, (r.col1 + 1) * 16, n)
        top, bot = D(xs, np.full(n, r.row * 16.0)), D(xs[::-1], np.full(n, (r.row + 1) * 16.0))
        return Polygon(list(zip(top @ bx, top @ by)) + list(zip(bot @ bx, bot @ by)))

    z = gpd.read_file(A / "zoning_1955.geojson").to_crs(UTM).set_index("zone")
    k = csv("data/results/zoning_1955/zoning_1955_km2.csv").set_index("zone")
    for zn in ("I-1", "I-2"):
        mine = shapely.union_all([rect(r) for r in c[c.zone == zn].itertuples()])
        assert abs(mine.area / 1e6 - k.km2[zn]) < 0.08                                       # 0.5 m buffer + 3 m simplification
        assert mine.symmetric_difference(shapely.make_valid(z.geometry[zn])).area / 1e6 < 0.08
        assert z.km2[zn] == k.km2[zn]


# ====================================================================== zoning over time (R/zoning_over_time.R)

def test_common_land_area_matches_notes_and_tables():
    """Catches a change in the 'land mapped in 1929 and 1944' geography (203 km2) that the land, grade and site tables all share."""
    L = layers()
    km = L["common"].area / 1e6
    notes = (RES / "zoning_over_time" / "zoning_over_time_notes.txt").read_text()
    assert float(re.search(r"County: ([0-9.]+) km2", notes).group(1)) == round(km, 1)
    R1 = csv("data/results/zoning_over_time/zoning_land_by_year.csv")
    for y in ("1929", "1944", "1955"):
        assert abs(R1.km2[R1.year == y].sum() - km) < 0.02 and abs(R1.pct[R1.year == y].sum() - 100) < 0.11
    for y in ("2023", "today"):
        assert km - 1.0 < R1.km2[R1.year == y].sum() <= km + 0.02                           # zoned land cannot exceed the land
    assert np.allclose(R1.pct, (100 * R1.km2 / km).round(1), atol=0.051)


def test_zoning_land_by_year_industrial_recomputed():
    """Catches wrong industrial land shares by year (14.0 / 13.8 / 16.1 / 10.6 / 10.3 %) : polygons, clip geography, category mapping."""
    L = layers()
    R1 = csv("data/results/zoning_over_time/zoning_land_by_year.csv")
    ind = R1[R1["cat"] == "Industrial"].set_index("year").km2
    for y, geom, tol in (("1929", L["i29"], 0.011), ("1944", L["i44"], 0.011), ("1955", L["i55"], 0.02),
                         ("2023", cat_geom(L["2023"], ["Industrial"]), 0.15), ("today", cat_geom(L["today"], ["Industrial"]), 0.15)):
        assert abs(geom.intersection(L["common"]).area / 1e6 - ind[y]) < tol, y
    com = R1[R1["cat"] == "Commercial or mixed use"].set_index("year").km2
    assert abs(L["c29"].intersection(L["common"]).area / 1e6 - com["1929"]) < 0.011
    assert abs(L["c44"].intersection(L["common"]).area / 1e6 - com["1944"]) < 0.011


def test_zoning_by_holc_grade_years_recomputed():
    """Catches wrong industrial shares of each HOLC grade by year and a grade area (written to 2 decimals) that is not the grade's land on both sheets in Denver."""
    L, h = layers(), holc()
    R2 = csv("data/results/zoning_over_time/zoning_by_holc_grade_years.csv").set_index(["grade", "year"])
    tot = 0
    for g in GR:
        hg = shapely.union_all(h[h.grade == g].geometry.values).intersection(L["common"])
        assert (R2.grade_km2[g] == round(hg.area / 1e6, 3)).all() and len(R2.grade_km2[g]) == 5
        tot += hg.area / 1e6 if g != "D" else 0
        d_km2 = hg.area / 1e6
        for y, geom, tol in (("1929", L["i29"], 0.051), ("1944", L["i44"], 0.051), ("1955", L["i55"], 0.051),
                             ("2023", cat_geom(L["2023"], ["Industrial"]), 0.25), ("today", cat_geom(L["today"], ["Industrial"]), 0.25)):
            assert abs(100 * geom.intersection(hg).area / hg.area - R2.pct_industrial[(g, y)]) < tol, (g, y)
        assert (R2.pct_industrial_incl_imx[g] >= R2.pct_industrial[g]).all()
    assert round(d_km2, 1) == 25.3 and round(tot, 1) == 54.1                             # D (the last grade of the loop) and A+B+C, from the polygons


def test_abc_land_total_is_rounded_after_summing():
    """Catches a total built by adding rounded parts (off by one in the last printed digit)."""
    L, h = layers(), holc()
    tot = sum(shapely.union_all(h[h.grade == g].geometry.values).intersection(L["common"]).area / 1e6 for g in "ABC")
    R2 = csv("data/results/zoning_over_time/zoning_by_holc_grade_years.csv").query("year == '1929'").set_index("grade")
    assert round(R2.grade_km2[list("ABC")].sum(), 1) == round(tot, 1)


def test_zoning_1944_1955_change_adds_up():
    """Catches a kept/added/dropped table that does not reconcile with the 1944 and 1955 industrial land of zoning_land_by_year.csv."""
    L = layers()
    C = csv("data/results/zoning_over_time/zoning_1944_1955_change.csv").set_index("grade")
    a44, a55 = L["i44"].intersection(L["common"]), L["i55"].intersection(L["common"])
    assert abs(C.loc["all", "industrial in 1944 and 1955"] - a44.intersection(a55).area / 1e6) < 0.03
    assert abs(C.loc["all", "added by 1955"] - a55.difference(a44).area / 1e6) < 0.03
    assert abs(C.loc["all", "dropped by 1955"] - a44.difference(a55).area / 1e6) < 0.03
    ind = csv("data/results/zoning_over_time/zoning_land_by_year.csv").query("cat == 'Industrial'").set_index("year").km2
    assert abs(C.loc["all", "industrial in 1944 and 1955"] + C.loc["all", "dropped by 1955"] - ind["1944"]) < 0.02
    assert abs(C.loc["all", "industrial in 1944 and 1955"] + C.loc["all", "added by 1955"] - ind["1955"]) < 0.02
    assert (C.loc[GR].sum() <= C.loc["all"] + 0.02).all()


def test_zoning_1929_industrial_fate_adds_up():
    """Catches a fate table whose parts do not sum to the 1929 industrial land, or percentages on the wrong base."""
    F, L = csv("data/results/zoning_over_time/zoning_1929_industrial_fate.csv"), layers()
    tot = F.km2[F.part.str.startswith("1929 industrial")].iloc[0]
    assert abs(tot - L["i29"].intersection(den()).area / 1e6) < 0.02
    z = F[F.part == "zoned today"]
    assert tot - 0.3 < z.km2.sum() <= tot + 0.02 and abs(z.pct.sum() - 100) < 0.31
    assert np.allclose(z.pct, (100 * z.km2 / z.km2.sum()).round(1), atol=0.051)
    w = F[F.part.str.startswith("no longer industrial")]
    assert abs(w.km2.sum() - z.km2[z.group != "Industrial"].sum()) < 0.05 and abs(w.pct.sum() - 100) < 0.31
    still = cat_geom(L["today"], ["Industrial"]).intersection(L["i29"]).intersection(den()).area / 1e6
    assert abs(still - z.km2[z.group == "Industrial"].iloc[0]) < 0.15


def _denver(d):
    """Denver membership as zoning_over_time.R / zoning_2023.R now take it: the site's own tract GEOID."""
    return (d.GEOID.fillna("").str[:5] == "08031").values


@cached
def common_points():
    """Sites of the zoning-over-time tables: in a Denver tract by their own GEOID and on the land of both historical sheets."""
    L = layers()
    s, p = sites_addr(), hist_street()
    return s[_denver(s) & s.intersects(L["on_sheets"]).values], p[_denver(p) & p.intersects(L["on_sheets"]).values]


def test_zoning_sites_by_year_recomputed():
    """Catches wrong site counts on the two sheets in Denver (895 and 388) and wrong shares standing in an industrial district in each year."""
    L = layers()
    s, p = common_points()
    assert (len(s), len(p)) == (895, 388)
    R4 = csv("data/results/zoning_over_time/zoning_sites_by_year.csv").set_index(["series", "year"])
    for nm, q in (("Hazardous-sector manufacturers 1965-1992", s), ("Hazardous trades before 1960 (street level)", p)):
        assert (R4.sites[nm] == len(q)).all()
        for y, geom, tol in (("1929", L["i29"], 0.051), ("1944", L["i44"], 0.051), ("1955", L["i55"], 0.11),
                             ("2023", cat_geom(L["2023"], ["Industrial"]), 0.6), ("today", cat_geom(L["today"], ["Industrial"]), 0.6)):
            assert abs(100 * q.intersects(geom).mean() - R4.pct_industrial[(nm, y)]) < tol, (nm, y)
        for y in ("2023", "today"):
            ha = cat_geom(L[y], ["Industrial mixed use", "Commercial or mixed use", "Residential"])
            assert abs(100 * q.intersects(ha).mean() - R4.pct_housing_allowed[(nm, y)]) < 0.8, (nm, y)
            assert R4.pct_industrial_incl_imx[(nm, y)] >= R4.pct_industrial[(nm, y)]
            assert R4.pct_industrial[(nm, y)] + R4.pct_housing_allowed[(nm, y)] <= 100.05


def test_sites_off_the_common_land_are_accounted_for():
    """Catches unexplained loss of sites between Denver (972 sites by GEOID / 390 street-level trades of the town) and the zoning tables (895 / 388)."""
    L = layers()
    s, p = sites_addr(), hist_street()
    sd, pd_ = s[_denver(s)], p[p.town == "DENVER"]
    assert (len(sd), len(pd_)) == (972, 390)
    cs, cp = common_points()
    # 1965-92: every Denver site is either on both sheets (counted) or off them; none is lost at a tract boundary any more
    off_s = ~sd.intersects(L["on_sheets"])
    assert off_s.sum() == 77 and len(cs) == len(sd) - off_s.sum() == 895
    assert (off_s & sd.intersects(den())).sum() == 76                                    # 76 of the 77 lie inside the simplified county outline
    assert (sd[~sd.intersects(den())].distance(den()) < 20).all()                        # sites of Denver tracts outside the simplified outline: slivers only
    # pre-1960: all 390 lie on both sheets; the 2 not counted have an Adams County GEOID (the 3 that had none get one from the full-resolution tracts since 13 Nov)
    assert (~pd_.intersects(L["on_sheets"])).sum() == 0 and set(cp.hfirm) <= set(pd_.hfirm)
    lost = pd_[~pd_.hfirm.isin(cp.hfirm)]
    assert len(cp) == 388 and len(lost) == 2 and lost.GEOID.isna().sum() == 0 and (lost.GEOID.dropna().str[:5] == "08001").all()


def test_no_denver_site_on_both_sheets_is_lost_at_a_tract_boundary():
    """Catches sites dropped from the zoning tables only because the clip polygon has gaps or a generalised county boundary."""
    L = layers()
    R4 = csv("data/results/zoning_over_time/zoning_sites_by_year.csv").set_index(["series", "year"]).sites
    for nm, d, n in (("Hazardous-sector manufacturers 1965-1992", sites_addr(), 3), ("Hazardous trades before 1960 (street level)", hist_street(), 1)):
        d = d[_denver(d)]
        assert (R4[nm] == d.intersects(L["on_sheets"]).sum()).all()
        assert (d.intersects(L["on_sheets"]) & ~d.intersects(L["common"])).sum() == n   # the sliver sites, now counted (3 sites, 1 trade)


def test_every_street_level_trade_inside_a_tract_has_a_geoid():
    """Catches located sites without a tract id (they silently leave every table that selects by GEOID)."""
    p = hist_street()
    t = tracts()
    inside = gpd.sjoin(p[p.GEOID.isna()], t[["geometry"]], how="inner", predicate="intersects")
    assert inside.hfirm.nunique() == 0


@pytest.mark.xfail(strict=True, reason="FINDING 3: app/data/co_tracts_2010.geojson is used as an analysis geometry but its simplified tracts neither tile Denver County (91 interior slivers, 0.72 km2) nor avoid overlap (0.36 km2)")
def test_denver_tract_polygons_tile_the_county():
    """Catches a tract layer with gaps or overlaps being used for point-in-polygon tests and area shares."""
    t = tracts()
    d = t[t.GEOID.str[:5] == "08031"]
    u = den()
    holes = [Polygon(r) for g in getattr(u, "geoms", [u]) for r in g.interiors]
    assert sum(1 for h in holes if h.area < 3e5) == 0
    assert d.area.sum() - u.area < 1e4


# ====================================================================== zoning 2023 (R/zoning_2023.R)

def test_sites_zoning_2023_rows_are_the_selected_sites_once_each():
    """Catches duplicated or foreign rows in sites_zoning_2023.csv and a 'where' label that disagrees with the site's county."""
    z = csv("data/results/zoning_2023/sites_zoning_2023.csv")
    s = sites_addr().set_index("site_id")
    assert z.site_id.is_unique and z.site_id.isin(s.index).all() and len(z) == 1390
    t = tracts()
    core = t[(t.core.astype(str).str.lower() == "true") | (t.GEOID.str[:5] == "08031")]
    sa = sites_addr()
    member = sa.GEOID.isin(set(core.GEOID)).values | sa.intersects(shapely.union_all(core.geometry.values)).values   # own tract, or inside the outline
    assert set(z.site_id) == set(sa.site_id[member])                                                               # none left unmatched
    assert (z["where"] == "Denver County").sum() == 972
    den_geoid = s.GEOID.reindex(z.site_id).str[:5].values == "08031"
    assert ((z["where"] == "Denver County").values == den_geoid).all()
    last = site_years()[site_years().year.isin(ED_OK)].groupby("site_id").year.max()
    assert (z.last_listed.values == last.reindex(z.site_id).values).all()
    assert set(z.match) == {"inside polygon", "nearest polygon within 50 m"}
    assert not ((z.Local_zon.fillna("").str.match(r"^(I-MX|M-IMX)")) & (z.zone2023 != "Industrial mixed use (housing allowed)")).any()
    assert not ((z.GenZone2 == "Industrial") & ~z.Local_zon.fillna("").str.match(r"^(I-MX|M-IMX)") & (z.zone2023 != "Industrial (housing not allowed)")).any()


def test_sites_by_zoning_2023_tables_recomputed_from_site_rows():
    """Catches percentage tables (by place, by decade last listed) that do not follow from sites_zoning_2023.csv."""
    z = csv("data/results/zoning_2023/sites_zoning_2023.csv")
    T = csv("data/results/zoning_2023/sites_by_zoning_2023.csv")
    cats = [c for c in T.columns if c not in ("series", "where", "n")]
    t = T[T.series == "Hazardous-sector manufacturers 1965-1992"].set_index("where")
    for w, d in (("Denver County", z[z["where"] == "Denver County"]), ("Suburban study tracts", z[z["where"] != "Denver County"]), ("Study area", z)):
        assert t.n[w] == len(d)
        for c in cats:
            assert abs(t.loc[w, c] - 100 * (d.zone2023 == c).mean()) < 0.051, (w, c)
    assert (abs(T[cats].sum(axis=1) - 100) < 0.31).all()
    B = csv("data/results/zoning_2023/sites_by_zoning_2023_last_listed.csv").set_index("last_decade")
    dec = np.where(z.last_listed <= 1970, "1965-1970", np.where(z.last_listed <= 1980, "1971-1980", "1981-1992"))
    assert B.n.sum() == len(z)
    for k in B.index:
        assert B.n[k] == (dec == k).sum()
        for c in cats:
            assert abs(B.loc[k, c] - 100 * (z.zone2023[dec == k] == c).mean()) < 0.051
    h = T[T.series.str.startswith("Hazardous trades")].set_index("where")
    assert h.n["Denver County"] <= len(hist_street()) and h.n["Study area"] >= h.n["Denver County"]


def test_zoning_2023_area_tables_add_up():
    """Catches land tables whose rows do not sum (study area by category, 1929 districts in 2023, tract shares)."""
    R1 = csv("data/results/zoning_2023/zoning_2023_study_area.csv")
    body, tot = R1.iloc[:-1], R1.iloc[-1]
    assert abs(body.km2.sum() - tot.km2) < 0.3 and abs(body.pct.sum() - 100) < 0.31 and 95 < tot.pct <= 100
    R2 = csv("data/results/zoning_2023/zoning_1929_to_2023.csv")
    assert (abs(R2.drop(columns=["zone1929", "km2_1929"]).sum(axis=1) - 100) < 0.31).all()
    z = gpd.read_file(A / "zoning_1929.geojson").set_index("zone")
    assert ((R2.set_index("zone1929").km2_1929 <= z.km2 + 0.005) & (R2.set_index("zone1929").km2_1929 > 0.97 * z.km2)).all()
    TZ = csv("data/results/zoning_2023/tract_zoning_2023.csv", dtype={"GEOID": str})
    assert TZ.GEOID.is_unique and len(TZ) == 147 and (abs(TZ.drop(columns="GEOID").sum(axis=1) - 100) < 0.4).all()
    C = csv("data/results/zoning_2023/tract_composition_by_zoning_2023.csv")
    assert C.tracts.sum() == 147


# ====================================================================== rezoning (R/rezoning_denver.R)

@cached
def changes():
    return csv("data/results/rezoning/changes.csv", dtype={"GEOID": str, "ordinance": str})


def test_rezoning_changes_keys_years_and_coordinates():
    """Catches duplicated changes (many-to-many merge on ordinance + description), years outside 1925-1956 and points outside Denver."""
    c = changes()
    assert not c.duplicated(["ordinance", "description"]).any()
    assert (c.year == c.ordinance.str[:4].astype(int)).all() and c.year.between(1925, 1956).all()
    assert ((c.placed_by == "not placed") == c.lon.isna()).all() and (c.lon.isna() == c.holc.isna()).all()
    p = c[c.lon.notna()]
    assert p.lon.between(-105.12, -104.72).all() and p.lat.between(39.61, 39.92).all()
    assert (c.census_used.dropna() == np.where(c.year[c.census_used.notna()] < 1946, 1940, 1950)).all()


def test_rezoning_context_recomputed_from_coordinates():
    """Catches a wrong HOLC grade, 1929 district or nearby-trade count attached to a rezoning (CRS, join, year filter)."""
    c = changes()
    p = c[c.lon.notna()]
    g = pts(p)
    h = holc()
    j = gpd.sjoin(g, h[h.grade.isin(GR)][["grade", "geometry"]], how="left", predicate="within")
    assert (j[~j.index.duplicated()].grade.fillna("Not graded") == p.holc).all()
    z = gpd.read_file(A / "zoning_1929.geojson").to_crs(UTM)
    jz = gpd.sjoin(g, z[["zone", "geometry"]], how="left", predicate="within")
    assert (jz[~jz.index.duplicated()].zone.fillna("Residence or business (not mapped)") == p.zone_1929).all()
    hd = hist_denver()
    n = [int(((hd.distance(pt) <= 400) & (hd.first_year <= y)).sum()) for pt, y in zip(g.geometry, g.year)]
    assert (np.array(n) == p.haz_trades_400m.values).all()
    tp = csv("app/data/tract_panel.csv", dtype={"GEOID": str})
    tp = tp[tp.census.isin([1940, 1950])][["GEOID", "census", "p_black"]]
    m = c.assign(cu=np.where(c.year < 1946, 1940, 1950)).merge(tp, left_on=["GEOID", "cu"], right_on=["GEOID", "census"], how="left", suffixes=("", "_panel"))
    assert np.allclose(m.p_black, m.p_black_panel, equal_nan=True)


def test_rezoning_by_race_sure_and_placed_tables_recomputed():
    """Catches by_race.csv, by_holc_sure.csv and placed.csv drifting from changes.csv (the existing tests cover by_dir, by_holc, test)."""
    c = changes()
    rtb = c.direction.isin(["Residential to business", "Residential to industrial"])
    r = c[c.p_black.notna() & ~c.annexation]
    band = np.where(r.p_black < 1, "Under 1% Black", np.where(r.p_black < 10, "1-10% Black", "10%+ Black"))
    for row in csv("data/results/rezoning/by_race.csv").itertuples():
        d = r[band == row.black_band]
        assert row.changes == len(d)
        assert abs(row.pct_res_to_business_or_industrial - 100 * rtb[d.index].mean()) < 0.051
        assert abs(row.pct_to_residential - 100 * (d.to_group == "Residential").mean()) < 0.051
        assert abs(row.mean_haz_trades_400m - d.haz_trades_400m.mean()) < 0.051
    s = c[~c.annexation & c.holc.notna() & (c.placed_by.str.startswith("subdivision and block") | ((c.placed_by == "street crossings") & c.m_between_methods.notna()))]
    for row in csv("data/results/rezoning/by_holc_sure.csv").itertuples():
        d = s[s.holc == row.holc]
        assert row.changes == len(d) and abs(row.pct_res_to_business_or_industrial - 100 * rtb[d.index].mean()) < 0.051
    P = csv("data/results/rezoning/placed.csv").set_index("placed_by")
    for k, d in c.groupby("placed_by"):
        assert P.changes[k] == len(d) and P.checked_both_ways[k] == d.m_between_methods.notna().sum()
        assert abs(P.pct[k] - 100 * len(d) / len(c)) < 0.051
    assert (c.m_between_methods[c.placed_by.str.startswith("uncertain")] > 1000).all()
    assert (c.m_between_methods[c.placed_by == "subdivision and block (streets agree)"] <= 1000).all()


def test_every_placed_rezoning_has_a_tract():
    """Catches placed rezonings left without a census tract although they lie inside Denver, and a tract that is not the containing / nearest (<= 60 m) one."""
    c = changes()
    assert (c.lon.notna() & c.GEOID.isna()).sum() == 0
    p = c[c.lon.notna()]
    g, t = pts(p), tracts_raw().set_index("GEOID").geometry
    own = g.distance(gpd.GeoSeries(t.reindex(p.GEOID).values, index=g.index, crs=UTM))
    j = gpd.sjoin(g, tracts_raw()[["GEOID", "geometry"]], how="left", predicate="within")
    inside = j.GEOID_right.groupby(level=0).first().reindex(p.index).notna()
    hit = (j.GEOID_right == p.GEOID.reindex(j.index)).groupby(level=0).any().reindex(p.index)
    # inside a tract (two where the outlines overlap): that tract; changes.csv writes lon/lat to 5 decimals (about 1 m), so a point on a
    # boundary may be written just across it (2 changes, 0.1 and 0.4 m)
    assert (hit | (own.values < 1.0))[inside].all() and (inside & ~hit).sum() <= 2
    near = np.array([t.distance(pt).min() for pt in g.geometry[~inside]])
    assert (~inside).sum() == 6 and (own[~inside].values <= near + 1.4).all() and (own[~inside] <= 60).all()   # in a sliver: the nearest tract within 60 m (5-decimal coordinates move a point up to 0.7 m)


# ====================================================================== Sanborn 1903 (R/loc_sanborn_1903.R)

def test_sanborn_tables_recomputed_from_blocks():
    """Catches zone, zone-by-exposure, polygon-quality, area and persistence tables that do not follow from blocks.csv."""
    b = csv("data/results/sanborn_1903/blocks.csv")
    O = RES / "sanborn_1903"
    assert b.x.between(4.9e5, 5.1e5).all() and b.y.between(4.385e6, 4.41e6).all() and (b.dwellings >= 0).all()
    assert (b.n_heavy <= b.n_hazardous).all() and (b.n_hazardous <= b.n_industrial).all()
    assert (b.mixed_haz == ((b.dwellings > 0) & (b.n_hazardous > 0))).all() and (b.near_haz_150 == (b.d_haz_m <= 150)).all()
    Z = pd.read_csv(O / "zone.csv").set_index("zone_1929")
    for k, d in b.groupby("zone_1929"):
        assert (Z.blocks[k], Z.dwellings[k], Z.blocks_with_hazardous_trade[k], Z.blocks_with_heavy_trade[k], Z.blocks_mixed_with_hazardous_trade[k]) == \
               (len(d), d.dwellings.sum(), (d.n_hazardous > 0).sum(), (d.n_heavy > 0).sum(), d.mixed_haz.sum())
        assert Z.dwellings_on_heavy_blocks[k] == d.dwellings[d.n_heavy > 0].sum()
    assert Z.blocks.sum() == len(b) and abs(Z.pct_of_dwellings.sum() - 100) < 0.21
    ZE = pd.read_csv(O / "zexp.csv")
    q = b[b.dwellings > 0].groupby(["exposure", "zone_1929"]).dwellings.sum()
    assert len(ZE) == len(q) and all(q[(r.exposure, r.zone_1929)] == r.dwellings for r in ZE.itertuples())
    PQ = pd.read_csv(O / "polyq.csv").set_index("poly_from")
    assert PQ.blocks.to_dict() == b.groupby("poly_from").size().to_dict() and PQ.dwellings.sum() == b.dwellings.sum()
    EA = pd.read_csv(O / "expo_area.csv").set_index("area")
    for k, d in list(b.groupby("area")) + [("All placed sheets", b)]:
        d = d[d.dwellings > 0]
        tot = d.dwellings.sum()
        assert EA.dwellings[k] == tot
        assert abs(EA.pct_same_block_haz[k] - 100 * d.dwellings[d.mixed_haz].sum() / tot) < 0.051
        assert abs(EA.pct_within_150_haz[k] - 100 * d.dwellings[d.mixed_haz | d.near_haz_150].sum() / tot) < 0.051
        assert abs(EA.pct_across_street_haz[k] - 100 * d.dwellings[~d.mixed_haz & d.across_haz].sum() / tot) < 0.051
    PS = pd.read_csv(O / "persist.csv").iloc[0]
    hz = b[b.n_hazardous > 0]
    assert PS.n == len(hz) and abs(PS.pct_with_hidden_site_150m - 100 * hz.later_hidden_150.mean()) < 0.051
    assert abs(PS.pct_with_1965_92_site_150m - 100 * (hz.later_hidden_150 | hz.later_known_150).mean()) < 0.051


def test_sanborn_cover_follows_from_sheets():
    """Catches a coverage table (sheets read/placed, dwellings covered) out of step with sheets.csv and blocks.csv."""
    s, cv = csv("data/results/sanborn_1903/sheets.csv"), csv("data/results/sanborn_1903/cover.csv").set_index("volume")
    assert not s.duplicated(["volume", "sheet"]).any()
    for v, d in s.groupby("volume"):
        assert (cv.sheets_read[v], cv.sheets_placed[v], cv.dwellings_read[v], cv.dwellings_on_placed_sheets[v]) == \
               (len(d), d.placed.sum(), d.dwellings.sum(), d.dwellings[d.placed].sum())
    assert cv.dwellings_on_placed_sheets.sum() == csv("data/results/sanborn_1903/blocks.csv").dwellings.sum()


def test_sanborn_archival_check_file_is_complete():
    """Catches an archival-check CSV (read by R/sanborn_check.R) with missing verdicts, crop URLs or firms no longer in the inventory file."""
    s = csv("data/results/site_fate/archival_check_sanborn_1887_1904.csv", dtype=str, keep_default_na=False)
    h = csv("app/data/historical_sites.csv", dtype=str, keep_default_na=False)
    hd = h[(h.town == "DENVER") & (h.precision != "town")]
    key = lambda x: re.sub(r"[^A-Z0-9]", "", re.sub(r"\b(ST|STREET|AVE|AV|AVENUE|BLVD|RD|DR|PL|CT)\b\.?", "", str(x).upper()))  # noqa: E731
    keyed, blank = s[s.hfirm != ""], s[s.hfirm == ""]
    assert len(s) == 20 and keyed.hfirm.is_unique and (len(keyed), len(blank)) == (11, 9)
    # re-keyed by address (pipeline/rekey_sanborn_observations.py): an id must be a current firm-location at the recorded street
    # (or, where a review corrected the house number, the same firm on the same street within 50 numbers: "1622 Blake" -> "1616 Blake")
    from rapidfuzz import fuzz
    ns = lambda a: (lambda m: (int(m.group(1)), key(m.group(2))) if m else (None, None))(re.match(r"\s*(\d+)\s+(.*)", str(a).upper()))  # noqa: E731
    m = keyed.merge(hd[["hfirm", "street", "name"]], on="hfirm", how="left", suffixes=("", "_layer"))
    assert m.street_layer.notna().all()
    same = m.street.map(key) == m.street_layer.map(key)
    near = [(lambda a, b: a[1] == b[1] and a[0] is not None and b[0] is not None and abs(a[0] - b[0]) < 50)(ns(x), ns(y)) for x, y in zip(m.street, m.street_layer)]
    assert (same | pd.Series(near, index=m.index)).all()
    assert all(fuzz.token_sort_ratio(a.upper(), b.upper()) >= 60 for a, b in zip(m.name, m.name_layer)), "an id names a different firm"
    # a blank id only where no current Denver street-level firm-location of a similar name sits at that street
    for _, r in blank.iterrows():
        at = hd[hd.street.map(key) == key(r.street)]
        assert not any(fuzz.token_sort_ratio(str(r["name"]).upper(), n.upper()) >= 60 for n in at.name), r.street
    assert s.matches_geocode.isin(["yes", "partial", "no", "inconclusive"]).all()
    assert s.sheet_crop_url.str.startswith("https://").all() and s.use_shown_on_sheet.notna().all()


# ====================================================================== land use 1937-1997 (R/landuse_1937_1997.R)

GRP = ["Industrial", "Waste and extraction", "Transportation", "Commercial", "Residential, single family", "Residential, multifamily", "Institutional", "Open land"]


def _group_of(x):
    x = x.lower()
    for pat, g in ((r"industr|refiner", 0), (r"landfill|quarr|strip ?mine|gravel", 1), (r"transport|airport|ariport|railroad", 2),
                   (r"retail|office|mixed urban|commercial", 3), (r"single family", 4), (r"multi.?family|mobile", 5),
                   (r"institution|school|cemetery|communication|utilit", 6)):
        if re.search(pat, x):
            return GRP[g]
    return GRP[7]


def test_landuse_class_crosswalk_is_the_documented_one():
    """Catches a USGS class moved to another group (e.g. an industrial or residential class falling through to 'Open land')."""
    c = csv("data/results/landuse/landuse_class_groups.csv")
    assert set(c.year) == {1937, 1957, 1977, 1997} and set(c.group) <= set(GRP) and not c.duplicated(["year", "Class_Name"]).any()
    assert (c.group == c.Class_Name.map(_group_of)).all()
    assert (c.groupby("Class_Name").group.nunique() == 1).all()                              # a class never changes group between years
    open_land = set(c.Class_Name[c.group == "Open land"].str.lower())
    open_land -= {"non-residential developed"}                                                 # 0.0 km2 in the whole 1977 raster (VAT)
    assert not any(re.search(r"resid|factory|mill|plant$|warehouse|junk|rail|industr|commerc|retail", k) for k in open_land), sorted(open_land)
    for y, d in c.groupby("year"):
        assert set(d.group) == set(GRP), y


def test_landuse_tables_add_up():
    """Catches land-use shares on the wrong base: group shares not summing to 100, covered land changing between years, site counts not adding."""
    L = csv("data/results/landuse/landuse_by_year.csv")
    t = L.groupby(["unit", "year"]).agg(km2=("km2", "sum"), pct=("pct", "sum"))
    assert (abs(t.pct - 100) < 0.31).all()
    for u, d in t.groupby(level=0):
        assert d.km2.max() - d.km2.min() < 0.2, u                                            # the same mapped land every year
    assert t.km2["Study area"].max() <= 527.5 and t.km2["Denver County, land on the 1929 zoning map"].max() <= layers()["sheet"].intersection(den()).area / 1e6 + 0.05
    assert np.allclose(L.pct, (100 * L.km2 / L.groupby(["unit", "year"]).km2.transform("sum")).round(1), atol=0.11)
    V = csv("data/results/landuse/landuse_vs_zoning.csv")
    assert (abs(V.groupby("year").share_of_all_industrial_use.sum() - 100) < 0.21).all()
    den_ind = L[(L.unit != "Study area") & (L.group == "Industrial")].set_index("year").km2
    assert (abs(V.groupby("year").industrial_use_km2.sum() - den_ind) < 0.35).all()          # zones are clipped to the sheet, not the county
    zi = V[V.zoning == "1929 industrial district"]
    assert np.allclose(zi.pct_of_zone_in_industrial_use, 100 * zi.industrial_use_km2 / 28.6, atol=0.6)
    H = csv("data/results/landuse/landuse_by_holc_grade.csv")
    assert (abs(H.groupby(["grade", "year"]).pct.sum() - 100) < 0.41).all()
    S = csv("data/results/landuse/landuse_sites.csv")
    m = S[S.series.str.startswith("Hazardous-sector")].pivot(index="year", columns="status", values="sites")
    t_ = tracts()
    study = shapely.union_all(t_[(t_.core.astype(str).str.lower() == "true") | (t_.GEOID.str[:5] == "08031")].geometry.values)
    n_study = int(sites_addr().intersects(study).sum())                                   # landuse_1937_1997.R selects by the study-area outline
    assert n_study == 1386
    assert (m["all"] == m["on a current inventory"] + m["on no current inventory"]).all() and (m["all"] <= n_study).all() and (m["all"] >= n_study - 1).all()
    w = S[S.series.str.startswith("Hazardous-sector")].pivot(index="year", columns="status", values="pct_on_industrial_land")
    mix = (w["on a current inventory"] * m["on a current inventory"] + w["on no current inventory"] * m["on no current inventory"]) / m["all"]
    assert (abs(mix - w["all"]) < 0.11).all()
    X = csv("data/results/landuse/landuse_site_transitions.csv")
    assert (abs(X.groupby("land_use_1977").pct_of_1977_group.sum() - 100) < 0.31).all() and X.N.sum() <= n_study
    T = csv("data/results/landuse/landuse_tracts.csv", dtype={"GEOID": str})
    assert not T.duplicated(["GEOID", "year"]).any() and T.GEOID.nunique() == 147
    assert T.covered_share.between(0, 1.0005).all() and T.industrial_use_share.dropna().between(0, 1).all()


def test_landuse_20m_rasters_hold_only_the_eight_groups():
    """Catches a map raster written with raw USGS class codes, a wrong data type or a different grid from year to year."""
    tifffile = pytest.importorskip("tifffile")
    shapes = set()
    for y in (1937, 1957, 1977, 1997):
        try:
            a = tifffile.imread(RES / "landuse" / f"landuse_{y}_20m.tif")
        except Exception as e:  # compressed with a codec this environment lacks
            pytest.skip(f"cannot decode the GeoTIFF here: {e}")
        shapes.add(a.shape)
        v = set(np.unique(a).tolist())
        assert v - {0, 255} <= set(range(1, 9)) and {1, 5, 8} <= v, (y, sorted(v))
        ind_km2 = (a == 1).sum() * 400 / 1e6
        assert 5 < ind_km2 < 120, (y, ind_km2)
    assert len(shapes) == 1


# ====================================================================== highways (R/highways_denver.R)

def test_highway_alignment_years_are_plausible():
    """Catches unparsed or impossible opening / removal years in the alignments (e.g. a freeway dated before 1940, end before start)."""
    h = gpd.read_file(A / "highways_denver.geojson")
    assert set(h.kind) == {"Freeway", "Major road"} and h.geometry.geom_type.isin(["LineString", "MultiLineString"]).all()
    fw = h[(h.kind == "Freeway") & ~h.highway.str.contains("_link")]
    assert fw.start_year.notna().all() and fw.start_year.between(1945, 2026).all()
    e = h[h.end_year.notna()]
    assert (e.end_year >= e.start_year.fillna(0)).all() and e.end_year.between(1900, 2026).all()
    b = h.total_bounds
    assert -105.4 < b[0] and b[2] < -104.5 and 39.4 < b[1] and b[3] < 40.1


def test_highway_tables_add_up():
    """Catches decade totals, zoning shares and tract panels that do not reconcile (opened - removed = in service; shares sum to 100)."""
    K = csv("data/results/highways/highways_km_by_decade.csv")
    assert abs(K.km_opened.sum() - K.km_removed.sum() - K.km_open_at_decade_end.iloc[-1]) < 0.35
    assert (K.decade.diff().dropna() == 10).all() and (K.km_removed <= K.km_open_at_decade_end.shift(1).fillna(0) + K.km_opened + 0.05).all()
    Z = csv("data/results/highways/highways_by_zoning_1929.csv")
    assert abs(Z.pct.sum() - 100) < 0.21 and np.allclose(Z.pct, (100 * Z.km / Z.km.sum()).round(1), atol=0.11)
    L = layers()
    sh = Z.set_index("cls").share_of_land
    assert abs(sh["1929 industrial district"] - 100 * L["i29"].area / L["sheet"].area) < 0.051
    assert abs(sh["1929 commercial district"] - 100 * L["c29"].area / L["sheet"].area) < 0.051
    G = csv("data/results/highways/highways_by_holc_grade.csv").set_index("grade")
    km = holc().groupby("grade").km2.sum()
    assert (G.area_km2 == km.round(1).reindex(G.index)).all() and G.pct_within_250m.between(0, 100).all()
    T = csv("data/results/highways/highways_tracts.csv")
    assert (T.groupby("census").tracts.sum() == T.groupby("census").tracts.sum().iloc[0]).all() and T.groupby("crossed").tracts.nunique().max() == 1
    assert np.allclose(T.pop_index_1950_100, (100 * T.residents / T.groupby("crossed").residents.transform("first")).round(), atol=0.51)
    E = csv("data/results/highways/highways_tract_groups.csv", dtype={"GEOID": str})
    assert E.GEOID.is_unique and len(E) == 147 and set(E.group) == {"treated", "comparison", "other"}
    assert E.open_year[E.group == "treated"].between(1950, 1979).all()
    assert not ((E.group == "comparison") & E.open_year.between(1950, 1979)).any()
    N = csv("data/results/highways/highways_nber_check.csv").set_index("route")
    both = N.dropna(subset=["nber_first_opened", "ohm_first"])
    assert (both.ohm_km_in_service <= both.ohm_km).all() and (abs(both.ohm_km_in_service - 1.609 * both.nber_miles) < 6).all()


# ====================================================================== corridors (R/corridors.R)

@cached
def listings():
    L = csv("data/results/CO_directory_listings_1961-2002.csv", dtype={"sic": str, "zip": str})
    L = L[L.geo_level.isin(["address", "address_approx"]) & L.lat.notna()].copy()
    xy = pts(L).geometry
    L["x"], L["y"] = xy.x.values, xy.y.values
    L["cell"] = np.floor(L.x / 500).astype(int).astype(str) + " " + np.floor(L.y / 500).astype(int).astype(str)
    L["haz"] = L.fe_hazard.astype(str).isin(["True", "TRUE"])
    return L


def test_corridor_cells_recomputed_from_listings():
    """Catches a wrong grid (CRS, cell size), edition list or persistence class in cells_500m.csv."""
    L, C = listings(), csv("data/results/corridors/cells_500m.csv")
    eds = np.array(sorted(L.year.unique()))
    assert list(eds) == ED_OK and C.cell.is_unique
    cy = L.drop_duplicates(["cell", "year", "estab_id"])
    per = cy.groupby(["cell", "year"]).agg(n=("estab_id", "nunique"), nh=("haz", "sum")).reset_index()
    g = per.groupby("cell").agg(first=("year", "min"), last=("year", "max"), editions=("year", "nunique"), max_n=("n", "max"), ever=("nh", lambda s: (s > 0).any()))
    m = C.set_index("cell").join(g, rsuffix="_r", how="outer")
    assert len(m) == len(C) == len(g)
    assert (m["first"] == m.first_r).all() and (m["last"] == m.last_r).all() and (m.editions == m.editions_r).all() and (m.max_n == m.max_n_r).all()
    assert (m.ever_haz.astype(bool) == m.ever.astype(bool)).all()
    span = np.array([((eds >= f) & (eds <= l)).sum() for f, l in zip(m["first"], m["last"])])
    assert np.allclose(m.coverage, m.editions / span) and m.coverage.between(0, 1).all()
    base = np.where((m["first"] <= 1968) & (m["last"] >= 1990) & (m.coverage >= 0.6), "persistent",
                    np.where(m["first"] >= 1980, "emerging", np.where(m["last"] <= 1980, "former (gone by 1980s)", "intermittent")))
    assert (m["class"].str.replace(", sector turnover", "") == base).all()
    assert (m.n_sectors[m["class"] == "persistent, sector turnover"] >= 3).all()
    cx, cyy = m.index.str.split(" ").str[0].astype(int) * 500 + 250, m.index.str.split(" ").str[1].astype(int) * 500 + 250
    far = np.hypot(cx - 500250, cyy - 4399500) > 25000 + 360
    assert not m.metro.astype(bool)[far].any()
    md = (RES / "corridors" / "corridors_summary.md").read_text()
    assert f"cells with any manufacturer: {len(C)} ({int(C.metro.sum())} metro)" in md
    assert format(L.estab_id.nunique(), ",") + " statewide" in md


def test_corridor_model_tables_are_well_formed():
    """Catches empty or degenerate model tables (missing terms, non-positive SEs, Ellison-Glaeser p-values outside (0, 1])."""
    E = csv("data/results/corridors/entry_models.csv")
    assert len(E) == 5 and (E.se > 0).all()
    G = csv("data/results/corridors/ellison_glaeser_by_sector_edition.csv")
    assert G.p.between(1 / 500, 1).all() and (G.n >= 10).all() and (G.n <= G.n_all).all() and set(G.year) <= set(ED_OK)
    M = csv("data/results/corridors/legacy_tract_models.csv")
    assert len(M) == 12 and (M.se > 0).all() and M.lambda_.between(-1, 1).all() if "lambda_" in M else M["lambda"].between(-1, 1).all()
    assert (csv("app/data/legacy_tract_models.csv").round(9) == M.round(9)).all().all()


def test_corridors_tract_area_is_aligned_with_the_merged_table():
    """Catches a positional assignment of tract areas to a table that merge() has re-sorted (density control attached to the wrong tract)."""
    src = (ROOT / "R" / "corridors.R").read_text()
    area = re.search(r"^TT\[, area_km2 := as\.numeric\(st_area\(tr\)\) / 1e6\]", src, re.M)
    make, merge = re.search(r"^TT <- as\.data\.table\(st_drop_geometry\(tr\)\)", src, re.M), re.search(r"^TT <- merge\(", src, re.M)
    assert area and make and merge and make.start() < area.start() < merge.start()      # areas attached while TT is still in the tract file's order
    assert len(re.findall(r"area_km2 :=", src)) == 1 and not re.search(r"TT <- TT\[order|setorder\(TT|setkey\(TT", src[make.start():area.start()])


# ====================================================================== context layers (R/context_layers.R)

def test_tri_tables_recomputed_from_facility_years():
    """Catches TRI totals by year and by HOLC grade that do not follow from tri_facility_years_study.csv, and a wrong grade join."""
    fy = csv("app/data/tri_facility_years_study.csv")
    assert not fy.duplicated(["trifd", "year"]).any() and fy.year.between(1987, 2026).all() and (fy[["air_lb", "onsite_lb", "total_lb"]] >= 0).all().all()
    assert fy.lat.between(39.55, 39.95).all() and fy.lon.between(-105.2, -104.7).all()
    assert (fy.groupby("trifd")[["lat", "lon"]].nunique() == 1).all().all()
    ty = csv("data/results/context/tri_by_year.csv")
    r = fy.groupby("year").agg(f=("trifd", "nunique"), air=("air_lb", "sum"), on=("onsite_lb", "sum"), ca=("carcinogen_air_lb", "sum")).reset_index().merge(ty, on="year", how="outer")
    assert len(r) == len(ty) and (r.f == r.facilities).all()
    assert (abs(r.air - r.air_lb) <= 0.51).all() and (abs(r.on - r.onsite_lb) <= 0.51).all() and (abs(r.ca - r.carcinogen_air_lb) <= 0.51).all()
    h = holc()
    j = gpd.sjoin(pts(fy), h[h.grade.isin(GR)][["grade", "geometry"]], how="left", predicate="within")
    assert (j[~j.index.duplicated()].grade.fillna("ungraded") == fy.holc).all()
    th = csv("data/results/context/tri_by_year_holc.csv")
    r2 = fy.groupby(["year", "holc"]).agg(f=("trifd", "nunique"), air=("air_lb", "sum")).reset_index().merge(th, on=["year", "holc"], how="outer")
    assert len(r2) == len(th) and (r2.f == r2.facilities).all() and (abs(r2.air - r2.air_lb) <= 0.51).all()
    tn = csv("data/results/context/tri_near_sites.csv")
    assert tn.facility_years.sum() == len(fy) and (tn.set_index("near_historical_site").facility_years == fy.groupby("near_historical_site").size()).all()


def test_site_context_counts_agree_across_tables():
    """Catches site counts drifting between site_context.csv, its summary and the petroleum tables (same sites, same statuses)."""
    sc = csv("app/data/site_context.csv")
    S = csv("data/results/context/site_context_summary.csv").set_index(["series", "status"])
    P = csv("data/results/context/petroleum_by_status.csv").set_index(["series", "status"])
    n = sc.groupby(["series", "status"]).size()
    assert sc.id.is_unique and (S.sites == n.reindex(S.index)).all() and (P.sites == n.reindex(P.index)).all()
    for k, d in sc.groupby(["series", "status"]):
        assert abs(S.pct_petroleum_release_50m[k] - 100 * (d.petroleum_releases_50m > 0).mean()) < 0.051
        assert abs(S.pct_tank_facility_50m[k] - 100 * (d.tank_facility_50m > 0).mean()) < 0.051
        assert S.in_urban_renewal_project[k] == d.urban_renewal_project.notna().sum()
    U = csv("data/results/context/petroleum_by_use_now.csv")
    assert (U.groupby("series").sites.sum() <= n.groupby(level=0).sum().reindex(U.groupby("series").sites.sum().index)).all()
    ids = set(sites_addr().site_id) | set(hist_denver().hfirm)
    assert sc.id.isin(ids).all()


def test_petroleum_by_use_now_uses_the_current_parcel_match():
    """Catches context tables built from a stale site_fate file (today's use missing for sites that the committed site_fate file does match)."""
    U = csv("data/results/context/petroleum_by_use_now.csv")
    hf = set(csv("data/results/site_fate/site_fate_denver_pre1960.csv").hfirm)
    unmatched_now = (~hist_denver().hfirm.isin(hf)).sum()
    row = U[(U.series.str.startswith("Hazardous trades")) & (U.today == "not matched to a parcel")]
    assert (row.sites.iloc[0] if len(row) else 0) <= unmatched_now


def test_rerun_order_runs_site_fate_before_context_layers():
    """Catches a step that reads another step's output being scheduled before it."""
    steps = re.search(r"STEPS=\((.*?)\)", (ROOT / "rerun_results.sh").read_text(), re.S).group(1).split()
    assert steps.index("site_fate") < steps.index("context_layers")


def test_rerun_order_of_the_zoning_chain():
    """Catches a reordering that would feed stale HOLC areas or zoning layers into the steps that read them."""
    steps = re.search(r"STEPS=\((.*?)\)", (ROOT / "rerun_results.sh").read_text(), re.S).group(1).split()
    i = {s: k for k, s in enumerate(steps)}                     # last occurrence (holc_covenants runs twice)
    first_holc = steps.index("holc_covenants")
    assert first_holc < steps.index("zoning_1925") < i["holc_covenants"]
    for a, b in (("zoning_1925", "zoning_1944"), ("zoning_1944", "zoning_over_time"), ("zoning_1955", "zoning_over_time"), ("zoning_1925", "zoning_2023"),
                 ("zoning_over_time", "landuse_1937_1997"), ("landuse_1937_1997", "highways_denver"), ("zoning_1925", "rezoning_denver"), ("zoning_1925", "loc_sanborn_1903")):
        assert i[a] < steps.index(b), (a, b)


# ====================================================================== duplicated numbers

def test_share_of_d_land_zoned_industrial_in_1929_agrees_across_its_three_tables():
    """Catches the three published versions of 'share of D land zoned industrial in 1929' (15.9 / 16.0 / 16.2 %) drifting apart."""
    a = csv("data/results/holc/holc_zoning_by_grade.csv").set_index("grade").pct_industrial_1929["D"]
    b = csv("data/results/zoning_1944/zoning_change_by_holc_grade.csv").query("grade == 'D' and cls == 'industrial'").pct_1929.iloc[0]
    c = csv("data/results/zoning_over_time/zoning_by_holc_grade_years.csv").query("grade == 'D' and year == '1929'").pct_industrial.iloc[0]
    assert max(a, b, c) - min(a, b, c) <= 0.5
    k = [csv("data/results/holc/holc_zoning_by_grade.csv").set_index("grade").km2_on_map["D"],
         csv("data/results/zoning_1944/zoning_change_by_holc_grade.csv").query("grade == 'D'").grade_km2.iloc[0],
         csv("data/results/zoning_over_time/zoning_by_holc_grade_years.csv").query("grade == 'D'").grade_km2.iloc[0]]
    assert k[0] >= k[1] >= k[2] > 25                             # all of D on the sheet >= on both sheets >= on both sheets in Denver County


def test_generated_table_d_land_is_not_rounded_twice():
    """Catches an area rounded from an already rounded figure (25.347 -> 25.35 -> 25.4)."""
    L, h = layers(), holc()
    d = shapely.union_all(h[h.grade == "D"].geometry.values).intersection(L["common"]).area / 1e6
    m = re.search(r"HOLC D land \(([0-9.]+) km²\)", (ROOT / "paper" / "tables_generated.md").read_text())
    assert m and float(m.group(1)) == round(d, 1)


@pytest.mark.xfail(strict=True, reason="FINDING 7: zoning_tract_paths.csv compares 7 tracts in 1970 and 2020 with 6 in 1990 ('Industrial in 1929, not today'; 86/86/87 for 'Neither') because the 200-resident floor is applied census by census; the manuscript reads the three rows as the same seven tracts")
def test_zoning_tract_paths_follow_the_same_tracts_in_every_census():
    """Catches a before/after comparison whose set of tracts changes between censuses."""
    T = csv("data/results/zoning_over_time/zoning_tract_paths.csv")
    assert (T.groupby("path").tracts.nunique() == 1).all()


def test_app_copies_of_stage_outputs_are_identical():
    """Catches an app/data copy of a stage output that was not refreshed (files the existing copy test does not pair by name)."""
    pairs = [("zoning_1929/zoning_shares_tracts.csv", "zoning_shares_tracts.csv"), ("zoning_1944/zoning_change_by_holc_grade.csv", "zoning_change_by_holc_grade.csv"),
             ("zoning_1955/zoning_1955_km2.csv", "zoning_1955_km2.csv"), ("zoning_over_time/zoning_sites_by_year.csv", "zoning_sites_by_year.csv"),
             ("corridors/cells_500m.csv", "corridor_cells.csv"), ("holc/holc_industry_periods.csv", "holc_industry_periods.csv"),
             ("context/tri_by_year_holc.csv", "tri_by_year_holc.csv"), ("zoning_over_time/zoning_today_categories.geojson", "zoning_today_categories.geojson")]
    for r, a in pairs:
        fr, fa = RES / r, A / a
        if a == "corridor_cells.csv":                               # app copy (app_census_layers.R): the same cells with lon/lat instead of the cell key
            ca, cr = csv("app/data/corridor_cells.csv"), csv("data/results/corridors/cells_500m.csv")
            assert len(ca) == len(cr) and ca["class"].value_counts().to_dict() == cr["class"].value_counts().to_dict()
            assert ca.editions.sum() == cr.editions.sum() and ca.lon.between(-109.1, -102.0).all() and ca.lat.between(36.9, 41.1).all()
            continue
        assert fr.read_bytes() == fa.read_bytes(), (r, a)
