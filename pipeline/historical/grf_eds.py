"""Denver enumeration-district boundaries 1900-1940, reconstructed from Brown University's Geographic Reference Files (GRF).

Brown's GRF for Denver (Urban Transition HGIS, UTP2) lists every person of the 1900-1940 full-count censuses with the household's
street, house number and enumeration district (ED), but no coordinates and no ED boundaries. This script:
  1. geocodes every distinct address with the project's offline TIGER/Line geocoder (Denver's post-1887 numbering still applies);
  2. drops the geocodes that land far from the rest of their ED (misread numbers, renamed streets);
  3. builds a Voronoi tessellation of the remaining addresses, dissolves the cells by ED and clips them to the built-up area,
     which gives space-filling ED polygons in the manner of census tracts;
  4. attaches the IPUMS full-count ED aggregates (work/census/denver_ed_1880_1940.csv) and the GRF's own race counts.
1880 is done the same way from Brown's geocoded 1880 buildings (their coordinates, our polygons).
Outputs (the polygons are this project's derived product; Brown's address files stay in work/):
  data/results/denver_eds/denver_eds_<year>.geojson, data/results/denver_eds/ed_geocoding.csv
Run from the repository root:  python pipeline/historical/grf_eds.py [years...]
"""
import sys, re, os, json, collections
import numpy as np, pandas as pd, geopandas as gpd
from shapely import concave_hull
from shapely.geometry import Point, MultiPoint
from shapely.ops import voronoi_diagram
sys.path.insert(0, 'pipeline'); sys.path.insert(0, 'pipeline/historical')
from tiger_geocode import Geocoder
RENAME = {'HOLLADAY': 'MARKET', 'MCGAA': 'MARKET', 'BDWY': 'BROADWAY', 'WASH': 'WASHINGTON', 'SANTA': 'SANTA FE', 'PENNA': 'PENNSYLVANIA', 'PENN': 'PENNSYLVANIA',
          'CALIF': 'CALIFORNIA', 'COLO': 'COLORADO'}
GRF = 'work/census/brown/grf/DenverCO'; OUT = 'data/results/denver_eds'; os.makedirs(OUT, exist_ok=True)
UTM = 26913; KEEP = re.compile(r'^(fuzzy_)?range_interp')      # accepted geocode qualities (no zip/city centroids, no nearest-segment-end)
YEARS = [int(a) for a in sys.argv[1:]] or [1880, 1900, 1910, 1920, 1930, 1940]
ip = pd.read_csv('work/census/denver_ed_1880_1940.csv')

def ipums_ed(year):
    """IPUMS ENUMDIST -> the ED label used in the GRF (and in Brown's 1880 layer); sums counts, population-weights means/medians."""
    x = ip[(ip.YEAR == year) & (ip.COUNTYICP.isin([50, 310]))].copy()
    if year == 1940:
        e = x.ENUMDIST.astype(str).str.zfill(7)
        x['ED'] = e.str[2:6].astype(int).astype(str) + e.str[6].map({'0': '', '1': 'A', '2': 'B', '3': 'C'}).fillna('')
    else:
        x['ED'] = (x.ENUMDIST % 100000).astype(str)
    avg = [c for c in x.columns if c.startswith(('mean_', 'median_'))]
    cnt = [c for c in x.columns if c not in avg + ['YEAR', 'COUNTYICP', 'ENUMDIST', 'denver_city', 'denver', 'ED'] and pd.api.types.is_numeric_dtype(x[c])]
    out = x.groupby('ED', as_index=False)[cnt].sum()
    for c in avg:
        w = x.assign(_w=x['pop'] * x[c].notna()).groupby('ED').apply(lambda g: np.average(g[c].fillna(0), weights=g['_w']) if g['_w'].sum() > 0 else np.nan, include_groups=False)
        out[c] = out.ED.map(w)
    return out

def hn(s):
    m = re.search(r'(\d+)', str(s)); return int(m.group(1)) if m else None

