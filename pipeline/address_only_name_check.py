#!/usr/bin/env python3
"""How many "same entity" matches rest on the address alone, with no name in common?

The inventory match counts a site as the same entity as a regulatory record when the two share a normalised name OR a street
address (pipeline/build_sites.py: the contamination belongs to the lot, whoever occupies it). This check counts the F&E hazardous
sites matched by address only whose matched record's name shares no informative word (after the pipeline's STOP list) with any
firm listed at the site, and what the hidden share would be if they were treated as unmatched: under the published rule most of
them still have a differently named record within the tier radius or a cleanup boundary, so only those with neither become hidden;
under the strict rule all of them do.

Run from the repository root (reads committed files only):

    python3 pipeline/address_only_name_check.py

Writes data/results/known_hidden/address_only_name_check.csv, one row per variant of the token test.
"""
import re
import sys
from pathlib import Path

import geopandas as gpd
import pandas as pd

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "pipeline"))
from build_sites import nn  # noqa: E402  (the pipeline's own name normalisation and STOP list)

TIERS = ["cleanup", "tri", "rcra_handler", "solid_waste", "other_epa"]
COLS = [f"{t}_match" for t in TIERS]


def firm_names(s):
    """'Acme Plating (1970; SIC 3471) | *Foo Inc (1980)' -> ['Acme Plating', 'Foo Inc']."""
    return [re.sub(r"\s*\(\d{4}[^)]*\)\s*$", "", x.strip().lstrip("*")) for x in str(s or "").split(" | ") if x.strip()]


def hits(r):
    return [h for c in COLS if r[c] for h in str(r[c]).split(" | ")]


def main():
    g = gpd.read_file(REPO / "data/results/CO_historical_industrial_sites.geojson")
    fe = g[g.fe_hazard == True]  # noqa: E712
    n_fe = len(fe)
    n_hidden = int((fe.match_basis == "none").sum())
    kh = open(REPO / "data/results/known_hidden/summary.md", encoding="utf-8").read()
    m = re.search(r"Strict: a record with the same name or at the same address, or inside a cleanup boundary[^|]*\|\s*([\d,]+)", kh)
    strict_hidden = int(m.group(1).replace(",", "")) if m else None
    ent = fe[fe.match_basis == "same entity (name or address)"]
    rows = []
    # first row: the hazardous firms' names, the names the inventory name match itself uses (pipeline/build_sites.py names_n)
    for variant, use_all in [("hazardous firm names only", False), ("all firm names at the site", True)]:
        n_addr = n_notok = n_pub = n_strict = 0
        for _, r in ent.iterrows():
            hh = hits(r)
            if any("name match" in h for h in hh):
                continue
            addr = [h.split(" [")[0] for h in hh if "(address match)" in h]
            if not addr:
                continue
            n_addr += 1
            names = firm_names(r.hazard_firms) + (firm_names(r.all_firms) if use_all else [])
            site_tokens = {t for n in names for t in nn(n).split()}
            if any(set(nn(a).split()) & site_tokens for a in addr):
                continue
            n_notok += 1
            other = [h for h in hh if "(address match)" not in h]
            boundary = any("inside site boundary" in h for h in hh)
            if not boundary:
                n_strict += 1
                if not other:
                    n_pub += 1
        rows.append(dict(variant=variant, fe_hazard_sites=n_fe, same_entity_sites=len(ent), address_only_sites=n_addr,
                         no_shared_token=n_notok, newly_hidden_published_rule=n_pub,
                         hidden_published_pct=round(100 * (n_hidden + n_pub) / n_fe, 1),
                         newly_hidden_strict_rule=n_strict,
                         hidden_strict_pct=(round(100 * (strict_hidden + n_strict) / n_fe, 1) if strict_hidden else None),
                         hidden_now=n_hidden, strict_hidden_now=strict_hidden))
    out = pd.DataFrame(rows)
    out.to_csv(REPO / "data/results/known_hidden/address_only_name_check.csv", index=False)
    print(out.to_string(index=False))


if __name__ == "__main__":
    main()
