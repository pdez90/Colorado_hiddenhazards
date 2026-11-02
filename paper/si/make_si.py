"""Build paper/si/si_blocks.json for the Supplementary Information of "Before and After the Map" from the committed
result files (data/results/). Successor of make_si.py: every hard-coded
number in the prose has been traced to a current result file or to the reconciled manuscript
(paper/Before_and_After_the_Map_manuscript.md); the sources are noted in comments beside each paragraph.
Prose that is unchanged is still copied from si_prose_base.json (old[...]) and edited with .replace().

Run from the repository root:  python3 paper/si/make_si.py   ->  paper/si/si_blocks.json
Then:  cd paper/si && npm install docx && node build_si.js   ->  paper/Before_and_After_the_Map_SI.docx
"""
import pandas as pd, numpy as np, json, sys
import os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); from md2blocks import runs, plain
A = os.path.abspath(os.path.join(HERE, '..', '..')) + '/'
R = A + 'data/results/'
old = json.load(open(os.path.join(HERE, 'si_prose_base.json')))   # the 18 October SI: unchanged prose is reused from it

def f(b, d=2, sign=True):
    if pd.isna(b): return '—'
    s = f"{b:+.{d}f}" if sign else f"{b:.{d}f}"
    s = s.replace('-', '−')
    if sign and float(s.replace('−', '-')) == 0: s = s[1:]          # a zero never carries a sign (make_tables.num)
    return s
def pv(p):
    if pd.isna(p): return '—'
    return '<0.001' if p < 0.001 else f"{p:.3f}" if p < 0.01 else f"{p:.2f}"
def star(p): return '' if pd.isna(p) else '***' if p < .001 else '**' if p < .01 else '*' if p < .05 else ''
def chk(cond, msg):
    if not cond: raise SystemExit('CHECK FAILED: ' + msg)

B = []
def H(t): rs = runs(t); B.append({"type": "heading", "level": 2, "runs": rs, "text": plain(rs)})
def P(t): rs = runs(t); B.append({"type": "p", "level": 0, "runs": rs, "text": plain(rs)})
def T(cap, rows):
    trs = [[{"runs": runs(str(c)), "text": plain(runs(str(c))), "header": i == 0} for c in r] for i, r in enumerate(rows)]
    B.append({"type": "table", "rows": trs, "caption": cap})
B.append({"type": "heading", "level": 1, "runs": runs("Supplementary Information"), "text": "Supplementary Information"})
P("Before and After the Map: Industrial Siting and the Making of Environmental Inequality in Denver, 1880–2020")

