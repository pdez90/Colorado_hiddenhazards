"""Stage checks, review 4: health / mortality / CenSoc / enlistment / MLP result tables.

Stages: R/prepare_health_inputs.R, R/build_exposures.R, R/health_models.R, R/mortality_bg.R, pipeline/health/*.py,
R/mortality_block.R, R/mortality_redevelopment.R, R/censoc_denver_1940.R, R/censoc_extensions.R, R/censoc_enlistment.R,
R/mlp_residential_history.R, R/fetch_ipums_fullcount.R, R/fetch_ipums_mlp.R.

The death records and the person-level census / CenSoc / MLP files are restricted and are not in the repository, so the tests of
the committed files check what can be checked without them: every interval and p-value against its own estimate, nesting of the
model sequences, partitions of the samples that must add up, summaries (.md), manuscript tables and README against the .csv, small
cells, and constants that the scripts duplicate. Tests that need work/health, work/censoc or work/census skip when absent and print
aggregates only (never a person or death row).

Run:  STAGE_ROOT=/path/to/repo pytest test_stage_G_health_censoc.py     (or place the file in tests/stages/)
"""
import os
import pathlib
import re
import shutil
import subprocess

import numpy as np
import pandas as pd
import pytest
from scipy import stats

ROOT = pathlib.Path(os.environ["STAGE_ROOT"]) if os.environ.get("STAGE_ROOT") else pathlib.Path(__file__).resolve().parents[2]
RES = ROOT / "data" / "results"
CEN = RES / "censoc"
HEA = RES / "health"
MIN_CELL = 20          # smallest group the scripts publish (censoc_denver_1940.R: GR[n >= 20])
STATE_DEATHS_ALL, STATE_DEATHS_NAT = 189_606, 167_049   # Colorado deaths 2015-2019 in the death file (R/prepare_health_inputs.R log)


# ------------------------------------------------------------------------------------------------ helpers
def csv(path, **kw):
    return pd.read_csv(path, **kw)


def p_norm(est, se):
    return 2 * stats.norm.sf(np.abs(np.asarray(est, float) / np.asarray(se, float)))


def md_tables(path):
    """Every pipe table of a markdown file as (header, rows of strings)."""
    out, cur = [], []
    for line in list(pathlib.Path(path).read_text(encoding="utf-8").splitlines()) + [""]:
        if line.startswith("|"):
            cur.append([c.strip() for c in line.strip().strip("|").split("|")])
        elif cur:
            assert len(cur) >= 2 and set("".join(cur[1])) <= set("-: "), f"{path}: table without a separator row"
            out.append((cur[0], cur[2:])); cur = []
    return out


def same_cell(md, val):
    """A markdown cell against a csv value: numbers numerically (9 significant digits), blanks as missing, text trimmed."""
    if isinstance(val, (bool, np.bool_)):
        return md.strip().lower() == str(bool(val)).lower()
    if val is None or (isinstance(val, float) and np.isnan(val)):
        return md.strip() in ("", "NA")
    if isinstance(val, (int, float, np.integer, np.floating)):
        try:
            return bool(np.isclose(float(md), float(val), rtol=1e-9, atol=1e-12))
        except ValueError:
            return False
    return md.strip() == str(val).strip()


def assert_md_equals_csv(header, rows, d, what):
    assert header == list(d.columns), f"{what}: columns {header} != {list(d.columns)}"
    assert len(rows) == len(d), f"{what}: {len(rows)} rows in the summary, {len(d)} in the csv"
    bad = [(i, c, r[j], d.iloc[i][c]) for i, r in enumerate(rows) for j, c in enumerate(header) if not same_cell(r[j], d.iloc[i][c])]
    assert not bad, f"{what}: {len(bad)} cells differ, first {bad[:3]}"


def check_ci(d, est, what, half_unit, lo="lo", hi="hi", p="p", log=False, p_tol=0.15):
    """lo/hi must be est -/+ 1.96 SE (symmetric about est, on the log scale for ratios) and p must be the two-sided p of est/SE."""
    b, l, h = (np.log(d[c].astype(float)) if log else d[c].astype(float) for c in (est, lo, hi))
    assert (l <= b + half_unit).all() and (b <= h + half_unit).all(), f"{what}: estimate outside its interval"
    assert np.abs((l + h) / 2 - b).max() <= 2 * half_unit, f"{what}: interval not symmetric about the estimate"
    se = (h - l) / 3.92
    pn = p_norm(b, se)
    # rounding of est/lo/hi moves z a little; clustered-t p-values are a little larger than normal ones
    zlo = np.maximum(np.abs(b) - half_unit, 0) / (se + half_unit / 1.96); zhi = (np.abs(b) + half_unit) / np.maximum(se - half_unit / 1.96, 1e-12)
    p_hi, p_lo = 2 * stats.norm.sf(zlo), 2 * stats.norm.sf(zhi)
    pv = d[p].astype(float).to_numpy()
    ok = (pv <= p_hi * (1 + p_tol) + 1e-12) & (pv >= p_lo * (1 - p_tol) - 1e-12)
    assert ok.all(), f"{what}: p not consistent with estimate and interval in rows {list(np.where(~ok)[0][:5])} (p={pv[~ok][:3]}, normal p={pn[~ok][:3]})"


def utm(lon, lat):
    from pyproj import Transformer
    x, y = Transformer.from_crs(4326, 26913, always_xy=True).transform(np.asarray(lon, float), np.asarray(lat, float))
    return np.c_[x, y]


def max_neighbours(P, radius=2000.0):
    """Largest number of points within `radius` of any of the points themselves (a lower bound for any location)."""
    from scipy.spatial import cKDTree
    t = cKDTree(P)
    return max(len(j) for j in t.query_ball_point(P, radius))


def rsrc(name):
    return (ROOT / "R" / name).read_text(encoding="utf-8")


# ================================================================================================ tract health models
@pytest.fixture(scope="module")
def H():
    return csv(RES / "health_models.csv")


CHAIN = ["M1 SES", "M2 +regulated", "M3 +known historical", "M4 +hidden", "M4 +placebo"]
HVARS = ["z_tri", "z_cleanup", "z_prox_hazwaste", "z_prox_npl", "z_known_hist", "z_hidden", "z_placebo"]
K_PARAMS = {"M1 SES": 10, "M2 +regulated": 15, "M3 +known historical": 16, "M4 +hidden": 17, "Placebo: M2 +non-hazardous mfrs": 16, "M4 +placebo": 18}


def test_health_published_csv_is_the_R_table(H):
    """Catches health_models.csv drifting from health_models_R.csv (write_health_tables.py not rerun, or the Python script overwriting it)."""
    R = csv(RES / "health_models_R.csv")
    assert list(H.columns) == list(R.columns) and len(H) == len(R)
    assert (H[["outcome", "model"]] == R[["outcome", "model"]]).all().all()
    num = H.select_dtypes("number").columns
    assert np.allclose(H[num].to_numpy(float), R[num].to_numpy(float), rtol=1e-12, atol=0, equal_nan=True)


def test_health_layout_seven_outcomes_six_models_five_lr(H):
    """Catches a model or outcome silently missing from the table (a failed fit dropped by rbindlist)."""
    assert H.outcome.nunique() == 7
    for o, g in H.groupby("outcome"):
        assert sorted(g.model[~g.model.str.startswith("LR")]) == sorted(K_PARAMS), o
        assert (g.model.str.startswith("LR")).sum() == 5, o
    assert not H.duplicated(["outcome", "model"]).any()


def test_health_same_tracts_in_every_model_of_an_outcome(H):
    """Catches likelihood-ratio tests between models fit on different samples (NA in an added covariate changes n)."""
    m = H[~H.model.str.startswith("LR")]
    assert (m.groupby("outcome").n.nunique() == 1).all()
    assert m.n.between(1000, 1500).all()        # Colorado has 1,249 (2010) / 1,447 (2020) tracts


def test_health_p_values_follow_from_estimate_and_se(H):
    """Catches a coefficient, SE and p taken from different rows/models (column misalignment in the R-to-csv step)."""
    m = H[~H.model.str.startswith("LR")]
    for v in HVARS:
        s = m[m[v + "_b"].notna()]
        assert (s[v + "_se"] > 0).all()
        assert np.allclose(p_norm(s[v + "_b"], s[v + "_se"]), s[v + "_p"], rtol=1e-6, atol=1e-12), v
        assert s[v + "_p_ols"].between(0, 1).all() and s[v + "_b_ols"].notna().all()


