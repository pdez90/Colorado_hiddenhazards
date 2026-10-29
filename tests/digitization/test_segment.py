"""segment.py: column cuts (automatic, forced, adaptive) and line clustering on synthetic word boxes."""
import statistics
import numpy as np
import pytest
import segment
from synth import page_words, column_words, write_tsv, texts, word

COL0 = ['ACME METAL PRODUCTS COMPANY INC', '1234 BLAKE ST 80202 534-1234', 'CORP EST-1946 NTL EMP-20 TO 49', '3444 SHEET METAL WORK'] * 6
COL1 = ['FRONT RANGE FOUNDRY + MACHINE CO', '10401 W 120TH AVE 80020 466-1822', 'PART EST-1961 LOC EMP-10 TO 19', '3369 NONFERROUS FOUNDRIES NEC'] * 6
COL2 = ['PLATTE VALLEY PACKING COMPANY', '707 & 50TH 80216 825-7645', 'CORP EST-1930 REG 100-249', '2011 MEAT PACKING PLANTS'] * 6


def strip_tok(lines, tok):
    """Remove a planted bridging word from line texts (it sits on a real line and is read with it)."""
    return [' '.join(t for t in l.split() if t != tok) for l in lines]


def median_height(W):
    return statistics.median(w['h'] for w in W if w['h'] > 5)


def in_gutters(cuts, columns, x0s=(60, 500, 940)):
    """True when every cut lies strictly between the right edge of one column's text and the left edge of the next."""
    cols = [column_words(c, x0) for c, x0 in zip(columns, x0s)]
    right = [max(w['l'] + w['w'] for w in c) for c in cols]
    left = [min(w['l'] for w in c) for c in cols]
    return len(cuts) == len(columns) - 1 and all(right[k] <= cuts[k] < left[k + 1] for k in range(len(cuts)))


def test_find_columns_three_column_page():
    W = page_words([COL0, COL1, COL2])
    pw = max(w['l'] + w['w'] for w in W) + 5
    cuts = segment.find_columns(W, pw)
    assert in_gutters(cuts, [COL0, COL1, COL2])
    L = segment.lines_by_column(W, cuts, median_height(W))
    assert texts(L) == COL0 + COL1 + COL2


def test_adaptive_cuts_recover_a_gutter_bridged_by_a_word(tmp_path):
    """A single word box bleeding across a gutter (a smear, an underline) hides it from find_columns, and the page is
    read as two columns with the words of the merged columns interleaved line by line. adaptive_cuts tries forced
    3- and 2-column splits and keeps the one with the fewest over-long (>48 char) lines."""
    W = page_words([COL0, COL1, COL2])
    W.append(word(380, 100 + 28 * 5, 180, 22, 'xx'))   # bridges gutter 1 (column 0 text ends by ~400, column 1 starts at 500)
    pw = max(w['l'] + w['w'] for w in W) + 5
    mh = median_height(W)
    auto = segment.find_columns(W, pw)
    assert len(auto) == 1, 'precondition: the automatic search must miss the bridged gutter'
    merged = segment.lines_by_column(W, auto, mh)
    assert sum(len(l['text']) > 48 for l in merged) >= 20, 'precondition: columns 0 and 1 are read as one'
    cuts = segment.adaptive_cuts(W, pw, mh, (3, 2))
    assert in_gutters(cuts, [COL0, COL1, COL2])
    L = segment.lines_by_column(W, cuts, mh)
    assert not any(len(l['text']) > 48 for l in L)
    assert strip_tok(texts(L), 'xx') == COL0 + COL1 + COL2
    # the same through page_lines, as parse_block calls it
    p = write_tsv(tmp_path / 'p001.tsv', W)
    L2, cuts2 = segment.page_lines(str(p), adaptive=(3, 2))
    assert cuts2 == cuts and strip_tok(texts(L2), 'xx') == COL0 + COL1 + COL2


