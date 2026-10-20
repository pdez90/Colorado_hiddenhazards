"""Denver building-zone map, 1929 and 1944 revisions: industrial and commercial districts in 1944, on the 1929 cell grid.

    python3 pipeline/zoning/classify_zoning_1944.py prep      # warp both scans to a common frame and compute cell features
    python3 pipeline/zoning/classify_zoning_1944.py classify  # train on the 1929 labels, predict both years, find changed clusters
    python3 pipeline/zoning/classify_zoning_1944.py crops     # side-by-side crops of every candidate change for visual review
    python3 pipeline/zoning/classify_zoning_1944.py write     # 1944 cells = 1929 cells + the changes accepted in data/raw/zoning_1929/changes_1944_review.csv

Scans (Denver Public Library, free downloads; not redistributed, place in work/zoning/):
    R0213780483.TIF  "Building zone map ... as adopted February 1925", revised to 1 January 1929 (photocopy; 600 dpi, 11,849 x 12,000)
    R0248631198.tif  the same map revised to 1 April 1944 (282 dpi, 10,011 x 9,873)
The 1929 cells (data/raw/zoning_1929/zone_cells_1929.csv, 32-pixel cells of the 1929 scan) were labelled by the texture rules described
in R/zoning_1925.R. The 1944 sheet is registered to the 1929 scan by the affine in data/raw/zoning_1929/affine_1944_to_1929_px.csv
(1929 px = A * 1944 px). Both scans are resampled to half the 1929 resolution (a 1929 cell = 16 x 16 px), binarised with Otsu's
threshold, and described cell by cell (ink share, line orientation, stroke width, lot lines, with 3x3 and 7x7 neighbourhood means).
One random forest trained on the 1929 labels is applied to both years; only clusters of cells whose predicted class differs between
the two years are candidate changes, so the classifier's own errors (which are the same in both years) largely cancel. Each candidate
is reviewed on side-by-side crops and accepted or rejected by hand; the 1944 layer is the 1929 layer with the accepted changes applied.
"""
import sys, json, os
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
W = os.path.join(ROOT, "work", "zoning"); RAW = os.path.join(ROOT, "data", "raw", "zoning_1929")
S29, S44 = os.path.join(W, "R0213780483.TIF"), os.path.join(W, "R0248631198.tif")
W29, H29, CELL = 11849, 12000, 32
HALF = 2                         # common frame = 1929 pixels / 2
CW = CELL // HALF                # 16-px cells in the common frame
NC, NR = int(np.ceil(W29 / CELL)), int(np.ceil(H29 / CELL))   # 371 columns, 375 rows
CLASSES = ["none", "Industrial A", "Industrial B", "Commercial"]


def affine():
    import csv
    r = {row["coef"]: row for row in csv.DictReader(open(os.path.join(RAW, "affine_1944_to_1929_px.csv")))}
    A = np.array([[float(r["x1929"]["x1944"]), float(r["x1929"]["y1944"]), float(r["x1929"]["const"])],
                  [float(r["y1929"]["x1944"]), float(r["y1929"]["y1944"]), float(r["y1929"]["const"])]])
    return A


def gray_frame(path, warp=None):
    """Grayscale image in the common frame (1929 px / HALF)."""
    im = Image.open(path).convert("L")
    size = (int(np.ceil(W29 / HALF)), int(np.ceil(H29 / HALF)))
    if warp is None:
        return np.asarray(im.resize(size, Image.BILINEAR), dtype=np.uint8)
    # output (common frame) -> 1929 px (x HALF) -> 1944 px (inverse affine); PIL wants the output->input map
    A = np.vstack([warp, [0, 0, 1]]); Ainv = np.linalg.inv(A)
    S = np.diag([HALF, HALF, 1.0]); M = (Ainv @ S)[:2].ravel()
    return np.asarray(im.transform(size, Image.AFFINE, tuple(M), resample=Image.BILINEAR, fillcolor=255), dtype=np.uint8)


def otsu(g):
    h = np.bincount(g.ravel(), minlength=256).astype(float); p = h / h.sum(); w = np.cumsum(p); m = np.cumsum(p * np.arange(256))
    b = (m[-1] * w - m) ** 2 / np.maximum(w * (1 - w), 1e-12); return int(np.argmax(b))


def line_kernel(angle, L=11):
    k = np.zeros((L, L), np.float32); c = L // 2
    for t in np.linspace(-c, c, 4 * L):
        x = int(round(c + t * np.cos(np.radians(angle)))); y = int(round(c - t * np.sin(np.radians(angle)))); k[y, x] = 1
    return k / k.sum()


def cellmean(a):
    h, w = NR * CW, NC * CW
    b = np.zeros((h, w), np.float32); hh, ww = min(h, a.shape[0]), min(w, a.shape[1]); b[:hh, :ww] = a[:hh, :ww]
    return b.reshape(NR, CW, NC, CW).mean(axis=(1, 3))


