"""1950 Colorado State Business Directory: entries end with numeric classification codes 'GG-II, X'
(group-item, credit letter). Keep the hazardous manufacturing codes from the volume's code key."""
import re, os, sys
import pandas as pd
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hist_parse import town_events, despace, ADDR, page_abbrevs, in_range, norm_town

CODES = {  # (group, item): (sector, F&E group)
 (12, 2): ('Chemicals', '28'), (12, 17): ('Soap', '28'), (12, 21): ('Fertilizer & rendering', '28'), (12, 40): ('Paint & varnish', '28'),
 (12, 15): ('Plastics', '30'), (12, 12): ('Rubber', '30'), (12, 10): ('Petroleum refining & asphalt', '29'),
 (12, 7): ('Metal working', '34'), (12, 29): ('Iron & steel works', '33'), (12, 30): ('Iron & steel works', '33'),
 (12, 31): ('Metal working', '34'), (12, 43): ('Iron & steel works', '33'), (12, 60): ('Smelting & refining', '33'),
 (12, 6): ('Machine shop / machinery', '35'), (12, 41): ('Machine shop / machinery', '35'), (12, 66): ('Asbestos products', 'EXT'),
 (12, 8): ('Assay office', 'EXT'), (9, 1): ('Manufactured gas', 'EXT'), (10, 1): ('Machine shop / machinery', '35'),
}
FIX = str.maketrans({'l': '1', 'I': '1', 'Z': '2', 'O': '0', 'o': '0', 'S': '5', 'B': '8'})
CODE = re.compile(r"\s([0-9lIZOoSB]{1,2})\s?-\s?([0-9lIZOoSB]{1,2})(?:\s?,\s?[A-Z](?:-\d)?)?\s*$")

def parse(path):
    raw = open(path, encoding='utf-8', errors='ignore').read()
    out = []; town = None
    for pg, ptxt in enumerate(raw.split('\f'), 1):
        rawl = ptxt.split('\n')
        lines = [despace(l) for l in rawl]
        ev = dict(town_events(lines))
        for i, l in enumerate(rawl):            # letter-spaced section heads: 'D E N V E R'
            if re.fullmatch(r"\s*(?:[A-Z] ){3,}[A-Z]\s*", l) and norm_town(l): ev[i] = norm_town(l)
        buf = []
        for i, l in enumerate(lines):
            if i in ev: town = ev[i]; buf = []; continue
            s = l.strip()
            if not s: continue
            buf.append(s)
            m = CODE.search(' ' + s)
            if m:
                try: g, it = int(m.group(1).translate(FIX)), int(m.group(2).translate(FIX))
                except ValueError: buf = []; continue
                entry = ' '.join(buf); buf = []
                if (g, it) in CODES:
                    sec, grp = CODES[(g, it)]
                    if (g, it) == (12, 6) and not re.search(r"(?i)mach|mfg|works|tool|foundry|engine|manufactur", entry): continue
                    if (g, it) == (9, 1) and not re.search(r"(?i)\bgas\b", entry): continue
                    a = ADDR.search(entry)
                    name = re.split(r"\s\d{1,5}[-\s]", entry)[0]
                    out.append(dict(vol='narv_dir_coloradoBus_1950', year=1950, page=pg, town=town or '', town_src='heading' if town else '',
                                    name=name[:90], entry=entry[:240], trade=f'code {g}-{it}', sector=sec, fe_group=grp,
                                    street=(a.group(1) + ' ' + a.group(2)) if a else '', mode='coded'))
            elif len(buf) > 4: buf = buf[-2:]
    return out

if __name__ == '__main__':
    df = pd.DataFrame(parse(sys.argv[1]))
    print(len(df), (df.town != '').mean()); print(df.sector.value_counts()); print(df.sample(20, random_state=1)[['town', 'name', 'trade', 'street']].to_string())