def test_health_terms_present_exactly_in_the_models_that_contain_them(H):
    """Catches a specification list that lost or gained a term (e.g. the placebo model also carrying the hidden sites)."""
    m = H[~H.model.str.startswith("LR")].set_index(["outcome", "model"])
    has = {"z_known_hist": {"M3 +known historical", "M4 +hidden", "M4 +placebo"}, "z_hidden": {"M4 +hidden", "M4 +placebo"},
           "z_placebo": {"Placebo: M2 +non-hazardous mfrs", "M4 +placebo"}, "z_tri": set(K_PARAMS) - {"M1 SES"}, "z_cleanup": set(K_PARAMS) - {"M1 SES"}}
    for v, models in has.items():
        present = m[v + "_b"].notna()
        assert set(present[present].index.get_level_values("model")) == models, v
        assert present.groupby(level="model").nunique().max() == 1, v


def test_health_aic_is_minus_2_loglik_plus_2k(H):
    """Catches an AIC and log-likelihood from different fits, or a model with a different number of regressors than its label says."""
    m = H[~H.model.str.startswith("LR")]
    k = (m.aic_sem + 2 * m.logll_sem) / 2
    assert np.abs(k - m.model.map(K_PARAMS)).max() <= 0.06       # aic rounded to 0.1, logLik to 0.01


def test_health_loglik_and_r2_never_fall_when_terms_are_added(H):
    """Catches nested models that are not nested (different sample or weights matrix) or a failed ML optimisation."""
    pairs = list(zip(CHAIN[:-1], CHAIN[1:])) + [("M2 +regulated", "Placebo: M2 +non-hazardous mfrs"), ("Placebo: M2 +non-hazardous mfrs", "M4 +placebo")]
    for o, g in H[~H.model.str.startswith("LR")].groupby("outcome"):
        g = g.set_index("model")
        for small, big in pairs:
            assert g.logll_sem[big] >= g.logll_sem[small] - 0.011, (o, small, big)
            assert g.r2_ols[big] >= g.r2_ols[small] - 1e-4, (o, small, big)
        assert g.lambda_sem.abs().max() < 1 and g.r2_ols.between(0, 1).all()


def test_health_lr_rows_recompute_from_the_loglikelihoods(H):
    """Catches a likelihood-ratio statistic or its degrees of freedom (5 for the regulated block, 1 otherwise) computed wrongly."""
    for o, g in H.groupby("outcome"):
        ll = g.set_index("model").logll_sem
        for _, r in g[g.model.str.startswith("LR")].iterrows():
            big, small = r.model[3:].split(" vs ")
            assert abs(r.lr - 2 * (ll[big] - ll[small])) <= 0.045, (o, r.model)     # two logLik rounded to 0.01
            assert r.lr >= -0.045
            df = 5 if (big, small) == ("M2 +regulated", "M1 SES") else 1
            lo, hi = stats.chi2.sf(max(r.lr + 0.0051, 0), df), stats.chi2.sf(max(r.lr - 0.0051, 0), df)
            assert lo * (1 - 1e-9) <= r.lr_p <= hi * (1 + 1e-9), (o, r.model, r.lr_p, lo, hi)


def _star(p):
    return "***" if p < .001 else "**" if p < .01 else "*" if p < .05 else ""


def test_health_md_is_the_csv(H):
    """Catches health_models.md (pasted into the README) left over from an earlier run of the models."""
    (header, rows), = md_tables(RES / "health_models.md")
    assert len(rows) == 7
    for r in rows:
        g = H[H.outcome == r[0]].set_index("model")
        m4, m3, mp, lr = g.loc["M4 +hidden"], g.loc["M3 +known historical"], g.loc["M4 +placebo"], g.loc["LR M4 +hidden vs M3 +known historical"]
        want = [f"{m4.z_hidden_b:.3f} ({m4.z_hidden_se:.3f}){_star(m4.z_hidden_p)}", f"{m4.z_known_hist_b:.3f} ({m4.z_known_hist_se:.3f}){_star(m4.z_known_hist_p)}",
                f"{mp.z_placebo_b:.3f} ({mp.z_placebo_se:.3f}){_star(mp.z_placebo_p)}", f"{m4.aic_sem - m3.aic_sem:.1f}", f"{lr.lr_p:.3g}"]
        assert r[1:] == want, (r, want)


@pytest.mark.parametrize("md", ["health_models.md", "mortality_bg_models.md"])
def test_readme_carries_the_health_tables_verbatim(md):
    """Catches a README health / block-group mortality table that no longer equals the generated .md."""
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    missing = [l for l in (RES / md).read_text(encoding="utf-8").splitlines() if l.strip() and l not in readme]
    assert not missing, missing[:3]


# ================================================================================================ block-group mortality
@pytest.fixture(scope="module")
def BG():
    return csv(RES / "mortality_bg_models.csv")


BG_TERMS = {"M1 SES+age+PM2.5": set(), "M2 +regulated": set(), "M3 +known historical": {"z_known_hist"}, "M4 +hidden": {"z_known_hist", "z_hidden"},
            "M4 hidden high-confidence only": {"z_known_hist", "z_hidden_hiconf"}, "Placebo: M2 +non-hazardous mfrs": {"z_placebo"},
            "M4 +placebo": {"z_known_hist", "z_hidden", "z_placebo"}}
BG_NEST = [("M1 SES+age+PM2.5", "M2 +regulated", 5), ("M2 +regulated", "M3 +known historical", 1), ("M3 +known historical", "M4 +hidden", 1),
           ("M3 +known historical", "M4 hidden high-confidence only", 1), ("M2 +regulated", "Placebo: M2 +non-hazardous mfrs", 1),
           ("M4 +hidden", "M4 +placebo", 1), ("Placebo: M2 +non-hazardous mfrs", "M4 +placebo", 2)]


def test_bg_published_csv_is_the_R_table(BG):
    """Catches mortality_bg_models.csv drifting from mortality_bg_models_R.csv."""
    R = csv(RES / "mortality_bg_models_R.csv")
    assert list(BG.columns) == list(R.columns) and (BG[["outcome", "model"]] == R[["outcome", "model"]]).all().all()
    num = BG.select_dtypes("number").columns
    assert np.allclose(BG[num].to_numpy(float), R[num].to_numpy(float), rtol=1e-12, atol=0, equal_nan=True)


def test_bg_layout_and_terms(BG):
    """Catches a missing model, or an exposure term reported for a model that does not contain it."""
    assert sorted(BG.outcome.unique()) == ["deaths_all", "deaths_nat"]
    for o, g in BG.groupby("outcome"):
        assert list(g.model) == list(BG_TERMS), o
        for _, r in g.iterrows():
            got = {v for v in ("z_known_hist", "z_hidden", "z_hidden_hiconf", "z_placebo") if pd.notna(r[v + "_rr"])}
            assert got == BG_TERMS[r.model], (o, r.model, got)
            assert pd.notna(r.z_cleanup_rr) == (r.model != "M1 SES+age+PM2.5")


def test_bg_ci_is_exp_of_b_plus_minus_196_se_and_p_matches(BG):
    """Catches a rate-ratio interval built on the wrong scale (RR +/- 1.96 SE) or a p-value from another coefficient."""
    for v in [c[:-3] for c in BG.columns if c.endswith("_rr")]:
        s = BG[BG[v + "_rr"].notna()]
        b, lo, hi = np.log(s[v + "_rr"]), np.log(s[v + "_lo"]), np.log(s[v + "_hi"])
        assert (lo < b).all() and (b < hi).all()
        assert np.allclose((lo + hi) / 2, b, rtol=0, atol=1e-10), v
        assert np.allclose(p_norm(b, (hi - lo) / 3.92), s[v + "_p"], rtol=1e-6, atol=1e-12), v
        assert s[v + "_rr"].between(0.5, 2).all(), v           # per-SD ratios outside this range would mean an unstandardised exposure


def test_bg_one_sample_and_one_dispersion_per_outcome(BG):
    """Catches models of one outcome fit on different block groups or with different dispersion (AICs would not be comparable)."""
    for o, g in BG.groupby("outcome"):
        assert g.n.nunique() == 1 and g.deaths.nunique() == 1 and g.alpha.nunique() == 1 and (g.alpha > 0).all(), o
    assert BG.n.nunique() == 1 and 3000 <= BG.n.iloc[0] <= 3532         # Colorado has 3,532 block groups (2010)


def test_bg_aic_cannot_rise_by_more_than_two_per_added_term(BG):
    """Catches non-nested 'nested' models: with the dispersion held fixed, adding k terms can raise the AIC by at most 2k."""
    for o, g in BG.groupby("outcome"):
        a = g.set_index("model").aic
        for small, big, k in BG_NEST:
            assert a[big] <= a[small] + 2 * k + 0.11, (o, small, big, a[small], a[big])