# ------------------------------------------------------------------------------------------------ S1
H("S1. The directory inventory and its coverage")
# old[3]: 34 business-directory editions 1871–1956 — agrees with the manuscript §2; unchanged.
P(old[3]['text'])
# Listing and site counts: data/results/edition_coverage.csv (listings by edition, complete flag), README "Key results"
# (3,487 F&E sites; 1,212 hidden; all-editions 72,317 listings / 4,669 sites) and manuscript §2 (1,112 Denver sites;
# the 34 mis-placed listings, 25 of them 1965, were an earlier build; the current check finds none).
ec = pd.read_csv(R + 'edition_coverage.csv'); mf = ec[ec.series == 'Directory of Colorado Manufacturers']
complete = {1965, 1966, 1967, 1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992}
chk(set(mf[mf.complete == True].year) == complete, 'complete editions')
n_list_complete = int(mf[mf.complete == True].listings.sum()); n_list_all = int(mf.listings.sum())
chk(n_list_complete == 44808 and n_list_all == 72317, f'listing totals {n_list_complete} {n_list_all}')
sites_co = 3487; sites_denver = 1112; sites_all_editions = 4669; hidden = 1212
sf = pd.read_csv(R + 'site_fate/site_fate_denver.csv'); chk(len(sf) == sites_denver, 'Denver 1965-92 sites')
kh = open(R + 'known_hidden/summary.md').read(); chk('3,487 F&E' in kh and '1,212 (34.8%)' in kh, 'known_hidden summary')
P(f"The Directory of Colorado Manufacturers (Business Research Division, University of Colorado, 1961–2002) was scanned from library copies in 25 editions. "
  f"Twelve of the scans stop part-way through the geographic section or have missing pages (1961, 1962, 1971, 1976, 1979, 1982, 1984, 1985, 1986, 1993, 1999, 2002) and are excluded everywhere; "
  f"the thirteen complete editions are 1965, 1966, 1967, 1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990 and 1992. "
  f"Listings were linked across editions when within 30 m of each other, giving one site per address with first and last years of listing: "
  f"the {n_list_complete:,} listings of the complete editions yield {sites_co:,} street-located sites in the hazardous sectors, {sites_denver:,} of them in the City and County of Denver "
  f"(all 25 editions together hold {n_list_all:,} listings and {sites_all_editions:,} hazardous-sector sites; that inventory is kept for reference and is not used in the paper). "
  f"One definition of hazardous industry, the Frickel and Elliott sector set, is used for every count in the paper and the application. "
  f"Denver's street grid numbers north and south from Ellsworth Avenue and east and west from Broadway. In an earlier build, 34 Denver listings, 25 of them in the 1965 edition, had been placed by the geocoder's direction-loose pass on the unprefixed north-Denver street of a south-Denver address; "
  f"the geocoder now never places a prefixed address on the unprefixed street across those baselines, and a final check, which sets to unlocated any Denver listing whose point lies on the wrong side of the baseline for the direction in its own address, finds none. "
  f"Table S1 compares each edition with County Business Patterns.")
cb = pd.read_csv(R + 'benchmarks/cbp_vs_directory_state.csv').dropna(subset=['dir_haz'])
rows = [["Year", "Edition", "CBP manufacturing", "Directory manufacturers", "Ratio", "CBP hazardous sectors", "Directory hazardous", "Ratio"]]
for _, r in cb.iterrows():
    rows.append([int(r.year), "complete" if int(r.year) in complete else "partial", f"{int(r.cbp_mfg):,}", f"{int(r.dir_mfg):,}", f"{r.ratio_mfg:.2f}", f"{int(r.cbp_haz):,}", f"{int(r.dir_haz):,}", f"{r.ratio_haz:.2f}"])
T("Table S1. The Directory of Colorado Manufacturers against County Business Patterns, Colorado establishments", rows)
# Correlations and Denver ratio: data/results/benchmarks/benchmarks_summary.md (r = 0.84 / 0.88; Denver 0.94), as in manuscript §2.
bs = open(R + 'benchmarks/benchmarks_summary.md').read()
chk('r = 0.84 (log manufacturers), 0.88 (log hazardous sectors)' in bs and '(Denver 0.94)' in bs, 'benchmark correlations')
above1 = [int(y) for y in cb[cb.ratio_haz > 1].year]; chk(above1 == [1977, 1980, 1983], f'ratios above 1: {above1}')
P("Across 15 editions and 63 counties the log directory count correlates with the log CBP count at r = 0.84 (all manufacturing) and 0.88 (hazardous sectors); Denver's directory/CBP ratio is 0.94. "
  "CBP counts every employer establishment from administrative records and the directory lists firms that answered the publisher's questionnaire or were copied from other lists, so the ratios are coverage rates; "
  "ratios above 1 (1977, 1980, 1983) mean the directory listed more hazardous-sector firms than CBP counted employer establishments, plausibly because it includes some firms without employees. County files are from Eckert et al. (2021).")

