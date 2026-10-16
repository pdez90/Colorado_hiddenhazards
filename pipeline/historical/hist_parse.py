"""Extract hazardous-trade listings from Colorado State Business Directory text (1870s–1940s gazetteer format).

Each volume is a town-by-town gazetteer of 'Name, trade, address.' entries. We (1) track the current town from
running headers ('Alpine Business Directory.', 'DELTA COLO.') and town headings matched to a USGS GNIS gazetteer,
(2) split the text into entries, (3) keep entries whose trade matches a historically hazardous trade."""
import re, sys, os, json, glob
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
G = pd.read_csv(os.path.join(HERE, '..', '..', 'data', 'historical', 'gnis_places_co.csv'), dtype=str)
TOWNS = set(G.name)
ALIAS = {'COLOSPRINGS': 'COLORADO SPRINGS', 'CANONCITY': 'CANON CITY', 'ORO': 'LEADVILLE', 'COLORADO SPRINGS': 'COLORADO SPRINGS', 'COLO SPRINGS': 'COLORADO SPRINGS', 'CANON CITY': 'CANON CITY', 'CAÑON CITY': 'CANON CITY',
         'EAST DENVER': 'DENVER', 'WEST DENVER': 'DENVER', 'NORTH DENVER': 'DENVER', 'SOUTH DENVER': 'DENVER', 'ORO CITY': 'LEADVILLE'}

# historical trade vocabulary -> (sector, Frickel & Elliott major group or 'EXT')
TRADES = [
 (r"\bsmelt(?:er|ers|ing)\b|\breduction works\b|\brefining works\b|\blead works\b|\bblast furnace", 'Smelting & refining', '33'),
 (r"\bfoundr(?:y|ies)\b|\bbrass works\b|\bfoundrymen\b", 'Foundry', '33'),
 (r"\brolling mill|\bsteel works|\biron works|\bstructural (?:iron|steel)|\bornamental iron", 'Iron & steel works', '33'),
 (r"\bmachine (?:shop|works)|\bmachinists?\b|\bengine works|\bmining machinery|\bboiler (?:maker|works|shop)", 'Machine shop / machinery', '35'),
 (r"\btinners?\b|\btin shop|\bsheet (?:iron|metal)|\bcornice works|\bgalvaniz|\bplating|\belectroplat|\bstove (?:works|foundry)|\bwire works|\bstamping works|\bmetal works", 'Metal working', '34'),
 (r"\bchemical (?:works|co|company|laborator|mfg|manufactur)|\bchemicals?\b|\bacid works|\bcyanide", 'Chemicals', '28'),
 (r"\bpaint (?:works|mfr|manufactur|factory|mfg)|\bvarnish (?:works|manufactur)|\bwhite lead", 'Paint & varnish', '28'),
 (r"\bsoap (?:works|factory|mfr|manufactur|maker)", 'Soap', '28'),
 (r"\bpowder (?:works|mill|co|company|mfr|manufactur|magazine)|\bexplosives|\bdynamite|\bgiant powder", 'Explosives', '28'),
 (r"\bfertiliz|\bbone (?:works|mill)|\brendering", 'Fertilizer & rendering', '28'),
 (r"\boil refin|\brefinery\b|\bpetroleum (?:co|works|refin)|\basphalt", 'Petroleum refining & asphalt', '29'),
 (r"\brubber (?:works|goods mfr|manufactur|mfg|co\b)", 'Rubber', '30'),
 (r"\bcarriage (?:works|factory|maker|mfr|manufactur)|\bwagon (?:works|factory|maker|makers|shop|mfr|manufactur)|\bcar shops?\b|\brailroad shops|\brailway shops|\broundhouse|\bauto(?:mobile)? (?:body|works|mfr|manufactur)", 'Transportation equipment', '37'),
 (r"\bassay(?:er|ers|ing)?\b|\bassay office", 'Assay office', 'EXT'),
 (r"\bstamp mill|\bore (?:mill|buyers?|sampl|concentrat)|\bsampling (?:works|mill)|\bconcentrat(?:ing|or|ion) (?:works|mill)|\bcustom mill|\bmill(?:ing)? co\b.*\bore|\bchlorination", 'Ore milling & sampling', 'EXT'),
 (r"\bgas (?:works|light|co\b|company)|\bgas & electric|\bgaslight", 'Manufactured gas', 'EXT'),
 (r"\btanner(?:y|ies|s)?\b|\btanning", 'Tannery', 'EXT'),
 (r"\btie (?:treating|preserving|plant)|\bwood preserv|\bcreosot", 'Wood preserving', 'EXT'),
 (r"\bcoke (?:ovens|works|co)\b|\bcoking", 'Coke works', 'EXT'),
 (r"\bbatter(?:y|ies) (?:works|mfr|manufactur)", 'Batteries', 'EXT'),
]
TRADE_RE = [(re.compile(p, re.I), s, g) for p, s, g in TRADES]
EXCLUDE = re.compile(r"\b(supplies|supply|agent|agents|dealer|dealers|insurance|stock|broker|attorney|journal|school|teacher|church)\b", re.I)

