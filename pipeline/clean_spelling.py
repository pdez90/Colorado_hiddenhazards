"""Repair scan misreadings in firm and street names from the other editions' listings of the same establishment.

link.py gives every listing an estab_id (the same firm at the same address across editions). A firm listed in five editions is
read five times, and the misreadings differ ('ESKIMO RADIATOK HFG Co', 'ESKIMO RADIATOR MEG CO', 'ESKIMO RADIATOR MFG CC'), so the
readings can be voted on: word by word, and letter by letter inside words of equal length. A listing's name is replaced by the
consensus only when it is already a near match to it (similarity >= 80), so a renamed firm keeps its new name. Street names are
voted on the same way, but only among readings whose digits are identical: a house or street number is never changed here.
The text as read stays in name_as_read / street_as_read. Establishments listed once are left as read.

  python pipeline/clean_spelling.py        # rewrites work/inv/records_linked.pkl in place
"""
import re
from collections import Counter
import pandas as pd
from rapidfuzz import fuzz

def _norm(s):
    return re.sub(r'\s+', ' ', re.sub(r'[»«©@§_*|~`^=]+', ' ', str(s))).strip(' .,;:').upper()

def _alike(a, b):
    """Two words that can be misreadings of each other: near matches, or short words of equal length one letter apart (CC / CO)."""
    return a == b or fuzz.ratio(a, b) >= 60 or (len(a) == len(b) <= 3 and sum(x != y for x, y in zip(a, b)) == 1)

def clean_group(names, years=None, digits_must_match=False):
    """New spellings for one establishment's readings (same order).

    Readings are split into groups of near matches with the same number of words (so 'X CO' and 'X CO INC', or '319 N MAIN' and
    '319 MAIN', are never made alike). Inside a group of at least three readings a word is replaced only by a strict-majority
    word, or, where no word has a majority, letter by letter by strict-majority letters among the words of the same length.
    Two readings that disagree carry no information about which is right and are left alone, as is any reading whose words all
    survive the vote (its case and punctuation stay as read)."""
    N = [_norm(x).split(' ') for x in names]; J = [' '.join(t) for t in N]; out = list(names); groups = []
    dig = lambda x: re.findall(r'\d+', x)
    for i, x in enumerate(J):
        for g in groups:
            if len(N[i]) == len(N[g[0]]) and fuzz.ratio(x, J[g[0]]) >= 80 and (not digits_must_match or dig(x) == dig(J[g[0]])): g.append(i); break
        else: groups.append([i])
    for g in groups:
        if len(g) < 3: continue
        new = {i: list(N[i]) for i in g}
        for k in range(len(N[g[0]])):
            col = [N[i][k] for i in g]; w, c = Counter(col).most_common(1)[0]
            # in a street, a one- or two-letter word is a direction (N, SW) or a number: the geocoder reads it as printed, so it is not voted
            if digits_must_match and min(len(x) for x in col) <= 2: continue
            if c * 2 > len(col):
                for i in g:
                    if _alike(N[i][k], w): new[i][k] = w      # a different word ('HEATING' for 'MFG') is a different name, not a misreading
                continue
            L = Counter(len(x) for x in col).most_common(1)[0][0]; same = [i for i in g if len(N[i][k]) == L]
            if len(same) < 3: continue
            for j in range(L):
                ch, c = Counter(N[i][k][j] for i in same).most_common(1)[0]
                if c * 2 > len(same):
                    for i in same: new[i][k] = new[i][k][:j] + ch + new[i][k][j + 1:]
        for i in g:
            if new[i] != N[i] and (not digits_must_match or dig(' '.join(new[i])) == dig(J[i])): out[i] = ' '.join(new[i])
    return out

def main():
    df = pd.read_pickle('work/inv/records_linked.pkl')
    if 'name_as_read' in df.columns: df['name'] = df.name_as_read; df['street'] = df.street_as_read      # rerun: start from the text as read
    df['name_as_read'] = df['name']; df['street_as_read'] = df['street']
    nm, st = df['name'].tolist(), df['street'].tolist(); pos = {ix: k for k, ix in enumerate(df.index)}
    # readings that vote together: the listings of one establishment, plus listings at the same street address and town (link.py
    # does not always join a badly misread name to its establishment); clean_group then separates the different firms by name
    par = list(range(len(df)))
    def find(x):
        while par[x] != x: par[x] = par[par[x]]; x = par[x]
        return x
    for col in [df.estab_id.where(df.estab_id.notna(), None),
                (df.street_n.fillna('') + '|' + df.city_g.fillna('')).where(df.street_n.fillna('').str.match(r'^\d+ \S'), None)]:
        first = {}
        for k, v in enumerate(col):
            if v is None: continue
            if v in first: par[find(k)] = find(first[v])
            else: first[v] = k
    comp = {}
    for k in range(len(df)): comp.setdefault(find(k), []).append(k)
    names, streets, years = [str(x or '') for x in df['name']], [str(x or '') for x in df['street']], df.year.astype(int).tolist()
    for ks in comp.values():
        if len(ks) < 3: continue
        for k, v in zip(ks, clean_group([names[k] for k in ks], [years[k] for k in ks])): nm[k] = v
        ss = [k for k in ks if streets[k]]
        for k, v in zip(ss, clean_group([streets[k] for k in ss], [years[k] for k in ss], digits_must_match=True)): st[k] = v
    df['name'] = nm; df['street'] = st
    a = (df['name'] != df.name_as_read).sum(); b = (df.street != df.street_as_read).sum()
    print(f'spelling consensus: {a} of {len(df)} names and {b} street names respelled from other editions of the same establishment')
    df.to_pickle('work/inv/records_linked.pkl')

if __name__ == '__main__': main()
