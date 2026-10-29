"""Synthetic Tesseract word boxes and TSV pages for the segmentation and block-parser tests.

A page is given as columns of text lines; every word becomes a level-5 box whose width grows with its length, so the
pages have the geometry segment.py reasons about (column gutters, line pitch, word heights) without any OCR noise."""
import csv

CW = 11          # px per character
GAP = 11         # px between words
TSV_COLS = ['level', 'page_num', 'block_num', 'par_num', 'line_num', 'word_num', 'left', 'top', 'width', 'height', 'conf', 'text']


def word(l, t, w, h, s, c=90.0):
    return dict(l=int(l), t=int(t), w=int(w), h=int(h), c=float(c), s=s)


def column_words(lines, x0, y0=100, pitch=28, h=22, cw=CW, heights=None):
    """Word boxes for one column of text lines. heights(i, j, word) may give a per-word box height."""
    W = []
    for i, line in enumerate(lines):
        x = x0
        for j, s in enumerate(line.split()):
            hh = heights(i, j, s) if heights else h
            y = y0 + i * pitch
            W.append(word(x, y + (h - hh) / 2, len(s) * cw, hh, s))
            x += len(s) * cw + GAP
    return W


def page_words(columns, x0s=(60, 500, 940), **kw):
    """Word boxes for a multi-column page; columns is a list of line lists (an empty string leaves a blank row)."""
    W = []
    for col, x0 in zip(columns, x0s):
        W += column_words(col, x0, **kw)
    return W


def write_tsv(path, W):
    """Write word boxes as a Tesseract TSV page (what segment.load_words reads)."""
    with open(path, 'w', newline='') as f:
        wr = csv.writer(f, delimiter='\t', lineterminator='\n')
        wr.writerow(TSV_COLS)
        wr.writerow([1, 1, 0, 0, 0, 0, 0, 0, 2000, 3000, -1, ''])
        for k, w in enumerate(W):
            wr.writerow([5, 1, 1, 1, 1, k + 1, w['l'], w['t'], w['w'], w['h'], w['c'], w['s']])
    return path


def texts(lines):
    """Line texts of segment.lines_by_column output in reading order (column, then y)."""
    return [l['text'] for l in sorted(lines, key=lambda l: (l['col'], l['y']))]