NOSPACE = {}
for n in sorted(TOWNS, key=len):
    if any(w in n for w in (' COUNTY', ' DIVISION', 'CENSUS DESIGNATED')): continue
    NOSPACE.setdefault(re.sub(r'[^A-Z]', '', n), n)
    if n.startswith('SAINT '): NOSPACE.setdefault('ST' + re.sub(r'[^A-Z]', '', n[6:]), n)

def norm_town(t):
    t = re.sub(r"[^A-Z ]", " ", t.upper().replace('Ñ', 'N'))
    t = re.sub(r"\s+", " ", t).strip()
    t = re.sub(r"\s*\b(COLO|COLORADO|COL)$", "", t).strip()
    if t in ALIAS: return ALIAS[t]
    k = t.replace(' ', '')
    if k in ALIAS: return ALIAS[k]
    return NOSPACE.get(k)

HDR = [re.compile(r"^\s*([A-Z][A-Za-z\.' ]{2,30}?)\s+Business\s+Directory\.?\s*$"),
       re.compile(r"^\s*([A-Z][A-Z\.' ]{2,30}?),?\s+COLO\.?\s*$"),
       re.compile(r"^\s*([A-Z][A-Z\.' ]{2,30}?)[\.,]?\s*$")]
DESC = re.compile(r"\b(county|population|postoffice|post office|census|R\. ?R\b|railroad|miles (?:from|north|south|east|west))", re.I)

def collapse(l):
    return re.sub(r"[^A-Za-z]", "", l).upper()

def page_abbrevs(lines):
    """Running-head abbreviations ('DEN', 'D EL') giving the first/last town on the page."""
    ab = [collapse(l) for l in lines if re.fullmatch(r"\s*[A-Z](?:\s?[A-Z]){2}\s*", l)]
    return sorted(set(ab))

BIG = {'DEN': 'DENVER', 'LEA': 'LEADVILLE', 'PUE': 'PUEBLO'}

def in_range(town, ab):
    if not ab or not town: return True
    k = collapse(town)[:3]
    return ab[0] <= k <= ab[-1]

def town_events(lines):
    """Return list of (line_index, town) where the current town changes."""
    ev = []
    for i, l in enumerate(lines):
        s = l.strip()
        c = collapse(s)
        if c.endswith('BUSINESSDIRECTORY') and len(c) > 17:
            t = NOSPACE.get(c[:-17]) or NOSPACE.get(re.sub('(COLO|COLORADO)$', '', c[:-17]))
            if t: ev.append((i, t)); continue
        if not s or len(s) > 45: continue
        mc = re.match(r"^([A-Z][A-Z\.' ]{2,30}?)\s+CON[T'’ ]*[DI1]{1,2}\b", s)
        if mc and norm_town(mc.group(1)):
            ev.append((i, norm_town(mc.group(1)))); continue
        m = HDR[0].match(s)
        if m:
            t = norm_town(m.group(1))
            if t: ev.append((i, t)); continue
        m = HDR[1].match(s)
        if m:
            t = norm_town(m.group(1))
            if t: ev.append((i, t)); continue
        # bare caps heading followed within 3 lines by a gazetteer description
        if s.upper() == s and HDR[2].match(s):
            t = norm_town(s)
            if t and any(DESC.search(lines[j]) and len(lines[j]) < 90 for j in range(i + 1, min(i + 4, len(lines)))):
                ev.append((i, t))
    return ev

