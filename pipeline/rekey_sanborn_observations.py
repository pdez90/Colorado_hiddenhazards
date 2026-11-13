"""The hand-recorded Sanborn observations (data/raw/sanborn/sanborn_observations_batch1.csv) and the two work lists they were read
from (data/results/context/sanborn_batch1*.csv) name each checked place by the site id it had when the sheets were read. Site ids
(S..... and HF.....) are renumbered whenever the inventory or the pre-1960 layer is rebuilt, so this script re-keys the three files
to the current ids by the directory address (and, for pre-1960 trades, the best-matching name at that address). A row whose place
is no longer in the layer keeps its observation but gets a blank id (it then joins to nothing). Run after the two chains
(run_all.sh does); it changes nothing when the ids are current."""
import re
import pandas as pd
from rapidfuzz import fuzz
norm = lambda s: re.sub(r'[^A-Z0-9]', '', re.sub(r'\b(ST|STREET|AVE|AV|AVENUE|BLVD|RD|DR|PL|CT)\b\.?', '', str(s).upper()))
S = pd.read_csv('app/data/sites.csv', dtype=str, keep_default_na=False)
H = pd.read_csv('app/data/historical_sites.csv', dtype=str, keep_default_na=False)
H = H[(H.town == 'DENVER') & (H.precision == 'street')]
SA = {}; [SA.setdefault(norm(a), []).append(i) for a, i, c in zip(S.address, S.site_id, S.city) if c == 'DENVER']
HA = {}; [HA.setdefault(norm(a), []).append((i, n)) for a, i, n in zip(H.street, H.hfirm, H.name)]
H_ADDR = dict(zip(H.hfirm, H.street))
def num_street(a):
    m = re.match(r'\s*(\d+)\s+(.*)', str(a).upper())
    return (int(m.group(1)), norm(m.group(2))) if m else (None, None)
def rekey(old, addr, name, status):
    k = norm(addr)
    if str(old).startswith('HF') or 'pre-1960' in str(status):
        # the same firm at the same address; failing that, the same firm on the same street within the block (a review may have
        # corrected the house number: "1622 Blake" read on the sheet, "1616 Blake" in the reviewed layer). A different firm now
        # at the address is not the place that was read.
        sc = lambda t: fuzz.token_sort_ratio(str(name).upper(), t[1].upper())
        c = [t for t in HA.get(k, []) if sc(t) >= 60]
        if c: return max(c, key=sc)[0]
        n0, st0 = num_street(addr)
        if n0 is None: return ''
        c = [(i, nm) for a2, lst in HA.items() for i, nm in lst if num_street(H_ADDR[i])[1] == st0 and abs(num_street(H_ADDR[i])[0] - n0) < 50]
        c = [t for t in c if sc(t) >= 80]
        return max(c, key=sc)[0] if c else ''
    c = SA.get(k, [])
    return c[0] if len(c) == 1 else (old if old in c else (c[0] if c else ''))
for f, acol, ncol, scol, icol in [('data/raw/sanborn/sanborn_observations_batch1.csv', 'directory_address', 'directory_name', 'series_status', 'id'),
                            ('data/results/context/sanborn_batch1.csv', 'address', 'name', 'status', 'id'), ('data/results/context/sanborn_batch1_sheets.csv', 'address', 'name', 'status', 'id'),
                            ('data/results/site_fate/archival_check_sanborn_1887_1904.csv', 'street', 'name', None, 'hfirm')]:
    d = pd.read_csv(f, dtype=str, keep_default_na=False)
    new = [rekey(i, a, n, st) for i, a, n, st in zip(d[icol], d[acol], d[ncol], d[scol] if scol else ['pre-1960'] * len(d))]
    print(f'{f}: {len(d)} rows, {sum(n != o for n, o in zip(new, d[icol]))} ids changed, {sum(n == "" for n in new)} places no longer in the layer')
    d[icol] = new; d.to_csv(f, index=False)
