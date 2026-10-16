"""Parse OCR output of every volume into listing records -> work/parsed/<volume>.jsonl"""
import os, sys, json
sys.path.insert(0, os.path.dirname(__file__))
from volumes import VOLUMES
import parse_block, parse_1965, parse_table, parse_1988, parse_para, parse_2002
T = 'work/tsv'
os.makedirs('work/parsed', exist_ok=True)
for vol, (year, parser, mode) in VOLUMES.items():
    if parser == 'block':   R = parse_block.parse_volume(vol, T, year)
    elif parser == '1965':  R = parse_1965.parse(vol, T, year)
    elif parser == 'table': R = parse_table.parse(vol, T, year)
    elif parser == '1988':  R = parse_1988.parse(vol, T, year)
    elif parser == 'para':  R = parse_para.parse_coltxt(vol, year) if mode == 'coltxt' else parse_para.parse_tsv(vol, T, year)
    elif parser == '2002':  R = parse_2002.parse(vol, year, 3)
    with open(f'work/parsed/{vol}.jsonl', 'w') as f:
        for r in R: f.write(json.dumps(r) + '\n')
    print(f'{vol:22s} {year} {parser:6s} {len(R):6d} listings, with ZIP {sum(1 for r in R if r.get("zip"))}')