ENTRY_SPLIT = re.compile(r"(?:(?<=[a-z]{2}\.)|(?<=[a-z]\.\))|(?<=\d\.))\s+(?=(?:[A-Z][a-zA-Z'’\-]+|[A-Z]\.?)(?:,| &| and| [A-Z][a-z]+,| [A-Z]\.?,| [A-Z][a-z]+ [A-Z]))")
ADDR = re.compile(r"\b(\d{1,5})\s+((?:[NSEW]\.?\s+)?(?:\d{1,3}(?:st|nd|rd|th|d)|[A-Z][a-z]+)(?:\s+(?:st|av|ave|avenue|street|blvd|pl|ct|way|rd))?)\.?", re.I)

def entries(text):
    text = re.sub(r"[­­]\s*\n\s*", "", text)        # soft-hyphen line breaks
    text = re.sub(r"-\s*\n\s*(?=[a-z])", "", text)
    text = re.sub(r"\s*\n\s*", " ", text)
    return [e.strip() for e in ENTRY_SPLIT.split(text) if len(e.strip()) > 6 and '....' not in e and '. . .' not in e]

TOWN_RX = re.compile(r"\b(" + "|".join(sorted({re.escape(t.title()) for t in NOSPACE.values() if len(t) > 4}, key=len, reverse=True)) + r")\b")
OUT_OF_STATE = re.compile(r"\b(N\. ?Y|New York|Chicago|St\.? Louis|Ill\.|Mo\.|Kansas City|Omaha|Jersey City|Pa\.|Philadelphia|Boston|Cincinnati|San Francisco|Mass\.|Ohio)\b")

NARRATIVE = re.compile(r"\$\d|\bozs?\.?\b|per cent|per ton|\bPopulation\b|\bcensus\b|\bestimated\b|\bmiles\b|\btons\b|\bvalue\b|\bores?\b.*\b(gold|silver)\b|\bwe\b|\bthe (?:mine|lode|vein)", re.I)

ADDR_END = re.compile(r"\b\d{1,5}(?:-\d+)?\s+(?:[NSEW]\.?\s)?(?:\d{1,3}(?:st|nd|rd|th|d)|[A-Z][a-z]+)(?:\s(?:st|av|Av|Sts?|blk|Bldg))?\b|\bblk\b|\bBldg\b")
FIRMEND = re.compile(r"(?i)^[\w\s&'’\.]{0,25}?\b(works|co|company|foundry|mfg|mill|mills|shops?)\b\.?")
def firm_name(e, ms, me):
    """Name = text before the trade word; if the trade word is part of a firm name ('Colorado Chemical Works'),
    keep the firm name through its 'Works'/'Co'."""
    pre = e[:ms].strip(' ,.;—-')
    if re.search(r"(?i)works|co\b|foundry|company|mfg|shops?$", e[ms:me]) or FIRMEND.match(e[me:]):
        f = FIRMEND.match(e[me:]); end = me + (f.end() if f else 0)
        if pre and not pre.endswith(','): return (pre + ' ' + e[ms:end]).strip(' ,.')
    return pre or e.split(',')[0]

# place names that are also surnames, smelter names or ordinary words: only accepted when written as a place ('Grant, Colo')
AMBIG = {'GRANT', 'HENRY', 'GLOBE', 'ARGO', 'UNION', 'GARFIELD', 'GATES', 'EMPIRE', 'LINCOLN', 'WASHINGTON', 'FRANKLIN', 'JACKSON',
         'ADAMS', 'BRUSH', 'MODEL', 'STANDARD', 'CENTRAL', 'ORCHARD', 'LIBERTY', 'HOPE', 'VICTOR', 'MONARCH', 'EUREKA', 'PIONEER',
         'CLIMAX', 'SUPERIOR', 'STAR', 'SUNSHINE', 'WESTERN', 'NATIONAL', 'AMERICAN', 'PEOPLES', 'GOLDEN', 'SILVER', 'CRYSTAL',
         'IRON', 'BRIGHTON', 'MARBLE', 'BOONE', 'HOLLY', 'ALMA', 'PARKER', 'LAWSON', 'WALDEN', 'ROLLINSVILLE', 'MANITOU', 'GILMAN',
         'MORRISON', 'FLORENCE', 'ARVADA', 'LAMAR', 'TELLER', 'OURAY', 'KIOWA', 'OTIS', 'HUGO', 'MEAD', 'NIWOT', 'WINDSOR', 'BERTHOUD'}
