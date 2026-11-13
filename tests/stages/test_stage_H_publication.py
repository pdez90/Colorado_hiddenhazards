"""Stage H (publication layer and cross-stage flow): README / app / manuscript / SI text, the claims registry, the app manifest,
the orchestration scripts and the stage manifest (stages.yml).

Reads committed files only. Lives in tests/stages/ with new_claims.yml and stages.yml beside it; run as
    STAGE_ROOT=/path/to/repo pytest test_stage_H_publication.py
A test marked xfail(strict=True) documents a defect found in review 4 (see REPORT.md); remove the marker when it is fixed.
"""
import fnmatch
import hashlib
import html
import json
import os
import re
import sys
import zipfile
from pathlib import Path

import pandas as pd
import pytest
import yaml

HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ["STAGE_ROOT"]) if os.environ.get("STAGE_ROOT") else Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests" / "outputs"))
import outputs_helpers as C  # noqa: E402  (the claims helpers of tests/outputs; they resolve paths from their own location)
import test_claims as TC  # noqa: E402

assert Path(C.REPO).resolve() == ROOT.resolve(), "outputs_helpers resolves a different repository than STAGE_ROOT"

README = (ROOT / "README.md").read_text(encoding="utf-8")
APP = (ROOT / "app" / "app.R").read_text(encoding="utf-8")
MS = (ROOT / "paper" / "Before_and_After_the_Map_manuscript.md").read_text(encoding="utf-8")
RERUN = (ROOT / "rerun_results.sh").read_text(encoding="utf-8")
RUN_ALL = (ROOT / "run_all.sh").read_text(encoding="utf-8")
STAGES = yaml.safe_load((HERE / "stages.yml").read_text(encoding="utf-8"))
NEW_CLAIMS = yaml.load((HERE / "new_claims.yml").read_text(encoding="utf-8"), Loader=TC._Loader)
OLD_CLAIMS = TC.CLAIMS

NUM = re.compile(r"(?<![A-Za-z0-9_./#-])[−+-]?\d(?:\d|,(?=\d{3}))*(?:\.\d+)?(?![\d]*[A-Za-z_/])")


def _is_year(tok):
    return re.fullmatch(r"(18[5-9]\d|19\d\d|20[0-2]\d)", tok.lstrip("+−-")) is not None


# ----------------------------------------------------------------------------------------------------------- claims
def _claim_param(c):
    marks = [pytest.mark.xfail(strict=True, reason=str(c["stale"]))] if c.get("stale") else []
    return pytest.param(c, id=c["id"], marks=marks)


@pytest.mark.parametrize("claim", [_claim_param(c) for c in NEW_CLAIMS])
def test_new_claim(claim):
    """A number in README / app / manuscript prose that claims.yml did not cover no longer matches the committed data (or its sentence was edited)."""
    TC.test_claim(claim)


def test_new_claim_ids_do_not_collide_with_the_registry():
    """A new claim silently shadows an existing one when both files are merged."""
    ids = [c["id"] for c in NEW_CLAIMS]
    assert len(ids) == len(set(ids))
    assert not set(ids) & {c["id"] for c in OLD_CLAIMS}


def _expected_values_missing_from_text(c):
    exp = c["expect"] if isinstance(c["expect"], list) else [c["expect"]]
    printed = [abs(float(m.group().replace(",", "").replace("−", "-"))) for m in NUM.finditer(c["text"].replace("\\u2013", "–"))]
    return [e for e in exp if not isinstance(e, bool) and not any(abs(abs(float(e)) - p) < 1e-9 for p in printed)]


# claims whose `expect` holds values that the anchored `text` does not print (a boolean flag, a count that sits on the next line of
# the prose, a rounded "about half"): for those values the test would keep passing if the prose number were edited. Review-4 baseline.
EXPECT_NOT_IN_TEXT_BASELINE = 42


