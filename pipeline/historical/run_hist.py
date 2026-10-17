import re, os, glob, sys
import pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hist_parse import parse_volume
from parse_1950 import parse as parse_1950
LAST = re.compile(r"(?:^|(?<=\.)\s+|(?<=\s))([A-Z][A-Za-z'’\-]+(?:,\s| &| and | Bros| Mining| Smelting| Sampling| Reduction| [A-Z]\.)[^.]*(?:\.[^.]*)?)$")
def clean_name(n):
    parts = re.split(r"(?<=[a-z]{2}\.)\s+(?=[A-Z])", n)
    n = parts[-1] if len(parts) > 1 and len(parts[-1]) > 3 else n
    n = re.sub(r"^(?:[A-Z](?:\s?[A-Z]){2}\s+)+", "", n)          # running heads like 'DEN '
    return re.sub(r"\s+", " ", n).strip(' ,.;')
rows = []
for f in sorted(glob.glob('work/hist/text/*.txt')):
    y = int(re.search(r"(18\d\d|19\d\d)", f).group(1))
    r = parse_1950(f) if y == 1950 else parse_volume(f, y, os.path.basename(f)[:-4])
    print(f, y, len(r), flush=True)
    rows += r
df = pd.DataFrame(rows)
df['name'] = df.name.map(clean_name)
# --- drop individuals listed by occupation (city-directory style: 'Linquist Peter, lab, Globe smelter, r. 123 X')
PERSON = re.compile(r"\br\.\s?\d|\bbds\.?\s|\b(lab|labr|elk|clk|foreman|helper|emp|wks|bkpr|bookkpr|supt|engineer|fireman|furnaceman|clerk|driver|watchman|tmstr|teamster|wife|wid|student|bartender)\b[,.]", re.I)
FIRM = re.compile(r"\b(Co|Company|Works|Bros|Mfg|Foundry|Smelting|Sampling|Reduction|Mill|Mills|Refining|Iron|Shop|Shops|Corp|Corporation|Inc|Plant|Gas|Chemical)\b|&", re.I)
# an occupation word between the person's name and the employer ('Cain Patrick, stoker, Denver Gas Co') marks a worker
# listed at his home address, not a works: drop it even though the employer is a firm
OCC = re.compile(r"(?i)(?:^|,\s*|\s)(lab|labr|laborer|stoker|foreman|clk|elk|clerk|fireman|fitter|gas fitter|inspector|cashier|pres['’]?t|president|mgr|manager|supt|superintendent|switchman|porter|helper|engineer|driver|teamster|bkpr|bookkeeper|sec['’]?y|treas|agt|agent|collector|watchman|salesman|smelterman|furnaceman|roaster|sampler|worker|wire worker|carpenter|blacksmith|machinist|moulder|molder|tinner|boilermaker|coremaker|wks|emp|student|wid|bds|r\.)\s*[,.]?\s*(?:at\s+)?(?:the\s+)?[A-Z]")
def is_person(r):
    e = str(r.entry)
    m = re.search(re.escape(str(r.trade)), e, re.I)
    head = e[:m.start()] if m else e
    if re.search(r"\br\.\s?\d|\bbds\.?\s", e): return True                      # residence marker
    if OCC.search(head) and re.match(r"^[A-Z][a-z’']+\s+[A-Z][a-z]+", head.strip(' .,"<>*')): return True   # 'Surname Given, occupation, Employer'
    return bool(PERSON.search(e)) and not FIRM.search(str(r.name))
df['is_person'] = df.apply(is_person, axis=1)
# --- interleaved columns (1900+ text layers run several listings into one line):
# (1) a trade that comes after another listing's address belongs to that next listing ('Goldhammer S, phys, 312 17th. GOODRICH RUBBER CO')
# (2) the street must follow the firm within its own listing; text after the next 'Surname Initials,' is someone else's
from hist_parse import ADDR
NEXT = re.compile(r"[,.;]\s+[A-Z][a-z’']+\s+[A-Z](?:\s[A-Z])?(?:\s[A-Z][a-z]+)?,\s")
def own_listing(r):
    e = str(r.entry); m = re.search(re.escape(str(r.trade)), e, re.I)
    if not m: return pd.Series([True, r.street])
    in_name = str(r.trade).lower() in str(r['name']).lower()
    head = e[:m.start()]
    if not in_name and ADDR.search(head) and not re.search(r"(?i)\b(?:mfrs?|manufactur|works|shop)\b", head): return pd.Series([False, ''])
    rest = e[m.end():]; cut = NEXT.search(rest); rest = rest[:cut.start()] if cut else rest
    a = ADDR.search(rest) or (ADDR.search(head) if in_name else None)
    return pd.Series([True, (a.group(1) + ' ' + a.group(2)) if a else ''])
LINE = (df.year >= 1900) & (df.year != 1950) & (df.sector != 'Radium & uranium')   # radium firms: names repaired below, placed at town
df[['own', 'street2']] = [True, None]
df.loc[LINE, ['own', 'street2']] = df[LINE].apply(own_listing, axis=1).values
print('line-mode entries whose trade belongs to a neighbouring listing:', int((~df.own.astype(bool)).sum()),
      '; streets changed:', int((LINE & (df.street2.fillna('') != df.street.fillna(''))).sum()))