def town_in_text(e):
    for m in TOWN_RX.finditer(e):
        t = m.group(1).upper()
        if t not in AMBIG or re.match(r"\s*,?\s*Colo\b", e[m.end():]) or re.search(r"\b(?:at|in|of)\s+$", e[:m.start()]):
            return t
    return None

def parse_volume(path, year, vol, mode=None):
    mode = mode or ('classified' if year <= 1880 else 'entry' if year < 1900 else 'line')
    raw = open(path, encoding='utf-8', errors='ignore').read()
    pages = ['\n'.join(despace(l) for l in p.split('\n')) for p in raw.split('\f')]
    seen = {}
    for ptxt in pages:
        for _, t in town_events(ptxt.split('\n')): seen[t] = seen.get(t, 0) + 1
    def recover(ab):
        for a in ab:
            if a in BIG: return BIG[a]
        c = [t for t in seen if collapse(t)[:3] in ab]
        return max(c, key=seen.get) if c and len({collapse(t)[:3] for t in c}) == 1 else None
    out = []; town = None; keep = None
    for pg, ptxt in enumerate(pages, 1):
        lines = ptxt.split('\n')
        ab = page_abbrevs(lines)
        ev = [(i, t) for i, t in town_events(lines) if in_range(t, ab)]
        if ab and (town is None or not in_range(town, ab)):
            town = recover(ab)
        # running heads repeating the town name ('DENVER' ... 'DENVER') fix the town at the top of the page
        caps = [norm_town(l) for l in lines[:25] if l.strip() and l.strip().upper() == l.strip() and len(l.strip()) < 30]
        rh = [t for t in set(caps) if t and caps.count(t) >= 2]
        if len(rh) == 1 and not ab:
            town = rh[0]
        # city-directory sections ('DENVER DIRECTORY.') use surname running heads, not town abbreviations
        cd = [NOSPACE.get(collapse(l)[:-9]) for l in lines[:15] if collapse(l).endswith('DIRECTORY') and 'BUSINESS' not in collapse(l)]
        cd = [c for c in cd if c]
        if cd:
            town = cd[0]; ab = []
            ev = [(i, t) for i, t in town_events(lines)]
        # classified-by-trade sections ('Denver, STAR BOILER ...'): town is given in each entry
        if re.search(r"^(?:[A-Z][a-z]+ ?){1,3}, [A-Z]", ptxt, re.M) and sum(1 for l in lines if re.match(r"^(?:[A-Z][a-z]+ ?){1,3}, [A-Z]{2,}", l)) >= 3:
            keep = town; town = None; ev = []
        cuts = [(0, town)] + ev
        for k, (start, cur) in enumerate(cuts):
            end = cuts[k + 1][0] if k + 1 < len(cuts) else len(lines)
            seg = lines[start:end]
            cands = []
            if mode in ('entry', 'classified'):
                for e in entries('\n'.join(seg)):
                    for rx, sec, grp in TRADE_RE:
                        for m in (rx.finditer(e) if len(e) > 180 else [rx.search(e)]):
                            if not m: continue
                            ee, ms, me = e, m.start(), m.end()
                            if len(e) > 180:          # run-on address-list text (1887 classified etc.): cut a local window
                                lo = max(0, ms - 90)
                                pre = e[lo:ms]
                                cut = list(ADDR_END.finditer(pre))
                                lo = lo + cut[-1].end() if cut else lo
                                hi = min(len(e), me + 60)
                                post = ADDR.search(e, me, hi)
                                ee = e[lo:post.end() if post else hi]; ms -= lo; me -= lo
                            cands.append((firm_name(ee, ms, me), ee, (sec, grp, m.group(0))))
                        if cands and cands[-1][1] is not None and rx.search(e): break
            if mode == 'classified':
                for j, nm, hit in classified_entries(seg):
                    cands.append((nm, nm + ', ' + hit[2], hit))
            if mode == 'line':
                for j, ln, hit, ctx in line_entries(seg):
                    nm = re.split(r",\s|\s\(|\s\d{2,5}\s", ln)[0]
                    nm = re.split(r"(?<=[a-z])-\s+(?=[A-Z])", nm)[-1]
                    cands.append((nm, ctx, hit))
            for name, e, hit in cands:
                if EXCLUDE.search(e[:120]) and not re.search(r"works|mfr|manufactur|foundry|smelt|shop|assay", e, re.I): continue
                if OUT_OF_STATE.search(e): continue
                if len(e) > 200 or NARRATIVE.search(e) or re.match(r"^\W*\d", name): continue
                name = name[:90].strip(' ,.;')
                if len(name) < 3: continue
                t, src = cur, 'heading'
                if not t:
                    t = town_in_text(e); src = 'entry'
                a = ADDR.search(e)
                out.append(dict(vol=vol, year=year, page=pg, town=t or '', town_src=src if t else '', name=name,
                                entry=e[:240], trade=hit[2].lower(), sector=hit[0], fe_group=hit[1],
                                street=(a.group(1) + ' ' + a.group(2)) if a else '', mode=mode))
        if ev: town = ev[-1][1]
        elif keep: town = keep
        keep = None
    return out