def test_claim_expected_values_are_printed_in_the_anchored_text():
    """A claim checks a number that its `text` does not contain, so editing that number in the prose is not caught (ratchet: may only go down)."""
    loose = [c["id"] for c in OLD_CLAIMS if _expected_values_missing_from_text(c)]
    assert len(loose) <= EXPECT_NOT_IN_TEXT_BASELINE, f"{len(loose)} claims check values absent from their text (baseline {EXPECT_NOT_IN_TEXT_BASELINE}): {loose}"
    new_loose = [c["id"] for c in NEW_CLAIMS if _expected_values_missing_from_text(c)
                 and c["id"] not in ("h_readme_sanborn_sheets_and_ordinances", "h_readme_health_placebo_prose", "h_readme_mortality_bg_md_is_the_readme_table",
                                     "h_readme_mortality_bg_natural_reaches_threshold", "h_readme_ej_panel_tract_years", "h_readme_mortality_bg_table_rows_all_cause",
                                     "h_paper_sanborn_dwellings", "h_paper_site_fate_current_use", "h_paper_hidden_share", "h_paper_freeways_by_grade")]
    assert not new_loose, new_loose


@pytest.mark.xfail(strict=True, reason="FINDING 9: readme_pre1960_town_share checks firm-locations (87.8% at town level) for a sentence about entries (90.0%) and passes only through tol: 5")
def test_about_90pct_claim_measures_entries_not_firm_locations():
    """A claim passes for the wrong reason: the check computes a different quantity from the one the sentence states and a wide tolerance hides it."""
    c = next(c for c in OLD_CLAIMS if c["id"] == "readme_pre1960_town_share")
    got = float(eval(c["check"], dict(TC.NAMESPACE, __builtins__={})))
    listings = pd.read_csv(ROOT / "data/historical/CO_pre1960_hazardous_listings.csv", dtype=str, keep_default_na=False)
    assert abs(got - 100 * (listings.precision == "town").mean()) < 0.5


def _uncovered_numbers(body, file, claims, lo=0, hi=None, skip_line=lambda ln: False):
    spans = []
    for c in claims:
        if c["file"] != file:
            continue
        k = body.find(c["text"])
        while k >= 0:
            spans.append((k, k + len(c["text"])))
            k = body.find(c["text"], k + 1)
    out, pos = [], 0
    for i, ln in enumerate(body.split("\n"), 1):
        if lo < i and (hi is None or i < hi) and not skip_line(ln):
            masked = re.sub(r"`[^`]*`|https?://\S+", lambda m: " " * len(m.group()), ln)
            for m in NUM.finditer(masked):
                if not _is_year(m.group()) and not any(a <= pos + m.start() < b for a, b in spans):
                    out.append((i, m.group()))
        pos += len(ln) + 1
    return out


def test_number_coverage_of_the_claims_registry_does_not_shrink():
    """New prose numbers are added to README or the manuscript without a claim (ratchet on the count of non-year numbers outside any claim text)."""
    allc = OLD_CLAIMS + NEW_CLAIMS
    in_code = [False]

    def readme_skip(ln):
        if ln.startswith("```"):
            in_code[0] = not in_code[0]
            return True
        return in_code[0]

    readme_unc = _uncovered_numbers(README, "README.md", allc, skip_line=readme_skip)
    refs = next(i for i, ln in enumerate(MS.split("\n"), 1) if ln.startswith("## References"))
    ms_unc = _uncovered_numbers(MS, "paper/Before_and_After_the_Map_manuscript.md", allc, lo=8, hi=refs,
                                skip_line=lambda ln: ln.startswith("|") or ln.startswith("#"))
    # review-4 baselines, measured with claims.yml + new_claims.yml (most of the remainder are method parameters, dates and table cells)
    assert len(readme_unc) <= 404, f"README: {len(readme_unc)} numbers outside any claim (baseline 404)"
    assert len(ms_unc) <= 829, f"manuscript prose: {len(ms_unc)} numbers outside any claim (baseline 829)"