def features(g):
    t = otsu(g); ink = (g < t).astype(np.float32)
    resp = np.stack([ndi.convolve(ink, line_kernel(a)) for a in (0, 45, 90, 135)])        # fraction of a short line through the pixel that is ink
    strong = (resp > 0.8) & (ink[None] > 0)                                                 # pixel lies on a line of that orientation
    dist = ndi.distance_transform_edt(ink)                                                  # stroke half-width
    f = {"ink": cellmean(ink), "h": cellmean(strong[0]), "d45": cellmean(strong[1]), "v": cellmean(strong[2]), "d135": cellmean(strong[3]),
         "thick": cellmean((dist >= 2.5).astype(np.float32)), "blob": cellmean((dist >= 4).astype(np.float32))}
    out = dict(f)
    for k, v in f.items():
        for s in (3, 7):
            out[f"{k}_m{s}"] = ndi.uniform_filter(v, s, mode="nearest")
    out["ratio"] = (f["d45"] + 1e-3) / (f["d135"] + 1e-3); out["ratio_m3"] = ndi.uniform_filter(out["ratio"], 3, mode="nearest")
    return out, t


def labels29():
    import csv
    lab = np.zeros((NR, NC), np.uint8); unc = np.zeros((NR, NC), bool)
    for r in csv.DictReader(open(os.path.join(RAW, "zone_cells_1929.csv"))):
        lab[int(r["row"]), int(r["col"])] = CLASSES.index(r["zone"]); unc[int(r["row"]), int(r["col"])] = r["uncertain"] == "1"
    return lab, unc


def prep():
    A = affine()
    g29 = gray_frame(S29); np.save(os.path.join(W, "g29_half.npy"), g29)
    g44 = gray_frame(S44, A); np.save(os.path.join(W, "g44_on29_half.npy"), g44)
    on = np.asarray(Image.fromarray((np.full_like(g44, 0)).astype(np.uint8)))  # placeholder to keep shapes explicit
    # cells the 1944 sheet covers (warped from an all-black image: fill colour 255 marks off-sheet)
    cov = gray_frame_cover(A); np.save(os.path.join(W, "cover44.npy"), cov)
    for yr, g in (("29", g29), ("44", g44)):
        f, t = features(g); np.savez_compressed(os.path.join(W, f"feat{yr}_v2.npz"), **f); print(yr, "otsu", t, "cells", f["ink"].shape, flush=True)


def gray_frame_cover(A):
    im = Image.new("L", Image.open(S44).size, 0)
    A3 = np.vstack([A, [0, 0, 1]]); S = np.diag([HALF, HALF, 1.0]); M = (np.linalg.inv(A3) @ S)[:2].ravel()
    size = (int(np.ceil(W29 / HALF)), int(np.ceil(H29 / HALF)))
    w = np.asarray(im.transform(size, Image.AFFINE, tuple(M), resample=Image.NEAREST, fillcolor=255), dtype=np.uint8)
    return cellmean((w == 0).astype(np.float32)) > 0.99