def despace(l):
    """Undo letter-spaced OCR: 'B r e w e rie s .' -> 'Breweries.', 'W hite, W m .' -> 'White, Wm.'"""
    toks = l.split(' ')
    singles = sum(1 for t in toks if len(t) == 1 and t.isalpha())
    if singles >= 2 and singles >= 0.3 * len(toks):
        out = ''
        for t in toks:
            if not t: continue
            if out and (len(t) <= 3 and t[0].isalpha() and not out.endswith((',', '.')) or t in ('.', ',')):
                out += t
            else:
                out += (' ' if out else '') + t
        l = out
    l = re.sub(r"\b([A-Z]) ([a-z]{2,})", r"\1\2", l)
    return re.sub(r"\s+([\.,])", r"\1", l)

# ---- extra modes -------------------------------------------------------------------------------------------
NAME_LINE = re.compile(r"^[A-Z][A-Za-z'’\.\-]+(?:[ ,]+[A-Za-z&'’\.\-]+){0,6}\.?$")
HEADING_LINE = re.compile(r"^[A-Z][A-Za-z ,&\.\-]{3,45}$")

def classified_entries(lines):
    """Classified format (1878-80): a trade heading ('Foundry and Machine Shops,') followed by name lines."""
    out = []; i = 0
    while i < len(lines):
        s = lines[i].strip()
        hit = None
        if s and HEADING_LINE.match(s) and len(s.split()) <= 6:
            for rx, sec, grp in TRADE_RE:
                m = rx.search(s)
                if m: hit = (sec, grp, m.group(0)); break
        if hit:
            j = i + 1; names = []
            while j < len(lines) and len(names) < 40:
                t = lines[j].strip()
                if not t: j += 1; continue
                if NAME_LINE.match(t) and not any(rx.search(t) for rx, _, _ in TRADE_RE) and len(t) < 50 \
                        and re.search(r"\w,\s|\s&\s|\bCo\b|\bBros\b", t.rstrip(',. ')):
                    names.append((j, t)); j += 1
                else: break
            for j_, t in names:
                out.append((j_, t, hit))
            i = j
        else: i += 1
    return out

def line_entries(lines):
    """Modern format (1910-1939): one firm per line, trade usually in the firm name or after a comma; columns
    interleaved, so we take the line holding the keyword plus a short look-ahead for its address."""
    out = []
    for i, l in enumerate(lines):
        s = l.strip()
        if len(s) < 6: continue
        for rx, sec, grp in TRADE_RE:
            m = rx.search(s)
            if m:
                ctx = ' '.join(x.strip() for x in lines[i:i + 3])
                out.append((i, s, (sec, grp, m.group(0)), ctx)); break
    return out


if __name__ == '__main__':
    path, year = sys.argv[1], int(sys.argv[2])
    R = parse_volume(path, year, os.path.basename(path)[:-4])
    df = pd.DataFrame(R)
    print(len(df), 'hazardous-trade entries;', (df.town != '').mean().round(2), 'with town')
    print(df.sector.value_counts().to_string())
    print(df.sample(min(15, len(df)), random_state=1)[['town', 'name', 'trade', 'street']].to_string())