# ----------------------------------------------------------------------------------------------- cross-document agreement
def test_dc_ratio_by_period_agrees_between_data_readme_and_manuscript():
    """The D/C firm-density ratios quoted in README and manuscript drift from holc_industry_periods.csv (the app's copy of this sentence is FINDING 1)."""
    d = pd.read_csv(ROOT / "data/results/holc/holc_industry_periods.csv")
    r = {p: f"{d[d.period == p].dc_ratio_within_period.iloc[0]:.1f}" for p in ("1906-1920", "1921-1937", "1938-1956", "1965-1980", "1981-1992")}
    for p, v in r.items():
        a, b = p.split("-")
        short = f"{a}–{b[2:]}"
        assert re.search(rf"{re.escape(v)}×\s+in {short}", README.replace("\n", " ")), (p, v, "README")
    assert f"D/C {r['1938-1956']}, against {r['1906-1920']} in 1906–20 and {r['1921-1937']} in 1921–37" in MS
    # recompute the ratio a second way, from firms per edition and area
    for p in ("1906-1920", "1921-1937", "1938-1956", "1965-1980", "1981-1992"):
        g = d[d.period == p].set_index("grade")
        ratio = (g.loc["D", "firms_per_edition"] / g.loc["D", "km2"]) / (g.loc["C", "firms_per_edition"] / g.loc["C", "km2"])
        assert abs(ratio - float(r[p])) < 0.06, (p, ratio)


def test_headline_counts_agree_across_readme_manuscript_si_and_app_data():
    """README, manuscript and SI state different totals for the same inventory (sites, hidden sites, Denver sites, pre-1960 Denver trades)."""
    s = C.fe_sites()
    n, h = len(s), len(C.hidden_sites())
    den = len(pd.read_csv(ROOT / "data/results/site_fate/site_fate_denver.csv"))
    pre = len(pd.read_csv(ROOT / "data/results/site_fate/site_fate_denver_pre1960.csv"))
    si = " ".join(b.get("text", "") for b in json.load(open(ROOT / "paper/si/si_blocks.json", encoding="utf-8")))
    for doc, name in ((README, "README"), (MS, "manuscript"), (si, "SI")):
        assert f"{n:,}" in doc, (name, n)
    for doc, name in ((README, "README"), (MS, "manuscript")):
        assert f"{h:,}" in doc, (name, h)
    for doc, name in ((MS, "manuscript"), (si, "SI")):
        assert f"{den:,}" in doc, (name, den)
    assert f"Of the {pre} pre-1960 hazardous trades" in MS and f"({pre} Denver hazardous-sector firm-locations" in README


def test_manuscript_names_no_files_scripts_or_person_level_sources():
    """The manuscript leaks repository internals (file names, script names, work/ paths) or names restricted person-level files."""
    body = MS[: MS.index("## References")]
    for pat in (r"\.csv\b", r"\.R\b", r"\.py\b", r"\.geojson\b", r"\.xlsx\b", r"Rscript", r"data/results", r"app/data", r"\bwork/", r"CO_HIA",
                r"top_owners", r"HISTID", r"co_deaths_official", r"IPUMS_API_KEY"):
        assert not re.search(pat, body), pat
    assert not re.search(r"(owner|landlord) names? (is|are|were) (listed|given|shown)", body)


# --------------------------------------------------------------------------------------------------------------- SI, tables
def test_si_docx_contains_every_block_of_si_blocks_json():
    """The SI .docx was not rebuilt (node build_si.js) after si_blocks.json changed, so the Word file states older numbers."""
    blocks = json.load(open(ROOT / "paper/si/si_blocks.json", encoding="utf-8"))
    xml = zipfile.ZipFile(ROOT / "paper/Before_and_After_the_Map_SI.docx").read("word/document.xml").decode("utf-8")
    paras = {html.unescape("".join(re.findall(r"<w:t[^>]*>(.*?)</w:t>", p, re.S))).strip() for p in re.findall(r"<w:p[ >].*?</w:p>", xml, re.S)}
    missing = []
    for b in blocks:
        if b["type"] == "table":
            texts = [b["caption"]] + [c["text"] for r in b["rows"] for c in r if c["text"].strip()]
        else:
            texts = [b["text"]]
        missing += [t[:80] for t in texts if t.strip() not in paras]
    assert not missing, f"{len(missing)} SI block texts are not in the .docx, e.g. {missing[:3]}"