# ------------------------------------------------------------------------------------------------ S2
H("S2. Reconstruction of enumeration districts, 1880–1940")
# Mapped populations: data/results/denver_eds/denver_eds_summary.md (dissimilarity rows: 257,317; 284,823; 317,663);
# geocoding shares: denver_eds/ed_geocoding_R.csv (1900: 19,211 of 26,716 addresses = 72%) and manuscript §2
# (60% of the 1900 population after stray geocodes are dropped; 73% in 1940). Stray-geocode rule: README "Enumeration districts".
eg = pd.read_csv(R + 'denver_eds/ed_geocoding_R.csv').set_index('year')
chk(round(100 * eg.loc[1900, 'geocoded'] / eg.loc[1900, 'addresses']) == 72, '1900 geocoded share')
es = open(R + 'denver_eds/denver_eds_summary.md').read()
for s in ['| 309 | 257,317 |', '| 228 | 284,823 |', '| 330 | 317,663 |']: chk(s in es, 'mapped population ' + s)
t = old[6]['text']
t = t.replace("clipped to the city.", "clipped to the city. Only the districts of Denver itself are used: Arapahoe County's districts before the 1902 consolidation, and the City and County of Denver's from 1910; because district numbers repeat across counties, districts are selected by county as well as number, and the mapped population is checked against the county total (1920: 257,317 of 258,017; 1930: 284,823 of 287,832; 1940: 317,663 of 322,780).")
t = t.replace("Districts with fewer than three geocoded households were merged with their neighbours. 73% of the 1900 population is placed at street level.",
              "Stray geocodes — farther from the district's person-weighted median centre than the larger of 400 m and 2.5 times the median distance, or with fewer than 30% of their ten nearest neighbours in the same district — are dropped before the tessellation, and districts with fewer than three geocoded households were merged with their neighbours. 72% of the 1900 addresses are geocoded at street level, and the addresses kept after stray geocodes are dropped hold 60% of the 1900 population (73% in 1940).")
chk('317,663' in t and '72% of the 1900 addresses' in t, 'S2 edits applied')
P(t)
# Fixed grid: denver_eds/ed_dissimilarity_fixed_grid.csv (53 and 310 cells).
fg = pd.read_csv(R + 'denver_eds/ed_dissimilarity_fixed_grid.csv'); chk(set(fg.cells) == {53, 310}, 'grid cells')
P("A measure is set to missing in a census whose questionnaire or extract does not carry it (ownership in 1880; SEI in the 1900 extract; rent and residence in 1935 except in 1940; 1940 sample-line items), rather than to zero. Hispanic origin is IPUMS HISPAN, inferred from birthplace, parents' birthplace and Spanish surname. \"Boarders and lodgers\" are household members unrelated to the head (RELATE 12–13). Because the number and size of districts change between censuses, Black–nonblack dissimilarity is also computed on a fixed 500 m grid: each census's district counts are area-weighted onto the grid, using the area mapped in all six censuses (53 cells) and the area mapped from 1900 (310 cells).")
m = pd.read_csv(R + 'denver_eds/ed_distance_models.csv')
names = {'pct_black': '% Black', 'pct_hisp': '% Hispanic', 'pct_fb': '% foreign born', 'pct_laborers': '% laborers', 'pct_owner_hh': '% owner households', 'mean_sei': 'mean SEI', 'pct_haz_industry': '% in hazardous industries'}
rows = [["Outcome", "Census", "Without downtown control", "p", "With downtown control", "p", "EDs"]]
for o, n in names.items():
    for c in [1880, 1900, 1910, 1920, 1930, 1940, 0]:
        r = m[(m.outcome == o) & (m.census == c)]
        if not len(r): continue
        r = r.iloc[0]; rows.append([n, "pooled" if c == 0 else c, f(r.b_per_log_m), pv(r.p), f(r.b_cbd_ctrl), pv(r.p_cbd_ctrl), int(r.EDs)])
T("Table S2. District distance gradients, 1880–1940, with and without the log distance to downtown (percentage points per log metre from the nearest hazardous firm; HC1)", rows)

# ------------------------------------------------------------------------------------------------ S3
H("S3. The 1925 zoning ordinance: classification and georeferencing")
# Zone areas: data/results/zoning_1929/zoning_1929.geojson (Industrial A 24.77, Industrial B 3.79, Commercial 3.62 km²);
# uncertain share: data/raw/zoning_1929/zone_cells_1929.csv (43% of industrial cells).
try:
    import geopandas as gpd
    zg = gpd.read_file(R + 'zoning_1929/zoning_1929.geojson').to_crs(32613); za = (zg.area / 1e6).groupby(zg.zone).sum()
