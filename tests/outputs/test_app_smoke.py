"""Smoke test of the Shiny app: start it, open every tab in a headless browser, look for errors.

Marked ``slow`` (about 2-4 minutes: the app loads ~200 data files, then every tab is rendered).
Skipped by ``tests/run_tests.sh --fast`` and in CI (``-m "not slow"``). Needs R with the app's
packages and Playwright's chromium.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

from outputs_helpers import REPO

pytestmark = pytest.mark.slow

PORT = int(os.environ.get("APP_SMOKE_PORT", "8790"))
URL = f"http://127.0.0.1:{PORT}"
STARTUP_TIMEOUT = 420  # seconds to wait for "Listening"
TAB_SETTLE = 5  # seconds given to each tab before its outputs are inspected

# Tabs (data-value of the nav links) and the plotly outputs that must have at least one trace once
# the tab is open. Every tab is opened; every plotly widget found on it must have traces, and these
# named ones must be present.
EXPECTED_PLOTS = {
    "Map": [],
    "Trends": ["p_timeline", "p_sector", "p_status", "p_share", "p_hist", "p_eg"],
    "Denver 1880–2020": ["p_city", "p_ed_sh", "p_pan"],
    "What became of the sites": ["p_sf_use", "p_zland", "p_zsites"],
    "Before zoning: 1903": [],
    "Land use & freeways": ["p_lu_year", "p_hw_ev", "p_ur_case"],
    "Lifespan of 1940 residents": ["p_cs_grp", "p_cs_coef", "p_enl"],
    "Redlining & covenants": ["p_holc_tr", "p_holc_sh", "p_holc_bd"],
    "Colorado trends": ["p_co_reg", "p_co_share", "p_co_assoc", "p_mix", "p_longev", "p_eg_co", "p_trans"],
    "Contamination & health": ["p_cx_tri", "p_cx_aqs", "p_hedonic"],
    "Who owns rental housing": ["p_own_size"],
    "Neighborhoods": ["p_cmp"],
    "Nearby schools & health care": [],
    "Benchmarks": ["p_bm_state", "p_bm_cty"],
    "About the data": [],
    "Data & downloads": [],
}
# selectInputs whose choices are computed at start-up from data files, and the tab each sits on
STARTUP_SELECTS = {"hw_ev_cmp": "Land use & freeways", "cx_var": "Contamination & health",
                   "cx_pol": "Contamination & health", "bm_year": "Benchmarks"}
MAIN_MAP_LABELS = ["Zone changes", "Sanborn 1903–04 sheet images"]
# Known client-side issues of the *test environment's* DT 0.31 install (not of app.R, and not reproducible against the
# manifest's DT 0.34.0): its bundled jquery.nouislider.min.js is the plain noUiSlider build (window.noUiSlider, so
# $.fn.noUiSlider never exists and DT's numeric filter sliders throw), and its bootstrap5 CSS sits under js/css/ while
# DT 0.31 requests css/. Neither can be fixed from app.R without changing package versions; new issues fail the test.
KNOWN_JS_ERRORS = ["$x.noUiSlider is not a function"]
KNOWN_404_PATHS = ["/strftime-0.9.2/strftime-min.js", "/dt-core-bootstrap5-1.13.6/css/dataTables.bootstrap5.min.css"]

NAV_SELECTOR = 'a.nav-link[data-value]:not(.dropdown-toggle), a.dropdown-item[data-value]'


def _pids_on_port():
    """PIDs of R processes started for this port, found with ps."""
    out = subprocess.run(["ps", "-eo", "pid,args"], capture_output=True, text=True).stdout
    pids = []
    for line in out.splitlines()[1:]:
        pid, _, args = line.strip().partition(" ")
        if f"port={PORT}" in args and "shiny::runApp" in args:
            pids.append(int(pid))
    return pids


def _kill(pids):
    for sig in ("-TERM", "-KILL"):
        alive = [p for p in pids if Path(f"/proc/{p}").exists()]
        if not alive:
            return
        subprocess.run(["kill", sig] + [str(p) for p in alive], capture_output=True)
        time.sleep(2)


@pytest.fixture(scope="module")
def app_server(tmp_path_factory):
    if shutil.which("Rscript") is None:
        pytest.skip("Rscript not available")
    if _pids_on_port():
        pytest.fail(f"an app is already running on port {PORT}; stop it first")
    log = tmp_path_factory.mktemp("app") / "app.log"
    env = dict(os.environ, LANG="C.UTF-8", LC_ALL="C.UTF-8")
    with open(log, "w") as fh:
        proc = subprocess.Popen(
            ["Rscript", "-e", f'shiny::runApp("app", port={PORT}, launch.browser=FALSE)'],
            cwd=REPO, stdout=fh, stderr=subprocess.STDOUT, env=env, start_new_session=True)
    t0 = time.time()
    try:
        while True:
            txt = log.read_text(errors="replace")
            if "Listening on" in txt:
                break
            if proc.poll() is not None:
                pytest.fail(f"app exited during start-up (code {proc.returncode}):\n{txt[-4000:]}")
            if time.time() - t0 > STARTUP_TIMEOUT:
                pytest.fail(f"app did not start within {STARTUP_TIMEOUT}s:\n{txt[-4000:]}")
            time.sleep(2)
        yield {"url": URL, "log": log, "startup_s": round(time.time() - t0, 1)}
    finally:
        # find the PID(s) via ps and kill them in a separate call
        pids = _pids_on_port()
        _kill(pids)
        if proc.poll() is None:
            proc.kill()
        proc.wait(timeout=30)


@pytest.fixture(scope="module")
def page(app_server):
    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        browser = p.chromium.launch()
        pg = browser.new_page(viewport={"width": 1400, "height": 900})
        console, failed = [], []
        pg.on("console", lambda m: console.append((m.type, m.text)) if m.type == "error" else None)
        pg.on("response", lambda r: failed.append((r.status, r.url)) if r.status >= 400 and "127.0.0.1" in r.url else None)
        pg.goto(app_server["url"], wait_until="load", timeout=180_000)
        # the main map's layer control appears once the server has rendered the first tab
        pg.wait_for_selector("#map .leaflet-control-layers", timeout=180_000)
        pg.console_errors = console
        pg.failed_responses = failed
        yield pg
        browser.close()


def _tabs(page):
    return page.evaluate(f"Array.from(document.querySelectorAll('{NAV_SELECTOR}')).map(a => a.getAttribute('data-value'))")


def _open_tab(page, tab):
    ok = page.evaluate(
        "v => { const a = document.querySelector(`a.nav-link[data-value=\"${v}\"], a.dropdown-item[data-value=\"${v}\"]`);"
        " if (!a) return false; a.click(); return true; }", tab)
    assert ok, f"no nav link with data-value {tab!r}"
    time.sleep(TAB_SETTLE)
    try:
        page.wait_for_function("document.querySelectorAll('.recalculating').length === 0", timeout=90_000)
    except Exception:  # noqa: BLE001
        pass  # inspected below anyway


def _inspect_active_tab(page):
    return page.evaluate("""() => {
        const pane = document.querySelector('.tab-pane.active');
        const out = {plots: {}, errors: [], validation: []};
        pane.querySelectorAll('.plotly.html-widget').forEach(el => { out.plots[el.id] = el.data ? el.data.length : -1; });
        pane.querySelectorAll('.shiny-output-error').forEach(e => {
            const rec = e.id + ': ' + e.textContent.trim().slice(0, 160);
            (e.classList.contains('shiny-output-error-validation') ? out.validation : out.errors).push(rec);
        });
        return out; }""")


def test_app_starts(app_server):
    assert app_server["startup_s"] < STARTUP_TIMEOUT


def test_every_tab_renders_without_errors(page):
    tabs = _tabs(page)
    assert set(tabs) == set(EXPECTED_PLOTS), f"tabs changed: {tabs}"
    problems, empty_plots, missing_plots, seen = [], [], [], {}
    for tab in tabs:
        _open_tab(page, tab)
        info = _inspect_active_tab(page)
        seen[tab] = info["plots"]
        problems += [f"{tab}: {e}" for e in info["errors"]]
        empty_plots += [f"{tab}: {pid} ({n} traces)" for pid, n in info["plots"].items() if n < 1]
        missing_plots += [f"{tab}: {pid}" for pid in EXPECTED_PLOTS[tab] if pid not in info["plots"]]
    assert not problems, "Shiny output errors:\n" + "\n".join(problems)
    assert not empty_plots, "plotly widgets without traces:\n" + "\n".join(empty_plots)
    assert not missing_plots, "expected plots not rendered:\n" + "\n".join(missing_plots)


def test_main_map_has_overlay_groups(page):
    _open_tab(page, "Map")
    labels = page.evaluate("Array.from(document.querySelectorAll('#map .leaflet-control-layers-overlays label')).map(l => l.textContent.trim())")
    assert len(labels) >= 30, f"{len(labels)} overlay groups: {labels}"
    for want in MAIN_MAP_LABELS:
        assert any(want in l for l in labels), f"overlay {want!r} missing from {labels}"


def test_startup_selects_are_populated(page):
    counts = {}
    for sel, tab in STARTUP_SELECTS.items():
        _open_tab(page, tab)
        deadline = time.time() + 5
        n = 0
        while time.time() < deadline:
            n = page.evaluate(
                "s => { const el = document.getElementById(s); if (!el) return -1;"
                " if (el.selectize) return Object.keys(el.selectize.options).length;"
                " return el.querySelectorAll('option').length; }", sel)
            if n > 1:
                break
            time.sleep(0.5)
        counts[sel] = n
    bad = {k: v for k, v in counts.items() if v <= 1}
    assert not bad, f"selects with one or no option: {bad} (all: {counts})"


def test_no_new_javascript_errors_or_missing_assets(page):
    """Runs last: the other tests have opened every tab. Tile and font servers may be unreachable in a
    sandbox, so only the app's own origin counts; the issues in KNOWN_* are reported, not failed."""
    js = [t for _, t in page.console_errors if "Failed to load resource" not in t]
    new_js = [t for t in js if not any(k in t for k in KNOWN_JS_ERRORS)]
    missing = sorted({u for _, u in page.failed_responses})
    new_missing = [u for u in missing if not any(u.endswith(k) for k in KNOWN_404_PATHS)]
    assert not new_js, f"new JavaScript errors: {new_js}"
    assert not new_missing, f"app assets not served: {new_missing}"