def test_si_and_manuscript_name_the_same_source_for_the_business_directory_scans():
    """Prose reused from si_prose_base.json contradicts the reconciled manuscript on a fact that make_si.py does not check."""
    si = " ".join(b.get("text", "") for b in json.load(open(ROOT / "paper/si/si_blocks.json", encoding="utf-8")))
    assert "34 editions digitised by the University of Colorado Boulder Libraries" in MS
    assert "Denver Public Library has scanned 34 editions" not in si


def test_si_and_manuscript_agree_on_shared_table_ns():
    """An SI table states a different n from the manuscript for the same model set (change models: 61 tracts; boundary bands; 147 tracts)."""
    si = " ".join(b.get("text", "") + " " + b.get("caption", "") for b in json.load(open(ROOT / "paper/si/si_blocks.json", encoding="utf-8")))
    m = pd.read_csv(ROOT / "data/results/holc/holc_tract_models.csv")
    assert m.n.nunique() == 1 and f"with {int(m.n.iloc[0])} tracts" in MS
    g = pd.read_csv(ROOT / "data/results/denver_eds/ed_year_groups.csv")
    d40 = g[(g.census == 1940) & g.group.str.startswith("dissimilarity")].iloc[0]
    assert f"{int(d40.population):,}" in MS and f"{int(d40.population):,}" in si