except Exception:
    za = pd.read_csv(R + 'zoning_1944/zoning_1929_vs_1944.csv').set_index('zone').km2_1929
chk(abs(za['Industrial A'] - 24.8) < 0.1 and abs(za['Industrial B'] - 3.8) < 0.1 and abs(za['Commercial'] - 3.6) < 0.1, f'1929 zone areas {za.to_dict()}')
zc = pd.read_csv(A + 'data/raw/zoning_1929/zone_cells_1929.csv'); unc = zc[zc.zone.str.startswith('Industrial')].uncertain.mean()
chk(round(100 * unc) == 43, f'uncertain share {unc}')
P(old[8]['text'].replace("24.6 km² Industrial A", f"{za['Industrial A']:.1f} km² Industrial A").replace("3.8 km² Industrial B", f"{za['Industrial B']:.1f} km² Industrial B").replace("3.6 km² Commercial", f"{za['Commercial']:.1f} km² Commercial").replace(" and 3.6 km² Commercial.", " and 3.6 km² Commercial") + " on the whole sheet (the main text's 28.4 km² is the industrial land on the part of the sheet that the 1944 map also covers, within Denver County; its 24.7 km² of Industrial A is the part covered by the 2023 zoning layer).")
# Georeferencing: data/results/zoning_1929/gcp_fit.csv (15 points, RMSE 19 m); the dropped sixteenth point and the 1944
# registration and comparison: README "The 1925 zoning ordinance" and manuscript §2 Instruments (ten-point affine fit,
# RMSE ≈ 32 m; 118 of 226 clusters inspected; 8 areas; no industrial district added; 0.48 km² = 2% of Industrial A redrawn).
# Off-sheet areas: zoning_1929/zoning_shares_holc.csv (area 6571, C, 4.363 km²; area 6572, D, 1.239 km²; 56 areas in all).
g = pd.read_csv(R + 'zoning_1929/gcp_fit.csv'); rmse = float(np.sqrt((g.residual_m ** 2).mean()))
chk(len(g) == 15 and round(rmse) == 19, f'gcp {len(g)} {rmse}')
worst = g.loc[g.residual_m.idxmax()]
zs = pd.read_csv(R + 'zoning_1929/zoning_shares_holc.csv'); off = zs[zs.share_industrial_1929.isna()]
chk(len(zs) == 56 and sorted(off.grade) == ['C', 'D'] and abs(off[off.grade == 'C'].area_km2.iloc[0] - 4.4) < 0.1 and abs(off[off.grade == 'D'].area_km2.iloc[0] - 1.2) < 0.1, 'off-sheet HOLC areas')
ch = pd.read_csv(R + 'zoning_1944/zoning_1929_vs_1944.csv').set_index('zone'); chk(abs(ch.loc['Industrial A', 'change_km2'] + 0.48) < 0.01, '1929-44 change')
P(f"Georeferencing used sixteen street intersections and park corners read off the scan and resolved to TIGER/Line road intersections. One of them, the City Park south-west corner at E 17th Avenue and York Street, was dropped as mis-identified (TIGER's 17th Avenue jogs half a block there); the remaining fifteen all resolve, and an affine fit in UTM zone 13N has a root-mean-square residual of {rmse:.0f} m (individual residuals {g.residual_m.min():.0f}–{g.residual_m.max():.0f} m, the largest at {worst.street1} and {worst.street2}; Table S3). "
  "The 1944 revision of the same map (CG4314 .G44 1944, revised to 1 April 1944) was registered to the 1929 scan by a ten-point affine fit (RMSE 25 scan pixels, about 32 m). It is a darker print of the same plate. One texture classifier trained on the 1929 labels was applied to both scans; every cluster of disagreement of about a city block or more (118 of 226 clusters) was inspected on side-by-side crops of the two scans, and only districts visibly redrawn were accepted (8 areas). "
  f"No industrial district was added between the two revisions; about {-ch.loc['Industrial A', 'change_km2']:.2f} km² of Industrial A (2% of it) was redrawn as commercial, business or apartment districts. Most disagreements came from the darker 1944 print rather than from redrawn districts; changes smaller than a block, and amendments coloured by hand on the 1944 copy, are not included. "
  f"The map sheet does not cover the whole 1938 graded area: of the 56 HOLC areas, two (one C, {off[off.grade == 'C'].area_km2.iloc[0]:.1f} km², and one D, {off[off.grade == 'D'].area_km2.iloc[0]:.1f} km²) lie off the sheet, and zoning shares are computed over the land on the sheet only; districts and tracts less than half on the sheet are left missing.")
