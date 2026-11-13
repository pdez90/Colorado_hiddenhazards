"""Stage checks: site fate, archival follow-up, hedonic, ownership, housing conditions (review 4, stage F).

Reads committed files only (data/results/{site_fate,hedonic,ownership,housing_conditions}, app/data, paper/, data/raw/ownership).
The parcel cache, sales, owner and 311 files (work/) are not needed; nothing here prints or needs an owner name.
Lives in tests/stages/; run elsewhere with STAGE_ROOT=/path/to/repo pytest test_stage_F_sitefate_property.py
"""
import math
import os
import pathlib
import re

import numpy as np
import pandas as pd
import pytest

ROOT = pathlib.Path(os.environ["STAGE_ROOT"]) if os.environ.get("STAGE_ROOT") else pathlib.Path(__file__).resolve().parents[2]
SF = ROOT / "data" / "results" / "site_fate"
HD = ROOT / "data" / "results" / "hedonic"
OW = ROOT / "data" / "results" / "ownership"
HC = ROOT / "data" / "results" / "housing_conditions"
APP = ROOT / "app" / "data"

LAB_S = "Manufacturers' directory sites 1965-1992"
LAB_H = "Business-directory hazardous trades 1891-1956"
PM = ["same address", "same street and side, nearest number", "same street, nearest parcel", "nearest parcel", "no parcel within 40 m"]
USES = {"Industrial / utility", "Commercial / office", "Residential", "Vacant", "Civic / school / health", "Park / open space", "Other", "No parcel match"}
SENSITIVE = ["Residential", "Civic / school / health", "Park / open space"]


def csv(p, **kw):
    if not p.exists():
        pytest.skip(f"{p} not present")
    return pd.read_csv(p, low_memory=False, **kw)


def true_(s):
    return s.astype(str).str.upper().eq("TRUE")


@pytest.fixture(scope="module")
def S():
    return csv(SF / "site_fate_denver.csv", dtype={"SCHEDNUM": str})


@pytest.fixture(scope="module")
def H():
    return csv(SF / "site_fate_denver_pre1960.csv", dtype={"SCHEDNUM": str})


# ------------------------------------------------------------------------------------------------------------------
# 1. site fate: universe, schema, parcel choice
# ------------------------------------------------------------------------------------------------------------------
PARCEL_COLS = ["SCHEDNUM", "PROP_CLASS", "D_CLASS_CN", "ZONE_ID", "ZONE_10", "TOT_UNITS", "year_built", "SITUS_ADDRESS_LINE1", "LAND_AREA",
               "parcel_dist_m", "parcel_match", "use_now", "zone_industrial", "redeveloped", "last_decade"]
S_COLS = ["site_id", "address", "first_year", "last_year", "radar", "fe_sectors", "lat", "lon"] + PARCEL_COLS
H_COLS = ["hfirm", "name", "street", "first_year", "last_year", "sectors", "persists_to_1961plus", "lat", "lon"] + PARCEL_COLS
SEN_COLS = ["site_id", "address", "first_year", "last_year", "fe_sectors", "use_now", "D_CLASS_CN", "ZONE_ID", "ZONE_10", "TOT_UNITS", "year_built",
            "SITUS_ADDRESS_LINE1", "parcel_match", "parcel_dist_m", "lat", "lon"]
ARCH_COLS = ["series", "id", "name_or_address", "sectors", "first_year", "last_year", "parcel_class_today", "use_now", "year_built", "units", "lat", "lon",
             "sanborn_edition_to_check", "directory_years_to_check", "sanborn_use", "reverse_directory_occupants", "notes"]


def test_site_fate_files_have_exactly_the_documented_columns(S, H):
    """A parcel-service field added to the output (OWNER_NAME is fetched into the cache) would change the column list."""
    assert list(S.columns) == S_COLS
    assert list(H.columns) == H_COLS
    assert list(csv(SF / "site_fate_sensitive.csv").columns) == SEN_COLS
    assert list(csv(SF / "archival_followup_hidden_conversions.csv").columns) == ARCH_COLS


def test_site_fate_rows_are_exactly_the_denver_hazardous_sites(S):
    """Sites dropped or duplicated by the county filter or the parcel merge (row conservation against app/data/sites.csv)."""
    A = csv(APP / "sites.csv", dtype={"GEOID": str})
    A = A[A.lat.notna() & true_(A.fe_hazard)]
    den = A[A.GEOID.fillna("").str[:5] == "08031"]
    edge = A[A.GEOID.fillna("") == ""]                      # tract-edge points the script may assign to the nearest tract
    assert S.site_id.is_unique
    assert set(den.site_id) <= set(S.site_id) <= set(den.site_id) | set(edge.site_id)
    m = S.merge(A, on="site_id", suffixes=("", "_src"))
    assert len(m) == len(S)
    for c in ("first_year", "last_year", "radar", "fe_sectors"):
        assert (m[c].fillna("") == m[c + "_src"].fillna("")).all(), c
    assert np.allclose(m.lat, m.lat_src) and np.allclose(m.lon, m.lon_src)


def test_pre1960_rows_are_exactly_the_street_level_denver_trades(H):
    """Pre-1960 trades dropped, duplicated or taken at town level (row conservation against app/data/historical_sites.csv)."""
    A = csv(APP / "historical_sites.csv")
    A = A[A.lat.notna() & (A.precision != "town") & true_(A.fe_hazard) & (A.town.str.upper() == "DENVER")]
    assert H.hfirm.is_unique and set(H.hfirm) == set(A.hfirm)
    m = H.merge(A, on="hfirm", suffixes=("", "_src"))
    assert (m.last_year == m.last_year_src).all() and (m.first_year == m.first_year_src).all()
    assert (m.street.fillna("") == m.street_src.fillna("")).all()


def test_coordinates_years_and_distances_in_range(S, H):
    """Points outside the City and County of Denver, a parcel farther than the 40 m search, impossible years."""
    for d in (S, H):
        assert d.lat.between(39.61, 39.92).all() and d.lon.between(-105.11, -104.59).all()
        assert d.parcel_dist_m.dropna().between(0, 40).all()
        assert (d.first_year <= d.last_year).all()
        yb = d.year_built.dropna()
        assert yb.between(1800, 2030).all()
        assert set(d.use_now) <= USES and set(d.parcel_match) <= set(PM)
        nomatch = d.use_now == "No parcel match"
        assert (d.SCHEDNUM.isna() == nomatch).all() and (d.parcel_match.eq(PM[4]) == nomatch).all()
    assert S.last_year.between(1965, 1992).all() and H.last_year.between(1871, 1956).all()