def test_tables_generated_md_is_what_make_tables_builds():
    """paper/tables_generated.md is older than the data: a builder's row is missing from the committed file."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("make_tables_stage_h", ROOT / "paper" / "make_tables.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["make_tables_stage_h"] = mod   # dataclasses / namedtuples resolve the module by name
    spec.loader.exec_module(mod)
    lines = set((ROOT / "paper" / "tables_generated.md").read_text(encoding="utf-8").splitlines())
    missing = [(b.__name__, r) for b in mod.TABLES for r in b().rows if r not in lines]
    assert not missing, missing[:3]


# ---------------------------------------------------------------------------------------------------------------------- app
def _app_cards():
    """(line, header, has unit_note, has data output, is map) for every bslib card( call in app.R; parentheses matched outside strings."""
    src, n = APP, len(APP)
    mask, j = list(src), 0
    while j < n:
        ch = src[j]
        if ch == "#":
            k = src.find("\n", j)
            k = n if k < 0 else k
            mask[j:k] = " " * (k - j)
            j = k
            continue
        if ch in "\"'":
            k = j + 1
            while k < n and src[k] != ch:
                k += 2 if src[k] == "\\" else 1
            for t in range(j + 1, min(k, n)):
                if src[t] != "\n":
                    mask[t] = " "
            j = k + 1
            continue
        j += 1
    m = "".join(mask)
    out = []
    for mm in re.finditer(r"(?<![A-Za-z0-9_.])card\(", m):
        depth, k = 0, mm.end() - 1
        while k < n:
            depth += (m[k] == "(") - (m[k] == ")")
            if depth == 0:
                break
            k += 1
        mb, body = m[mm.start(): k + 1], src[mm.start(): k + 1]
        h = re.search(r'card_header\(\s*"((?:[^"\\]|\\.)*)"', body)
        out.append((src.count("\n", 0, mm.start()) + 1, h.group(1)[:70] if h else "(no header)", "unit_note(" in mb,
                    bool(re.search(r"plotlyOutput\(|tableOutput\(|DTOutput\(|plotOutput\(", mb)), "leafletOutput(" in mb))
    return out


def test_app_has_cards_and_most_state_their_spatial_unit():
    """The card parser broke or unit notes were dropped wholesale (at review 4: 119 cards, 102 with a 'Spatial unit:' note)."""
    cards = _app_cards()
    assert len(cards) >= 100
    assert sum(c[2] for c in cards) >= 102


def test_every_app_card_with_a_plot_or_table_states_its_spatial_unit():
    """A card that shows a statistic does not say whether it counts sites, tracts, districts, blocks, parcels or people."""
    bad = [(ln, hdr) for ln, hdr, unit, data, is_map in _app_cards() if data and not unit]
    assert not bad, bad


def test_app_manifest_and_app_folder_hold_the_same_files():
    """A file was added under app/ (or removed) without regenerating manifest.json, so Posit Connect would not deploy it."""
    man = json.load(open(ROOT / "app" / "manifest.json", encoding="utf-8"))["files"]
    disk = {str(Path(dp, f).relative_to(ROOT / "app")).replace(os.sep, "/") for dp, _, fs in os.walk(ROOT / "app") for f in fs}
    disk -= {"manifest.json"}
    disk = {f for f in disk if "rsconnect/" not in f and not f.endswith((".Rhistory", ".RData"))}
    assert disk == set(man), {"not in manifest": sorted(disk - set(man))[:10], "not on disk": sorted(set(man) - disk)[:10]}
    stale = [f for f in sorted(disk) if hashlib.md5((ROOT / "app" / f).read_bytes()).hexdigest() != man[f]["checksum"]]
    assert not stale, stale[:10]


# ------------------------------------------------------------------------------------------------- orchestration and stages
def _steps():
    return re.search(r"STEPS=\((.*?)\)", RERUN, re.S).group(1).split()


def _rerun_order():
    tail = re.findall(r"Rscript R/(\w+)\.R", RERUN.split("for s in")[1]) + re.findall(r"python3 (pipeline/\S+\.py)", RERUN)
    return _steps() + tail


def _match(pat, f):
    g, _, ex = pat.partition("!")
    return fnmatch.fnmatchcase(f, g) and not (ex and fnmatch.fnmatchcase(os.path.basename(f), ex))


def _committed(roots):
    return sorted(str(Path(dp, f).relative_to(ROOT)).replace(os.sep, "/") for r in roots for dp, _, fs in os.walk(ROOT / r) for f in fs)


def test_every_committed_file_is_declared_once():
    """An orphan file (written by no declared stage), or a file two stages both claim, sits under data/results, data/historical, data/by_year or app/data."""
    owners = {}
    for f in _committed(STAGES["roots"]):
        o = [(s["id"], "output") for s in STAGES["stages"] if any(_match(p, f) for p in s["outputs"])]
        o += [(s["id"], "copy") for s in STAGES["stages"] if any(_match(p, f) for p in s.get("copies", []))]
        o += [("unscripted", "unscripted") for u in STAGES["unscripted"] if u["path"] == f]
        owners[f] = o
    undeclared = [f for f, o in owners.items() if not o]
    multiple = {f: o for f, o in owners.items() if len(o) > 1}
    assert not undeclared, f"{len(undeclared)} committed files are the output of no declared stage: {undeclared[:10]}"
    assert not multiple, f"declared more than once: {list(multiple.items())[:5]}"


def test_declared_patterns_and_unscripted_files_exist():
    """stages.yml declares an output that is no longer committed (renamed or dropped result), so the manifest is stale."""
    files = _committed(STAGES["roots"])
    dead = [(s["id"], p) for s in STAGES["stages"] for p in s["outputs"] + s.get("copies", []) if not any(_match(p, f) for f in files)]
    assert not dead, dead
    assert all((ROOT / u["path"]).is_file() for u in STAGES["unscripted"])
    assert all((ROOT / s["script"]).is_file() for s in STAGES["stages"]), [s["script"] for s in STAGES["stages"] if not (ROOT / s["script"]).is_file()]


def test_declared_copies_are_byte_identical_to_an_output_of_the_same_stage():
    """An app/data copy differs from the result file it is declared to copy (the app would show numbers other than data/results)."""
    files = _committed(STAGES["roots"])
    md5 = lambda f: hashlib.md5((ROOT / f).read_bytes()).hexdigest()  # noqa: E731
    bad = []
    for s in STAGES["stages"]:
        outs = {md5(f) for f in files if any(_match(p, f) for p in s["outputs"])}
        bad += [(s["id"], f) for f in files if any(_match(p, f) for p in s.get("copies", [])) and md5(f) not in outs]
    assert not bad, bad[:10]


def test_stage_run_by_matches_the_orchestration_scripts():
    """stages.yml says a script is run by an orchestrator that does not call it (or 'none' for one that is called)."""
    wrong = []
    for s in STAGES["stages"]:
        name = s["script"]
        code = lambda t: "\n".join(ln for ln in t.splitlines() if not ln.lstrip().startswith("#"))  # noqa: E731  (comments mention scripts that are NOT run)
        in_rerun = (name.startswith("R/") and Path(name).stem in _rerun_order()) or name in code(RERUN)
        in_runall = name in code(RUN_ALL)
        actual = "rerun_results.sh" if in_rerun else "run_all.sh" if in_runall else "none"
        if actual != s["run_by"]:
            wrong.append((s["id"], s["run_by"], actual))
    assert not wrong, wrong


def test_every_r_script_is_a_stage_a_step_a_fetcher_or_a_library():
    """A new R script writes results but no orchestrator runs it and stages.yml does not know it."""
    known = {Path(s["script"]).stem for s in STAGES["stages"] if s["script"].startswith("R/")} | set(_rerun_order())
    run_all_r = (ROOT / "R" / "run_all.R").read_text(encoding="utf-8")
    other = []
    for p in sorted((ROOT / "R").glob("*.R")):
        n = p.stem
        if n in known or n.startswith("fetch_") or f"{n}.R" in run_all_r or f"R/{n}.R" in RUN_ALL or n in ("run_all", "fuzz"):
            continue
        other.append(n)
    assert not other, other


UNORCHESTRATED_BASELINE = {"address_only_name_check", "check_r_vs_python", "edition_coverage", "benchmarks", "fetch_hmda", "fetch_gnis_historical", "grf_eds"}


def test_no_new_result_stage_is_left_out_of_the_orchestrators():
    """A stage that writes committed results is run by neither run_all.sh nor rerun_results.sh (ratchet on the review-4 list)."""
    none = {s["id"] for s in STAGES["stages"] if s["run_by"] == "none"}
    assert none <= UNORCHESTRATED_BASELINE, none - UNORCHESTRATED_BASELINE


def test_address_only_name_check_is_rerun_with_the_results():
    """known_hidden/address_only_name_check.csv goes stale after a rerun because nothing regenerates it."""
    assert "address_only_name_check.py" in RERUN or "address_only_name_check.py" in RUN_ALL


def _order_violations():
    order = _rerun_order()
    first, last = {}, {}
    for i, s in enumerate(order):
        first.setdefault(s, i)
        last[s] = i
    stages = {Path(s["script"]).stem if s["script"].startswith("R/") else s["script"]: s for s in STAGES["stages"] if s["run_by"] == "rerun_results.sh"}
    files = _committed(STAGES["roots"])
    bad = []
    for rname, r in stages.items():
        for inp in r["inputs"]:
            if " " in inp:          # free-text input (restricted or external source)
                continue
            for wname, w in stages.items():
                if wname == rname:
                    continue
                produced = [f for f in files if any(_match(p, f) for p in w["outputs"] + w.get("copies", []))]
                if any(_match(inp, f) for f in produced) and first[wname] > last[rname]:
                    bad.append((rname, inp, wname))
    return sorted(set(bad))


def test_rerun_results_runs_every_writer_before_its_reader():
    """A result script reads a file that a later step of rerun_results.sh writes, so one pass publishes numbers computed from the previous run."""
    assert not _order_violations(), _order_violations()


@pytest.mark.xfail(strict=True, reason="FINDING 3 (observed effect): data/results/context/petroleum_by_use_now.csv lists all 255 pre-1960 Denver trades as 'not matched to a "
                                       "parcel' and 556/295/170 later sites by use, while site_fate now matches all 266 trades and gives 557/297/171: context_layers ran before site_fate")
def test_context_tables_were_built_from_the_committed_site_fate():
    """context_layers.R was run before site_fate.R, so its by-use tables (shown in the app) carry the previous run's parcel uses."""
    pet = pd.read_csv(ROOT / "data/results/context/petroleum_by_use_now.csv")
    pre = pd.read_csv(ROOT / "data/results/site_fate/site_fate_denver_pre1960.csv")
    post = pd.read_csv(ROOT / "data/results/site_fate/site_fate_denver.csv")
    hist = pd.read_csv(ROOT / "app/data/historical_sites.csv", dtype=str, keep_default_na=False)
    den = hist[hist.fe_hazard.str.upper().eq("TRUE") & (hist.precision != "town") & (hist.town == "DENVER")]
    unmatched_now = (~den.hfirm.isin(pre.hfirm[pre.use_now.notna()])).sum()
    row = pet[pet.series.str.startswith("Hazardous trades before 1960") & (pet.today == "not matched to a parcel")]
    assert (row.sites.sum() if len(row) else 0) <= unmatched_now + 5, (int(row.sites.sum()), int(unmatched_now))
    later = pet[pet.series.str.startswith("Hazardous-sector manufacturers") & (pet.today != "not matched to a parcel")].set_index("today").sites
    now = post.use_now.value_counts()
    assert all(later[u] == now[u] for u in later.index), {u: (int(later[u]), int(now[u])) for u in later.index if later[u] != now[u]}


def test_rerun_order_violations_are_only_the_known_three():
    """A NEW out-of-order dependency was introduced in rerun_results.sh (beyond the three recorded as FINDING 3)."""
    known = {("context_layers", "site_fate"), ("known_hidden_sensitivity", "holc_covenants"), ("loc_sanborn_1903", "context_layers")}
    assert {(r, w) for r, _, w in _order_violations()} <= known, _order_violations()


def test_rerun_steps_exist_and_declared_twice_only_where_documented():
    """rerun_results.sh names a script that does not exist, or repeats a step other than the two documented re-runs."""
    steps = _steps()
    assert all((ROOT / "R" / f"{s}.R").is_file() for s in steps), [s for s in steps if not (ROOT / "R" / f"{s}.R").is_file()]
    assert sorted(s for s in set(steps) if steps.count(s) > 1) == ["app_census_layers", "holc_covenants"]


def test_run_tests_sh_and_ci_run_every_test_directory():
    """A test directory exists that tests/run_tests.sh or the CI workflow never runs (e.g. tests/stages after these files are installed)."""
    sh = (ROOT / "tests" / "run_tests.sh").read_text(encoding="utf-8")
    ci = (ROOT / ".github" / "workflows" / "tests.yml").read_text(encoding="utf-8")
    py_dirs = sorted({str(p.parent.relative_to(ROOT)).replace(os.sep, "/") for p in (ROOT / "tests").rglob("test_*.py")})
    r_dirs = sorted({str(p.parent.relative_to(ROOT)).replace(os.sep, "/") for p in (ROOT / "tests").rglob("test-*.R")})
    assert not [d for d in py_dirs if d not in sh], [d for d in py_dirs if d not in sh]
    assert not [d for d in py_dirs if d not in ci], [d for d in py_dirs if d not in ci]
    indirect = {"tests/geocoding/testthat": "tests/geocoding/test_r_port.py"}     # run through pytest
    for d in r_dirs:
        assert d in sh and d in ci or (ROOT / indirect.get(d, "missing")).is_file(), d
    ci_dirs = re.search(r"for d in ([^;]+); do", ci).group(1).split()
    sh_dirs = re.search(r"for d in ([^;]+); do \[ -d", sh).group(1).split()
    assert ci_dirs == sh_dirs, (ci_dirs, sh_dirs)
    assert '-m "not slow"' in ci and "testthat::test_dir(\"tests/r\")" in ci


# ------------------------------------------------------------------------------------------------- duplicated result files
def test_published_health_tables_equal_the_r_outputs_and_their_markdown():
    """health_models.csv / mortality_bg_models.csv drift from the *_R.csv files they are published from, or the .md tables from the .csv."""
    for a, b, key in (("health_models.csv", "health_models_R.csv", ["outcome", "model"]), ("mortality_bg_models.csv", "mortality_bg_models_R.csv", ["outcome", "model"])):
        x, y = pd.read_csv(ROOT / "data/results" / a), pd.read_csv(ROOT / "data/results" / b)
        assert list(x.columns) == list(y.columns) and len(x) == len(y)
        assert (x[key] == y[key]).all().all()
        num = [c for c in x.columns if c not in key]
        diff = (x[num].astype(float) - y[num].astype(float)).abs().max().max()
        assert not diff > 1e-9, (a, diff)
    t = pd.read_csv(ROOT / "data/results/mortality_bg_models.csv")
    md = (ROOT / "data/results/mortality_bg_models.md").read_text(encoding="utf-8")
    for _, r in t.iterrows():
        assert f"| {r.aic:.1f} |" in md
        v = "z_hidden_hiconf" if "high-confidence" in r.model else "z_hidden"
        if pd.notna(r[v + "_rr"]):
            assert f"{r[v + '_rr']:.3f} ({r[v + '_lo']:.3f}–{r[v + '_hi']:.3f})" in md, r.model
    assert f"Block groups: {int(t.n.iloc[0])}, natural-cause deaths 2015-2019: {int(t.deaths.iloc[0]):,}" in md
    assert f"Block groups: {int(t.n.iloc[0])}, natural-cause deaths 2015-2019: {int(t.deaths.iloc[0]):,}" in README


def test_workbook_summary_formulas_cover_the_whole_site_sheet():
    """The workbook's Summary sheet (formulas, no cached values) counts a stale row range or the wrong columns after sites are added or columns move."""
    openpyxl = pytest.importorskip("openpyxl")
    wb = openpyxl.load_workbook(ROOT / "data/results/CO_hazardous_sites_1961-2002.xlsx")
    ws, fe = wb["Summary"], wb["All F&E hazardous sites"]
    n = fe.max_row                                   # header + sites
    assert n - 1 == len(C.fe_sites())
    head = {c.column_letter: c.value for c in fe[1]}
    labels = [ws.cell(row=i, column=1).value for i in range(2, 9)]
    assert labels[-1] == "Total" and set(labels[:-1]) >= set(C.fe_sites().radar.unique()), labels
    for i in range(2, 8):
        f = ws.cell(row=i, column=2).value
        m = re.fullmatch(r"=COUNTIF\('All F&E hazardous sites'!\$([A-Z]+)\$2:\$([A-Z]+)\$(\d+),A%d\)" % i, f)
        assert m and int(m.group(3)) == n and head[m.group(1)] == "radar", f
        g = ws.cell(row=i, column=4).value
        cols = re.findall(r"!\$([A-Z]+)\$2:\$[A-Z]+\$(\d+)", g)
        assert [head[c] for c, _ in cols] == ["radar", "confidence"] and all(int(r) == n for _, r in cols), g


@pytest.mark.xfail(strict=True, reason="FINDING 8: data/results/r_vs_python.md is from an older inventory (4,312 hazardous-sector sites; the all-editions run now has 4,669)")
def test_r_vs_python_report_describes_the_committed_inventory():
    """The R-vs-Python comparison report is stale: it compares an inventory that is no longer the committed one."""
    md = (ROOT / "data/results/r_vs_python.md").read_text(encoding="utf-8")
    n = int(re.search(r"same inventory status: ([\d,]+) of", md).group(1).replace(",", ""))
    full = pd.read_csv(ROOT / "data/full_inventory/sites.csv", dtype=str)
    cur = len(C.fe_sites())
    assert n in ((full.fe_hazard == "TRUE").sum(), cur), (n, (full.fe_hazard == "TRUE").sum(), cur)


def test_gitignore_hides_no_declared_output_except_the_documented_one():
    """.gitignore ignores a file that a stage declares as a committed output (it would never reach the repository or the server)."""
    pats = [ln.strip() for ln in (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines() if ln.strip() and not ln.startswith("#")]
    lic = "data/results/zoning_over_time/zoning_2023_categories.geojson"   # licensed layer: only the app copy is published
    hit = [f for f in _committed(STAGES["roots"]) for p in pats if "/" in p and not p.endswith("/") and fnmatch.fnmatchcase(f, p) and f != lic]
    assert not hit, hit
    assert lic in pats