def geocode_year(year, geo):
    g = pd.read_csv(f'{GRF}/DenverCO_{year}.csv', dtype=str, usecols=lambda c: c in {'b_ed', 'b_hn', 'b_stfull', 'b_race', 'b_head', 'b_hh', 'b_hisp'})
    g['num'] = g.b_hn.map(hn); g = g[g.num.notna() & g.b_stfull.notna() & g.b_ed.notna()].copy()
    g['addr'] = g.num.astype(int).astype(str) + ' ' + g.b_stfull.str.upper().str.replace(r'[^A-Z0-9 ]', '', regex=True).str.strip()
    g['black'] = g.b_race == '2'
    A = g.groupby('addr').agg(persons=('addr', 'size'), black=('black', 'sum'), ED=('b_ed', lambda s: s.mode().iloc[0]),
                              households=('b_hh', 'nunique')).reset_index()
    cache = f'work/census/grf_geocoded_{year}.csv'
    if os.path.exists(cache):
        C = pd.read_csv(cache, dtype={'addr': str})
    else:
        rows = []
        for i, a in enumerate(A.addr):
            st = a
            for k, v in RENAME.items(): st = re.sub(rf'\b{k}\b', v, st)
            la, lo, q = geo.geocode(st, 'DENVER', '')
            rows.append((a, la, lo, q))
            if i % 10000 == 0: print(year, i, '/', len(A), flush=True)
        C = pd.DataFrame(rows, columns=['addr', 'lat', 'lon', 'q']); C.to_csv(cache, index=False)
    A = A.merge(C, on='addr', how='left')
    A['ok'] = A.q.fillna('').str.match(KEEP) & A.lat.notna()
    return g, A

def ed_polygons(P, year):
    """P: GeoDataFrame (UTM) of address points with ED and persons. Returns ED polygons."""
    P = P.copy()
    # outliers: farther from the ED's (person-weighted) median centre than max(400 m, 2.5 x the ED's median distance)
    keep = np.zeros(len(P), bool)
    for ed, grp in P.groupby('ED'):
        cx, cy = np.median(np.repeat(grp.geometry.x, grp.persons.clip(1, 50))), np.median(np.repeat(grp.geometry.y, grp.persons.clip(1, 50)))
        d = np.hypot(grp.geometry.x - cx, grp.geometry.y - cy); thr = max(400, 2.5 * np.median(d)) if len(grp) >= 5 else 600
        keep[P.index.get_indexer(grp.index)] = d <= thr
    P = P[keep].reset_index(drop=True)
    # neighbourhood smoothing: a point whose 10 nearest neighbours (person-weighted) mostly belong to another ED is a misplaced
    # geocode (or an ED's isolated address) and is dropped; EDs are compact, so a lone point inside another district is noise
    from scipy.spatial import cKDTree
    xy = np.c_[P.geometry.x, P.geometry.y]; tree = cKDTree(xy); _, nb = tree.query(xy, k=11)
    eds = P.ED.values; w = P.persons.clip(1, 50).values
    agree = np.array([np.sum(w[nb[i, 1:]][eds[nb[i, 1:]] == eds[i]]) / np.sum(w[nb[i, 1:]]) for i in range(len(P))])
    P = P[agree >= 0.3].reset_index(drop=True)
    pts = MultiPoint([(x, y) for x, y in zip(P.geometry.x, P.geometry.y)])
    hull = concave_hull(pts, ratio=0.25).buffer(120)
    cells = list(voronoi_diagram(pts, envelope=hull.buffer(500)).geoms)
    cg = gpd.GeoDataFrame(geometry=cells, crs=UTM)
    j = gpd.sjoin(cg, P[['ED', 'geometry']], predicate='contains', how='inner').drop_duplicates(subset=None, keep='first')
    j = j[~j.index.duplicated()]
    j['geometry'] = j.geometry.intersection(hull)
    E = j.dissolve(by='ED', as_index=False)[['ED', 'geometry']]
    E['geometry'] = E.geometry.buffer(0)
    # keep each ED's main body (parts smaller than a quarter of the largest are islands from stray geocodes); then give the
    # freed ground to the ED whose main body is nearest, so the districts stay space-filling
    def main_parts(g):
        if g.geom_type != 'MultiPolygon': return g
        parts = sorted(g.geoms, key=lambda p: p.area, reverse=True); big = parts[0].area
        from shapely.ops import unary_union
        return unary_union([p for p in parts if p.area >= 0.25 * big])
    E['geometry'] = E.geometry.map(main_parts)
    freed = hull.difference(E.geometry.union_all() if hasattr(E.geometry, 'union_all') else E.geometry.unary_union)
    if not freed.is_empty:
        pieces = [p for p in (freed.geoms if freed.geom_type == 'MultiPolygon' else [freed]) if p.area > 1]
        bodies = E.geometry.values
        for p in pieces:
            d = [p.distance(b) for b in bodies]; k = int(np.argmin(d))
            E.loc[E.index[k], 'geometry'] = bodies[k].union(p); bodies = E.geometry.values
    E['geometry'] = E.geometry.buffer(0)
    stats = P.groupby('ED').agg(addresses=('persons', 'size'), persons_geocoded=('persons', 'sum'), black_geocoded=('black', 'sum')).reset_index()
    E = E.merge(stats, on='ED', how='left')
    E['area_km2'] = E.geometry.area / 1e6
    return E, len(P)