def test_bg_md_is_the_csv(BG):
    """Catches mortality_bg_models.md (and so the README) not regenerated after the models."""
    text = (RES / "mortality_bg_models.md").read_text(encoding="utf-8")
    assert text.splitlines()[0] == f"Block groups: {int(BG.n.iloc[0])}, natural-cause deaths 2015-2019: {int(BG.deaths.iloc[0]):,}"
    (header, rows), = md_tables(RES / "mortality_bg_models.md")
    assert len(rows) == len(BG)

    def cell(r, v):
        if pd.isna(r[v + "_rr"]):
            return ""
        return f"{r[v + '_rr']:.3f} ({r[v + '_lo']:.3f}–{r[v + '_hi']:.3f})" + ("*" if r[v + "_p"] < .05 else "")
    for row, (_, r) in zip(rows, BG.iterrows()):
        hv = "z_hidden_hiconf" if "high-confidence" in r.model else "z_hidden"
        want = ["natural-cause" if r.outcome == "deaths_nat" else "all-cause", r.model, cell(r, hv), cell(r, "z_known_hist"), cell(r, "z_placebo"),
                cell(r, "z_cleanup"), f"{r.aic:.1f}"]
        assert row == want, (row, want)


# ================================================================================================ block mortality
@pytest.fixture(scope="module")
def BL():
    return csv(HEA / "mortality_block_models.csv")


BL_TERMS = {"M2 + regulated (TRI, cleanup)": {"tri", "cleanup"}, "M3 + known historical": {"tri", "cleanup", "known_hist"},
            "M4 + hidden": {"tri", "cleanup", "known_hist", "hidden"}, "M4 hidden high-confidence": {"tri", "cleanup", "known_hist", "hidden_hiconf"},
            "M5 + pre-1960 trades": {"tri", "cleanup", "known_hist", "hidden", "pre1960"}, "Placebo: non-hazardous manufacturers": {"tri", "cleanup", "placebo"},
            "M4 + placebo": {"tri", "cleanup", "known_hist", "hidden", "placebo"}}
BL_NEST = [("M2 + regulated (TRI, cleanup)", "M3 + known historical", 1), ("M3 + known historical", "M4 + hidden", 1), ("M3 + known historical", "M4 hidden high-confidence", 1),
           ("M4 + hidden", "M5 + pre-1960 trades", 1), ("M4 + hidden", "M4 + placebo", 1), ("M2 + regulated (TRI, cleanup)", "Placebo: non-hazardous manufacturers", 1),
           ("Placebo: non-hazardous manufacturers", "M4 + placebo", 2)]


def test_block_layout_terms_and_one_sample_per_fit_set(BL):
    """Catches a model reported with the wrong terms, duplicated rows, or models of one sample fit on different blocks."""
    assert not BL.duplicated(["sample", "outcome", "model", "term"]).any()
    assert set(BL["sample"]) == {"Colorado, all blocks with 100+ person-years", "Denver study area"} and set(BL.outcome) == {"natural causes", "all causes"}
    for (s, o, m), g in BL.groupby(["sample", "outcome", "model"]):
        assert set(g.term) == BL_TERMS[m], (s, o, m)
        assert g.aic.nunique() == 1
    assert (BL.groupby("sample")[["blocks", "tracts"]].nunique() == 1).all().all()
    b = BL.groupby("sample")[["blocks", "tracts"]].first()
    assert (b.loc["Denver study area"] < b.loc["Colorado, all blocks with 100+ person-years"]).all()
    assert b.tracts.max() <= 1249 and (b.blocks / b.tracts > 5).all()


def test_block_ci_and_p_consistent(BL):
    """Catches block-model intervals that are not exp(b +/- 1.96 SE), or p-values that do not belong to the ratio shown."""
    check_ci(BL, "rr", "mortality_block_models.csv", half_unit=6e-5, log=True, p_tol=0.02)
    assert BL.rr.between(0.5, 2).all()


def test_block_aic_nesting(BL):
    """Catches block models of a sample/outcome that are not nested as labelled (dispersion is held fixed, so AIC can rise by at most 2 per term)."""
    for (s, o), g in BL.groupby(["sample", "outcome"]):
        a = g.groupby("model").aic.first()
        for small, big, k in BL_NEST:
            assert a[big] <= a[small] + 2 * k + 0.11, (s, o, small, big)


def test_death_totals_are_ordered_block_blockgroup_state(BL, BG):
    """Catches a death count that cannot be right: modelled blocks hold more deaths than block groups, or either more than the state file."""
    t = csv(HEA / "mortality_block_totals.csv").set_index("sample")
    co, den = t.loc["Colorado, all blocks with 100+ person-years"], t.loc["Denver study area"]
    bg = BG.groupby("outcome").deaths.first()
    assert den.deaths_nat < den.deaths_all < co.deaths_all and den.deaths_nat < co.deaths_nat < co.deaths_all
    assert co.deaths_all <= bg["deaths_all"] <= STATE_DEATHS_ALL and co.deaths_nat <= bg["deaths_nat"] <= STATE_DEATHS_NAT
    assert bg["deaths_nat"] < bg["deaths_all"]
    assert 0.80 < co.deaths_nat / co.deaths_all < 0.95 and 0.80 < bg["deaths_nat"] / bg["deaths_all"] < 0.95     # natural causes are ~88% of deaths
    assert bg["deaths_all"] / STATE_DEATHS_ALL > 0.90        # block groups keep ~95% of the state's deaths


CO_BLOCKS = "Colorado, all blocks with 100+ person-years"
DISCLOSURE_MIN = 11        # smallest count of deaths that may be published (R/mortality_block.R combines smaller cells)


@pytest.fixture(scope="module")
def ACC():
    return csv(HEA / "mortality_block_death_accounting.csv")


def test_block_death_accounting_rows_sum_to_all_deaths(ACC):
    """Catches deaths lost between the death file and the block models without a stated reason: the rows must add up to every death of
    2015-2019 (all causes and natural causes; the script itself only checks all causes)."""
    assert list(ACC.columns) == ["status", "blocks", "deaths_all", "deaths_nat", "pct_deaths_all", "pct_deaths_nat"]
    assert ACC.status.is_unique and (ACC.status == "in the models").sum() == 1
    assert ACC.deaths_all.sum() == STATE_DEATHS_ALL and ACC.deaths_nat.sum() == STATE_DEATHS_NAT
    assert (ACC.deaths_nat <= ACC.deaths_all).all() and (ACC[["blocks", "deaths_all", "deaths_nat"]] >= 0).all().all()
    assert list(ACC.deaths_all) == sorted(ACC.deaths_all, reverse=True)


def test_block_death_accounting_shares(ACC):
    """Catches shares that are not deaths / all deaths of the state file (one decimal), or that do not add to 100."""
    assert np.allclose(ACC.pct_deaths_all, (100 * ACC.deaths_all / STATE_DEATHS_ALL).round(1), rtol=0, atol=1e-9)
    assert np.allclose(ACC.pct_deaths_nat, (100 * ACC.deaths_nat / STATE_DEATHS_NAT).round(1), rtol=0, atol=1e-9)
    assert abs(ACC.pct_deaths_all.sum() - 100) <= 0.05 * len(ACC) and abs(ACC.pct_deaths_nat.sum() - 100) <= 0.05 * len(ACC)


def test_block_death_accounting_in_the_models_row_is_the_model_sample(ACC, BL):
    """Catches an accounting table whose 'in the models' row is not the sample the block models were fit on."""
    r = ACC.set_index("status").loc["in the models"]
    t = csv(HEA / "mortality_block_totals.csv").set_index("sample").loc[CO_BLOCKS]
    assert (r.deaths_all, r.deaths_nat) == (t.deaths_all, t.deaths_nat)
    assert r.blocks == BL[BL["sample"] == CO_BLOCKS].blocks.iloc[0]
    assert any(s.startswith("fewer than 100 person-years 2015-2019") for s in ACC.status)        # the rule in the sample's name is a row of the table
    ms = (ROOT / "paper" / "Before_and_After_the_Map_manuscript.md").read_text(encoding="utf-8")
    assert f"{int(r.blocks):,} blocks" in ms and f"{int(r.deaths_nat):,} natural-cause deaths" in ms


def test_block_death_accounting_has_no_cell_under_11_deaths(ACC):
    """Catches a published count of deaths below the disclosure minimum."""
    small = ACC[(ACC.deaths_all < DISCLOSURE_MIN) | (ACC.deaths_nat < DISCLOSURE_MIN)]
    assert small.empty, small[["status", "blocks"]].to_dict("records")


def test_block_models_keep_the_share_of_deaths_the_text_states(ACC):
    """Catches a text that does not say what share of the deaths the block models keep (was FINDING 1: loss not accounted for in any output)."""
    pct = ACC.set_index("status").loc["in the models"].pct_deaths_nat
    ms = (ROOT / "paper" / "Before_and_After_the_Map_manuscript.md").read_text(encoding="utf-8")
    para = next(l for l in ms.splitlines() if "132,051 natural-cause deaths" in l or "assigned to the 2010 census block" in l)
    assert re.search(r"\b%s(?:\.0)?\s?%%" % f"{pct:.0f}", para) or f"{pct:.1f}%" in para, pct