# an independent re-implementation of the address rule (house number, direction, street name, street type)
_TYP = {"STREET": "ST", "ST": "ST", "AVENUE": "AVE", "AVE": "AVE", "AV": "AVE", "BOULEVARD": "BLVD", "BLVD": "BLVD", "PLACE": "PL", "PL": "PL", "DRIVE": "DR",
        "DR": "DR", "COURT": "CT", "CT": "CT", "WAY": "WAY", "LANE": "LN", "LN": "LN", "ROAD": "RD", "RD": "RD", "PARKWAY": "PKWY", "PKWY": "PKWY",
        "CIRCLE": "CIR", "CIR": "CIR", "TERRACE": "TER", "TER": "TER", "HIGHWAY": "HWY", "HWY": "HWY", "TRAIL": "TRL", "TRL": "TRL"}
_DIR = {"NORTH": "N", "SOUTH": "S", "EAST": "E", "WEST": "W", "N": "N", "S": "S", "E": "E", "W": "W"}


def _parts(x):
    x = "" if pd.isna(x) else str(x).upper().strip()
    x = re.sub(r"\s*(#|\b(UNIT|APT|STE|SUITE|BLDG|RM)\b).*$", "", x)
    x = re.sub(r"\bSAINT\b", "ST", re.sub(r"[.,]", " ", x))
    t = x.split()
    if not t:
        return "", "", "", ""
    n = ""
    if re.match(r"^[0-9]", t[0]):
        n, t = re.sub(r"[^0-9].*$", "", t[0]), t[1:]
    d = ""
    if len(t) >= 2 and t[0] in _DIR:
        d, t = _DIR[t[0]], t[1:]
    j = [i for i, w in enumerate(t) if w in _TYP and i >= 1]
    ty = ""
    if j:
        ty, t = _TYP[t[max(j)]], t[:max(j)]
    return n, d, " ".join(t), ty


def _rule(d, col):
    a = pd.DataFrame([_parts(x) for x in d[col]], columns=list("ndst"))
    p = pd.DataFrame([_parts(x) for x in d.SITUS_ADDRESS_LINE1], columns=list("ndst"))
    same = (a.s != "") & (a.s == p.s) & ((a.d == "") | (p.d == "") | (a.d == p.d)) & ((a.t == "") | (p.t == "") | (a.t == p.t))
    na, npn = pd.to_numeric(a.n, errors="coerce"), pd.to_numeric(p.n, errors="coerce")
    both = na.notna() & npn.notna()
    # rule 2 needs the same side AND the same block: fewer than 100 house numbers away (site_fate.R, review 5); farther is only "same street"
    gap = (na - npn).abs()
    r = np.where(same & both & (na == npn), PM[0], np.where(same & both & (na % 2 == npn % 2) & (gap < 100), PM[1], np.where(same, PM[2], PM[3])))
    return pd.Series(r, index=d.index), (na - npn).abs()


@pytest.mark.parametrize("which,col", [("S", "address"), ("H", "street")])
def test_parcel_match_label_follows_from_the_two_addresses(S, H, which, col):
    """A parcel_match label that the site's address and the parcel's situs address do not support (e.g. 'same address' on another street)."""
    d = S if which == "S" else H
    d = d[d.parcel_match != PM[4]].reset_index(drop=True)
    r, _ = _rule(d, col)
    bad = d[r != d.parcel_match]
    assert bad.empty, bad[[col, "SITUS_ADDRESS_LINE1", "parcel_match"]].head(10).values.tolist()


def test_same_street_and_side_match_stays_within_the_block(S, H):
    """'same street and side' given to a parcel 100 or more house numbers away (the rule is limited to the block)."""
    for d, col in ((S, "address"), (H, "street")):
        d = d[d.parcel_match == PM[1]].reset_index(drop=True)
        _, gap = _rule(d, col)
        assert gap.notna().all() and (gap < 100).all()


@pytest.mark.xfail(strict=True, reason="FINDING 2 (remains; ids renumbered): S08040 '267 W ALAMEDA AVE' sits on the parcel 3325 W ALAMEDA AVE (3,058 house numbers "
                                       "away, now labelled 'same street, nearest parcel'): the site's address and coordinates disagree by about 3.8 km. In the "
                                       "rebuilt pre-1960 layer HF02952 '1329 Walnut' and HF05049 '1327 Walnut' sit on 2536 WALNUT ST (1,200 numbers away)")
def test_same_street_match_is_not_blocks_away(S, H):
    """A geocode that put the site far along its street from its printed house number, so that the parcel is not the site's lot."""
    for d, col, idc in ((S, "address", "site_id"), (H, "street", "hfirm")):
        d = d[d.parcel_match.isin(PM[1:3])].reset_index(drop=True)
        _, gap = _rule(d, col)
        assert not (gap >= 1000).any(), d.loc[gap >= 1000, [idc, col, "SITUS_ADDRESS_LINE1"]].values.tolist()


def test_share_of_same_street_matches_a_block_or_more_away_stays_small(S):
    """A geocoder regression that moves many sites along their streets (currently 49 of the 457 same-street matches are 100+ numbers away)."""
    d = S[S.parcel_match.isin(PM[1:3])].reset_index(drop=True)
    _, gap = _rule(d, "address")
    assert gap.notna().all() and ((gap >= 100).sum(), len(d)) == (49, 457) and (gap >= 100).mean() <= 0.12