def test_adaptive_cuts_keep_the_automatic_split_on_a_clean_page():
    W = page_words([COL0, COL1, COL2])
    pw = max(w['l'] + w['w'] for w in W) + 5
    mh = median_height(W)
    assert segment.adaptive_cuts(W, pw, mh, (3, 2)) == segment.find_columns(W, pw)


def test_two_column_page_forced_split(tmp_path):
    """1965 pages are two columns; adaptive=(2,) must not cut a clean two-column page into three."""
    A = ['2011 E1 SIGMAN MEAT PACKING COMPANY INC.', '8.0 RAILWAY'] * 10
    B = ['3591 E1 AMERICAN WELDING + FABRICATING', '220 S. VICTORIA'] * 10
    W = page_words([A, B], x0s=(60, 600))
    p = write_tsv(tmp_path / 'p001.tsv', W)
    L, cuts = segment.page_lines(str(p), adaptive=(2,))
    assert in_gutters(cuts, [A, B], (60, 600))
    assert texts(L) == A + B
    # with the gutter bridged, the forced two-column split still recovers both columns
    W2 = W + [word(400, 100 + 28 * 2, 250, 22, 'x')]   # bridges the gutter on one line
    p2 = write_tsv(tmp_path / 'p002.tsv', W2)
    L2, cuts2 = segment.page_lines(str(p2), adaptive=(2,))
    assert len(cuts2) == 1 and strip_tok(texts(L2), 'x') == A + B


def tight_column(n=40, pitch=14, tall=30, short=12):
    """A low-resolution 1992-style column: line pitch 14 px, most word boxes 30 px tall (ascender to descender),
    one word in three a 12 px x-height box. Each line carries its own number so merged lines are visible."""
    lines = [f'firm{i} makes widgets here' for i in range(n)]
    heights = lambda i, j, s: short if (i + j) % 3 == 0 else tall
    return lines, column_words(lines, 60, y0=100, pitch=pitch, h=tall, heights=heights)


def test_line_threshold_uses_the_lower_quartile_height():
    lines, W = tight_column()
    mh = median_height(W)
    assert mh == 30
    thr = segment.line_threshold(W, mh)
    assert thr == pytest.approx(0.55 * 12)
    assert thr < 14, 'threshold must be below the line pitch or neighbouring lines merge'
    assert 0.55 * mh > 14, 'precondition: the median-height rule would merge neighbouring lines'


def test_lines_by_column_keeps_tight_lines_apart():
    lines, W = tight_column()
    mh = median_height(W)
    L = segment.lines_by_column(W, [], mh)
    assert texts(L) == lines
    # the old rule (0.55 * median height) merges them: pass it explicitly to show the case the fix addresses
    merged = segment.lines_by_column(W, [], mh, thr=0.55 * mh)
    assert len(merged) < len(lines)


def test_lines_by_column_normal_page_unchanged():
    W = page_words([COL0, COL1, COL2])
    mh = median_height(W)
    L = segment.lines_by_column(W, segment.find_columns(W, max(w['l'] + w['w'] for w in W) + 5), mh)
    assert texts(L) == COL0 + COL1 + COL2
    for l in L:
        assert l['conf'] == pytest.approx(90.0)


def test_line_threshold_fallbacks():
    assert segment.line_threshold([], 20) == pytest.approx(0.55 * 20)
    tiny = [word(0, 0, 10, 4, 'a')] * 5                       # boxes <= 5 px are ignored
    assert segment.line_threshold(tiny, 20) == pytest.approx(0.55 * 20)
    small = [word(0, 0, 10, 6, 'a')] * 40
    assert segment.line_threshold(small, 5) == 3.0           # floor (0.55 * 5 = 2.75)


def test_small_columns_use_median_rule():
    """Columns with fewer than 30 words (a short last page) keep the median-height rule."""
    lines = ['AB CD', 'EF GH', 'IJ KL']
    W = column_words(lines, 60, pitch=30, h=22)
    L = segment.lines_by_column(W, [], 22)
    assert texts(L) == lines


def test_page_lines_empty_file(tmp_path):
    p = write_tsv(tmp_path / 'p001.tsv', [])
    assert segment.page_lines(str(p)) == ([], [])