def test_block_summary_md_is_the_csv(BL):
    """Catches mortality_block_summary.md out of step with mortality_block_models.csv."""
    (header, rows), = md_tables(HEA / "mortality_block_summary.md")
    sub = BL[BL.term.isin(["hidden", "hidden_hiconf", "known_hist", "pre1960", "placebo"]) &
             BL.model.isin(["M4 + hidden", "M4 hidden high-confidence", "M5 + pre-1960 trades", "M3 + known historical", "Placebo: non-hazardous manufacturers"])]
    assert len(rows) == len(sub)
    for row, (_, r) in zip(rows, sub.iterrows()):
        assert row[:4] == [r["sample"], r.outcome, r.model, r.term]
        assert abs(float(row[4]) - r.rr) <= 5.1e-4
        lo, hi = (float(x) for x in re.fullmatch(r"(\d+\.\d+)-(\d+\.\d+)", row[5]).groups())
        assert abs(lo - r.lo) <= 5.1e-4 and abs(hi - r.hi) <= 5.1e-4
        assert np.isclose(float(row[6]), r.p, rtol=0.06, atol=6e-5)      # format(p, digits = 2) on the column


def _generated(name):
    text = (ROOT / "paper" / "tables_generated.md").read_text(encoding="utf-8")
    m = re.search(r"<!-- table: %s ;.*?-->\n(.*?)(?:\n\n|\Z)" % re.escape(name), text, re.S)
    assert m, name
    lines = m.group(1).splitlines()
    return [[c.strip() for c in l.strip().strip("|").split("|")] for l in lines[2:]], lines[2:]


def _nums(cell):
    return [float(x.replace("−", "-")) for x in re.findall(r"[−-]?\d+\.\d+", cell)]


def test_paper_table21_block_mortality_from_csv(BL):
    """Catches Table 21 cells taken from the wrong model/term/sample of the block-mortality csv (independent of paper/make_tables.py)."""
    rows, raw = _generated("s7_block_mortality")
    spec = [("M4 + hidden", "known_hist"), ("M4 + placebo", "known_hist"), ("M4 + hidden", "hidden"), ("M4 hidden high-confidence", "hidden_hiconf"),
            ("M5 + pre-1960 trades", "pre1960"), ("Placebo: non-hazardous manufacturers", "placebo")]
    cols = [("Colorado, all blocks with 100+ person-years", "natural causes"), ("Colorado, all blocks with 100+ person-years", "all causes"), ("Denver study area", "natural causes")]
    assert len(rows) == len(spec)
    for row, (model, term) in zip(rows, spec):
        for cell, (s, o) in zip(row[1:], cols):
            r = BL[(BL["sample"] == s) & (BL.outcome == o) & (BL.model == model) & (BL.term == term)].iloc[0]
            assert np.allclose(_nums(cell), [r.rr, r.lo, r.hi], rtol=0, atol=5.1e-4), (row[0], s, o, cell)
    ms = (ROOT / "paper" / "Before_and_After_the_Map_manuscript.md").read_text(encoding="utf-8")
    assert all(l in ms for l in raw)


# ================================================================================================ redevelopment panel
@pytest.fixture(scope="module")
def RD():
    return csv(HEA / "mortality_redevelopment_models.csv"), csv(HEA / "mortality_redevelopment_event.csv")


def test_redevelopment_ci_p_and_layout(RD):
    """Catches fixed-effects Poisson ratios whose interval or p does not follow from the estimate, or a missing group/lead/lag."""
    R, E = RD
    check_ci(R, "rr", "mortality_redevelopment_models.csv", half_unit=6e-5, log=True, p_tol=0.03)
    check_ci(E, "rr", "mortality_redevelopment_event.csv", half_unit=6e-5, log=True, p_tol=0.03)
    for o, g in R.groupby("outcome"):
        assert g.n_obs.nunique() == 1
        assert sorted(g[g.model == "All three groups together"].term) == ["hidden", "known", "pre1960"]
        assert sorted(g[g.model.str.startswith("One group")].term) == ["hidden", "known", "pre1960"]
    for o, g in E.groupby("outcome"):
        assert list(g.years_since_rebuild) == ["-4 or earlier", "-3", "-2", "0", "1", "2", "3", "4 or later"]     # -1 is the reference
        assert g.n_obs.nunique() == 1
    assert E.rebuilt_blocks.nunique() == 1 and E.comparison_blocks.nunique() == 1
    assert (R.groupby("outcome").n_obs.first()["deaths_nat"] <= R.groupby("outcome").n_obs.first()["deaths_all"])   # blocks with no death drop out


def test_redevelopment_summary_md_is_the_csvs_and_counts_fit(RD):
    """Catches a summary whose tables differ from the csvs, or sample sizes that exceed the panel they are drawn from."""
    R, E = RD
    path = HEA / "mortality_redevelopment_summary.md"
    tabs = md_tables(path)
    assert [t[0][0] for t in tabs] == ["year", "group", "model", "outcome"]
    assert_md_equals_csv(tabs[2][0], tabs[2][1], R, "redevelopment models")
    assert_md_equals_csv(tabs[3][0], tabs[3][1], E, "redevelopment event study")
    head = path.read_text(encoding="utf-8").splitlines()[2]
    blocks, block_years, deaths_nat, y0, y1 = (int(x.replace(",", "")) for x in re.fullmatch(
        r"([\d,]+) blocks, ([\d,]+) block-years, ([\d,]+) natural-cause deaths, years (\d{4})-(\d{4})\.", head).groups())
    years = [int(r[0]) for r in tabs[0][1]]; pct = [float(r[1]) for r in tabs[0][1]]
    assert years == list(range(2000, 2020)) and min(pct) >= 0 and max(pct) <= 100
    kept = [y for y, p in zip(years, pct) if p >= 90]
    assert (y0, y1) == (min(kept), max(kept))
    assert block_years <= blocks * len(kept) and R.n_obs.max() <= block_years
    assert E.n_obs.max() <= (E.rebuilt_blocks.iloc[0] + E.comparison_blocks.iloc[0]) * len(kept)
    assert E.rebuilt_blocks.iloc[0] + E.comparison_blocks.iloc[0] <= blocks
    assert 0.5 < deaths_nat / (len(kept) * 4500) < 1.5       # Denver County: roughly 4,000-5,000 deaths a year


def test_redevelopment_site_table_recomputes_from_site_fate():
    """Catches the rebuilt / standing site counts (quoted in the paper: 20 hidden, 51 known, 38 pre-1960 rebuilt in 2000-2019) drifting from site_fate."""
    tabs = md_tables(HEA / "mortality_redevelopment_summary.md")
    got = {r[0]: [int(x) for x in r[1:]] for r in tabs[1][1]}
    years = [int(r[0]) for r in tabs[0][1] if float(r[1]) >= 90]
    F = csv(RES / "site_fate" / "site_fate_denver.csv"); F2 = csv(RES / "site_fate" / "site_fate_denver_pre1960.csv")
    assert not F.site_id.duplicated().any() and not F2.hfirm.duplicated().any()

    def counts(d):
        d = d.dropna(subset=["lat", "lon"])
        rb = np.where(d.year_built.notna() & (d.year_built > d.last_year), d.year_built, np.inf)
        return [len(d), int(((rb >= min(years)) & (rb <= max(years))).sum()), int((rb < min(years)).sum()), int((rb > max(years)).sum())]
    want = {"hidden": counts(F[F.radar == "Not on any list"]), "known": counts(F[F.radar != "Not on any list"]), "pre1960": counts(F2)}
    assert got == want
    assert all(v[0] == v[1] + v[2] + v[3] for v in got.values())


def test_redevelopment_summary_names_its_sample_correctly():
    """Catches the summary heading naming a different sample from the one the script models (County of Denver, GEOID prefix 08031)."""
    src = rsrc("mortality_redevelopment.R")
    assert 'substr(den_tr$GEOID, 1, 5) == "08031"' in src and "core" not in src.split("# ---")[1]
    assert "study area" not in (HEA / "mortality_redevelopment_summary.md").read_text(encoding="utf-8").splitlines()[0]


# ================================================================================================ kernel exposures (code vs data)
def _k_cap(src, pattern):
    m = re.search(pattern, src)
    assert m, pattern
    return int(m.group(1))


def test_every_script_uses_the_same_kernel_500m_bandwidth_2km_cutoff():
    """Catches one copy of the Gaussian kernel (there are eight) changing bandwidth or cutoff while the text says 500 m / 2 km everywhere."""
    for f in ["build_exposures.R", "mortality_bg.R", "mortality_block.R", "mortality_redevelopment.R", "censoc_denver_1940.R", "mlp_residential_history.R"]:
        s = rsrc(f)
        bw = set(re.findall(r"exp\(-0\.5 \* \(\w+ / (\w+)\)\^2\)", s))
        assert bw and bw <= {"500", "SIG"}, (f, bw)
        if "SIG" in bw:
            assert re.search(r"SIG <- 500\b", s) and re.search(r"CUT <- 2000\b", s), f
        else:
            assert "2000" in s, f
    for f in ["build_exposures.py", "mortality_bg.py"]:
        s = (ROOT / "pipeline" / "health" / f).read_text(encoding="utf-8")
        assert ("SIG, CUT = 500.0, 2000.0" in s) or ("/ 500) ** 2" in s and "2000" in s), f