rows = [["Control point", "Note", "Scan x (px)", "Scan y (px)", "Residual (m)"]]
for _, r in g.iterrows():
    rows.append([f"{r.street1} & {r.street2}", "" if pd.isna(r.note) or r.note == "" else r.note, int(r.px_x), int(r.px_y), f"{r.residual_m:.1f}"])
rows.append(["Root-mean-square residual", "", "", "", f"{rmse:.1f}"])
T("Table S3. Control points for the 1929 zone map and their residuals from the affine fit (UTM zone 13N)", rows)

# ------------------------------------------------------------------------------------------------ S4
H("S4. Parcel matching, regulatory status and the archival check")
# Parcel matching: data/results/site_fate/site_fate_denver.csv (1,112 sites, all with a parcel; median 4.3 m),
# site_fate_denver_pre1960.csv (395 trades, 394 matched), site_fate_parcel_match.csv (match stages; situs agreement 45.8% / 19.7%).
# Regulatory inventories and radii: manuscript §2 Instruments; hidden share: known_hidden/summary.md (1,212 of 3,487, 34.8%).
pre = pd.read_csv(R + 'site_fate/site_fate_denver_pre1960.csv')
chk(sf.SCHEDNUM.notna().all() and (sf.parcel_dist_m <= 40).all(), 'all 1965-92 sites matched within 40 m')
chk(len(pre) == 395 and pre.SCHEDNUM.notna().sum() == 394, 'pre-1960 parcel matches')
med = sf.parcel_dist_m.median(); chk(round(med) == 4, f'median distance {med}')
pm = pd.read_csv(R + 'site_fate/site_fate_parcel_match.csv'); ag = pm[pm.parcel_match.str.startswith('agreement')].set_index('series').pct
ag_mfg = ag["Manufacturers' directory sites 1965-1992"]; ag_pre = ag['Business-directory hazardous trades 1891-1956']
t = old[12]['text']
t = t.replace("Each geocoded Denver site was matched to the nearest City and County of Denver assessor parcel within 40 m (1,256 of 1,258 distinct coordinates; median distance 10 m).",
              f"Each geocoded Denver site was matched to the City and County of Denver assessor parcel within 40 m whose situs address matches the directory address, else the parcel on the same street and side with the nearest house number, else the nearest parcel on the same street, else the nearest parcel. All {len(sf):,} manufacturers' sites of 1965–92 and {int(pre.SCHEDNUM.notna().sum())} of the {len(pre)} pre-1960 trades have a parcel within 40 m; the median distance is {med:.0f} m, and the situs address matches the directory address outright for {ag_mfg:.0f}% of the manufacturers' sites and {ag_pre:.0f}% of the pre-1960 trades.")
t = t.replace("Regulatory status was assigned from EPA's Facility Registry Service, TRI, SEMS and RCRA and from Colorado's voluntary-cleanup and environmental-covenant registers by location (40–75 m), address or name; a geocoding error",
              f"Regulatory status was assigned from EPA's Facility Registry Service, TRI, SEMS, ACRES brownfields and RCRA (handlers and corrective action) and from Colorado's cleanup, Superfund, brownfield, voluntary-cleanup, UMTRA, solid-waste and environmental-covenant registers, matched by location (40–100 m by inventory, grown by the site's spread up to 250 m), by a record at the same address (street type and unit ignored) or by name; under this rule {hidden:,} of the {sites_co:,} Colorado sites (35%) match no record. A geocoding error")
