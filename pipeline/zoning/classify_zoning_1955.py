"""Denver zone map of 1 July 1955: industrial districts (I-1, I-2) by texture classification.

    python3 pipeline/zoning/classify_zoning_1955.py            # features, classifier, cells (about two minutes)
    python3 pipeline/zoning/classify_zoning_1955.py sheets     # also draw the random check sheets (work/zoning/check_1955_*.png)
    python3 pipeline/zoning/classify_zoning_1955.py web        # only redraw the two web images in app/www from zone_cells_1955.csv

Scan (History Colorado, Stephen H. Hart Research Center; licensed to the author for this publication, NOT redistributed):
    "Zone map, City and County of Denver", prepared by the Department of Zoning Administration, July 1, 1955
    (call number rG4314 .D4G44 1955 .D4; 600 dpi, 6,000 x 5,847 px). Place it as work/zoning/zone_map_1955_history_colorado.tif.
Citation (History Colorado's format): Zone map, City and County of Denver, July 1, 1955. History Colorado. rG4314 .D4G44 1955 .D4.
The use agreement covers this publication and its website; the website shows the whole sheet at 1,800 px (app/www/zoning_1955_scan.jpg)
and the same image with the classified industrial districts drawn over it (app/www/zoning_1955_classified.jpg).

The map shows 15 zone districts as black-and-white patterns (R-0 to R-4, B-1 to B-5, I-0 to I-2, O-1, P-1). Industrial land is
printed without lot lines, as vertical dashes (I-1) or rings of dots (I-2); no I-0 district was found on the sheet.
Method:
  1. Binarise against the local paper tone (85th percentile of a 250-px window); label connected ink components.
  2. Describe every 16-px cell (about 46 m): ink share; shares of ink in small dots, ringed components, vertical and horizontal
     dashes and large connected networks; component counts; gradient-orientation energy; the radial and angular spectrum of the
     64-px window around the cell; and the same averaged over 3x3, 7x7 (and, for ink, 15x15) cells.
  3. A random forest is trained on hand-drawn boxes of known pattern (data/raw/zoning_1955/training_boxes_1955.csv: I-1, I-2,
     O-1, R-1 to R-4, B-4, B-5 and the blank paper outside the city) and applied to every cell; class probabilities are averaged
     over 5x5 cells and the most probable class kept.
  4. Industrial cells (I-1 or I-2) form one connected area of about 15,000 cells; the six other clusters are small (2 to 40 cells).
     The two largest were inspected and are park drawings (Washington Park, the Skeel reservoir golf course), so clusters under
     100 cells are dropped. The legend, title block and margins are masked.
  5. Business districts are not written: on a random check most cells predicted as business on the edges of the narrow B-4
     strips were in fact residential, so only industrial districts are used (as for 1929 and 1944, where only industrial and
     commercial districts were classified).
Accuracy (data/raw/zoning_1955/check_sample_1955.csv): 60 random cells (30 predicted industrial, 30 predicted not industrial
within about 550 m of an industrial district), judged by eye on the scan: 29 of 30 and 29 of 30 correct; I-1 against I-2 agreed
for 26 of 28 industrial cells.
Output: data/raw/zoning_1955/zone_cells_1955.csv, runs of industrial cells (row, col0, col1, zone) on the 16-px grid of the scan;
R/zoning_1955.R places them with the control points in data/raw/zoning_1955/gcps_1955.csv.
"""
import os, sys, csv, json
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
W = os.path.join(ROOT, "work", "zoning"); RAW = os.path.join(ROOT, "data", "raw", "zoning_1955")
SCAN = os.path.join(W, "zone_map_1955_history_colorado.tif")
C = 16                      # cell size, px (about 46 m)
CLASSES = ["B4", "B5", "I1", "I2", "O1", "R1", "R2", "R3", "R4", "X"]


def binarise(g):
    bg = ndi.percentile_filter(g[::8, ::8], 85, size=31)
    bg = ndi.zoom(bg, (g.shape[0] / bg.shape[0], g.shape[1] / bg.shape[1]), order=1)[:g.shape[0], :g.shape[1]]
    return g < bg - 45