def test_nearest_neighbour_caps_do_not_truncate_the_kernel_censoc_and_mlp():
    """Catches RANN::nn2(k = cap) silently dropping sites within 2 km once a layer grows past the cap (CenSoc 200 / 300, MLP 100)."""
    Hs = csv(ROOT / "app" / "data" / "historical_sites.csv")
    Hs = Hs[(Hs.town == "DENVER") & (Hs.precision != "town") & Hs.lat.notna() & (Hs.fe_hazard == True)]   # noqa: E712
    cs = rsrc("censoc_denver_1940.R"); ml = rsrc("mlp_residential_history.R")
    cap_haz = _k_cap(cs, r"nn2\(hx, as\.matrix\(U\[, \.\(x, y\)\]\), k = min\(nrow\(hx\), (\d+)\)")
    cap_sites = _k_cap(cs, r"nn2\(px, UXY, k = min\(nrow\(px\), (\d+)\)")
    cap_mlp = _k_cap(ml, r"nn2\(hk, xy, k = min\(nrow\(hk\), (\d+)\)")
    upto40 = Hs[Hs.first_year <= 1940]
    assert max_neighbours(utm(upto40.lon, upto40.lat)) < cap_haz
    for yr in (1910, 1920, 1930, 1940):
        w = Hs[(Hs.first_year <= yr) & (Hs.last_year >= yr - 9)]
        assert len(w) <= cap_mlp, (yr, len(w))                      # 98 of 100 in the 1911-1920 window: no headroom
    S = csv(ROOT / "app" / "data" / "sites.csv")
    S = S[(S.fe_hazard == True) & S.geo_level.isin(["address", "address_approx"])]   # noqa: E712
    for g in (S[S.radar == "Not on any list"], S[S.radar != "Not on any list"]):
        assert max_neighbours(utm(g.lon, g.lat)) < cap_sites


def test_nearest_neighbour_cap_does_not_truncate_the_kernel_redevelopment():
    """Catches the redevelopment kernel being truncated at the nn2 cap instead of the documented 2 km cutoff."""
    cap = _k_cap(rsrc("mortality_redevelopment.R"), r"nn2\(sxy, CXY, k = min\(nrow\(S\), (\d+)\)")
    F = pd.concat([csv(RES / "site_fate" / "site_fate_denver.csv")[["lat", "lon"]], csv(RES / "site_fate" / "site_fate_denver_pre1960.csv")[["lat", "lon"]]]).dropna()
    assert max_neighbours(utm(F.lon, F.lat)) <= cap


def test_exposure_layers_are_usable_points_in_colorado():
    """Catches an exposure layer with missing or out-of-state coordinates, an unlabelled radar status, or hidden + known not adding to all sites."""
    A = ROOT / "app" / "data"
    S = csv(A / "sites.csv")
    fe = S[S.fe_hazard == True]   # noqa: E712
    assert S.radar.notna().all() and S.confidence.notna().all() and set(S.geo_level) <= {"address", "address_approx"}
    assert (fe.radar == "Not on any list").sum() + (fe.radar != "Not on any list").sum() == len(fe)
    assert ((fe.radar == "Not on any list") & (fe.confidence == "high")).sum() < (fe.radar == "Not on any list").sum()
    for f in ["sites.csv", "tri_facilities.csv", "cleanup_sites.csv"]:
        d = csv(A / f)
        assert d.lat.notna().all() and d.lon.notna().all(), f
        assert d.lat.between(36.9, 41.1).all() and d.lon.between(-109.1, -102.0).all(), f
    L = csv(RES / "CO_directory_listings_1961-2002.csv", dtype={"sic": str}, low_memory=False)
    a = L[L.geo_level == "address"]
    assert a.lat.notna().all() and a.lon.notna().all()        # R/build_exposures.R and R/mortality_bg.R index the placebo by a vector built after dropping NA coordinates


def _placebo_points(sic_filter):
    from scipy.spatial import cKDTree
    S = csv(ROOT / "app" / "data" / "sites.csv")
    L = csv(RES / "CO_directory_listings_1961-2002.csv", dtype={"sic": str}, low_memory=False)
    nh = L[(L.geo_level == "address") & ~(L.fe_hazard | L.ext_hazard) & ~L.site_id.isin(S.site_id)]
    if sic_filter:
        nh = nh[pd.to_numeric(nh.sic.str[:2], errors="coerce").between(20, 39)]
    nh = nh.assign(k=nh.lat.map("{:.4f}".format) + nh.lon.map("{:.4f}".format)).drop_duplicates("k")
    fe = S[S.fe_hazard == True]   # noqa: E712
    d, _ = cKDTree(utm(fe.lon, fe.lat)).query(utm(nh.lon, nh.lat))
    return nh[d > 100]


def test_placebo_is_manufacturers_sic_20_39_away_from_hazardous_sites():
    """Catches the placebo set emptying or admitting non-manufacturers / listings at a hazardous site (recomputed from the committed listings)."""
    for f in ["build_exposures.R", "mortality_bg.R", "mortality_block.R"]:
        assert re.search(r"%between% c\(20L, 39L\)", rsrc(f)), f
    P = _placebo_points(True)
    assert 2000 < len(P) < 3500                                      # 2,697 points at commit 2a2610e
    assert pd.to_numeric(P.sic.str[:2]).between(20, 39).all() and not (P.fe_hazard | P.ext_hazard).any()


def test_python_health_scripts_define_the_placebo_as_the_R_scripts_do():
    """Catches the R and Python versions of the health tables resting on different placebo sets."""
    for f in ["build_exposures.py", "mortality_bg.py"]:
        s = (ROOT / "pipeline" / "health" / f).read_text(encoding="utf-8")
        assert re.search(r"between\(20, ?39\)|20 ?<=.*<= ?39", s), f
    # (the unfiltered and filtered sets differ by construction: 2,852 against 2,697 points at commit 2a2610e; what must agree is the rule)
    assert len(_placebo_points(False)) > len(_placebo_points(True))


def test_hazardous_industry_codes_are_the_same_in_both_scripts():
    """Catches the IND1950 hazardous-industry list of R/censoc_denver_1940.R drifting from R/fetch_ipums_fullcount.R."""
    def codes(expr):
        out = set()
        for a, b in re.findall(r"(\d+):(\d+)", expr):
            out |= set(range(int(a), int(b) + 1))
        return out
    a = codes(re.search(r"HAZ_IND <- c\(([^)]*)\)", rsrc("censoc_denver_1940.R")).group(1))
    b = codes(re.search(r"haz_industry = na0\(IND1950\) %in% c\(([^)]*)\)", rsrc("fetch_ipums_fullcount.R")).group(1))
    assert a == b and len(a) == 34 + 4 * 4 + 4 + 3


# ================================================================================================ CenSoc: age at death
@pytest.fixture(scope="module")
def C():
    d = {f.stem: csv(f) for f in CEN.glob("*.csv")}
    assert len(d) == 18
    return d


DMF, NUM = "DMF (men, deaths 1975 on)", "Numident (men and women, deaths 1988-2005)"
EXT_DMF, EXT_NUM = "Men, deaths 1975-2020 (CenSoc-DMF)", "Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident)"


def n_models(C):
    m = C["censoc_models"]
    assert (m.groupby("file").n.nunique() == 1).all()
    return m.groupby("file").n.first()


def test_censoc_models_ci_is_estimate_plus_minus_196_se_and_p_matches(C):
    """Catches lo/hi not equal to years -/+ 1.96 SE, or p from another term, in the main age-at-death table."""
    m = C["censoc_models"]
    assert np.abs(m.lo - (m.years - 1.96 * m.se)).max() <= 0.0025 and np.abs(m.hi - (m.years + 1.96 * m.se)).max() <= 0.0025
    check_ci(m, "years", "censoc_models.csv", half_unit=5.1e-4)
    assert not m.duplicated(["file", "model", "term", "exposure"]).any()
    assert m.years.abs().max() < 5            # years of life per unit; anything larger means an unscaled exposure


def test_censoc_models_layout(C):
    """Catches a missing exposure/model in the main table (fit() returns NULL silently when a term has no variation)."""
    m = C["censoc_models"]
    assert set(m.file) == {DMF, NUM}
    for f, g in m.groupby("file"):
        assert len(g) == 24, f                                        # 8 exposures x M1, M2 (+ M3 for six of them) + 2 joint rows
        assert (g.model.str.startswith("M3")).sum() == 6 and (g.model == "M2 joint").sum() == 2
        assert set(g.term) == {"haz_kz", "haz_500", "ind10", "com10", "zone_ind", "hidden_kz", "known_kz", "holc_D"}