def classify():
    from sklearn.ensemble import RandomForestClassifier
    f29 = dict(np.load(os.path.join(W, "feat29_v2.npz"))); f44 = dict(np.load(os.path.join(W, "feat44_v2.npz")))
    keys = sorted(f29); X29 = np.stack([f29[k].ravel() for k in keys], 1); X44 = np.stack([f44[k].ravel() for k in keys], 1)
    lab, unc = labels29(); y = lab.ravel(); cov = np.load(os.path.join(W, "cover44.npy")).ravel()
    # spatial cross-validation: 4 vertical strips
    strip = np.tile(np.arange(NC) * 4 // NC, NR)
    acc = []
    for s in range(4):
        rf = RandomForestClassifier(300, min_samples_leaf=3, n_jobs=-1, random_state=1, class_weight="balanced_subsample").fit(X29[strip != s], y[strip != s])
        p = rf.predict(X29[strip == s]); acc.append([(p[y[strip == s] == c] == c).mean() for c in range(4)])
    print("spatial-CV recall by class (none, IndA, IndB, Comm):", np.round(np.mean(acc, 0), 3), flush=True)
    rf = RandomForestClassifier(400, min_samples_leaf=3, n_jobs=-1, random_state=1, class_weight="balanced_subsample").fit(X29, y)
    P29 = rf.predict_proba(X29); P44 = rf.predict_proba(X44)
    p29 = P29.argmax(1).reshape(NR, NC); p44 = P44.argmax(1).reshape(NR, NC)
    cov = cov.reshape(NR, NC); p44[~cov] = 255
    np.save(os.path.join(W, "pred29.npy"), p29); np.save(os.path.join(W, "pred44.npy"), p44); np.save(os.path.join(W, "prob44.npy"), P44.reshape(NR, NC, 4))
    print("1929 labels:", np.bincount(lab.ravel(), minlength=4), " pred29:", np.bincount(p29.ravel(), minlength=4), " pred44 (on sheet):", np.bincount(p44[cov].ravel(), minlength=4), flush=True)
    # candidate changes: industrial (A or B) or commercial predicted in 1944 but not 1929 ("added"), and the reverse ("removed"),
    # in clusters of at least 6 cells (about half a city block), judged on model output in both years
    cand = []
    for kind, a, b in (("added", p44, p29), ("removed", p29, p44)):
        for zc, zname in ((1, "industrial"), (3, "commercial")):
            isz = lambda m: np.isin(m, [1, 2]) if zc == 1 else (m == 3)
            m = isz(a) & ~isz(b) & cov
            m = ndi.binary_opening(m, np.ones((2, 2)))
            lb, n = ndi.label(m)
            for i, sl in enumerate(ndi.find_objects(lb), 1):
                sz = int((lb[sl] == i).sum())
                if sz >= 6:
                    rr, cc = np.nonzero(lb == i)
                    cand.append({"id": len(cand) + 1, "kind": kind, "zone": zname, "cells": sz, "row0": int(rr.min()), "row1": int(rr.max()), "col0": int(cc.min()), "col1": int(cc.max()),
                                 "label_1929": int(np.bincount(lab[rr, cc], minlength=4).argmax())})
                    np.save(os.path.join(W, f"cand_{len(cand):03d}.npy"), np.stack([rr, cc], 1))
    json.dump(cand, open(os.path.join(W, "candidates_1944.json"), "w"), indent=0)
    print(len(cand), "candidate changes;", sum(c["cells"] for c in cand), "cells", flush=True)


def crops():
    from PIL import ImageDraw
    g29 = np.load(os.path.join(W, "g29_half.npy")); g44 = np.load(os.path.join(W, "g44_on29_half.npy"))
    g29 = np.where(g29 < otsu(g29), 0, 255).astype(np.uint8); g44 = np.where(g44 < otsu(g44), 0, 255).astype(np.uint8)   # same black-and-white rendering for both years
    lab, _ = labels29()
    cand = json.load(open(os.path.join(W, "candidates_1944.json"))); os.makedirs(os.path.join(W, "cand_crops"), exist_ok=True)
    for c in cand:
        pad = 6; r0, r1 = max(0, c["row0"] - pad), min(NR, c["row1"] + pad + 1); c0, c1 = max(0, c["col0"] - pad), min(NC, c["col1"] + pad + 1)
        ys, xs = slice(r0 * CW, r1 * CW), slice(c0 * CW, c1 * CW)
        rc = np.load(os.path.join(W, f"cand_{c['id']:03d}.npy"))
        tiles = []
        for g in (g29, g44):
            im = Image.fromarray(g[ys, xs]).convert("RGB"); d = ImageDraw.Draw(im)
            for r, cc in rc:
                x, y = (cc - c0) * CW, (r - r0) * CW; d.rectangle([x, y, x + CW - 1, y + CW - 1], outline=(220, 0, 0) if c["kind"] == "added" else (0, 90, 220))
            tiles.append(im)
        w, h = tiles[0].size; out = Image.new("RGB", (2 * w + 10, h), "white"); out.paste(tiles[0], (0, 0)); out.paste(tiles[1], (w + 10, 0))
        if max(out.size) > 1100: out.thumbnail((1100, 1100))
        out.save(os.path.join(W, "cand_crops", f"cand_{c['id']:03d}_{c['kind']}_{c['zone']}_{c['cells']}_was{CLASSES[c['label_1929']].replace(' ', '')}.jpg"), quality=85)
    print(len(cand), "crops written")


def write():
    import csv
    lab, unc = labels29(); cand = {c["id"]: c for c in json.load(open(os.path.join(W, "candidates_1944.json")))}
    rev = list(csv.DictReader(open(os.path.join(RAW, "changes_1944_review.csv"))))
    lab44 = lab.copy(); src = np.full((NR, NC), "1929", dtype=object)
    for r in rev:
        if r["accept"] != "1":
            continue
        rc = np.load(os.path.join(W, f"cand_{int(r['id']):03d}.npy")); new = r["zone_1944"]
        lab44[rc[:, 0], rc[:, 1]] = CLASSES.index(new); src[rc[:, 0], rc[:, 1]] = f"change {r['id']}"
    cov = np.load(os.path.join(W, "cover44.npy"))
    with open(os.path.join(RAW, "zone_cells_1944.csv"), "w", newline="") as fh:
        wr = csv.writer(fh); wr.writerow(["col", "row", "px_x0", "px_y0", "px_x1", "px_y1", "zone", "source", "uncertain"])
        for r in range(NR):
            for c in range(NC):
                if lab44[r, c] and cov[r, c]:
                    wr.writerow([c, r, c * CELL, r * CELL, min((c + 1) * CELL, W29), min((r + 1) * CELL, H29), CLASSES[lab44[r, c]], src[r, c], int(unc[r, c] and src[r, c] == "1929")])
    with open(os.path.join(RAW, "cells_off_1944_sheet.csv"), "w", newline="") as fh:   # 1929 grid cells the 1944 sheet does not cover
        wr = csv.writer(fh); wr.writerow(["col", "row"])
        for r, c in zip(*np.nonzero(~cov)): wr.writerow([c, r])
    print("1944 cells:", np.bincount(lab44[cov].ravel(), minlength=4))


if __name__ == "__main__":
    {"prep": prep, "classify": classify, "crops": crops, "write": write}[sys.argv[1]]()