def main():
    geo = Geocoder(); log = []
    for year in YEARS:
        if year == 1880:
            B = pd.concat([gpd.read_file(f'work/census/brown/{k}1880/{k}1880.shp') if os.path.exists(f'work/census/brown/{k}1880/{k}1880.shp') else gpd.read_file(f'work/census/brown/{k}1880.shp')
                           for k in ('singleunit', 'multiunit')])
            B = B[B.Match_addr.str.contains('Denver, CO', na=False)].to_crs(UTM)
            P = gpd.GeoDataFrame({'ED': B.enumdist.astype(int).astype(str), 'persons': B.poptotB.fillna(1).astype(float), 'black': 0.0}, geometry=B.geometry, crs=UTM)
            n_addr = len(P); n_ok = len(P)
        else:
            g, A = geocode_year(year, geo)
            n_addr = len(A); n_ok = int(A.ok.sum())
            print(f'{year}: {len(g):,} persons at {n_addr:,} addresses; {n_ok:,} addresses geocoded at street level ({100 * A.persons[A.ok].sum() / A.persons.sum():.1f}% of persons)')
            Ak = A[A.ok]
            P = gpd.GeoDataFrame(Ak[['ED', 'persons', 'black']], geometry=gpd.points_from_xy(Ak.lon, Ak.lat), crs=4326).to_crs(UTM)
        E, n_used = ed_polygons(P, year)
        I = ipums_ed(year); E = E.merge(I, on='ED', how='left')
        E['year'] = year
        E.to_crs(4326).to_file(f'{OUT}/denver_eds_{year}.geojson', driver='GeoJSON')
        cov = E['pop'].notna().sum()
        print(f'{year}: {len(E)} ED polygons ({cov} with IPUMS totals, {I.ED.nunique()} EDs in IPUMS), {n_used:,} addresses used after outlier removal; median ED area {E.area_km2.median():.2f} km2')
        log.append(dict(year=year, addresses=n_addr, geocoded=n_ok, used=n_used, eds=len(E), eds_ipums=int(I.ED.nunique()), median_area_km2=round(float(E.area_km2.median()), 3)))
    pd.DataFrame(log).to_csv(f'{OUT}/ed_geocoding.csv', index=False, mode='a', header=not os.path.exists(f'{OUT}/ed_geocoding.csv'))

if __name__ == '__main__': main()