def test_censoc_linkage_funnel_is_monotone_and_windows_hold(C):
    """Catches a join that duplicates people (more linked than residents, more modelled than linked) or deaths outside the files' windows."""
    L = C["censoc_linkage"].set_index("file"); n = n_models(C)
    census = L.loc["1940 census, Denver residents"]
    assert abs(census.linked - 322_412) / 322_412 < 0.01               # Denver's 1940 census population
    assert census.with_address_point <= census.linked
    for f in (DMF, NUM):
        r = L.loc[f]
        assert n[f] <= r.with_address_point <= r.linked < census.with_address_point
        assert r.with_address_point / r.linked > 0.6
    assert (L.loc[NUM].min_dyear, L.loc[NUM].max_dyear) == (1988, 2005)
    assert L.loc[DMF].min_dyear == 1975 and L.loc[DMF].max_dyear <= 2020
    assert 65 <= L.loc[NUM].median_death_age <= 95 and 65 <= L.loc[DMF].median_death_age <= 95


def test_censoc_groups_partition_the_model_sample(C):
    """Catches group means computed on a different sample from the models: each measure's groups must add up to the model n."""
    g = C["censoc_groups"]; n = n_models(C)
    assert (g.n >= MIN_CELL).all()
    for (f, measure), s in g.groupby(["file", "measure"]):
        # a group under 20 is suppressed, so the sum may fall short by less than 20 per missing group
        assert n[f] - 2 * MIN_CELL < s.n.sum() <= n[f], (f, measure, s.n.sum(), n[f])
    assert g.adj_mean_age_at_death.between(65, 100).all()              # CenSoc weights cover deaths at 65-100
    assert set(g[g.measure == "1938 HOLC grade"].group) == {"A", "B", "C", "D", "ungraded"}


def test_censoc_extension_samples_partition_the_model_sample(C):
    """Catches a subgroup model fit on the wrong file or sample: age groups, tenure groups and stayers/leavers must add up."""
    n = n_models(C); N = {EXT_DMF: n[DMF], EXT_NUM: n[NUM]}
    ch = C["censoc_ext_childhood"]
    for p, g in ch.groupby("people"):
        per = g.groupby("age_in_1940").n.agg(["nunique", "first"])
        assert (per["nunique"] == 1).all() and per["first"].sum() == N[p], p
        assert len(per) == 3
    gr = C["censoc_ext_groups"]
    for p, g in gr.groupby("people"):
        per = g.groupby("group").n.first()
        assert per["Renting household"] + per["Owner household"] == N[p], p
        assert per["White, not Hispanic"] + per["Hispanic"] <= N[p]
    wh = C["censoc_ext_work_home"]
    for p, g in wh.groupby("people"):
        assert set(g[g.analysis.str.contains("veryone")].n) == {N[p]}
        men = set(g[g.analysis.str.contains("labour force")].n)
        assert len(men) == 1 and men.pop() < N[p]
    dp = C["censoc_ext_displacement"]
    assert set(dp.groupby("people").n.first().items()) == set(N.items()) and (dp.groupby("people").n.nunique() == 1).all()
    st = C["censoc_ext_stayers"]; sh = C["censoc_ext_stayers_shares"]
    lpm = st[st.analysis.str.startswith("Died in the Denver metro")].n.unique()
    stay = st[st.analysis.str.contains("who died in the Denver metro")].n.unique(); leave = st[st.analysis.str.contains("elsewhere")].n.unique()
    assert len(lpm) == len(stay) == len(leave) == 1
    assert stay[0] + leave[0] == lpm[0] == sh.people.sum() <= N[EXT_NUM]
    assert abs((sh.people * sh.pct_died_denver_metro).sum() / sh.people.sum() - 100 * stay[0] / lpm[0]) < 3      # weighted share vs unweighted count


@pytest.mark.parametrize("name,est,half", [("censoc_ext_childhood", "years", 5.1e-4), ("censoc_ext_displacement", "years", 5.1e-4), ("censoc_ext_stayers", "years", 5.1e-3),
                                           ("censoc_ext_work_home", "years", 5.1e-4), ("censoc_ext_groups", "years", 5.1e-4), ("mlp_models", "years", 5.1e-4),
                                           ("enlistment_models", "estimate", 5.1e-4), ("censoc_ext_linkage_models", "pct_points", 5.1e-4)])
def test_censoc_family_ci_symmetric_and_p_consistent(C, name, est, half):
    """Catches an interval that is not estimate +/- 1.96 SE or a p that belongs to another coefficient, in every CenSoc-family table."""
    check_ci(C[name], est, name, half_unit=half, p_tol=0.2)


def test_censoc_small_cells_and_no_person_level_columns(C):
    """Catches a published count under 20 people, a model on fewer people than the scripts' floors, or a person identifier in a public file."""
    count_cols = ["n", "linked", "with_address_point", "people", "n_1940", "residents_1940", "men_1940", "with_height", "n_exposed"]
    for name, d in C.items():
        assert len(d) <= 100, name                                      # aggregate tables only
        assert not [c for c in d.columns if re.search(r"histid|serial|pernum|^name$|ssn|^addr$|^b_hn|street|^lat$|^lon$|^x$|^y$", c, re.I)], name
        for c in count_cols:
            if c in d.columns and pd.api.types.is_numeric_dtype(d[c]):
                assert d[c].dropna().min() >= MIN_CELL, (name, c, d[c].min())
    floors = {"censoc_ext_childhood": 200, "censoc_ext_groups": 200, "censoc_ext_work_home": 200, "censoc_ext_stayers": 200, "mlp_models": 200, "enlistment_models": 150}
    for name, floor in floors.items():
        assert C[name].n.min() >= floor, name
    assert C["censoc_ext_displacement"].n_exposed.min() >= 30
    for f in list(HEA.glob("*.csv")) + [RES / "mortality_bg_models.csv", RES / "health_models.csv"]:
        d = csv(f)
        assert len(d) <= 120 and not [c for c in d.columns if re.search(r"^bck$|^bg$|geoid|^tract$|^block$", c, re.I)], f.name   # no small-area rows


def test_censoc_gompertz_consistent_with_the_ols_sample(C):
    """Catches a Gompertz fit on more people than the OLS sample, a hazard ratio outside its interval, or e65 with the sign of the hazard."""
    g = C["censoc_ext_gompertz"]; n = n_models(C)
    assert g.converged.all() and len(g) == 10
    assert ((g.hr_lower <= g.hr) & (g.hr <= g.hr_upper)).all() and ((g.e65_lower <= g.e65_years) & (g.e65_years <= g.e65_upper)).all()
    assert (np.sign(np.log(g.hr).round(2)) * np.sign(g.e65_years.round(1)) <= 0).all()      # higher hazard, fewer years
    d, m = g[g.people == EXT_DMF], g[g.people == EXT_NUM]
    assert set(d.window) == {"1975-2005"} and set(m.window) == {"1988-2005"}
    assert d.n.nunique() == 1 and d.n.iloc[0] < n[DMF]                 # DMF deaths after 2005 are left out of the Gompertz check
    assert m.n.nunique() == 1 and m.n.iloc[0] == n[NUM]                # every Numident death is inside 1988-2005


def test_censoc_linkage_shares_and_models_agree(C):
    """Catches the 'who is linked' shares and linear-probability models being run on different sets of 1940 residents."""
    s = C["censoc_ext_linkage_shares"]; m = C["censoc_ext_linkage_models"].groupby("outcome").n.first()
    men = s[s.people.str.startswith("Men")].n_1940.sum(); women = s[s.people.str.startswith("Women")].n_1940.sum(); allp = s[s.people.str.startswith("Everyone")].n_1940.sum()
    assert men == m["linked_dmf"] and men + women == m["linked_num"] == allp
    assert s.pct_linked_numident.between(0, 100).all() and s.pct_linked_dmf.dropna().between(0, 100).all()
    L = C["censoc_linkage"].set_index("file")
    assert allp <= L.loc["1940 census, Denver residents"].with_address_point
    # linked men aged 0-50 with an address cannot outnumber all linked men with an address
    linked_men = (s[s.people.str.startswith("Men")].n_1940 * s[s.people.str.startswith("Men")].pct_linked_dmf / 100).sum()
    assert linked_men <= L.loc[DMF].with_address_point * 1.001
    w = C["censoc_ext_displacement_who"]
    assert allp < w.residents_1940.sum() <= L.loc["1940 census, Denver residents"].with_address_point
    d = C["censoc_ext_displacement"]
    for (p, fe), g in d.groupby(["people", "ed_fixed_effects"]):
        e = g.set_index("term").n_exposed
        row, cl, both = e["1940 address in a later freeway's path (within 75 m)"], e["1940 address on residential land cleared by 1977"], e["in a freeway's path or cleared"]
        assert max(row, cl) <= both <= row + cl, (p, fe)