df.loc[LINE, 'street'] = df.loc[LINE, 'street2']
df = df[df.own.astype(bool)].drop(columns=['own', 'street2'])
df.loc[df.entry.str.contains(r"\br\.\s?(?:rear\s+)?\d", na=False), 'is_person'] = True     # 'r. rear 2152 Champa' = residence
# corporate / sales offices are not works: keep the firm, but do not map it at the office address
df['office'] = df.entry.str.contains(r"(?i)\b(?:offices?|bldg|blk|block|building|rooms?|suite)\b|\b(?:agt|agency|agents?)\b")
print('dropped as persons:', int(df.is_person.sum()), '; office listings:', int(df.office.sum()))
# radium & uranium: the text layers interleave columns, so the entry's first words are often a neighbouring listing
# ('Roehford Mrs E, hairdressing, 26 Rocky Mountain Radium Products'); take the firm name around the radium/vanadium words instead,
# and drop descriptive town paragraphs ('At Idaho Springs there are radium water baths') and bare section headings
RAD = df.sector == 'Radium & uranium'
FIRM_RAD = (r"((?:(?:[A-Z][\w'.]*|&)\s+){0,4}(?:Radium|RADIUM|Carnotite|Vanadium|VANADIUM|Uranium|MINERALS RECOVERY|Minerals Recovery)"
            r"(?:[\w&'. ]{0,40}?\b(?:Products|Springs|Baths|Mill|Ores)(?:\s+(?:Co|CO|co)\b)?|[\w&'. ]{0,40}?\b(?:Co|CO|co|Corp\w*|Gorp|Company)\b))")
def _radname(e):
    m = re.search(FIRM_RAD, str(e)); return m.group(1).strip(' -—“"&') if m else None
nm = df.loc[RAD, 'entry'].map(_radname)
df.loc[RAD & nm.reindex(df.index).notna(), 'name'] = nm.dropna()
_moved = RAD & pd.Series([str(e).find(str(n)) > 3 for e, n in zip(df.entry, df.name)], index=df.index)
df.loc[RAD, 'street'] = ''   # their addresses are offices or belong to the neighbouring listing: place radium firms at the town only
df = df[~(RAD & (nm.reindex(df.index).isna() | df.entry.str.match(r"\s*(?:At |largest|of |outschools|[a-z])")))]
df = df[~df.is_person]
# listings whose name is plainly not an industrial firm (column-interleaving in the 1950 coded volume attaches codes to neighbours)
NONIND = r"(?i)\b(groc\w*|grocery|club|fruit|cafe|caf[eé]|store|hotel|motel|assn|association|church|school|bank|tavern|bar|restaurant|beauty|barber|insurance|realty|sales|calculating|florist|house|saloon|bakery|dairy|drug\w*|press club)\b"
df = df[~df.name.str.contains(NONIND) | (df.sector == 'Radium & uranium')]   # radium-cure hotels/baths are kept on purpose
# names made only of trade/place words are section headings or ad slogans, not firms
GENERIC = r"(?i)\b(the|co|company|inc|corp|mfg|manufactur\w*|works?|and|of|sheet|metal|iron|steel|brass|wire|ornamental|structural|foundr\w*|machine\w*|machinists?|shops?|tinners?|tanners?|tannery|assay\w*|smelt\w*|refin\w*|reduction|sampling|mills?|chemicals?|chemists?|gas|electric|light|oil|supply|supplies|plating|electro|platers?|wagons?|carriage|makers?|boilers?|repair\w*|denver|colorado|rocky|mountain|creosote|asphalt|rubber|powder|soap|paint|cornice|galvaniz\w*|engines?|mining|coal|ore|stamp|fertiliz\w*|machining|welding|painting|body|auto|suite|upon|request|office|for|years?|phone|pounders|finishers|pattern|consumers|petroleum|coordinator|abstract)\b"
distinct = df.name.str.replace(GENERIC, ' ', regex=True).str.replace(r'[^A-Za-z]', '', regex=True)
df = df[distinct.str.len() >= 3]
# a street must look like 'number + street name'; drop fragments like '4 Gas', '2 CD', '447 av'
ok = df.street.fillna('').str.match(r"^\d{1,5}(?:-\d+)?\s+(?:[NSEW]\.?\s+)?(?:\d{1,3}(?:st|nd|rd|th|d)\b|[A-Z][a-z]{2,})") & \
     ~df.street.fillna('').str.contains(r"(?i)\b(gas|agts?|co|works?|miles?|feet|ft|tons?|stamps?|to|business|denver)\b$")
df.loc[~ok, 'street'] = ''
# a 'name' that is just a town ('Greeley', 'Kit Carson') is a classified-section town label, not a firm
_towns = set(pd.read_csv('data/historical/gnis_places_co.csv').name)
df = df[~df.name.str.upper().str.replace(r'[^A-Z ]', '', regex=True).str.strip().isin(_towns)]
# the same text in many towns in one edition is a running advertisement
_k = df.name.str.upper().str.replace(r'[^A-Z0-9]', '', regex=True)
_spread = df.assign(k=_k).groupby(['year', 'k']).town.transform('nunique')
df = df[_spread <= 3]
print('kept', len(df))
# --- junk names
bad = (df.name.str.len() < 4) | df.name.str.match(r"^[a-z]") | (df.name.str.count(r"[^A-Za-z0-9 ,\.&'’\-]") > 3) \
      | df.name.str.fullmatch(r"(?i)(the )?(smelt\w*|foundr\w*|assay\w*|stamp mills?|machin\w*|tinners?|ers|works?)") \
      | (df.name.str.len() > 70)
df['name_quality'] = (~bad).map({True: 'ok', False: 'poor'})
df = df[df.name.str.len() >= 4]
# --- duplicate copies of the same edition
df['nkey'] = df.name.str.upper().str.replace(r"[^A-Z0-9]", "", regex=True)
df = df.drop_duplicates(['year', 'town', 'nkey', 'sector'])
df.to_csv('work/hist/hist_hazard_entries.csv', index=False)
print(len(df)); print(df.groupby('year').agg(n=('name','size'), town=('town', lambda s: (s!='').mean().round(2))).to_string())
