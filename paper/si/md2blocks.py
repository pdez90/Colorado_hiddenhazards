"""Convert the Docs markdown export into the blocks.json format used by build.js.
Drops editorial 'To add' / 'Open items' notes and file references; tables get captions from CAPTIONS in order."""
import json, re, sys

CAPTIONS = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else []

def runs(text):
    text = text.replace('\\*', '\x00')
    out = []
    # tokens: **bold**, *italic*, `code`
    pat = re.compile(r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)')
    pos = 0
    for m in pat.finditer(text):
        if m.start() > pos:
            out.append({"t": text[pos:m.start()], "b": False, "i": False, "c": False})
        tok = m.group(0)
        if tok.startswith('**'):
            out.append({"t": tok[2:-2], "b": True, "i": False, "c": False})
        elif tok.startswith('`'):
            out.append({"t": tok[1:-1], "b": False, "i": False, "c": True})
        else:
            out.append({"t": tok[1:-1], "b": False, "i": True, "c": False})
        pos = m.end()
    if pos < len(text):
        out.append({"t": text[pos:], "b": False, "i": False, "c": False})
    for r in out:
        r["t"] = r["t"].replace("\x00", "*").replace("\\*", "*").replace("\\_", "_").replace("\\|", "|")
    return out

def plain(rs):
    return "".join(r["t"] for r in rs)

def main(md_path):
    lines = open(md_path).read().split("\n")
    blocks, i, ti = [], 0, 0
    while i < len(lines):
        ln = lines[i].rstrip()
        if not ln.strip():
            i += 1; continue
        if ln.startswith("#"):
            lvl = len(ln) - len(ln.lstrip("#")); rs = runs(ln.lstrip("#").strip())
            blocks.append({"type": "heading", "level": lvl, "runs": rs, "text": plain(rs)}); i += 1; continue
        if ln.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in re.split(r'(?<!\\)\|', lines[i].strip())[1:-1]]
                if not all(re.fullmatch(r'-{3,}|:?-+:?', c) for c in cells if c):
                    rows.append(cells)
                i += 1
            trs = []
            for ri, r in enumerate(rows):
                trs.append([{"runs": runs(c), "text": plain(runs(c)), "header": ri == 0} for c in r])
            cap = CAPTIONS[ti] if ti < len(CAPTIONS) else f"Table {ti + 1}."
            ti += 1
            blocks.append({"type": "table", "rows": trs, "caption": cap}); continue
        m = re.match(r'^(\d+)\.\s+(.*)', ln); b = re.match(r'^[-*]\s+(.*)', ln)
        if m or b:
            kind = "ordered" if m else "bullet"; items = []
            while i < len(lines):
                l2 = lines[i].rstrip(); mm = re.match(r'^(\d+)\.\s+(.*)', l2) if kind == "ordered" else re.match(r'^[-*]\s+(.*)', l2)
                if not mm: break
                rs = runs(mm.group(2) if kind == "ordered" else mm.group(1)); items.append({"runs": rs, "text": plain(rs)}); i += 1
            blocks.append({"type": "list", "kind": kind, "items": items}); continue
        rs = runs(ln.strip())
        blocks.append({"type": "p", "level": 0, "runs": rs, "text": plain(rs)}); i += 1
    # drop editorial notes and the date/byline line
    keep = []
    for x in blocks:
        t = x.get("text", "")
        if x["type"] == "p" and (t.startswith("To add") or t.startswith("Open items") or re.match(r'^[A-Z][a-z]{2} \d+, \d{4} ·', t) or t.startswith("Draft for")):
            continue
        keep.append(x)
    return keep

if __name__ == "__main__":
    json.dump(main(sys.argv[1]), open("blocks_new.json", "w"), ensure_ascii=False, indent=0)
    print("ok")