@pytest.mark.parametrize("md,tables", [("censoc_extensions_summary.md", ["censoc_ext_childhood", "censoc_ext_stayers_shares", "censoc_ext_stayers", "censoc_ext_work_home",
                                                                        "censoc_ext_groups", "censoc_ext_linkage_shares", "censoc_ext_linkage_models", "censoc_ext_gompertz",
                                                                        "censoc_ext_displacement_who", "censoc_ext_displacement"]),
                                       ("enlistment_summary.md", ["enlistment_shares", "enlistment_models"]),
                                       ("mlp_summary.md", ["mlp_persistence", "mlp_exposure_windows", "mlp_models"])])
def test_censoc_summaries_equal_their_csvs(C, md, tables):
    """Catches a summary .md written by a different run from the csv beside it (the two are written by separate calls)."""
    tabs = md_tables(CEN / md)
    assert len(tabs) == len(tables), md
    for (header, rows), name in zip(tabs, tables):
        assert_md_equals_csv(header, rows, C[name], f"{md}:{name}")


def test_censoc_summary_md_equals_its_csvs(C):
    """Catches censoc_summary.md out of step with censoc_linkage / censoc_models / censoc_groups."""
    tabs = md_tables(CEN / "censoc_summary.md")
    assert len(tabs) == 3
    assert_md_equals_csv(tabs[0][0], tabs[0][1], C["censoc_linkage"], "linkage")
    assert_md_equals_csv(tabs[2][0], tabs[2][1], C["censoc_groups"], "groups")
    m = C["censoc_models"]; header, rows = tabs[1]
    assert header == ["file", "model", "exposure", "years", "ci", "p", "n"] and len(rows) == len(m)
    for row, (_, r) in zip(rows, m.iterrows()):
        assert row[:3] == [r.file, r.model, r.exposure] and same_cell(row[3], r.years) and same_cell(row[5], r.p) and same_cell(row[6], r.n)
        lo, hi = (float(x) for x in re.fullmatch(r"(-?\d+\.\d+) to (-?\d+\.\d+)", row[4]).groups())
        assert abs(lo - r.lo) <= 0.0051 and abs(hi - r.hi) <= 0.0051


def test_paper_table22_censoc_from_csv(C):
    """Catches Table 22 cells from the wrong file/model/term of censoc_models.csv (independent of paper/make_tables.py)."""
    rows, raw = _generated("s7_censoc_table22")
    m = C["censoc_models"]
    terms = ["zone_ind", "ind10", "haz_500", "haz_kz", "com10", "holc_D", "hidden_kz", "known_kz"]
    cols = [(DMF, "M1: birth year (and sex) only"), (DMF, "M2: + 1940 person and household controls"), (NUM, "M1: birth year (and sex) only"),
            (NUM, "M2: + 1940 person and household controls")]
    assert len(rows) == len(terms)
    for row, t in zip(rows, terms):
        for cell, (f, model) in zip(row[1:], cols):
            r = m[(m.file == f) & (m.model == model) & (m.term == t)].iloc[0]
            assert np.allclose(_nums(cell), [r.years, r.lo, r.hi], rtol=0, atol=0.0051), (t, f, model, cell)
    ms = (ROOT / "paper" / "Before_and_After_the_Map_manuscript.md").read_text(encoding="utf-8")
    assert all(l in ms for l in raw)


# ================================================================================================ enlistment
def test_enlistment_samples_add_up(C):
    """Catches enlistment models and the by-address table resting on different men (shares must add to the model n; BMI needs height and weight)."""
    e = C["enlistment_models"]; s = C["enlistment_shares"]
    n = e.groupby(["sample", "outcome"]).n.agg(["nunique", "first"])
    assert (n["nunique"] == 1).all()
    n = n["first"]; men, boys = "Men born 1905-1927", "Boys aged 13-17 in 1940"
    assert s.men_1940.sum() == n[men, "Enlisted (percentage points)"]
    assert s.with_height.sum() == n[men, "Height (inches)"]
    for smp in (men, boys):
        assert n[smp, "Body-mass index"] <= min(n[smp, "Height (inches)"], n[smp, "Weight (pounds)"])
        assert n[smp, "Height (inches)"] < n[smp, "Years of schooling at enlistment"] < n[smp, "Enlisted (percentage points)"]
    for o in e.outcome.unique():
        assert n[boys, o] < n[men, o], o
    mean = e.groupby(["sample", "outcome"]).outcome_mean.first()
    assert abs((s.men_1940 * s.pct_enlisted).sum() / s.men_1940.sum() - mean[men, "Enlisted (percentage points)"]) < 0.1
    assert abs(n[men, "Years of schooling at enlistment"] / n[men, "Enlisted (percentage points)"] * 100 - mean[men, "Enlisted (percentage points)"]) < 2.5
    assert len(e) == 2 * 5 * 7 and not e.duplicated(["sample", "outcome", "exposure"]).any()


def test_enlistment_outcome_means_are_physically_plausible(C):
    """Catches unscreened codes in the enlistment height / weight / schooling fields (the script applies no range filter of its own)."""
    e = C["enlistment_models"]; mean = e.groupby("outcome").outcome_mean.agg(["min", "max"])
    assert 66 <= mean.loc["Height (inches)", "min"] and mean.loc["Height (inches)", "max"] <= 71
    assert 135 <= mean.loc["Weight (pounds)", "min"] and mean.loc["Weight (pounds)", "max"] <= 165
    assert 19 <= mean.loc["Body-mass index", "min"] and mean.loc["Body-mass index", "max"] <= 25
    assert 8 <= mean.loc["Years of schooling at enlistment", "min"] and mean.loc["Years of schooling at enlistment", "max"] <= 17
    s = C["enlistment_shares"]
    assert s.mean_height.between(66, 71).all() and s.mean_weight.between(135, 165).all() and s.mean_school_years.between(8, 17).all()
    # BMI from the mean height and weight must be near the mean BMI
    assert abs(703 * mean.loc["Weight (pounds)", "max"] / mean.loc["Height (inches)", "min"] ** 2 - mean.loc["Body-mass index", "max"]) < 1


def test_paper_table23_enlistment_from_csv(C):
    """Catches Table 23 cells from the wrong sample/outcome/exposure of enlistment_models.csv (independent of paper/make_tables.py)."""
    rows, raw = _generated("s7_enlistment_table23")
    e = C["enlistment_models"]
    exps = ["1929 industrial district", "Industrial land within 250 m, 1937 (per 10 points)", "Hazardous trade within 500 m (to 1940)", "HOLC grade D (vs A/B)",
            "Major road open in 1940 within 100 m", "Placebo: commercial land within 250 m (per 10 points)"]
    cols = [("Men born 1905-1927", "Years of schooling at enlistment", 0.0051), ("Men born 1905-1927", "Height (inches)", 0.0051), ("Men born 1905-1927", "Weight (pounds)", 0.051),
            ("Boys aged 13-17 in 1940", "Years of schooling at enlistment", 0.0051)]
    assert len(rows) == len(exps)
    for row, x in zip(rows, exps):
        for cell, (s, o, tol) in zip(row[1:], cols):
            r = e[(e["sample"] == s) & (e.outcome == o) & (e.exposure == x)].iloc[0]
            assert np.allclose(_nums(cell), [r.estimate, r.lo, r.hi], rtol=0, atol=tol), (x, s, o, cell)
    ms = (ROOT / "paper" / "Before_and_After_the_Map_manuscript.md").read_text(encoding="utf-8")
    assert all(l in ms for l in raw)


# ================================================================================================ MLP residential histories
def test_mlp_exposure_windows_recompute_from_historical_sites(C):
    """Catches the per-census site counts and directory years (which decide which censuses are 'comparable') drifting from the pre-1960 layer."""
    w = C["mlp_exposure_windows"].set_index("census")
    Hs = csv(ROOT / "app" / "data" / "historical_sites.csv")
    Hs = Hs[(Hs.town == "DENVER") & (Hs.precision != "town") & Hs.lat.notna() & (Hs.fe_hazard == True)]   # noqa: E712
    allyears = {int(t) for s in Hs.years.astype(str) for t in re.split(r"[^0-9]+", s) if t}
    assert list(w.index) == [1910, 1920, 1930, 1940]
    for yr, r in w.iterrows():
        assert r.window == f"{yr - 9}-{yr}"
        assert r.hazardous_sites_listed == ((Hs.first_year <= yr) & (Hs.last_year >= yr - 9)).sum(), yr
        assert str(r.directory_years_with_a_denver_listing).split() == [str(y) for y in sorted(allyears) if yr - 9 <= y <= yr], yr
        assert bool(r.comparable) == (r.hazardous_sites_listed >= 20)
        assert 0 <= r.pct_residents_within_500m <= 100