# ------------------------------------------------------------------------------------------------------------------
# 2. site fate: derived flags and the summary tables
# ------------------------------------------------------------------------------------------------------------------
def test_redeveloped_and_last_decade_recompute(S, H):
    """The comparison year_built > last_year (strict; no year built = not redeveloped) or the decade label drifting."""
    for d in (S, H):
        assert (true_(d.redeveloped) == (d.year_built > d.last_year)).all()
        assert not true_(d.redeveloped)[d.year_built.isna()].any()
        assert (d.last_decade == (d.last_year // 10 * 10).astype(int).astype(str) + "s").all()


def test_zone_industrial_follows_zone_id(S, H):
    """zone_industrial not matching the I-A / I-B / I-MX districts of the parcel's ZONE_ID (M-IMX read from ZONE_10: the service writes its ZONE_ID as 'MIX')."""
    for d in (S, H):
        z = d.ZONE_ID.fillna("").str.upper().where(~d.ZONE_10.fillna("").str.upper().str.match(r"^M-IMX"), "M-IMX")
        assert (true_(d.zone_industrial) == z.str.match(r"^I-?(A|B|MX)|^M-IMX")).all()
        hyph = d.ZONE_10.fillna("").str.upper()
        assert true_(d.zone_industrial)[hyph.str.match(r"^I-(A|B|MX)")].all()


def test_m_imx_parcels_are_flagged_industrial(S, H):
    """Industrial mixed-use master-plan districts (M-IMX-*) left out of 'still zoned industrial'."""
    for d in (S, H):
        m = d.ZONE_10.fillna("").str.upper().str.startswith("M-IMX")
        assert true_(d.zone_industrial)[m].all()


def test_use_now_agrees_with_assessor_class_prefix(S, H):
    """A regex-order slip in broad() that sends a whole assessor class to the wrong broad use."""
    for d in (S, H):
        c = d.D_CLASS_CN.fillna("").str.upper()
        assert (d.use_now[c.str.match(r"^(SFR|RESIDENTIAL-)")] == "Residential").all()
        assert (d.use_now[c.str.match(r"^COMMERCIAL-")] == "Commercial / office").all()
        assert (d.use_now[c == "VACANT LAND"] == "Vacant").all()
        assert (d.use_now[c.str.match(r"^INDUSTRIAL-(WAREHOUSE|FACTORY|FOOD PROCESSING|PRINTING PLANT|MEAT PACKING)")] == "Industrial / utility").all()
        ce = c.str.contains("COMMON ELEMENT")
        assert set(d.use_now[ce]) <= {"Residential", "Industrial / utility"}
        assert (d.use_now[ce & true_(d.zone_industrial)] == "Industrial / utility").all()
        # one class, one use (except common-element parcels, classed by zone)
        assert (d[~ce].groupby("D_CLASS_CN").use_now.nunique() == 1).all()


def test_summary_by_decade_recomputes(S, H):
    """site_fate_summary.csv out of step with the per-site files (counts, shares, missing or extra cells)."""
    SM = csv(SF / "site_fate_summary.csv")
    assert set(SM.series) == {LAB_S, LAB_H}
    for lab, d in ((LAB_S, S), (LAB_H, H)):
        g = d.groupby(["last_decade", "use_now"]).size().rename("n2").reset_index()
        g["pct2"] = 100 * g.n2 / g.groupby("last_decade").n2.transform("sum")
        m = SM[SM.series == lab].merge(g, on=["last_decade", "use_now"], how="outer")
        assert m.n.notna().all() and m.n2.notna().all() and (m.n == m.n2).all()
        assert (m.pct - m.pct2).abs().max() <= 0.051
        assert int(m.n.sum()) == len(d)
        assert (SM[SM.series == lab].groupby("last_decade").pct.sum() - 100).abs().max() <= 0.35


def test_parcel_match_table_recomputes(S, H):
    """site_fate_parcel_match.csv (rule counts, shares, agreement rate) out of step with the per-site files."""
    T = csv(SF / "site_fate_parcel_match.csv")
    for lab, d, col in ((LAB_S, S, "address"), (LAB_H, H, "street")):
        t = T[T.series == lab].set_index("parcel_match")
        vc = d.parcel_match.value_counts()
        rules = [k for k in t.index if not k.startswith("agreement rate")]
        assert set(rules) == set(vc.index)
        for k in rules:
            assert int(t.loc[k, "n"]) == int(vc[k]) and abs(t.loc[k, "pct"] - 100 * vc[k] / len(d)) <= 0.051, k
        ag = t.loc[[k for k in t.index if k.startswith("agreement rate")][0]]
        a = d[(d.parcel_match != PM[4]) & d[col].fillna("").str.strip().str.match(r"^[0-9]")]
        assert int(ag.n) == len(a) and abs(ag.pct - 100 * (a.parcel_match == PM[0]).mean()) <= 0.051


def test_zoning_table_recomputes(S, H):
    """site_fate_zoning.csv (still zoned industrial, rebuilt, median year built) out of step with the per-site files."""
    Z = csv(SF / "site_fate_zoning.csv").set_index("series")
    for lab, d in ((LAB_S, S), (LAB_H, H)):
        d = d[d.use_now != "No parcel match"]
        assert int(Z.loc[lab, "n"]) == len(d)
        assert abs(Z.loc[lab, "pct_zone_industrial"] - 100 * true_(d.zone_industrial).mean()) <= 0.051
        assert abs(Z.loc[lab, "pct_redeveloped"] - 100 * true_(d.redeveloped).mean()) <= 0.051
        assert Z.loc[lab, "median_year_built"] == d.year_built.median()


def test_sensitive_and_archival_lists_are_the_stated_selection(S, H):
    """The hidden-conversion lists not being exactly: 1965-92 sites in residential/civic/park use on no list, plus pre-1960 trades now residential."""
    sel = S[S.use_now.isin(SENSITIVE) & (S.radar == "Not on any list")]
    sen = csv(SF / "site_fate_sensitive.csv")
    assert sen.site_id.is_unique and set(sen.site_id) == set(sel.site_id)
    W = csv(SF / "archival_followup_hidden_conversions.csv", keep_default_na=False)
    a, b = W[W.series == "manufacturers 1965-92"], W[W.series == "business directory 1891-1956"]
    assert len(a) + len(b) == len(W) and W.id.is_unique
    assert set(a.id) == set(sel.site_id)
    assert set(b.id) == set(H[H.use_now == "Residential"].hfirm)
    m = a.merge(S, left_on="id", right_on="site_id", suffixes=("", "_s"))
    assert (m.use_now == m.use_now_s).all() and (m.last_year.astype(int) == m.last_year_s).all() and (m.parcel_class_today == m.D_CLASS_CN).all()
    mb = b.merge(H, left_on="id", right_on="hfirm", suffixes=("", "_h"))
    assert (mb.last_year.astype(int) == mb.last_year_h).all() and (mb.parcel_class_today == mb.D_CLASS_CN).all()
    ly = W.last_year.astype(int)
    assert (W.directory_years_to_check == ["Polk reverse directory %d and %d" % (y, y + 5) for y in ly]).all()
    early = b.first_year.astype(int) <= 1910
    assert (b.sanborn_edition_to_check[early] == "1904 (LoC online)").all() and (b.sanborn_edition_to_check[~early] != "1904 (LoC online)").all()
    assert (W[["sanborn_use", "reverse_directory_occupants", "notes"]] == "").all().all()


def _manuscript():
    p = ROOT / "paper" / "Before_and_After_the_Map_manuscript.md"
    if not p.exists():
        pytest.skip("manuscript not present")
    return p.read_text(encoding="utf-8")


@pytest.mark.xfail(strict=True, reason="TEXT PENDING: manuscript Results (site fate) still has the pre-rebuild counts '171 of the later sites are residential "
                                       "parcels ... 96 of those 171 (56%) ... (136 have no cleanup record)' and 'For 108 of the 171 ... (45 were built later; 18 have "
                                       "no date) ... Of the 96 ..., 75 ... Of the 47 pre-1960 trades now residential, 22'; site_fate_denver*.csv now give 183; 104 of "
                                       "183 (57%); 143; 115 of 183 (51; 17); of the 104, 81; of the 75 pre-1960, 39")
def test_manuscript_residential_site_counts(S, H):
    """The manuscript's counts of residential sites (171; 96 on no list; 136 without a cleanup record; 108 / 45 / 18 by building date; 75; 47 and 22)."""
    t = _manuscript()
    R = S[S.use_now == "Residential"]
    hid = R[R.radar == "Not on any list"]
    Hr = H[H.use_now == "Residential"]
    m = re.search(r"([\d,]+) of the later sites are residential parcels.*?(\d+) of those \d+ \((\d+)%\) match no record.*?\((\d+) have no cleanup record\)", t)
    assert m, "sentence not found"
    assert [int(m.group(i).replace(",", "")) for i in (1, 2, 4)] == [len(R), len(hid), int((R.radar != "Cleanup / contamination list").sum())]
    assert int(m.group(3)) == round(100 * len(hid) / len(R))
    m = re.search(r"For (\d+) of the (\d+) residential sites.*?\((\d+) were built later; (\d+) have no date\).*?Of the (\d+) residential sites on no inventory, (\d+) are of this kind\. "
                  r"Of the (\d+) pre-1960 trades now residential, (\d+) carry", t)
    assert m, "sentence not found"
    got = [int(x) for x in m.groups()]
    want = [int((R.year_built <= R.last_year).sum()), len(R), int((R.year_built > R.last_year).sum()), int(R.year_built.isna().sum()),
            len(hid), int((hid.year_built <= hid.last_year).sum()), len(Hr), int((Hr.year_built > Hr.last_year).sum())]
    assert got == want


@pytest.mark.xfail(strict=True, reason="TEXT PENDING (FINDING 1 fixed in site_fate.R, which now counts units once per parcel): the manuscript still says "
                                       "'171 ... residential parcels holding 5,637 dwelling units'; the 183 residential sites stand on 180 parcels with 4,982 units "
                                       "(5,555 if summed over sites)")
def test_manuscript_dwelling_units_count_each_parcel_once(S):
    """Dwelling units double-counted where two or more sites share one parcel."""
    t = _manuscript()
    m = re.search(r"residential parcels holding ([\d,]+) dwelling units", t)
    assert m, "sentence not found"
    R = S[S.use_now == "Residential"]
    assert int(m.group(1).replace(",", "")) == int(R.drop_duplicates("SCHEDNUM").TOT_UNITS.sum())


def test_units_of_one_parcel_do_not_differ_between_sites(S, H):
    """The same parcel carrying different attributes on two rows (a stale or mixed parcel cache)."""
    for d in (S, H):
        g = d.dropna(subset=["SCHEDNUM"]).groupby("SCHEDNUM")
        for c in ("D_CLASS_CN", "ZONE_ID", "use_now", "SITUS_ADDRESS_LINE1"):
            assert (g[c].nunique(dropna=False) == 1).all(), c
        assert (g.TOT_UNITS.nunique(dropna=True) <= 1).all() and (g.year_built.nunique(dropna=True) <= 1).all()


# ------------------------------------------------------------------------------------------------------------------
# 3. hedonic models
# ------------------------------------------------------------------------------------------------------------------
BANDS = ["0-200 m", "200-400 m", "400-800 m"]
KINDS = ["Hidden (no current inventory)", "Known (on a current inventory)", "Pre-1960 hazardous trade"]


@pytest.fixture(scope="module")
def HM():
    return csv(HD / "hedonic_models.csv")


def test_hedonic_pct_and_ci_follow_from_estimate_and_se(HM):
    """pct / lo / hi not being 100*(exp(b)-1) and exp(b -/+ 1.96 se): a table edited by hand or columns from different runs."""
    for col, v in (("pct", HM.estimate), ("lo", HM.estimate - 1.96 * HM.se), ("hi", HM.estimate + 1.96 * HM.se)):
        assert (HM[col] - 100 * (np.exp(v) - 1)).abs().max() <= 0.03, col      # estimate and se are rounded to 4 decimals
    assert (HM.lo < HM.pct).all() and (HM.pct < HM.hi).all() and (HM.se > 0).all()


def test_hedonic_p_values_consistent_with_t_statistics(HM):
    """A p-value column that does not belong to the estimate and (tract-clustered) standard error beside it."""
    lo_t = (HM.estimate.abs() - 5e-5).clip(lower=0) / (HM.se + 5e-5)
    hi_t = (HM.estimate.abs() + 5e-5) / (HM.se - 5e-5)
    p_norm = lambda z: z.map(lambda v: math.erfc(v / math.sqrt(2)))
    # the t reference (clusters - 1 df, about 140) gives p above the normal p: by a few per cent at |t| < 3, by orders of magnitude far out
    assert (HM.p >= p_norm(hi_t) * 0.97).all()
    near = lo_t < 3
    assert (HM.p[near] <= p_norm(lo_t[near]) * 1.6 + 1e-12).all()
    assert (HM.p[~near] < 0.01).all()


def test_hedonic_models_are_complete_and_n_is_coherent(HM):
    """A model or band missing from the table, n differing within one model, or model n above the described sample."""
    SMP = csv(HD / "hedonic_sample.csv")
    tot = SMP.groupby("kind").sales.sum()
    assert tot.nunique() == 1 and set(tot.index) == {"hidden", "known", "pre1960"}        # each kind's bands partition the same sales
    assert list(SMP[SMP.kind == "hidden"].distance) == ["over 800 m"] + BANDS
    n = HM.groupby("model").n.agg(["min", "max"])
    assert (n["min"] == n["max"]).all()
    assert (n["max"] <= tot.iloc[0]).all()
    full = n[~n.index.str.startswith("M4")]["max"]
    assert (full >= 0.995 * tot.iloc[0]).all()                                         # fixed-effect singletons only
    for mdl in [m for m in HM.model.unique() if m[:2] in ("M1", "M2", "M3", "M4")]:
        d = HM[(HM.model == mdl) & HM.kind.isin(KINDS)]
        assert sorted(zip(d.kind, d.distance)) == sorted((k, b) for k in KINDS for b in BANDS), mdl
    m6 = HM[HM.model.str.startswith("M6")].set_index("kind")
    assert abs(m6.loc["Hidden minus known", "estimate"] - (m6.loc[KINDS[0], "estimate"] - m6.loc[KINDS[1], "estimate"])) <= 2e-4
    f = HD / "hedonic_summary.md"
    if f.exists():
        m = re.search(r"([\d,]+) arm's-length residential sales, (\d{4})-(\d{4})", f.read_text(encoding="utf-8"))
        assert m and int(m.group(1).replace(",", "")) == int(tot.iloc[0]) and int(m.group(2)) == 2015


def test_hedonic_sample_is_plausible():
    """Prices, floor areas or years that betray a unit error or an untrimmed sample (a $1 or $50 million median, an area in the wrong unit)."""
    SMP = csv(HD / "hedonic_sample.csv")
    assert SMP.median_price.between(150_000, 1_500_000).all()
    assert SMP.median_area.between(600, 3000).all() and SMP.median_year_built.between(1900, 2015).all()
    assert SMP.pct_condo.between(0, 100).all() and (SMP.sales > 1000).all()


# ------------------------------------------------------------------------------------------------------------------
# 4. ownership
# ------------------------------------------------------------------------------------------------------------------
SIZE_BOUNDS = {"1 unit": (1, 1), "2-4 units": (2, 4), "5-19 units": (5, 19), "20-99 units": (20, 99), "100-999 units": (100, 999), "1,000+ units": (1000, 10 ** 7)}
SMALL = ["Single-family house", "Condominium unit", "Rowhouse / townhouse", "Duplex / triplex"]


def test_occupancy_table_arithmetic():
    """units != owner-occupied + rental, a percentage on the wrong denominator, or one-unit types with units != parcels."""
    o = csv(OW / "occupancy_by_type.csv")
    assert (o.units == o.owner_occupied_units + o.rental_units).all()
    assert (o.pct_owner_occupied - 100 * o.owner_occupied_units / o.units).abs().max() <= 0.051
    one = o[o.type.isin(SMALL[:3])]
    assert (one.units == one.parcels).all()
    multi = o[~o.type.isin(SMALL[:3])]
    assert (multi.units >= 2 * multi.parcels).all()


def test_owner_size_bands_hold_what_they_say():
    """An owner filed in the wrong size band, or a band total that cannot come from that many owners."""
    s = csv(OW / "owner_size.csv")
    t = csv(OW / "owner_types.csv")
    for grp, g in s.groupby("grouping"):
        assert set(g["size"]) <= set(SIZE_BOUNDS)
        for r in g.itertuples(index=False):
            lo, hi = SIZE_BOUNDS[r.size]
            assert lo * r.owners <= r.rental_units <= hi * r.owners, (grp, r.size)
        assert int(g.rental_units.sum()) == int(t.rental_units.sum()), grp
        assert (g.pct_owners - 100 * g.owners / g.owners.sum()).abs().max() <= 0.0051
        assert (g.pct_rental_units - 100 * g.rental_units / g.rental_units.sum()).abs().max() <= 0.051
    n = s.groupby("grouping").owners.sum()
    assert n["by owner family (shared mailing address)"] <= n["by owner name"]            # families only merge names


def test_owner_types_and_private_total():
    """Shares of owner types on the wrong base; the 'private owners' total not being all rentals less public and unnamed owners."""
    t = csv(OW / "owner_types.csv")
    assert (t.pct_rental_units - 100 * t.rental_units / t.rental_units.sum()).abs().max() <= 0.051
    assert (t.rental_units >= t.parcels).all() or (t.rental_units > 0).all()
    priv = int(t[~t.owner_type.isin(["Public", "Unknown (no name recorded)"])].rental_units.sum())
    c = csv(OW / "concentration.csv").set_index("grouping")
    assert int(c.loc["Private owners, by name", "rental_units"]) == priv == int(c.loc["Private owners, by family", "rental_units"])
    loc = csv(OW / "owner_location.csv")
    lt = loc[loc.group == "Owner type"].set_index("value").rental_units
    for k, v in lt.items():
        assert int(v) == int(t.set_index("owner_type").rental_units[k]), k
    assert "Public" not in lt.index and "Unknown (no name recorded)" not in lt.index


def test_concentration_is_internally_ordered_and_linking_only_concentrates():
    """Top-k shares out of order, or a later linking stage (which only merges owners) showing more owners or less concentration."""
    c = csv(OW / "concentration.csv")
    L = csv(OW / "linking_stages.csv")
    for d in (c, L):
        assert (d.top10_pct <= d.top50_pct).all() and (d.top50_pct <= d.top100_pct).all() and (d.owners_100plus_pct <= d.owners_20plus_pct).all()
        assert d[["top10_pct", "top50_pct", "top100_pct", "top1pct_owners_pct", "owners_20plus_pct", "owners_100plus_pct"]].stack().between(0, 100).all()
        assert d.hhi.between(0, 10000).all()
    assert [g[:2] for g in L.grouping] == ["S1", "S2", "S3", "S4", "S5"][: len(L)]
    assert L.rental_units.nunique() == 1
    assert (L.owners.diff().dropna() <= 0).all()
    for col in ("top10_pct", "top50_pct", "top100_pct", "owners_100plus_pct", "hhi"):
        assert (L[col].diff().dropna() >= -0.11).all(), col                              # rounding only
    byname = c[c.grouping == "Private owners, by name"].iloc[0]
    s3 = L[L.grouping.str.startswith("S3")].iloc[0]
    for col in c.columns[1:]:
        assert byname[col] == s3[col], col


def test_ownership_geographic_tables_recompute():
    """pct_rental on the wrong base; tract rows exceeding the city; small-building rows not being the four small types."""
    o = csv(OW / "occupancy_by_type.csv")
    for f in ("by_holc.csv", "by_site_proximity.csv", "by_site_proximity_small_buildings.csv", "by_tract.csv"):
        d = csv(OW / f)
        assert (d.pct_rental - 100 * d.rental_units / d.units).abs().max() <= 0.051, f
        assert (d.rental_units <= d.units).all() and (d.units >= d.parcels).all(), f
        assert d.filter(like="pct_").stack().between(0, 100).all(), f
    p = csv(OW / "by_site_proximity.csv").set_index("area")
    allrow = p.loc["All of Denver"]
    assert (p.drop("All of Denver")[["parcels", "units", "rental_units"]] <= allrow[["parcels", "units", "rental_units"]]).all().all()
    assert int(allrow.units) <= int(o.units.sum()) and int(allrow.units) >= 0.99 * o.units.sum()      # parcels without coordinates only
    sb = csv(OW / "by_site_proximity_small_buildings.csv")
    sm = o[o.type.isin(SMALL)]
    for c in ("parcels", "units", "rental_units"):
        assert abs(int(sb[c].sum()) - int(sm[c].sum())) <= 0.01 * sm[c].sum(), c
    t = csv(OW / "by_tract.csv", dtype={"GEOID": str})
    assert t.GEOID.is_unique and t.GEOID.str.match(r"^08031\d{6}$").all()
    for c in ("parcels", "units", "rental_units"):
        assert 0.99 * allrow[c] <= t[c].sum() <= allrow[c], c
    for c in ("pct_rental_owner_20plus", "pct_rental_owner_100plus", "pct_rental_company", "pct_rental_out_of_state", "pct_rental_public"):
        assert abs(np.average(t[c], weights=t.rental_units) - allrow[c]) <= 0.3, c       # tract shares aggregate to the city's


def _wls(y, X, w):
    X = np.column_stack([np.ones(len(X)), X]); W = np.sqrt(w)[:, None]
    b, *_ = np.linalg.lstsq(X * W, y * W[:, 0], rcond=None)
    res = y - X @ b
    s2 = (w * res ** 2).sum() / (len(y) - X.shape[1])
    se = np.sqrt(np.diag(s2 * np.linalg.inv((X * w[:, None]).T @ X)))
    return b[1:], se[1:]


def test_tract_associations_and_tenure_validation_recompute_from_by_tract():
    """The published tract regressions or the census-tenure check not being what by_tract.csv gives (stale table, other sample)."""
    t = csv(OW / "by_tract.csv", dtype={"GEOID": str})
    A = csv(OW / "tract_associations.csv")
    m = t[(t.rental_units >= 50) & t.p_black.notna() & t.p_pov.notna()].copy()
    assert (A.tracts == len(m)).all()
    X = np.column_stack([m.p_black, m.p_hisp, m.p_pov, (m.hidden_1965_92 > 0) * 1.0, (m.known_1965_92 > 0) * 1.0])
    for y, a in A.groupby("outcome", sort=False):
        b, se = _wls(m[y].to_numpy(float), X, m.rental_units.to_numpy(float))
        assert np.abs(b - a.estimate.to_numpy()).max() <= 0.002 and np.abs(se - a.se.to_numpy()).max() <= 0.002, y
    v = t[t.p_owner.notna() & (t.units >= 100)]
    V = csv(OW / "validation_census_tenure.csv").iloc[0]
    assert int(V.tracts) == len(v)
    assert abs(V.assessor_owner_occupied - (100 - np.average(v.pct_rental, weights=v.units))) <= 0.06
    assert abs(V.census_owner_occupied - np.average(v.p_owner, weights=v.units)) <= 0.06
    assert abs(V.correlation - np.corrcoef(100 - v.pct_rental, v.p_owner)[0, 1]) <= 0.006


# ------------------------------------------------------------------------------------------------------------------
# 5. housing conditions and evictions
# ------------------------------------------------------------------------------------------------------------------
def test_request_linking_shares_recompute():
    """Linking shares on the wrong base (they are within each request class) or not summing to 100."""
    L = csv(HC / "linking.csv")
    for cls, g in L.groupby("class"):
        assert (g.pct - 100 * g.N / g.N.sum()).abs().max() <= 0.051, cls
        assert abs(g.pct.sum() - 100) <= 0.5, cls


def test_condition_rates_are_bounded_by_the_requests_that_were_linked():
    """Rates per unit and year that imply more requests than were linked to any building, or rental buildings holding more units than exist."""
    r = csv(HC / "rates.csv")
    L = csv(HC / "linking.csv")
    linked = L[L.how.str.match(r"^(address|nearest|coordinates)")].groupby("class").N.sum()
    m = re.search(r"311 requests (\d{4})-(\d{4}) \((\d+) years\)", (HC / "summary.md").read_text(encoding="utf-8"))
    assert m
    ny = int(m.group(3))
    assert ny == int(m.group(2)) - int(m.group(1)) + 1
    a = r[r.group == "All rental buildings"].iloc[0]
    assert a.inside_per_100_units_yr * a.units * ny / 100 <= linked["Conditions inside the home"] * 1.03
    assert a.outside_per_100_buildings_yr * a.buildings * ny / 100 <= linked["Outside of the property"] * 1.03
    assert (r.rental_units <= r.units).all() and (r.units >= r.buildings).all()
    assert r[["pct_buildings_inside_request", "pct_buildings_outside_request"]].stack().between(0, 100).all()
    hs = r[r.group == "Historical sites"]
    assert (hs[["buildings", "units", "rental_units"]] <= a[["buildings", "units", "rental_units"]].astype(float)).all().all()
    occ = csv(OW / "occupancy_by_type.csv")
    assert a.rental_units <= occ.rental_units.sum() and a.units <= occ.units.sum()
    # group rates must bracket the overall rate
    for grp in ("Owner type", "Building type", "1938 HOLC grade", "Owner location"):
        g = r[r.group == grp]
        assert g.inside_per_100_units_yr.min() <= a.inside_per_100_units_yr <= g.inside_per_100_units_yr.max(), grp
        assert abs(np.average(g.inside_per_100_units_yr, weights=g.units) - a.inside_per_100_units_yr) <= 0.011, grp
        assert abs(np.average(g.outside_per_100_buildings_yr, weights=g.buildings) - a.outside_per_100_buildings_yr) <= 0.011, grp
        assert abs(np.average(g.pct_buildings_inside_request, weights=g.buildings) - a.pct_buildings_inside_request) <= 0.11, grp


def test_condition_models_irr_ci_and_p_are_coherent():
    """An incidence-rate ratio outside its interval, a p-value from another row, or models fitted on different building counts."""
    M = csv(HC / "models.csv")
    r = csv(HC / "rates.csv")
    assert ((M.lo < M.irr) & (M.irr < M.hi)).all()
    assert M.buildings.nunique() == 1 and M.buildings.iloc[0] <= r[r.group == "All rental buildings"].buildings.iloc[0]
    se = (np.log(M.hi) - np.log(M.lo)) / (2 * 1.96)
    z = np.log(M.irr).abs() / se
    p = z.map(lambda v: math.erfc(v / math.sqrt(2)))
    ok = (np.log10(M.p) - np.log10(p)).abs() <= 0.35                                    # irr, lo, hi are rounded to 3 decimals
    assert ok.all(), M[~ok][["outcome", "portfolio", "term", "p"]].values.tolist()
    bands = M[M.portfolio.str.contains("size bands")]
    for o, g in bands.groupby("outcome"):
        assert list(g.term) == ["2-4 units", "5-19 units", "20-99 units", "100-999 units", "1,000+ units"], o


def test_eviction_tables_agree_with_the_county_series():
    """Tract filings (five-year mean) drifting away from the county's own filings for the same years; rates not per 100 renter households."""
    e = csv(HC / "evictions_by_large_owner_share.csv")
    c = csv(HC / "evictions_denver_county.csv")
    assert e.years.nunique() == 1
    y0, y1 = (int(x) for x in e.years.iloc[0].split("-"))
    assert y1 - y0 == 4
    cy = c[c.year.between(y0, y1)]
    assert len(cy) == 5
    assert abs(e.filings_per_year.sum() - cy.filings.mean()) <= 0.03 * cy.filings.mean()
    assert abs(100 * e.filings_per_year.sum() / e.renter_households.sum() - cy.filing_rate.mean()) <= 0.6
    assert (c.judgments <= c.filings).all() and (c.judgment_rate <= c.filing_rate).all()
    assert (c.filing_rate.between(0, 25)).all() and c.year.is_monotonic_increasing and c.year.is_unique
    M = csv(HC / "evictions_models.csv")
    assert M.tracts.nunique() == 1 and M.tracts.iloc[0] <= e.tracts.sum()
    assert (M.groupby("model").size() == 6).all() and (M.se > 0).all()


# ------------------------------------------------------------------------------------------------------------------
# 6. nothing about individual owners is published
# ------------------------------------------------------------------------------------------------------------------
NUM = re.compile(r"^-?\d+(\.\d+)?(e[+-]?\d+)?$", re.I)
VOCAB = set(SIZE_BOUNDS) | set(SMALL) | set(KINDS) | set(BANDS) | {
    "Apartment building (4+ units)", "Mixed-use building (homes with shops or offices)",
    "Company", "Individual", "Trust", "Public", "Non-profit or religious", "Unknown (no name recorded)",
    "A", "B", "C", "D", "Not graded", "all", "All of Denver", "All private rental units", "All rental buildings",
    "by owner name", "by owner family (shared mailing address)",
    "Private owners, by name", "Private owners, by family", "Private owners, by family: houses, condos, rowhouses, duplexes only",
    "S1 raw name and mailing address, exact", "S2 cleaned names and addresses", "S3 + near-identical names (fuzzy)",
    "S4 + shared mailing address (owner families)", "S5 + Colorado business registry (principal address, individual agent)",
    "Within 400 m of a hidden site (1965-92, no inventory)", "Within 400 m of a known site (1965-92, on an inventory)",
    "Within 400 m of a pre-1960 hazardous trade", "More than 400 m from any historical site",
    "Houses, condos, rowhouses, duplexes within 400 m of any historical site", "Houses, condos, rowhouses, duplexes farther away",
    "1938 HOLC grade", "Historical sites", "Owner family size (rental units in Denver)", "Owner type", "Owner location", "Building type",
    "More than 400 m from any", "Within 400 m of a hidden site", "Within 400 m of a known site",
    "Mailing address in Colorado", "Mailing address out of state",
    "pct_rental_owner_20plus", "pct_rental_owner_100plus", "pct_rental_company", "pct_rental_out_of_state",
    "Black residents (per point of %)", "Hispanic residents (per point of %)", "Poverty rate (per point of %)",
    "Tract has a hidden 1965-92 site", "Tract has a known 1965-92 site", "p_black", "p_hisp", "p_pov", "any_hidden", "any_known",
    "Conditions inside the home", "Outside of the property",
    "Requests about conditions inside the home", "Requests about the outside of the property",
    "S3 by owner name", "S4 by owner family", "S5 by registry group", "S4 by owner family (size bands vs 1 unit)",
    "per doubling of the owner's Denver rental units", "Largest 1% of owner families",
    "lowest third", "middle third", "highest third",
    "Eviction Lab validated tract file", "Eviction Lab full tract file (not the validated subset); years limited to those validated for Denver County",
    "Filing rate (% of renter households per year) on share of rental units held by owners of 100+ units",
    "Filing rate on share of rental units held by companies", "Filing rate on share of rental units with an out-of-state owner",
    "address", "no usable address or coordinates", "address not matched to a residential building",
    "nearest house number on the same street and side (within 10; 100 for 20+ units)",
    "the request's address is a non-residential parcel (not linked)",
    "address (only one building fits; ZIP, direction or street type missing on one side)",
    "coordinates (building of 20+ units within 150 m)", "coordinates (nearest building within 60 m)",
    "no usable address; no building near the coordinates",
    "M1 base: neighbourhood x year FE", "M2 + present-day hazards", "M3 tract x year FE", "M4 single-family homes (as M2)",
    "M5 site counts within 400 m", "M6 within 400 m (pooled)", "All residential sales", "Single-family homes",
    "Present-day control", "Hidden minus known", "0-400 m", "per site within 400 m", "over 800 m",
    "petro_100", "tri_500", "superfund", "freeway_250", "zoned_ind", "hidden", "known", "pre1960"}
AGENCIES = {"Environmental Health", "Public Health & Environment", "Community Planning & Development", "Excise & License", "Neighborhood Inspection Services", ""}
ENTITY = re.compile(r"\bL\.?\s?L\.?\s?C\b|\bLLLP\b|\bL\.?P\b|\bINC\b|\bCORP\b|\bTRUST(EE)?\b|\bREVOCABLE\b|\bESTATE OF\b|\bET ?AL\b|\bLTD\b|\bPROPERTIES\b|\bHOLDINGS\b|\bPARTNERS\b|"
                    r"\bMR\b|\bMRS\b|\bJR\b|\bC/O\b", re.I)


def _aggregate_csvs():
    out = []
    for folder, pref in ((OW, "ownership_"), (HC, "conditions_"), (HD, "")):
        for p in sorted(folder.glob("*.csv")):
            out.append(p)
            q = APP / (pref + p.name)
            if q.exists():
                out.append(q)
    for p in sorted(APP.glob("ownership_*.csv")) + sorted(APP.glob("conditions_*.csv")) + sorted(APP.glob("hedonic_*.csv")):
        if p not in out:
            out.append(p)
    return out


def test_ownership_housing_hedonic_tables_hold_only_numbers_and_known_labels():
    """An owner name, mailing address or other free text reaching a published table under any column name (closed vocabulary of labels)."""
    files = _aggregate_csvs()
    assert len(files) >= 20
    bad = []
    for p in files:
        d = pd.read_csv(p, dtype=str, keep_default_na=False)
        for c in d.columns:
            for v in d[c].unique():
                if v == "" or NUM.match(v) or v in VOCAB or re.fullmatch(r"(19|20)\d\d-(19|20)\d\d", v):
                    continue
                if c == "GEOID" and re.fullmatch(r"08031\d{6}", v):
                    continue
                if p.name.endswith("classes.csv") and c == "agency" and v in AGENCIES:
                    continue
                if p.name.endswith("classes.csv") and c == "request":      # 311 request types: common summaries only, no digits, no entity words
                    n = pd.to_numeric(d.loc[d[c] == v, "N"]).min()
                    if (n >= 20 and not re.search(r"\d", v) and not ENTITY.search(v) and len(v) <= 60) or v == "Other (rare or free-text summaries)":
                        continue
                bad.append((p.name, c, v[:40]))
    assert not bad, bad[:15]


def test_summaries_in_markdown_show_only_what_the_tables_hold():
    """A Markdown summary carrying a row (for example a list of the largest owners) that is in none of the published CSV tables."""
    bad = []
    for folder in (OW, HC, HD):
        allowed = set()
        for p in folder.glob("*.csv"):
            d = pd.read_csv(p, dtype=str, keep_default_na=False)
            allowed |= set(d.columns) | {v for c in d.columns for v in d[c].unique()}
        for md in folder.glob("*.md"):
            for line in md.read_text(encoding="utf-8").splitlines():
                if not line.startswith("|") or set(line) <= set("|- "):
                    continue
                for cell in (x.strip() for x in line.strip().strip("|").split("|")):
                    if cell == "" or NUM.match(cell) or cell in allowed or cell in VOCAB or cell in ("NA", "NaN"):
                        continue
                    if md.parent == HC and not re.search(r"\d", cell) and not ENTITY.search(cell) and len(cell) <= 60:
                        continue                                            # request types (classes table, top 15 per class)
                    bad.append((md.name, cell[:40]))
            txt = md.read_text(encoding="utf-8")
            assert not ENTITY.search(re.sub(r"\|\s*Trust\s*\|", "|", txt)), md.name
    assert not bad, bad[:15]


FORBIDDEN_COL = re.compile(r"^(owner_?(name|address.*|addr.*|city|state|zip)|grantor.*|grantee.*|taxpayer.*|mail(ing)?_?(addr.*|name|city|zip|line.*)|example_names|names|"
                           r"raw_key|name_key|s2_key|addr_key|addr_n|own_k|ra_own|agent(first|last|middle)name|entityname)$", re.I)
PRIVATE_FILES = {"owners.csv", "sales.csv", "res_chars.csv", "legal.csv", "parcels_by_point.csv", "top_owners_private.csv", "parcel_owner_groups_private.csv",
                 "registry_links_private.csv", "co_business_entities.csv"}


def _walk(exts):
    skip = {".git", "work", "__pycache__", ".cache", "node_modules", "rsconnect", "_to_delete"}
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in skip]
        for f in fn:
            if pathlib.Path(f).suffix.lower() in exts:
                yield pathlib.Path(dp) / f


def test_no_owner_or_grantee_column_in_any_committed_table():
    """An owner, mailing-address, grantor/grantee or name-key column in any committed CSV or GeoJSON anywhere in the repository (not only app/data and data/results)."""
    bad = []
    for p in _walk({".csv"}):
        with open(p, encoding="utf-8", errors="replace") as fh:
            head = fh.readline()
        cols = [c.strip().strip('"') for c in head.strip().split(",")]
        bad += [(str(p.relative_to(ROOT)), c) for c in cols if FORBIDDEN_COL.match(c)]
    key = re.compile(r'"(OWNER_?(NAME|ADDR[A-Z0-9_]*|CITY|STATE|ZIP)|GRANTOR[A-Z_]*|GRANTEE[A-Z_]*|MAIL(ING)?_?ADDR[A-Z0-9_]*)"\s*:', re.I)
    # the 1931-35 racial-covenant deeds (Denver Public Library's published file) name the parties to deeds of ninety years ago; see REPORT, RISK 9
    historical_deeds = {"denver_racial_covenants_1931_1935.geojson"}
    for p in _walk({".geojson"}):
        if p.stat().st_size > 30e6 or p.name in historical_deeds:
            continue
        with open(p, encoding="utf-8", errors="replace") as fh:
            if key.search(fh.read()):
                bad.append((str(p.relative_to(ROOT)), "geojson property"))
    assert not bad, bad[:15]


def test_private_work_files_are_not_committed_and_work_is_ignored():
    """A parcel, sales, owner-group or registry file copied out of work/ into the repository, or work/ no longer git-ignored."""
    hits = [str(p.relative_to(ROOT)) for p in _walk({".csv", ".rds", ".parquet", ".xlsx", ".json", ".txt"})
            if p.name in PRIVATE_FILES or "_private" in p.name.lower() or re.fullmatch(r"311_\d{4}\.csv", p.name)]
    assert not hits, hits
    gi = ROOT / ".gitignore"
    if gi.exists():
        assert re.search(r"^work/\s*$", gi.read_text(encoding="utf-8"), re.M)
    aud = ROOT / "data" / "raw" / "ownership" / "audited_addresses.csv"
    if aud.exists():
        a = pd.read_csv(aud, dtype=str)
        assert list(a.columns) == ["addr_md5"] and a.addr_md5.str.fullmatch(r"[0-9a-f]{32}").all()


def test_site_fate_free_text_fields_are_addresses_not_owners(S, H):
    """An owner or company name inside the situs-address field or the parcel-class field of the per-site files (names hidden in free text)."""
    files = [S, H, csv(SF / "site_fate_sensitive.csv"), csv(SF / "archival_followup_hidden_conversions.csv").rename(columns={"parcel_class_today": "D_CLASS_CN"})]
    for d in files:
        if "SITUS_ADDRESS_LINE1" in d:
            s = d.SITUS_ADDRESS_LINE1.dropna().astype(str)
            assert s.str.match(r"^\d+[A-Z]? ").all(), s[~s.str.match(r"^\d+[A-Z]? ")].head().tolist()
            assert not s.map(lambda v: bool(ENTITY.search(v))).any() and s.str.len().max() <= 45
            assert not s.str.contains(r"[@,;]").any()
        c = d.D_CLASS_CN.dropna().astype(str)
        assert not c.map(lambda v: bool(ENTITY.search(v))).any() and c.nunique() <= 80
    for d in (S, H):
        for col in ("ZONE_ID", "ZONE_10", "PROP_CLASS", "SCHEDNUM"):
            v = d[col].dropna().astype(str)
            assert v.str.fullmatch(r"[A-Za-z0-9 .+\-/]{1,20}").all(), col
