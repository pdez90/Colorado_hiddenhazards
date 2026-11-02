// Renders paper/si/si_blocks.json (from make_si.py) as paper/Before_and_After_the_Map_SI.docx. Needs the npm package docx (npm install docx).
const fs = require('fs');
const D = require('docx');
const { Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell, WidthType, AlignmentType, PageOrientation, PageBreak, ShadingType, LevelFormat, BorderStyle } = D;

const blocks = JSON.parse(fs.readFileSync(__dirname + '/si_blocks.json'));
const FONT = 'Times New Roman';
const runsOf = (rs, extra = {}) => rs.filter(r => r.t !== '').map(r => new TextRun({ text: r.t, bold: !!r.b, italics: !!r.i, font: r.c ? 'Consolas' : FONT, size: extra.size || 24, ...extra }));
const para = (rs, opts = {}) => new Paragraph({ children: runsOf(rs, opts.run || {}), spacing: { after: 160, line: 360 }, alignment: AlignmentType.JUSTIFIED, ...opts.p });

const PORTRAIT = { page: { size: { width: 12240, height: 15840 }, margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } } };
const LANDSCAPE = { page: { size: { width: 12240, height: 15840, orientation: PageOrientation.LANDSCAPE }, margin: { top: 1080, bottom: 1080, left: 1080, right: 1080 } } };

function table(b, landscape) {
  const rows = b.rows; const ncol = Math.max(...rows.map(r => r.length));
  const total = landscape ? 13680 : 9360; const first = Math.min(Math.round(total * (ncol > 6 ? 0.22 : 0.3)), 3200);
  const rest = Math.floor((total - first) / (ncol - 1)); const widths = [first, ...Array(ncol - 1).fill(rest)]; widths[ncol - 1] += total - widths.reduce((a, c) => a + c, 0);
  const size = ncol > 9 ? 14 : ncol > 6 ? 16 : 18;
  const trs = rows.map((r, ri) => new TableRow({ tableHeader: ri === 0, children: Array.from({ length: ncol }, (_, ci) => {
    const c = r[ci] || { runs: [], text: '' }; const hdr = ri === 0;
    return new TableCell({ width: { size: widths[ci], type: WidthType.DXA }, shading: hdr ? { type: ShadingType.CLEAR, fill: 'EDEDED', color: 'auto' } : undefined,
      margins: { top: 40, bottom: 40, left: 60, right: 60 },
      children: [new Paragraph({ alignment: ci === 0 ? AlignmentType.LEFT : AlignmentType.RIGHT, children: runsOf(c.runs.length ? c.runs : [{ t: c.text }], { size, bold: hdr }) })] }); }) }));
  const cap = new Paragraph({ spacing: { before: 240, after: 80 }, children: [new TextRun({ text: b.caption, font: FONT, size: 20, bold: true })] });
  const tbl = new Table({ width: { size: total, type: WidthType.DXA }, columnWidths: widths, rows: trs, borders: { top: { style: BorderStyle.SINGLE, size: 6 }, bottom: { style: BorderStyle.SINGLE, size: 6 }, left: { style: BorderStyle.NONE }, right: { style: BorderStyle.NONE }, insideHorizontal: { style: BorderStyle.SINGLE, size: 2, color: 'BBBBBB' }, insideVertical: { style: BorderStyle.NONE } } });
  return [cap, tbl, new Paragraph({ spacing: { after: 120 } })];
}

// front matter
const title = blocks[0];
const front = [
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 240 }, children: [new TextRun({ text: title.text, font: FONT, size: 32, bold: true })] }),

];

// split into sections: landscape for wide tables
const sections = []; let cur = { props: PORTRAIT, children: [...front] };
let numbering = { config: [{ reference: 'bul', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
                            { reference: 'num', levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] }] };
let numInst = 0;
for (let i = 1; i < blocks.length; i++) {
  const b = blocks[i];
  if (b.type === 'heading') {
    const txt = b.text.replace(/^\d+\.\s*/, m => m);
    cur.children.push(new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 360, after: 160 }, children: [new TextRun({ text: txt, font: FONT, size: 26, bold: true, color: '000000' })] }));
  } else if (b.type === 'p') {
    if (b.text.startsWith('Abstract.')) { cur.children.push(para(b.runs, { run: { size: 22 }, p: { spacing: { after: 160, line: 300 } } })); }
    else if (b.text.startsWith('Keywords:')) { cur.children.push(para(b.runs, { run: { size: 22 } })); }
    else cur.children.push(para(b.runs));
  } else if (b.type === 'list') {
    const ref = b.kind === 'ordered' ? 'num' : 'bul';
    if (b.kind === 'ordered') { numInst++; numbering.config.push({ reference: 'num' + numInst, levels: numbering.config[1].levels }); }
    for (const it of b.items) cur.children.push(new Paragraph({ numbering: { reference: b.kind === 'ordered' ? 'num' + numInst : 'bul', level: 0 }, spacing: { after: 120, line: 340 }, alignment: AlignmentType.JUSTIFIED, children: runsOf(it.runs) }));
  } else if (b.type === 'table') {
    const wide = Math.max(...b.rows.map(r => r.length)) > 8;
    if (wide) { sections.push(cur); sections.push({ props: LANDSCAPE, children: table(b, true) }); cur = { props: PORTRAIT, children: [] }; }
    else cur.children.push(...table(b, false));
  }
}
sections.push(cur);
const doc = new Document({ creator: 'Priyanka deSouza', title: title.text, numbering,
  styles: { default: { document: { run: { font: FONT, size: 24 } } }, paragraphStyles: [{ id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { size: 26, bold: true, font: FONT, color: '000000' }, paragraph: { spacing: { before: 360, after: 160 }, outlineLevel: 0 } }] },
  sections: sections.filter(s => s.children.length).map(s => ({ properties: s.props, children: s.children })) });
Packer.toBuffer(doc).then(buf => { fs.writeFileSync(__dirname + '/../Before_and_After_the_Map_SI.docx', buf); console.log('written', buf.length); });