chk('median distance is 4 m' in t and '1,212 of the 3,487' in t, 'S4 edits applied')
P(t)
# Residential sites: site_fate_denver.csv (184 residential; built in or before last listing 119, later 47, no date 18;
# 97 on no inventory, of which 76 built in or before) — as manuscript §6.
res = sf[sf.use_now == 'Residential']; n_res = len(res)
before = int((res.year_built <= res.last_year).sum()); later = int((res.year_built > res.last_year).sum()); nodate = int(res.year_built.isna().sum())
nr = res[res.radar == 'Not on any list']; n_nr = len(nr); nr_before = int((nr.year_built <= nr.last_year).sum())
chk((n_res, before, later, nodate, n_nr, nr_before) == (184, 119, 47, 18, 97, 76), f'residential counts {(n_res, before, later, nodate, n_nr, nr_before)}')
P(f"For {before} of the {n_res} residential sites of 1965–92 the present building was built in or before the site's last listing year; {later} were built later and {nodate} have no date. Most residential sites are therefore small firms in or beside dwellings, or geocodes that fell on a neighbouring dwelling, rather than conversions. Of the {n_nr} residential sites with no record in the searched inventories, {nr_before} are of this kind.")
sb = pd.read_csv(R + 'site_fate/archival_check_sanborn_1887_1904.csv'); chk(len(sb) == 20, 'Sanborn check rows')
rows = [["Firm", "Address", "Sector", "Listed", "1890 sheet", "Use shown on the sheet", "Matches geocode"]]
for _, r in sb.iterrows():
    ys = str(r.years_listed).split()
    rows.append([r.hfirm, r.street, r.sectors, ys[0] if len(ys) == 1 else ys[0] + '–' + ys[-1], str(r.sanborn_sheet).replace('1890 ', ''), str(r.use_shown_on_sheet).replace('""', '"'), r.matches_geocode])
T("Table S4. Sanborn check of twenty street-located hazardous trades on the 1890 sheets (Library of Congress)", rows)
# Tally as in manuscript §2 Archival check (5 / 5 / 6 / 4).
P("Of the twenty, the sheet shows the listed trade at the geocoded lot for five, a related use on or immediately beside the lot for five, a different use for six, and is inconclusive for four.")

# ------------------------------------------------------------------------------------------------ S5
H("S5. Robustness of the boundary and change estimates")
b = pd.read_csv(R + 'holc/holc_boundary.csv'); b = b[b.pair == 'D-C']
for o, lab, cap in [('p_black', 'Black', 'Table S5. D–C boundary gaps in the Black share with HC1 and Conley (2 km) standard errors'), ('p_hisp', 'Hispanic', 'Table S6. D–C boundary gaps in the Hispanic share with HC1 and Conley (2 km) standard errors')]:
    rows = [["Census", "Units", "D units", "C units", "Gap", "HC1 SE", "HC1 p", "Conley SE", "Conley p", "Rail- and zoning-adjusted gap", "p"]]
    for _, r in b[b.outcome == o].sort_values(['census', 'basis'], ascending=[True, False]).iterrows():
        if pd.isna(r.gap): continue
        rows.append([r.census, "districts" if r.basis == 'districts' else "tracts", r.n_D, r.n_C, f(r.gap), f(r.se, 2, False), pv(r.p), f(r.se_conley2km, 2, False), pv(r.p_conley2km), f(r.gap_zone), pv(r.p_zone)])
    T(cap, rows)
P("The 1940 tract Black share is nonwhite; the 1940 tract Hispanic share is filled from the 1940 districts.")
bw = pd.read_csv(R + 'holc/holc_boundary_bandwidth.csv')
rows = [["Census", "Units", "Narrow", "Standard", "Wide"]]
bw['_ord'] = (bw.basis != 'districts').astype(int)                      # districts before tracts within a census
for (c, _o, u), gg in bw.groupby(['census', '_ord', 'basis'], sort=True):
    d = {k: gg[gg.bandwidth == k] for k in ['narrow', 'standard', 'wide']}
    rows.append([c, "districts" if u == 'districts' else "tracts"] + [f(d[k].gap.iloc[0], 2) + star(d[k].p.iloc[0]) if len(d[k]) else '—' for k in ['narrow', 'standard', 'wide']])
