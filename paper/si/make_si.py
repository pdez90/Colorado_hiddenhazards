"""Build paper/si/si_blocks.json for the Supplementary Information of "Before and After the Map" from the committed
result files (data/results/, data/historical/, app/data/). Every count in the prose is computed from a result file where a file
holds it, and each chk(...) compares a computed value with a second, independent computation or with the text it is printed in,
never with a number typed here; the few figures that no committed file holds (method parameters, and those marked "typed" in the
comments) are listed beside their paragraph.
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
_WORDS = 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty'.split()
def W(n, cap=False):                                                  # a count spelled out as the prose does (up to twenty), else digits
    w = _WORDS[n] if 0 <= n < len(_WORDS) else f"{n:,}"
    return w.capitalize() if cap else w
def yrs(ys, short=True):                                              # 1877, 1878, 1879 -> "1877–79"; single years stay
    ys = sorted(int(y) for y in ys); out = []; i = 0
    while i < len(ys):
        j = i
        while j + 1 < len(ys) and ys[j + 1] == ys[j] + 1: j += 1
        out.append(str(ys[i]) if j == i else f"{ys[i]}–{str(ys[j])[2:] if short else ys[j]}"); i = j + 1
    return ', '.join(out)
def listing(xs): xs = [str(x) for x in xs]; return xs[0] if len(xs) == 1 else ', '.join(xs[:-1]) + ' and ' + xs[-1]
def rep(t, a, b):                                                     # an edit of the base prose must find its text exactly once
    chk(t.count(a) == 1, 'base prose no longer holds: ' + a[:60]); return t.replace(a, b)

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
# old[3]: the business-directory editions, counted and listed from the published pre-1960 listings.
HIST = A + 'data/historical/'
HL = pd.read_csv(HIST + 'CO_pre1960_hazardous_listings.csv', low_memory=False); HS = pd.read_csv(HIST + 'CO_pre1960_hazardous_sites.csv', low_memory=False)
hist_years = sorted(HL.year.unique())
t = old[3]['text']
chk(f"digitised {len(hist_years)} editions between {hist_years[0]} and {hist_years[-1]} ({yrs(hist_years)})" in t, 'business-directory editions in the base prose')
t = rep(t, "checked by hand for Denver, and geocoded", "read by hand against the page text (three reviews, described below), and geocoded")
P(t)
# The three hand reviews: verdict tallies from the review tables in data/historical/ (street-level, town-level, entries without a
# town) and the independent reader's sample of the third; layer counts from the published pre-1960 listings and firm-locations.
SRV = pd.read_csv(HIST + 'street_review.csv', dtype=str).fillna(''); TRV = pd.read_csv(HIST + 'town_review.csv', dtype=str).fillna('')
NRV = pd.read_csv(HIST + 'notown_review.csv', dtype=str).fillna(''); NCK = pd.read_csv(HIST + 'notown_check_2026-11-13.csv', dtype=str).fillna('')
sv, tv, nv = SRV.verdict.value_counts(), TRV.verdict.value_counts(), NRV.verdict.value_counts()
chk(set(sv.index) == {'ok', 'not_works', 'fix_address', 'fix_name', 'doubtful', 'other_town'} and set(tv.index) == {'ok', 'not_works', 'other_town', 'doubtful', 'other_sector'}
    and set(nv.index) == {'ok', 'not_works', 'other_sector', 'doubtful'}, 'review verdict vocabularies')
chk((NRV.town == '').all() and not NRV.duplicated(['year', 'nkey', 'sector']).any(), 'no-town review: one row per entry without a town')
n_nt = len(NRV); nt_drop = int(nv['not_works']); nt_kept = n_nt - nt_drop; nt_doubt = int(nv['doubtful'])
chk(nt_kept == int(((NRV.verdict != 'not_works') & (NRV.town_fix != '')).sum()), 'every kept no-town entry was given a town')
mk = NCK.merge(NRV, on=['year', 'nkey', 'sector'], suffixes=('_c', '_r'), validate='1:1')
chk(len(mk) == len(NCK), 'independent sample rows all found in the review')
kc, kr = mk.verdict_c != 'not_works', mk.verdict_r != 'not_works'
ck_n = len(mk); ck_kept = int(kr.sum()); ck_both = int((kc & kr).sum()); ck_more = int((kc & ~kr).sum()); ck_town = int((mk[kc & kr].town_fix_c == mk[kc & kr].town_fix_r).sum())
chk(ck_both + int((~kc & kr).sum()) == ck_kept and ck_town <= ck_both, 'independent sample tallies')
kept_all = ("kept every one of the " + f"{ck_kept}" + " that the review kept") if ck_both == ck_kept else f"kept {ck_both} of the {ck_kept} that the review kept"
h_street = int((HS.precision == 'street').sum()); h_den = HS[(HS.town == 'DENVER') & (HS.precision == 'street') & (HS.fe_hazard == True)]
chk(set(HS.precision) == {'street', 'town'} and HL.hfirm.nunique() == len(HS), 'pre-1960 firm-locations: one row per firm-location of the listings')
P(f"The business-directory listings were then read against the page text in three hand reviews. The first read every listing placed at a street address ({len(SRV):,}): "
  f"{int(sv['not_works']):,} were dropped as not works, {int(sv['fix_address']):,} addresses and {int(sv['fix_name']):,} names were corrected, {int(sv['other_town']):,} listings were moved to another town and {int(sv['doubtful']):,} doubtful ones were kept and flagged. "
  f"The second read the town-level listings ({len(TRV):,}): {int(tv['not_works']):,} were dropped as not works (offices, dealers, mines, advertisements and neighbours' trades), {int(tv['other_town']):,} were moved to another town, {int(tv['other_sector']):,} were given another hazardous sector and {int(tv['doubtful']):,} doubtful ones were kept and flagged. "
  f"The third read the {n_nt:,} entries that had been extracted without a town: {nt_drop:,} were dropped as not works and {nt_kept:,} were kept and given their town and, where one is printed, their street address ({nt_doubt:,} of them doubtful and flagged). "
  f"An independent reader read a random sample of {ck_n} of these entries and {kept_all}, placing {ck_town} of them in the same town" + (f"; the reader also kept {ck_more} that the review dropped. " if ck_more else ". ") +
  f"After the three reviews the layer holds {len(HL):,} listings of {len(HS):,} firm-locations, {h_street:,} of them placed at street level ({len(h_den):,} hazardous-sector firm-locations in Denver, {int((h_den.review == 'doubtful').sum())} of them doubtful); listings reviewed to a town for which the gazetteer has no point are left out. "
  f"The reviews checked what was extracted, not what was missed: works printed on the pages but never extracted are absent, so the layer still undercounts the hazardous trades.")
# Editions: config/editions.json (complete / partial), checked against the complete flag of data/results/edition_coverage.csv and
# against the editions present in the listing files. Listing totals are counted from the listing files themselves (the per-edition
# files of the complete editions and the all-editions file), not from edition_coverage.csv, whose listing counts are only as
# current as the last run of R/edition_coverage.R. Site counts: app/data/sites.csv, data/full_inventory/sites.csv, checked against
# data/results/known_hidden/sensitivity_counts.csv and summary.md and against site_fate_denver.csv.
# Typed, no committed result file holds them: the 30 m linking distance (method parameter); the 34 mis-placed listings of an
# earlier build, 25 of them 1965, and "finds none" for the current baseline check (manuscript §2).
import glob
cfg = json.load(open(A + 'config/editions.json')); complete = set(cfg['complete_editions']); partial = set(cfg['partial_editions'])
ec = pd.read_csv(R + 'edition_coverage.csv'); mf = ec[ec.series == 'Directory of Colorado Manufacturers']
chk(set(mf[mf.complete == True].year) == complete and set(mf[mf.complete != True].year) == partial, 'complete editions')
LA = pd.read_csv(A + 'data/full_inventory/CO_directory_listings_1961-2002.csv', usecols=['year']).year
chk(set(LA) == complete | partial and not (complete & partial), 'editions in the all-editions listing file')
by_year = {int(os.path.basename(p).split('_')[2]): len(pd.read_csv(p, usecols=[0], low_memory=False)) for p in sorted(glob.glob(A + 'data/by_year/CO_DCM_*_geocoded.csv'))}
chk(set(by_year) == complete, 'one per-edition listing file for each complete edition')
n_list_complete = sum(by_year.values()); n_list_all = len(LA)
chk(n_list_complete == int(LA.isin(complete).sum()), f'listing totals {n_list_complete} {int(LA.isin(complete).sum())}')
_S = pd.read_csv(A + 'app/data/sites.csv', dtype={'GEOID': str}); _S = _S[_S.fe_hazard == True]   # the headline counts are computed, not typed
sites_co = len(_S); sites_denver = int((_S.GEOID.fillna('').str[:5] == '08031').sum()); hidden = int((_S.radar == 'Not on any list').sum())
_SA = pd.read_csv(A + 'data/full_inventory/sites.csv'); sites_all_editions = int((_SA.fe_hazard == True).sum())
chk(sites_all_editions >= sites_co and n_list_all >= n_list_complete, 'all-editions inventory holds the complete editions')
sf = pd.read_csv(R + 'site_fate/site_fate_denver.csv'); chk(len(sf) == sites_denver, 'Denver 1965-92 sites')
ks = pd.read_csv(R + 'known_hidden/sensitivity_counts.csv'); ks = ks[ks.rule == 'published'].set_index('sites')
kh_all, kh_den = ks.loc['F&E hazardous-sector sites (headline)'], ks.loc['F&E sites in the City and County of Denver']
chk((int(kh_all.n_sites), int(kh_all.n_hidden), int(kh_den.n_sites)) == (sites_co, hidden, sites_denver), 'known_hidden counts')
kh = open(R + 'known_hidden/summary.md').read(); chk(f'{sites_co:,} F&E' in kh and f'{hidden:,} ({100 * hidden / sites_co:.1f}%)' in kh, 'known_hidden summary')
P(f"The Directory of Colorado Manufacturers (Business Research Division, University of Colorado, 1961–2002) was scanned from library copies in {len(complete | partial)} editions. "
  f"{W(len(partial), True)} of the scans stop part-way through the geographic section or have missing pages ({', '.join(str(y) for y in sorted(partial))}) and are excluded everywhere; "
  f"the {W(len(complete))} complete editions are {listing(sorted(complete))}. "
  f"The page text was parsed with corrections for defects of the scans (pages scanned twice are read once, listings run together are separated, and fragments without a name are attached to their listing or dropped). "
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
# Correlations and Denver ratio: data/results/benchmarks/benchmarks_summary.md (r = 0.84 / 0.88; Denver 0.96), as in manuscript §2.
# computed here from the county table (cbp_vs_directory_county.csv) and checked against the sentence of the summary.
bs = open(R + 'benchmarks/benchmarks_summary.md').read()
cc = pd.read_csv(R + 'benchmarks/cbp_vs_directory_county.csv', dtype={'county': str}); cc = cc[cc.dir_all > 0]
r_mfg = float(np.corrcoef(np.log1p(cc.dir_mfg), np.log1p(cc.cbp_mfg))[0, 1]); r_haz = float(np.corrcoef(np.log1p(cc.dir_haz), np.log1p(cc.cbp_haz))[0, 1])
den_ratio = float((cc.dir_mfg / cc.cbp_mfg)[cc.county == '031'].median()); n_ed, n_cty = cc.year.nunique(), cc.county.nunique()
chk(f'across {n_ed} editions and {n_cty} counties: r = {r_mfg:.2f} (log manufacturers), {r_haz:.2f} (log hazardous sectors)' in bs and f'(Denver {den_ratio:.2f})' in bs, 'benchmark correlations')
chk(n_ed == len(cb) and set(cb.year) <= complete | partial, 'benchmark editions')
above1 = [int(y) for y in cb[cb.dir_haz > cb.cbp_haz].year]; chk(above1 == [int(y) for y in cb[cb.ratio_haz > 1].year], f'ratios above 1: {above1}')
P(f"Across {n_ed} editions and {n_cty} counties the log directory count correlates with the log CBP count at r = {r_mfg:.2f} (all manufacturing) and {r_haz:.2f} (hazardous sectors); Denver's directory/CBP ratio is {den_ratio:.2f}. "
  "CBP counts every employer establishment from administrative records and the directory lists firms that answered the publisher's questionnaire or were copied from other lists, so the ratios are coverage rates" +
  (f"; ratios above 1 ({', '.join(map(str, above1))}) mean the directory listed more hazardous-sector firms than CBP counted employer establishments, plausibly because it includes some firms without employees." if above1 else ".") +
  " County files are from Eckert et al. (2021).")

# ------------------------------------------------------------------------------------------------ S2
H("S2. Reconstruction of enumeration districts, 1880–1940")
# Mapped populations: the district-group table (denver_eds/ed_year_groups.csv, row "all mapped EDs" = the two groups added),
# checked against the rows of denver_eds_summary.md; county totals: app/data/denver_city_1880_1940.csv;
# geocoding share: denver_eds/ed_geocoding_R.csv (geocoded / addresses, 1900).
# Typed, no committed result file holds them: "60% of the 1900 population after stray geocodes are dropped (73% in 1940)"
# (manuscript §2) and the stray-geocode rule (method parameters, README "Enumeration districts").
eg = pd.read_csv(R + 'denver_eds/ed_geocoding_R.csv').set_index('year')
geo1900 = round(100 * eg.loc[1900, 'geocoded'] / eg.loc[1900, 'addresses'])
chk(eg.loc[1900, 'used'] <= eg.loc[1900, 'geocoded'] <= eg.loc[1900, 'addresses'], '1900 geocoded share')
es = open(R + 'denver_eds/denver_eds_summary.md').read()
yg = pd.read_csv(R + 'denver_eds/ed_year_groups.csv'); yg['census'] = np.repeat(sorted(set(eg.index.tolist()) | {1880}), 3)   # three rows per census, in census order
city = pd.read_csv(A + 'app/data/denver_city_1880_1940.csv').set_index('census')
mapped = {}
for c in [1920, 1930, 1940]:
    g = yg[yg.census == c].set_index('group'); tot = g.loc['dissimilarity (all mapped EDs)']
    chk(int(tot.population) == int(g.loc['EDs with hazardous firms', 'population'] + g.loc['EDs without', 'population']) and int(tot.EDs) == int(eg.loc[c, 'eds']), f'{c} district groups')
    chk(f"| {c} | dissimilarity (all mapped EDs) | {int(tot.EDs)} | {int(tot.population):,} |" in es, f'mapped population {c}')
    chk(int(tot.population) <= int(city.loc[c, 'pop']), f'mapped population within the county total {c}')
    mapped[c] = f"{c}: {int(tot.population):,} of {int(city.loc[c, 'pop']):,}"
t = old[6]['text']
t = rep(t, "clipped to the city.", "clipped to the city. Only the districts of Denver itself are used: Arapahoe County's districts before the 1902 consolidation, and the City and County of Denver's from 1910; because district numbers repeat across counties, districts are selected by county as well as number, and the mapped population is checked against the county total (" + '; '.join(mapped[c] for c in [1920, 1930, 1940]) + ").")
t = rep(t, "Districts with fewer than three geocoded households were merged with their neighbours. 73% of the 1900 population is placed at street level.",
        f"Stray geocodes — farther from the district's person-weighted median centre than the larger of 400 m and 2.5 times the median distance, or with fewer than 30% of their ten nearest neighbours in the same district — are dropped before the tessellation, and districts with fewer than three geocoded households were merged with their neighbours. {geo1900}% of the 1900 addresses are geocoded at street level, and the addresses kept after stray geocodes are dropped hold 60% of the 1900 population (73% in 1940).")
P(t)
# Fixed grid: denver_eds/ed_dissimilarity_fixed_grid.csv (53 and 310 cells).
fg = pd.read_csv(R + 'denver_eds/ed_dissimilarity_fixed_grid.csv'); gx = fg.drop_duplicates('extent').set_index('extent').cells
chk(len(gx) == 2 and fg.groupby('extent').cells.nunique().eq(1).all() and fg[fg.cells == gx.min()].census.nunique() == 6 and fg[fg.cells == gx.max()].census.min() == 1900, 'grid cells')
cells_all, cells_1900 = int(gx['area mapped in all six censuses (1880 city)']), int(gx['area mapped in 1900-1940 (1900 city)'])
P(f"A measure is set to missing in a census whose questionnaire or extract does not carry it (ownership in 1880; SEI in the 1900 extract; rent and residence in 1935 except in 1940; 1940 sample-line items), rather than to zero. Hispanic origin is IPUMS HISPAN, inferred from birthplace, parents' birthplace and Spanish surname. \"Boarders and lodgers\" are household members unrelated to the head (RELATE 12–13). Because the number and size of districts change between censuses, Black–nonblack dissimilarity is also computed on a fixed 500 m grid: each census's district counts are area-weighted onto the grid, using the area mapped in all six censuses ({cells_all} cells) and the area mapped from 1900 ({cells_1900} cells).")
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
# the areas of the layer agree with the 1929 column of the 1929–1944 comparison (an independent tabulation of the same layer);
# the main text's two areas: app/data/zoning_1929_industrial_fate.csv (1929 industrial land in Denver County) and
# app/data/zoning_1929_to_2023.csv (Industrial A covered by the 2023 layer).
ch = pd.read_csv(R + 'zoning_1944/zoning_1929_vs_1944.csv').set_index('zone')
chk(all(abs(za[z] - ch.loc[z, 'km2_1929']) < 0.02 for z in ['Industrial A', 'Industrial B', 'Commercial']), f'1929 zone areas {za.to_dict()}')
zc = pd.read_csv(A + 'data/raw/zoning_1929/zone_cells_1929.csv'); unc = zc[zc.zone.str.startswith('Industrial')].uncertain.mean()
unc_pct = round(100 * unc); chk(0 < unc_pct < 100, f'uncertain share {unc}')
fate = pd.read_csv(A + 'app/data/zoning_1929_industrial_fate.csv'); ind_county = float(fate[fate.group == 'all'].km2.iloc[0])
z23 = pd.read_csv(A + 'app/data/zoning_1929_to_2023.csv').set_index('zone1929').km2_1929
chk(ind_county <= za['Industrial A'] + za['Industrial B'] + 0.05 and z23['Industrial A'] <= za['Industrial A'] + 0.05 and len(fate[fate.group == 'all']) == 1, 'main-text zone areas are parts of the sheet totals')
t = old[8]['text']
t = rep(t, "(43% of industrial cells)", f"({unc_pct}% of industrial cells)")
t = rep(t, "the map yields 24.6 km² Industrial A, 3.8 km² Industrial B and 3.6 km² Commercial.", f"the map yields {za['Industrial A']:.1f} km² Industrial A, {za['Industrial B']:.1f} km² Industrial B and {za['Commercial']:.1f} km² Commercial")
P(t + f" on the whole sheet (the main text's {ind_county:.1f} km² is the industrial land on the part of the sheet that the 1944 map also covers, within Denver County; its {z23['Industrial A']:.1f} km² of Industrial A is the part covered by the 2023 zoning layer).")
# Georeferencing: data/results/zoning_1929/gcp_fit.csv (points and residuals), checked against the control-point table it was
# fitted from (data/raw/zoning_1929/gcps_1929.csv); the 1929–1944 comparison: the review table of the disagreement clusters
# (data/raw/zoning_1929/changes_1944_review.csv: clusters, reviewed, accepted; two accepted clusters of one area count once) and
# zoning_1944/zoning_1929_vs_1944.csv (areas by zone in the two revisions). Off-sheet areas: zoning_1929/zoning_shares_holc.csv.
# Typed, no committed result file holds them: the dropped sixteenth control point (one more than the fitted points) and the
# registration of the 1944 scan (ten-point affine fit, RMSE 25 scan pixels, about 32 m; README "The 1925 zoning ordinance").
g = pd.read_csv(R + 'zoning_1929/gcp_fit.csv'); rmse = float(np.sqrt((g.residual_m ** 2).mean()))
g0 = pd.read_csv(A + 'data/raw/zoning_1929/gcps_1929.csv')
chk(len(g) == len(g0) and (g.px_x.values == g0.px_x.values).all() and (g.px_y.values == g0.px_y.values).all() and g.residual_m.notna().all(), f'gcp {len(g)} {rmse}')
worst = g.loc[g.residual_m.idxmax()]
zs = pd.read_csv(R + 'zoning_1929/zoning_shares_holc.csv'); off = zs[zs.share_industrial_1929.isna()]
hz = pd.read_csv(R + 'holc/holc_zoning_by_grade.csv')
ha = pd.read_csv(R + 'holc/holc_areas.csv')                              # the 1938 map's areas: the graded ones and its two ungraded (industrial, commercial) zones
chk(len(zs) == len(ha) and int(zs.grade.notna().sum()) == int(hz.areas.sum()) and len(off) == int((hz.areas - hz.areas_on_map).sum()) and sorted(off.grade) == sorted(hz[hz.areas > hz.areas_on_map].grade) == ['C', 'D'], 'off-sheet HOLC areas')
rv = pd.read_csv(A + 'data/raw/zoning_1929/changes_1944_review.csv'); acc = rv[rv.accept == 1]
n_areas = len(acc) - int(acc.note.str.contains('same area as').sum())
chk((acc.reviewed == 1).all() and not ((acc.kind == 'added') & (acc.zone_model == 'industrial') & acc.zone_1944.fillna('').str.startswith('Industrial')).any(), '1944 review: accepted clusters')
dA = float(ch.loc['Industrial A', 'change_km2']); chk(dA < 0 and ch.loc['Industrial B', 'change_km2'] <= 0 and abs(dA - (ch.loc['Industrial A', 'km2_1944'] - ch.loc['Industrial A', 'km2_1929'])) < 0.011, '1929-44 change')
P(f"Georeferencing used {W(len(g) + 1)} street intersections and park corners read off the scan and resolved to TIGER/Line road intersections. One of them, the City Park south-west corner at E 17th Avenue and York Street, was dropped as mis-identified (TIGER's 17th Avenue jogs half a block there); the remaining {W(len(g))} all resolve, and an affine fit in UTM zone 13N has a root-mean-square residual of {rmse:.0f} m (individual residuals {g.residual_m.min():.0f}–{g.residual_m.max():.0f} m, the largest at {worst.street1} and {worst.street2}; Table S3). "
  f"The 1944 revision of the same map (CG4314 .G44 1944, revised to 1 April 1944) was registered to the 1929 scan by a ten-point affine fit (RMSE 25 scan pixels, about 32 m). It is a darker print of the same plate. One texture classifier trained on the 1929 labels was applied to both scans; every cluster of disagreement of about a city block or more ({int(rv.reviewed.sum())} of {len(rv)} clusters) was inspected on side-by-side crops of the two scans, and only districts visibly redrawn were accepted ({n_areas} areas). "
  f"No industrial district was added between the two revisions; about {-dA:.2f} km² of Industrial A ({-100 * dA / ch.loc['Industrial A', 'km2_1929']:.0f}% of it) was redrawn as commercial, business or apartment districts. Most disagreements came from the darker 1944 print rather than from redrawn districts; changes smaller than a block, and amendments coloured by hand on the 1944 copy, are not included. "
  f"The map sheet does not cover the whole 1938 graded area: of the {len(zs)} HOLC areas, {W(len(off))} (one C, {off[off.grade == 'C'].area_km2.iloc[0]:.1f} km², and one D, {off[off.grade == 'D'].area_km2.iloc[0]:.1f} km²) lie off the sheet, and zoning shares are computed over the land on the sheet only; districts and tracts less than half on the sheet are left missing.")
rows = [["Control point", "Note", "Scan x (px)", "Scan y (px)", "Residual (m)"]]
for _, r in g.iterrows():
    rows.append([f"{r.street1} & {r.street2}", "" if pd.isna(r.note) or r.note == "" else r.note, int(r.px_x), int(r.px_y), f"{r.residual_m:.1f}"])
rows.append(["Root-mean-square residual", "", "", "", f"{rmse:.1f}"])
T("Table S3. Control points for the 1929 zone map and their residuals from the affine fit (UTM zone 13N)", rows)

# ------------------------------------------------------------------------------------------------ S4
H("S4. Parcel matching, regulatory status and the archival check")
# Parcel matching: data/results/site_fate/site_fate_denver.csv (sites, parcel, distance), site_fate_denver_pre1960.csv (pre-1960
# trades), site_fate_parcel_match.csv (match stages and the situs agreement rate, recomputed here from the stage counts).
# Hidden share: counted from the site inventory above (checked there against the known/hidden tables).
# Typed: the 40 m parcel radius and the inventory radii (method parameters, manuscript §2 Instruments).
pre = pd.read_csv(R + 'site_fate/site_fate_denver_pre1960.csv')
chk(sf.SCHEDNUM.notna().all() and (sf.parcel_dist_m <= 40).all(), 'all 1965-92 sites matched within 40 m')
chk(len(pre) == len(h_den) and set(pre.hfirm.dropna()) <= set(h_den.hfirm), 'pre-1960 parcel matches: one row per Denver street-level F&E trade')
med = sf.parcel_dist_m.median()
pm = pd.read_csv(R + 'site_fate/site_fate_parcel_match.csv'); ag = pm[pm.parcel_match.str.startswith('agreement')].set_index('series').pct
SER_M, SER_P = "Manufacturers' directory sites 1965-1992", 'Business-directory hazardous trades 1891-1956'
ag_mfg = ag[SER_M]; ag_pre = ag[SER_P]
for ser, d_, a_ in [(SER_M, sf, ag_mfg), (SER_P, pre, ag_pre)]:        # the stage counts add up to the sites, and the agreement rate is the same-address stage over the numbered addresses
    st = pm[(pm.series == ser) & ~pm.parcel_match.str.startswith('agreement')].set_index('parcel_match').n
    chk(int(st.sum()) == len(d_) and st.to_dict() == d_.parcel_match.value_counts().to_dict(), 'parcel-match stages ' + ser)
    n_num = int(pm[(pm.series == ser) & pm.parcel_match.str.startswith('agreement')].n.iloc[0]); chk(abs(100 * st['same address'] / n_num - a_) < 0.06, 'situs agreement ' + ser)
t = old[12]['text']
t = rep(t, "Each geocoded Denver site was matched to the nearest City and County of Denver assessor parcel within 40 m (1,256 of 1,258 distinct coordinates; median distance 10 m).",
              f"Each geocoded Denver site was matched to the City and County of Denver assessor parcel within 40 m whose situs address matches the directory address, else the parcel on the same street and side with the nearest house number (fewer than 100 numbers away), else the nearest parcel on the same street, else the nearest parcel. All {len(sf):,} manufacturers' sites of 1965–92 and {('all ' + str(len(pre))) if pre.SCHEDNUM.notna().all() else (str(int(pre.SCHEDNUM.notna().sum())) + ' of the ' + str(len(pre)))} pre-1960 street-located trades have a parcel within 40 m; the median distance is {med:.0f} m, and the situs address matches the directory address outright for {ag_mfg:.0f}% of the manufacturers' sites and {ag_pre:.0f}% of the pre-1960 trades.")
t = rep(t, "Regulatory status was assigned from EPA's Facility Registry Service, TRI, SEMS and RCRA and from Colorado's voluntary-cleanup and environmental-covenant registers by location (40–75 m), address or name; a geocoding error",
              f"Regulatory status was assigned from EPA's Facility Registry Service, TRI, SEMS, ACRES brownfields and RCRA (handlers and corrective action) and from Colorado's cleanup, Superfund, brownfield, voluntary-cleanup, UMTRA, solid-waste and environmental-covenant registers, matched by location (40–100 m by inventory, grown by the site's spread up to 250 m), by a record at the same address (street type and unit ignored) or by name; under this rule {hidden:,} of the {sites_co:,} Colorado sites ({100 * hidden / sites_co:.0f}%) match no record. A geocoding error")
P(t)
# Residential sites: counted from site_fate_denver.csv; the residential total is checked against the use-by-decade table
# (site_fate_summary.csv), and the sentence's "most" and "of this kind" against the counts.
res = sf[sf.use_now == 'Residential']; n_res = len(res)
before = int((res.year_built <= res.last_year).sum()); later = int((res.year_built > res.last_year).sum()); nodate = int(res.year_built.isna().sum())
nr = res[res.radar == 'Not on any list']; n_nr = len(nr); nr_before = int((nr.year_built <= nr.last_year).sum())
fs = pd.read_csv(R + 'site_fate/site_fate_summary.csv')
chk(n_res == int(fs[(fs.series == SER_M) & (fs.use_now == 'Residential')].n.sum()) and before + later + nodate == n_res and int(fs[fs.series == SER_M].n.sum()) == len(sf), f'residential counts {(n_res, before, later, nodate, n_nr, nr_before)}')
chk(2 * before > n_res and 2 * nr_before > n_nr and 0 < n_nr <= n_res, f'"most residential sites" no longer holds {(n_res, before, n_nr, nr_before)}')
P(f"For {before} of the {n_res} residential sites of 1965–92 the present building was built in or before the site's last listing year; {later} were built later and {nodate} have no date. Most residential sites are therefore small firms in or beside dwellings, or geocodes that fell on a neighbouring dwelling, rather than conversions. Of the {n_nr} residential sites with no record in the searched inventories, {nr_before} are of this kind.")
sb = pd.read_csv(R + 'site_fate/archival_check_sanborn_1887_1904.csv'); sbv = sb.matches_geocode.value_counts()
chk(set(sbv.index) == {'yes', 'partial', 'no', 'inconclusive'} and int(sbv.sum()) == len(sb) and sb.sanborn_sheet.str.startswith('1890').all(), 'Sanborn check rows')
# a checked trade whose firm number is blank is no longer in the reviewed street-level layer (the check file is re-keyed to the layer)
sb_gone = sb.hfirm.isna(); chk(sb.hfirm.dropna().isin(h_den.hfirm.tolist() + HS[(HS.town == 'DENVER') & (HS.precision == 'street')].hfirm.tolist()).all(), 'Sanborn check: firm numbers are those of the current layer')
rows = [["Firm", "Address", "Sector", "Listed", "1890 sheet", "Use shown on the sheet", "Matches geocode"]]
for _, r in sb.iterrows():
    ys = str(r.years_listed).split()
    rows.append(['—' if pd.isna(r.hfirm) else r.hfirm, r.street, r.sectors, ys[0] if len(ys) == 1 else ys[0] + '–' + ys[-1], str(r.sanborn_sheet).replace('1890 ', ''), str(r.use_shown_on_sheet).replace('""', '"'), r.matches_geocode])
T(f"Table S4. Sanborn check of {W(len(sb))} street-located hazardous trades on the 1890 sheets (Library of Congress)", rows)
# Tally of the check's verdict column (yes / partial / no / inconclusive).
P(f"Of the {W(len(sb))}, the sheet shows the listed trade at the geocoded lot for {W(int(sbv['yes']))}, a related use on or immediately beside the lot for {W(int(sbv['partial']))}, a different use for {W(int(sbv['no']))}, and is inconclusive for {W(int(sbv['inconclusive']))}." +
  (f" The sheets were read before the hand reviews of the pre-1960 layer: {W(int(sb_gone.sum()))} of the {W(len(sb))} placements are no longer in the street-level layer ({W(int((sb_gone & (sb.matches_geocode == 'no')).sum()))} of the {W(int(sbv['no']))} with a different use and {'all ' + W(int(sbv['inconclusive'])) if (sb_gone | (sb.matches_geocode != 'inconclusive')).all() else W(int((sb_gone & (sb.matches_geocode == 'inconclusive')).sum())) + ' of the ' + W(int(sbv['inconclusive']))} inconclusive ones among them) and are shown without a firm number in Table S4." if sb_gone.any() else ""))

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
# Typed, no committed result file holds it: the ungraded Industrial and Commercial zones have four tracts each (manuscript §4).
tm = pd.read_csv(R + 'holc/holc_tract_models.csv'); chk(set(tm.grade) == {'B', 'C', 'D'} and (tm.n_class >= 5).all(), 'tract model classes')
hisp_start = int(tm[tm.outcome == 'p_hisp'].period.str[:4].astype(int).min())
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
bsel = pd.concat([tm[(tm.outcome == o) & (tm.period == per) & (tm.grade == 'B')] for o, per, _ in sel])
bx = bsel[(bsel[['p', 'p_conley2km', 'p_zone_strict']] < 0.05).any(axis=1)]
chk((bsel[['p', 'p_zone', 'p_zone_strict']] >= 0.05).all().all(), 'B estimates under HC1 and strict zoning')
labs = {o: l for o, _, l in sel}
bnote = ("No B estimate in the table differs from A under HC1 standard errors or with the zoning controls" +
         ("." if not len(bx) else "; with Conley standard errors " + "; ".join(f"the B estimate for {labs[r.outcome]} {r.period.replace('-', '–')} ({f(r.b, 1)}) has p = {pv(r.p_conley2km)}" for _, r in bx.iterrows()) + "."))
P(f"The strict zoning layer drops the {unc_pct}% of industrial cells classified only by the platted thick-hatch rule. The Hispanic-share models start in {hisp_start}, the first census that identifies Hispanic residents comparably on tracts; the ungraded Industrial and Commercial zones (four tracts each) are dropped with the other classes of fewer than five tracts. " + bnote)

# ------------------------------------------------------------------------------------------------ S6
H("S6. Tract analyses on fixed tract sets")
# Tract counts: the largest model n of each census in denver_tracts/denver_tracts_models.csv (a model drops tracts missing its
# outcome); fixed sets: the model n of denver_tracts_models_fixed.csv, checked against the count in each set's label.
# Typed: the 10 km radius and the 200-resident floor (method parameters).
import re
fx = pd.read_csv(R + 'denver_tracts/denver_tracts_models_fixed.csv')
tmod = pd.read_csv(R + 'denver_tracts/denver_tracts_models.csv'); tn = tmod[tmod.census > 0].groupby('census').EDs.max().astype(int)
fixed_n = {}
for s_ in fx.set.unique():
    y0, n_lab = map(int, re.fullmatch(r'fixed (\d{4})-2020 \((\d+) tracts\)', s_).groups()); n_mod = int(fx[(fx.set == s_) & (fx.census > 0)].EDs.max())
    chk(n_mod == n_lab and n_lab <= int(tn[tn.index >= y0].min()), f'fixed set {s_}: model n {n_mod}'); fixed_n[y0] = n_lab
chk(sorted(fixed_n) == [1950, 1960, 1970] and tn[1950] < tn[1960] <= tn[tn.index >= 1970].min(), f'fixed sets {set(fx.set)}')
later_n = tn[tn.index >= 1970]
P(f"Every tract analysis uses the {int(tn.max())} tracts (2010 boundaries) whose centroid lies within 10 km of downtown Denver, dropping tracts with fewer than 200 residents. Because fewer of these tracts were populated and tracted in 1950 ({tn[1950]}) than in 1960 ({tn[1960]}) or from 1970 ({later_n.min()}–{later_n.max()}), Table S10 repeats the distance models on the tracts observed in every census from 1950 ({fixed_n[1950]} tracts), 1960 ({fixed_n[1960]}) and 1970 ({fixed_n[1970]}).")
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
# The gap in the editions is the longest run of years without one in the published pre-1960 listings.
# Typed: the 100-resident floor (method parameter).
gaps = [(b - a, a, b) for a, b in zip(hist_years[:-1], hist_years[1:])]; _, g_a, g_b = max(gaps)
first_after = [int(v) for v in C.first_trade.dropna() if g_b <= v < g_b + 5]
chk(g_b - g_a > 10 and not ((C.first_trade > g_a) & (C.first_trade < g_b)).any() and len(first_after) > 0, 'edition gap and first listings after it')
P(f"Location quotients from the 1900–1940 districts area-weighted into each D area (the first census with a location quotient of 2 is reported only where the area then held at least 100 residents). No business-directory edition survives for {g_a + 1}–{g_b - 1}, so a first listing in {g_b}–{str(g_b + 4)[2:]} is an upper bound on when a trade arrived.")
A2 = pd.read_csv(R + 'descriptive/grid_first_arrival_1900_1940.csv')
rows = [["Decade", "Group", "Cells", "Population", "% Black", "% Hispanic", "% foreign born", "% laborers", "% owner", "km to downtown", "Change % Black", "Change % Hispanic", "Change % foreign born", "Change % owner"]]
for _, r in A2.iterrows(): rows.append([f"{r['from']}–{r['to']}", r.group, int(r.cells), f"{int(r['pop']):,}", r.pct_black_before, r.pct_hisp_before, r.pct_fb_before, r.pct_laborers_before, r.pct_owner_before, r.km_to_downtown, f(r.chg_black), f(r.chg_hisp), f(r.chg_fb), f(r.chg_owner)])
T("Table S12. Grid cells with no hazardous trade ever listed, by whether a first trade was listed in the next decade: composition at the start and change over the decade (all decades)", rows)

# ------------------------------------------------------------------------------------------------ S8
H("S8. The companion application")
P(old[-1]['text'])

json.dump(B, open(os.path.join(HERE, 'si_blocks.json'), 'w'), ensure_ascii=False)
print(len(B), 'blocks,', sum(x['type'] == 'table' for x in B), 'tables')
