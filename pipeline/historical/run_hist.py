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
# corporate / sales offices are not works: keep the firm, but do not map it at the office address
df['office'] = df.entry.str.contains(r"(?i)\b(?:offices?|bldg|blk|block|building|rooms?|suite)\b|\b(?:agt|agency|agents?)\b")
print('dropped as persons:', int(df.is_person.sum()), '; office listings:', int(df.office.sum()))
df = df[~df.is_person]
# listings whose name is plainly not an industrial firm (column-interleaving in the 1950 coded volume attaches codes to neighbours)
NONIND = r"(?i)\b(groc\w*|grocery|club|fruit|cafe|caf[eé]|store|hotel|motel|assn|association|church|school|bank|tavern|bar|restaurant|beauty|barber|insurance|realty|sales|calculating|florist|bakery|dairy|drug\w*|press club)\b"
df = df[~df.name.str.contains(NONIND)]
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