def features(ink):
    H, Wd = ink.shape; nr, nc = H // C, Wd // C
    lab, n = ndi.label(ink); sl = ndi.find_objects(lab)
    area = np.bincount(lab.ravel(), minlength=n + 1)[1:].astype(float)
    hgt = np.array([s[0].stop - s[0].start for s in sl]); wid = np.array([s[1].stop - s[1].start for s in sl])
    holes = np.zeros(n, bool)
    for i, s in enumerate(sl):
        if 12 <= area[i] <= 4000:
            m = lab[s] == i + 1; holes[i] = (ndi.binary_fill_holes(m).sum() - m.sum()) >= 4
    cy = np.array([(s[0].start + s[0].stop) // 2 for s in sl]); cx = np.array([(s[1].start + s[1].stop) // 2 for s in sl])
    pm = lambda v: np.concatenate([[0], v]).astype(np.float32)[lab]
    cellsum = lambda m: m[:nr * C, :nc * C].reshape(nr, C, nc, C).sum((1, 3))
    inkf = ink.astype(np.float32)
    small = area < 60; dot = small & (np.abs(hgt - wid) <= 2)
    vdash = (hgt >= 2.2 * wid) & (area < 200) & (hgt >= 6); ring = holes & (area < 400); big = area > 3000
    hdash = (wid >= 2.2 * hgt) & (area < 200) & (wid >= 6); vthin = vdash & (wid <= 4) & (hgt <= 30)
    maps = {"ink": inkf, "small": pm(small) * inkf, "dot": pm(dot), "vdash": pm(vdash), "ring": pm(ring), "big": pm(big),
            "hdash": pm(hdash), "vthin": pm(vthin), "logarea": pm(np.log1p(area))}
    F = {k: cellsum(v) / C ** 2 for k, v in maps.items()}
    F["logarea"] = F["logarea"] / np.maximum(F["ink"], 1e-3)
    cnt = np.zeros((nr, nc)); np.add.at(cnt, (np.clip(cy // C, 0, nr - 1), np.clip(cx // C, 0, nc - 1)), 1); F["ncomp"] = cnt
    del lab
    g = ndi.gaussian_filter(inkf, 1.5); gy = ndi.sobel(g, 0); gx = ndi.sobel(g, 1)
    mag = np.hypot(gx, gy) + 1e-6; th = np.mod(np.arctan2(gy, gx), np.pi)
    for k in range(4):
        F[f"or{k}"] = cellsum(np.cos(2 * (th - k * np.pi / 4)).clip(0) * mag) / C ** 2
    F["gmag"] = cellsum(mag) / C ** 2
    del g, gy, gx, mag, th
    P = 64; pad = np.pad(inkf, ((P, P), (P, P)))
    yy, xx = np.mgrid[-P // 2:P // 2, -P // 2:P // 2]; rr = np.hypot(yy, xx); ang = np.mod(np.arctan2(yy, xx), np.pi)
    bins = [2, 4, 6, 8, 11, 14, 18, 24, 32]; win = np.outer(np.hanning(P), np.hanning(P)).astype(np.float32)
    masks = [(rr >= bins[i]) & (rr < bins[i + 1]) for i in range(len(bins) - 1)]
    amask = [(rr >= 3) & (rr < 32) & (np.abs(((ang - k * np.pi / 4 + np.pi / 2) % np.pi) - np.pi / 2) < np.pi / 8) for k in range(4)]
    R = np.zeros((nr, nc, len(masks)), np.float32); A = np.zeros((nr, nc, 4), np.float32)
    for i in range(nr):
        y = i * C + C // 2 + P
        w = np.stack([pad[y - P // 2:y + P // 2, j * C + C // 2 + P // 2: j * C + C // 2 + 3 * P // 2] for j in range(nc)])
        S = np.abs(np.fft.fftshift(np.fft.fft2((w - w.mean((1, 2), keepdims=True)) * win), axes=(1, 2))); tot = S.sum((1, 2)) + 1e-6
        for b, m in enumerate(masks): R[i, :, b] = S[:, m].sum(1) / tot
        for k, m in enumerate(amask): A[i, :, k] = S[:, m].sum(1) / tot
    for b in range(R.shape[2]): F[f"fr{b}"] = R[:, :, b]
    for k in range(4): F[f"fa{k}"] = A[:, :, k]
    X = np.stack([F[k] for k in F], -1)
    return np.concatenate([X, ndi.uniform_filter(X, (3, 3, 1)), ndi.uniform_filter(X, (7, 7, 1)), ndi.uniform_filter(X[..., :1], (15, 15, 1))], -1).astype(np.float32)


def classify(X):
    from sklearn.ensemble import RandomForestClassifier
    nr, nc, nf = X.shape; Xs, ys = [], []
    for r in csv.DictReader(open(os.path.join(RAW, "training_boxes_1955.csv"))):
        v = X[int(r["y0"]) // C:int(r["y1"]) // C, int(r["x0"]) // C:int(r["x1"]) // C].reshape(-1, nf); Xs.append(v); ys += [r["cls"]] * len(v)
    rf = RandomForestClassifier(300, min_samples_leaf=3, n_jobs=2, random_state=1, class_weight="balanced").fit(np.concatenate(Xs), np.array(ys))
    assert list(rf.classes_) == CLASSES, rf.classes_
    P = rf.predict_proba(X.reshape(-1, nf)).reshape(nr, nc, -1)
    return ndi.uniform_filter(P, (5, 5, 1))


def industrial(Ps):
    nr, nc, _ = Ps.shape; lab = Ps.argmax(-1); ys, xs = np.mgrid[0:nr, 0:nc] * C
    ind = np.isin(lab, [CLASSES.index("I1"), CLASSES.index("I2")])
    ind[(xs > 4500) & (ys > 4900)] = False                                       # legend and title block
    ind[(ys < 130) | (ys > 5640) | (xs < 130) | (xs > 5800)] = False             # margins and grid frame
    L, n = ndi.label(ind); size = ndi.sum(ind, L, range(1, n + 1))
    keep = np.isin(L, 1 + np.flatnonzero(size >= 100))
    print("industrial clusters (cells):", sorted(size.astype(int).tolist(), reverse=True))
    zone = np.where(Ps[..., CLASSES.index("I2")] >= Ps[..., CLASSES.index("I1")], "I-2", "I-1")
    return keep, zone


def write_runs(keep, zone):
    out = os.path.join(RAW, "zone_cells_1955.csv")
    with open(out, "w", newline="") as f:
        w = csv.writer(f); w.writerow(["row", "col0", "col1", "zone"])     # cells col0..col1 inclusive; cell = 16x16 px of the scan
        for r in range(keep.shape[0]):
            c = 0
            while c < keep.shape[1]:
                if keep[r, c]:
                    z = zone[r, c]; c1 = c
                    while c1 + 1 < keep.shape[1] and keep[r, c1 + 1] and zone[r, c1 + 1] == z: c1 += 1
                    w.writerow([r, c, c1, z]); c = c1 + 1
                else: c += 1
    print(f"{int(keep.sum())} industrial cells ({(zone[keep] == 'I-1').sum()} I-1, {(zone[keep] == 'I-2').sum()} I-2) -> {out}")


def sheets(keep, seed):
    """30 random cells (15 industrial, 15 not industrial within ~550 m) on one sheet, for judging by eye."""
    im = Image.open(SCAN).convert("RGB"); from PIL import ImageDraw
    near = ndi.binary_dilation(keep, iterations=12) & ~keep
    rng = np.random.default_rng(seed); pi, pn = np.argwhere(keep), np.argwhere(near)
    sel = [("industrial", p) for p in pi[rng.choice(len(pi), 15, replace=False)]] + [("not industrial", p) for p in pn[rng.choice(len(pn), 15, replace=False)]]
    rng.shuffle(sel); T = 180; sh = Image.new("RGB", (6 * T, 5 * T), "white"); d = ImageDraw.Draw(sh); key = []
    for k, (lab, (r, c)) in enumerate(sel):
        x, y = (k % 6) * T, (k // 6) * T; cx, cy = int(c) * C + C // 2, int(r) * C + C // 2
        sh.paste(im.crop((cx - T // 2, cy - T // 2, cx + T // 2, cy + T // 2)), (x, y))
        d.rectangle([x + T // 2 - 8, y + T // 2 - 8, x + T // 2 + 8, y + T // 2 + 8], outline=(255, 0, 0), width=2); d.text((x + 3, y + 3), str(k), fill=(0, 0, 255))
        key.append({"tile": k, "predicted": lab, "px_x": cx, "px_y": cy})
    sh.save(os.path.join(W, f"check_1955_{seed}.png")); json.dump(key, open(os.path.join(W, f"check_1955_{seed}.json"), "w"), indent=0)


def web(width=1800):
    """The whole sheet at web size, and the same with the industrial districts (I-1 orange, I-2 red) drawn over it."""
    im = Image.open(SCAN).convert("RGB"); Wd, H = im.size; h = round(H * width / Wd)
    sm = im.resize((width, h), Image.LANCZOS); www = os.path.join(ROOT, "app", "www")
    sm.save(os.path.join(www, "zoning_1955_scan.jpg"), quality=85, optimize=True)
    ov = np.zeros((H // C, Wd // C, 4), np.uint8)
    for r in csv.DictReader(open(os.path.join(RAW, "zone_cells_1955.csv"))):
        ov[int(r["row"]), int(r["col0"]):int(r["col1"]) + 1] = (230, 120, 0, 120) if r["zone"] == "I-1" else (200, 0, 0, 120)
    o = Image.fromarray(ov).resize((ov.shape[1] * C * width // Wd, ov.shape[0] * C * width // Wd), Image.NEAREST)
    sm.paste(o, (0, 0), o); sm.save(os.path.join(www, "zoning_1955_classified.jpg"), quality=85, optimize=True)


if __name__ == "__main__":
    if not os.path.exists(SCAN): sys.exit(f"place the History Colorado scan at {SCAN}")
    if "web" in sys.argv[1:]:
        web(); sys.exit(0)
    g = np.asarray(Image.open(SCAN).convert("L"), dtype=np.float32)
    ink = binarise(g); del g
    X = features(ink); del ink
    Ps = classify(X)
    keep, zone = industrial(Ps)
    write_runs(keep, zone)
    if "sheets" in sys.argv[1:]:
        for s in (1, 2): sheets(keep, s)
    web()