def test_mlp_persistence_and_models_are_coherent(C):
    """Catches persistence shares outside 0-100, groups that shrink between censuses, or models with more people than were traced."""
    p = C["mlp_persistence"]; L = C["censoc_linkage"].set_index("file"); n = n_models(C)
    pct = [c for c in p.columns if c.startswith("pct_")]
    assert p[pct].stack().between(0, 100).all() and (p.pct_within_100m_of_1940_address <= p.pct_within_1km).all()
    tot = p.groupby("census").residents_1940.sum()
    assert list(tot.index) == [1910, 1920, 1930] and tot.is_monotonic_increasing and tot.max() <= L.loc["1940 census, Denver residents"].with_address_point
    assert (p.groupby("census").address_1940.nunique() == 3).all()
    for g, s in p.groupby("address_1940"):
        s = s.sort_values("census")
        assert s.residents_1940.is_monotonic_increasing and s.pct_linked.is_monotonic_increasing, g   # more people were alive, and more are linked, at later censuses
    m = C["mlp_models"]
    assert len(m) == 14 and set(m.people) == {"Men, deaths 1975-2020", "Men and women, deaths at 65+ 1988-2005"}
    for people, full in (("Men, deaths 1975-2020", n[DMF]), ("Men and women, deaths at 65+ 1988-2005", n[NUM])):
        g = m[m.people == people]
        assert g.n.max() < full
        traced = g[g.term.isin(["mean_pct10", "top_share", "censuses_near_haz"])].n
        assert traced.nunique() == 1
        assert g[g.term == "mean_pct10_good"].n.iloc[0] <= traced.iloc[0]
        child = g[g.model.str.contains("hildhood")].n
        assert len(child) == 2 and child.nunique() == 1


# ================================================================================================ restricted inputs (author's machine)
def _need(*paths):
    missing = [str(p) for p in paths if not pathlib.Path(p).exists()]
    if missing:
        pytest.skip("restricted / work input not present: " + ", ".join(missing))


def test_work_deaths_by_block_group_totals_and_keys():
    """Catches a changed death file or a lossy aggregation: 189,606 deaths 2015-2019 (167,049 natural), one row per block group x year x cause."""
    f = ROOT / "work" / "health" / "deaths_bg_year.csv"; _need(f)
    d = pd.read_csv(f, dtype={"bg": str})
    assert not d.duplicated(["bg", "year", "natural_cause"]).any()
    assert d.bg.str.fullmatch(r"08\d{10}").all() and (d.deaths > 0).all() and d.year.between(2000, 2020).all()
    w = d[d.year.between(2015, 2019)]
    assert w.deaths.sum() == STATE_DEATHS_ALL, int(w.deaths.sum())
    assert w[w.natural_cause == 1].deaths.sum() == STATE_DEATHS_NAT, int(w[w.natural_cause == 1].deaths.sum())
    assert set(d.natural_cause.dropna().unique()) <= {0, 1} and d.natural_cause.notna().all()
    bg = csv(RES / "mortality_bg_models.csv").groupby("outcome").deaths.first()
    assert bg["deaths_all"] <= STATE_DEATHS_ALL and bg["deaths_nat"] <= STATE_DEATHS_NAT


def test_work_block_group_exposures_one_row_per_block_group():
    """Catches duplicated or missing block groups in the exposure file, negative densities, or hidden + known not adding to all historical sites."""
    f = ROOT / "work" / "health" / "bg_exposures_R.csv"; _need(f)
    e = pd.read_csv(f, dtype={"GEOID": str, "tract": str})
    assert e.GEOID.is_unique and e.GEOID.str.fullmatch(r"08\d{10}").all() and (e.tract == e.GEOID.str[:11]).all()
    kd = [c for c in e.columns if c.endswith("_kd")]; n1 = [c for c in e.columns if c.endswith("_n1k")]
    assert len(kd) == 9 and (e[kd] >= 0).all().all() and e[kd].notna().all().all()
    assert np.allclose(e.hidden_kd + e.known_hist_kd, e.hist_all_kd, atol=1e-8) and (e.hidden_n1k + e.known_hist_n1k == e.hist_all_n1k).all()
    assert (e.hidden_hiconf_kd <= e.hidden_kd + 1e-9).all() and (e.hidden_persist10_kd <= e.hidden_kd + 1e-9).all()
    assert (e[n1] == e[n1].round()).all().all() and (e.area_km2 > 0).all()
    for c in kd:                                                        # a count within 1 km implies a kernel of at least exp(-2) per site
        assert (e[c] >= e[c.replace("_kd", "_n1k")] * np.exp(-2) - 1e-9).all(), c


def test_work_tract_analysis_file_matches_the_published_sample_sizes():
    """Catches a tract file with duplicated tracts or fewer usable tracts than the n the health table reports."""
    f = ROOT / "work" / "health" / "tract_analysis_R.csv"; _need(f)
    a = pd.read_csv(f, dtype={"tract": str})
    assert a.tract.is_unique
    H = csv(RES / "health_models.csv"); n = H[~H.model.str.startswith("LR")].groupby("outcome").n.first()
    big = a[a.population >= 500]
    assert n.max() <= len(big)
    for col, label in [("heart_dis", "Heart disease (index)"), ("cancer", "Cancer (index)"), ("diabetes", "Diabetes (index)"), ("mental_health", "Poor mental health (%)")]:
        assert n[label] <= big[col].notna().sum()
    for col, label in [("asthma_hosp", "Asthma hospitalization rate (log)"), ("low_birth_wt", "Low birth weight (%)"), ("life_exp", "Life expectancy (years)")]:
        assert n[label] <= (big[col] > 0).sum()


def test_work_block_age_file_unique_blocks_and_shares():
    """Catches duplicated blocks or impossible age shares in the 2010 block age file that the block models merge on."""
    f = ROOT / "work" / "census" / "blocks_2010_age.csv"; _need(f)
    a = pd.read_csv(f, dtype={"bck": str})
    assert a.bck.is_unique and a.bck.str.fullmatch(r"08\d{13}").all()
    assert a.pct_65plus.between(0, 100).all() and a.pct_under5.between(0, 100).all() and ((a.pct_65plus + a.pct_under5) <= 100.01).all()
    assert abs(a.pop2010.sum() - 5_029_196) <= 5                         # Colorado, 2010 census


R_CHECK = r"""
suppressPackageStartupMessages(library(data.table))
P <- as.data.table(readRDS("work/censoc/denver_1940_residents.rds")); L <- as.data.table(readRDS("work/censoc/censoc_denver_1940_linked.rds"))
K <- fread("data/results/censoc/censoc_linkage.csv"); M <- fread("data/results/censoc/censoc_models.csv")
out <- c(dup_residents = sum(duplicated(P$HISTID)), dup_linked = sum(duplicated(L[, .(histid, file)])),
         residents = nrow(P) - K[file %like% "^1940", linked], residents_xy = sum(!is.na(P$x)) - K[file %like% "^1940", with_address_point],
         linked_not_in_census = sum(!L$histid %in% P$HISTID))
for (f in unique(L$file)) { d <- L[file == f]
  out[paste("linked", substr(f, 1, 3))] <- nrow(d) - K[file == f, linked]
  out[paste("xy", substr(f, 1, 3))] <- sum(!is.na(d$x)) - K[file == f, with_address_point]
  s <- d[!is.na(x) & !is.na(byear) & !is.na(death_age) & gq == 0 & !is.na(weight) & weight > 0]
  out[paste("model_n", substr(f, 1, 3))] <- nrow(s) - M[file == f, n][1]
  out[paste("age_outside_65_100", substr(f, 1, 3))] <- sum(s$death_age < 65 | s$death_age > 100)
  out[paste("one_person_two_points", substr(f, 1, 3))] <- sum(duplicated(s$histid)) }
cat(paste(names(out), out, sep = "=", collapse = "\n"), "\n")
"""


def test_work_censoc_person_files_have_unique_people_and_the_published_n():
    """Catches a merge that duplicates people (household heads per SERIAL, GRF rows per HISTID, geocodes per address) and n that differ from the tables."""
    _need(ROOT / "work" / "censoc" / "denver_1940_residents.rds", ROOT / "work" / "censoc" / "censoc_denver_1940_linked.rds")
    if not shutil.which("Rscript"):
        pytest.skip("Rscript not available")
    r = subprocess.run(["Rscript", "-e", R_CHECK], cwd=ROOT, capture_output=True, text=True, timeout=50)
    assert r.returncode == 0, r.stderr[-500:]
    vals = dict(l.split("=") for l in r.stdout.strip().splitlines())      # aggregates only; no person rows are printed
    assert all(int(v) == 0 for v in vals.values()), vals