T("Table S7. D–C gap in the Black share by boundary bandwidth (districts 200/400/800 m; tracts 400/800/1,600 m)", rows)
tt = pd.read_csv(R + 'holc/holc_trend_test.csv')
rows = [["Outcome", "Units", "Censuses", "Points", "Slope (points per decade)", "SE", "p"]]
for _, r in tt.iterrows(): rows.append(["% Black" if r.outcome == 'p_black' else "% Hispanic", r.unit, str(r.years).replace('-', '–'), r.points, f(r.slope_per_decade), f(r.se, 2, False), pv(r.p)])
T("Table S8. Trend in the D–C gap within one unit type (weighted by 1/SE²)", rows)
P("An earlier version pooled district and tract estimates in one regression with a post-1938 break; because the two unit types differ in size and in what they measure (Black vs nonwhite in 1940), the trend is now estimated within each unit type only.")
# Change models: holc/holc_tract_models.csv. The Hispanic-share models now start in 1970 (manuscript §4), and the ungraded
# Industrial and Commercial classes are dropped from the model, so the table carries B, C and D against A for the periods
# the manuscript reports.
tm = pd.read_csv(R + 'holc/holc_tract_models.csv'); chk(set(tm.grade) == {'B', 'C', 'D'}, 'tract model classes')
sel = [('p_hisp', '1970-1980', '% Hispanic'), ('p_hisp', '1980-2010', '% Hispanic'), ('p_hisp', '1970-2010', '% Hispanic'),
       ('p_black', '1940-2010', '% Black (1940 nonwhite)'), ('p_pov', '1970-2010', '% below poverty'), ('p_owner', '1940-2010', '% owner-occupied'),
       ('lmval', '1940-1980', 'log median value'), ('lmval', '1940-2010', 'log median value')]
rows = [["Outcome", "Period", "Class", "Estimate", "HC1 SE", "p", "Conley SE", "Conley p", "Zoning-adjusted", "Strict zoning layer", "p", "Tracts"]]
for o, per, lab in sel:
    for gr in ['B', 'C', 'D']:
        r = tm[(tm.outcome == o) & (tm.period == per) & (tm.grade == gr)]
        chk(len(r) == 1, f'tract model {o} {per} {gr}')
        r = r.iloc[0]; d = 2 if o == 'lmval' else 1
        rows.append([lab, per.replace('-', '–'), gr, f(r.b, d), f(r.se, d, False), pv(r.p), f(r.se_conley2km, d, False), pv(r.p_conley2km), f(r.b_zone, d), f(r.b_zone_strict, d), pv(r.p_zone_strict), int(r.n)])
T("Table S9. Change in tract outcomes by 1938 class, relative to A tracts: main estimates, Conley (2 km) standard errors, and estimates controlling for the 1929 industrial-zoned share (full and strict layers)", rows)
P("The strict zoning layer drops the 43% of industrial cells classified only by the platted thick-hatch rule. The Hispanic-share models start in 1970, the first census that identifies Hispanic residents comparably on tracts; the ungraded Industrial and Commercial zones (four tracts each) are dropped with the other classes of fewer than five tracts. No B estimate differs from A in any specification.")

