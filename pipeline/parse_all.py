"""Parse OCR output of every volume into listing records -> work/parsed/<volume>.jsonl

A scan page that is present twice in one edition (the part-volumes of 1966, 1970, 1977 and 1983 overlap by one or two
pages; DCM_1962_part2 holds three scans of the same two pages) is parsed once: duplicate_pages() finds the copies by
the similarity of their OCR text, drop_duplicate_pages() keeps the better-read copy and logs the others.
A record without a firm name is not a listing (see parse_block.attach_fragments); drop_nameless() removes what is left
of them after the parsers and logs the count per volume."""
import os, sys, re, json, glob, collections
sys.path.insert(0, os.path.dirname(__file__))
from volumes import VOLUMES
import parse_block, parse_1965, parse_table, parse_1988, parse_para, parse_2002
from segment import load_words
T = 'work/tsv'
DUP_SIM = 0.80        # share of the smaller page's words found on the other page (observed: copies 0.86-0.98, other pairs <= 0.60)
DUP_MIN_WORDS = 100   # title pages and section dividers (40-80 words, identical in every part) hold no listings
def parse_vol(vol, year, parser, mode, T=T, ctx=None):
    """ctx: town/county context handed from one part-volume of an edition to the next (block format only)."""
    if parser == 'block':   R = parse_block.parse_volume(vol, T, year, ctx)
    elif parser == '1965':  R = parse_1965.parse(vol, T, year)
    elif parser == 'table': R = parse_table.parse(vol, T, year)
    elif parser == '1988':  R = parse_1988.parse(vol, T, year)
    elif parser == 'para':  R = parse_para.parse_coltxt(vol, year) if mode == 'coltxt' else parse_para.parse_tsv(vol, T, year)
    elif parser == '2002':  R = parse_2002.parse(vol, year, 3)
    return R

def page_words(path):
    """Multiset of the words (4+ letters/digits, upper-cased) of one OCR page (.tsv word boxes or .txt column text)."""
    if path.endswith('.tsv'): toks = [w['s'] for w in load_words(path)]
    else: toks = [t for l in open(path) if not l.startswith('=====COL') for t in l.split()]
    c = collections.Counter(re.sub(r'[^A-Z0-9]', '', t.upper()) for t in toks)
    return collections.Counter({t: n for t, n in c.items() if len(t) >= 4})

def similarity(a, b):
    """Share of the words of the smaller page that also occur on the other (multiset overlap / smaller size)."""
    na, nb = sum(a.values()), sum(b.values())
    if not na or not nb: return 0.0
    return sum(min(n, b.get(t, 0)) for t, n in a.items()) / min(na, nb)

def duplicate_pages(pages, sim=DUP_SIM, min_words=DUP_MIN_WORDS):
    """pages: {(vol, page): word multiset} of ONE edition. Returns groups (sorted lists of keys) of pages that are scans
    of the same printed page: connected components of 'similarity >= sim', pages under min_words ignored."""
    keys = sorted(k for k, w in pages.items() if sum(w.values()) >= min_words)
    parent = {k: k for k in keys}
    def find(k):
        while parent[k] != k: parent[k] = parent[parent[k]]; k = parent[k]
        return k
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            if similarity(pages[a], pages[b]) >= sim: parent[find(b)] = find(a)
    groups = collections.defaultdict(list)
    for k in keys: groups[find(k)].append(k)
    return [sorted(g) for g in groups.values() if len(g) > 1]

def page_quality(recs):
    """How well a page copy was read: listings with a name, a street/ZIP and an industry (a page read with the wrong
    number of columns gives nameless fragments and merged lines)."""
    named = [r for r in recs if re.search(r'[A-Za-z]{3}', r.get('name') or '')]
    return (len(named), sum(1 for r in named if r.get('zip') or r.get('street')), sum(1 for r in named if r.get('sic') or r.get('sic_desc')))

def edition_pages(vols, tsvdir=T):
    P = {}
    for vol in vols:
        mode = VOLUMES[vol][2] if vol in VOLUMES else 'tsv'
        files = glob.glob(f'work/coltxt/{vol}/p*.txt') if mode == 'coltxt' else glob.glob(f'{tsvdir}/{vol}/p*.tsv')
        for f in files: P[(vol, int(os.path.basename(f)[1:4]))] = page_words(f)
    return P

def complete_editions(path='config/editions.json'):
    """Editions whose scans cover the whole geographic section (config/editions.json); none when the file is absent."""
    try: return set(json.load(open(path)).get('complete_editions', []))
    except OSError: return set()