# ------------------------------------------------------------------------------------------------ S6
H("S6. Tract analyses on fixed tract sets")
# Tract counts: manuscript §2 (97 in 1950, 144 in 1960, 145–147 from 1970; fixed sets 95 / 142 / 144), checked against the
# set labels in denver_tracts/denver_tracts_models_fixed.csv.
fx = pd.read_csv(R + 'denver_tracts/denver_tracts_models_fixed.csv')
chk(set(fx.set) == {'fixed 1950-2020 (95 tracts)', 'fixed 1960-2020 (142 tracts)', 'fixed 1970-2020 (144 tracts)'}, f'fixed sets {set(fx.set)}')
P("Every tract analysis uses the 147 tracts (2010 boundaries) whose centroid lies within 10 km of downtown Denver, dropping tracts with fewer than 200 residents. Because fewer of these tracts were populated and tracted in 1950 (97) than in 1960 (144) or from 1970 (145–147), Table S10 repeats the distance models on the tracts observed in every census from 1950 (95 tracts), 1960 (142) and 1970 (144).")
nm = {'p_hisp': '% Hispanic', 'p_white': '% White', 'p_black': '% Black', 'p_pov': '% below poverty', 'p_owner': '% owner-occupied'}
rows = [["Tract set", "Outcome", "1950", "1960", "1970", "1980", "1990", "2000", "2010", "2020"]]
for s in fx.set.unique():
    for o, n in nm.items():
        r = fx[(fx.set == s) & (fx.outcome == o)].set_index('census')
        rows.append([s.replace('-', '–'), n] + [(f(r.loc[c, 'b_per_log_m'], 1) + star(r.loc[c, 'p'])) if c in r.index and pd.notna(r.loc[c, 'b_per_log_m']) else '—' for c in [1950, 1960, 1970, 1980, 1990, 2000, 2010, 2020]])
T("Table S10. Tract distance gradients on fixed tract sets (percentage points per log metre from the nearest hazardous firm; HC1)", rows)

# ------------------------------------------------------------------------------------------------ S7
H("S7. Descriptive sequences")
C = pd.read_csv(R + 'descriptive/d_area_timeline.csv')
rows = [["D area", "Population 1930", "First census with Black LQ ≥ 2", "First census with Hispanic LQ ≥ 2", "Black LQ 1900", "Black LQ 1940", "First hazardous trade listed", "Trades listed by 1937"]]
gv = lambda v: '—' if pd.isna(v) else (str(int(v)) if float(v).is_integer() else f"{v:.2f}")
for _, r in C.iterrows():
    rows.append([r.label, f"{int(r.pop_1930):,}", gv(r.first_black_lq2), gv(r.first_hisp_lq2), gv(r.lq_black_1900), gv(r.lq_black_1940), gv(r.first_trade), int(r.trades_by_1937)])
T("Table S11. Timeline of each 1938 D area, 1900–1940: when its Black and Hispanic shares first exceeded twice the city's, and when its first hazardous trade was listed", rows)
P("Location quotients from the 1900–1940 districts area-weighted into each D area (the first census with a location quotient of 2 is reported only where the area then held at least 100 residents). No business-directory edition survives for 1893–1909, so a first listing in 1910–14 is an upper bound on when a trade arrived.")
A2 = pd.read_csv(R + 'descriptive/grid_first_arrival_1900_1940.csv')
rows = [["Decade", "Group", "Cells", "Population", "% Black", "% Hispanic", "% foreign born", "% laborers", "% owner", "km to downtown", "Change % Black", "Change % Hispanic", "Change % foreign born", "Change % owner"]]
for _, r in A2.iterrows(): rows.append([f"{r['from']}–{r['to']}", r.group, int(r.cells), f"{int(r['pop']):,}", r.pct_black_before, r.pct_hisp_before, r.pct_fb_before, r.pct_laborers_before, r.pct_owner_before, r.km_to_downtown, f(r.chg_black), f(r.chg_hisp), f(r.chg_fb), f(r.chg_owner)])
T("Table S12. Grid cells with no hazardous trade ever listed, by whether a first trade was listed in the next decade: composition at the start and change over the decade (all decades)", rows)

# ------------------------------------------------------------------------------------------------ S8
H("S8. The companion application")
P(old[-1]['text'])

json.dump(B, open(os.path.join(HERE, 'si_blocks.json'), 'w'), ensure_ascii=False)
print(len(B), 'blocks,', sum(x['type'] == 'table' for x in B), 'tables')