def handover(ctx, prev_vol, vol, groups):
    """Town/county context with which `vol` starts: that of the end of `prev_vol`, or, when `vol` opens with pages that
    repeat pages of `prev_vol`, the context in force when the first repeated page began there."""
    if not ctx: return {}
    twins = sorted((q, p) for g in groups for (v1, p) in g for (v2, q) in g if v1 == prev_vol and v2 == vol)
    if twins and twins[0][1] in ctx.get('page_start', {}):
        city, county = ctx['page_start'][twins[0][1]]
        return dict(city=city, county=county)
    return dict(city=ctx.get('city'), county=ctx.get('county'))

def drop_duplicate_pages(parsed, pages, log=print, min_words=DUP_MIN_WORDS, groups=None):
    """parsed: {vol: records} of one edition; pages: {(vol, page): word multiset}. For every group of duplicate scan
    pages keep the records of one copy and drop the others'. The copy kept is, in this order: not clearly worse read
    (at least 85% of the named listings of the best copy: DCM_1966_part1 p32 is read as two columns, its twin as three);
    the one with real pages before and after it in its own volume (a listing that starts on the previous page or ends
    on the next is whole only there: of 'part1 p52-53 = part2 p2-3' that is part1 p52 and part2 p3); best page_quality;
    first volume/page. Returns ({vol: records}, [(kept key, dropped key, n dropped)])."""
    skipped = []
    drop = set()
    real = lambda k: k in pages and sum(pages[k].values()) >= min_words
    for g in (duplicate_pages(pages, min_words=min_words) if groups is None else groups):
        byk = {k: [r for r in parsed.get(k[0], []) if r.get('page') == k[1]] for k in g}
        q = {k: page_quality(byk[k]) for k in g}
        best = max(x[0] for x in q.values())
        rank = lambda k: (q[k][0] >= 0.85 * best, real((k[0], k[1] - 1)) + real((k[0], k[1] + 1)), q[k], -g.index(k))
        keep = max(g, key=rank)
        for k in g:
            if k != keep:
                drop.add(k); skipped.append((keep, k, len(byk[k])))
                log(f'  duplicate scan page: {k[0]} p{k[1]} = {keep[0]} p{keep[1]}; kept {keep[0]} p{keep[1]} '
                    f'({len(byk[keep])} listings), dropped {len(byk[k])} listings of {k[0]} p{k[1]}')
    out = {v: [r for r in R if (v, r.get('page')) not in drop] for v, R in parsed.items()}
    return out, skipped

def drop_nameless(R):
    """Records without a firm name (no letter or digit in it) are fragments, not listings. Returns (kept, n dropped)."""
    keep = [r for r in R if re.search(r'[A-Za-z0-9]', r.get('name') or '')]
    return keep, len(R) - len(keep)

def main():
    os.makedirs('work/parsed', exist_ok=True)
    by_year = collections.defaultdict(list)
    for vol, (year, parser, mode) in VOLUMES.items(): by_year[year].append(vol)
    tot_dup = tot_frag = 0
    COMPLETE = complete_editions()
    for year, vols in by_year.items():
        pages = edition_pages(vols); groups = duplicate_pages(pages)
        parsed = {}; ctx = {}; prev = None             # volumes of an edition are listed in reading order in VOLUMES
        for vol in vols:
            # only where part N+1 continues part N: a partial edition has pages missing between its parts
            ctx = handover(ctx, prev, vol, groups) if year in COMPLETE else {}
            parsed[vol] = parse_vol(vol, *VOLUMES[vol], ctx=ctx); prev = vol
        parsed, skipped = drop_duplicate_pages(parsed, pages, groups=groups)
        tot_dup += sum(n for _, _, n in skipped)
        for vol in vols:
            R, nfrag = drop_nameless(parsed[vol]); tot_frag += nfrag
            with open(f'work/parsed/{vol}.jsonl', 'w') as f:
                for r in R: f.write(json.dumps(r) + '\n')
            S = getattr(parse_block, 'STATS', {}).get(vol, {})
            S65 = getattr(parse_1965, 'STATS', {}).get(vol)
            print(f'{vol:22s} {year} {VOLUMES[vol][1]:6s} {len(R):6d} listings, with ZIP {sum(1 for r in R if r.get("zip"))}'
                  f', nameless fragments dropped {nfrag}'
                  + (f', fragments attached {S.get("attached", 0)}, name-like lines left in extra {S.get("namelike_extra", 0)}' if S else '')
                  + (f', headings {S65}' if S65 else ''))
    print(f'duplicate-page listings dropped: {tot_dup}; nameless fragments dropped: {tot_frag}')
if __name__ == '__main__': main()
