# Housing and industry before zoning: Denver's 1903-04 Sanborn maps (Library of Congress, public domain).
#
#   Rscript R/fetch_loc_sanborn.R sheets       (sheet images, only needed to re-read them)
#   Rscript R/loc_sanborn_1903.R
#
# Inputs
#   data/raw/sanborn_loc/readings/1903_batch_*.json   block-by-block transcriptions of 152 sheets (vol. 1 Auraria / West Denver / South
#                                                     Platte; vol. 2 north side: LoDo, Platte valley, Five Points, Ironton, Cole, Elyria,
#                                                     Swansea): street crossings in sheet pixels, and per block the dwellings, flats,
#                                                     shanties, stores and every industrial or workshop establishment with its trade and
#                                                     equipment, and dwellings directly facing industry across a street
#   data/raw/sanborn_loc/catalogue.csv                Library of Congress image ids, IIIF services and page links
#   work/tiger/tl_2023_08031_addrfeat.shp             Census TIGER street lines for Denver (downloaded with tigris if missing)
#   app/data: sanborn_volumes.geojson, zoning_1929.geojson, denver_eds.geojson (1900, 1910 enumeration districts), sites.csv, historical_sites.csv
# Placing the sheets: every printed street crossing is matched to the crossings of streets with the same name today (ordinal and
# type-insensitive: "38th" matches 38th St and 38th Ave), and a similarity transform (scale, rotation, shift) is fitted by RANSAC:
# the pair of crossings whose transform puts the most other crossings within 35 m of a same-named modern crossing, refitted by
# least squares; the sheet must fall inside its volume's Library of Congress outline. Where a crossing has since disappeared (Auraria
# campus, rail yards) or the names have changed (Elyria, Swansea, West Denver), crossings read off each volume's 1903 key map stand in:
# the key map is fitted to today's streets from its surviving crossings (similarity transform by RANSAC, then an affine refit), and its
# historic crossings become a 1903 gazetteer (data/raw/sanborn_loc/readings/key_v*.json). Fit quality is kept (inliers, RMSE).
# Street-name check: each block's centroid, once placed, should lie within 120 m of the streets the sheet says bound it (tested on
# the streets shown to survive under the same name: those in one of the sheet's crossings that lands on a modern crossing). A sheet placed on only two crossings is kept only if at least 75% of its block-street pairs pass (4+ testable pairs);
# the check is reported for every sheet (sheets.csv: street_pairs, pct_streets_within_120m).
# Block outlines: the block's corners are the modern (or 1903 key-map) crossings of the streets that bound it (N-E, N-W, S-E, S-W, the
# nearest within 250 m; a missing fourth corner completes the parallelogram), shrunk 12 m to the lot line; blocks with fewer than three
# corners get a 50 m circle. Plants drawn on unplatted ground (rail yards, river bottoms, smelter and packing-house grounds) are placed
# from their outlines on the sheet (data/raw/sanborn_loc/readings/1903_outside_xy.json). Distances are edge to edge, block to plant.
# Measures (dwellings = D-marked buildings, incl. flats and shanties; heavy trades = foundries, smelters, chemical, gas, oil/paint/tar, tanneries,
# packing houses and stockyards, brick and pottery kilns, rail shops and power plants; hazardous adds metal working and machine shops,
# breweries and distilleries):
#   share of dwellings on a block with industry; with a hazardous trade (foundry, smelter, metal and machine works, chemical, gas works,
#   oil/paint/tar, tannery/hides, meat packing and stockyards, brewery/distillery, brick/pottery, rail shops, power plants); across the
#   street from one (block edges within 30 m: the next block over a street, not diagonally across a crossing); facing industry as drawn; within 150 m (edge to edge) of a hazardous block or plant; by the
#   block's 1929 zoning (Industrial A/B, Commercial, or residential use districts) and by the 1900 and 1910 enumeration district it fell in.
# Outputs: data/results/sanborn_1903/*.csv, summary.md; app/data/sanborn_1903_sheets.geojson, sanborn_1903_blocks.geojson
for (p in c("data.table", "sf", "jsonlite")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(sf) })
sf_use_s2(FALSE); UTM <- 26913; A <- "app/data"; RD <- "data/raw/sanborn_loc"; O <- "data/results/sanborn_1903"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
JS <- Sys.glob(file.path(RD, "readings", "1903_batch_*.json")); if (!length(JS)) stop("no readings in ", file.path(RD, "readings"))
SH <- unlist(lapply(JS, function(f) jsonlite::fromJSON(f, simplifyVector = FALSE)), recursive = FALSE)
SH <- SH[!duplicated(vapply(SH, function(s) paste(s$volume, s$sheet), ""), fromLast = TRUE)]   # a later re-read (e.g. batch_06b) replaces the first reading
message(length(SH), " sheets read")
nz <- function(x, d = NA) if (is.null(x) || length(x) == 0) d else x
# ---------------------------------------------------------------- street names
ORD <- c(FIRST = 1, SECOND = 2, THIRD = 3, FOURTH = 4, FIFTH = 5, SIXTH = 6, SEVENTH = 7, EIGHTH = 8, NINTH = 9, TENTH = 10, ELEVENTH = 11, TWELFTH = 12,
         THIRTEENTH = 13, FOURTEENTH = 14, FIFTEENTH = 15, SIXTEENTH = 16, SEVENTEENTH = 17, EIGHTEENTH = 18, NINETEENTH = 19, TWENTIETH = 20, THIRTIETH = 30, FORTIETH = 40)
TENS <- c(TWENTY = 20, THIRTY = 30, FORTY = 40, FIFTY = 50)
sfx <- function(n) paste0(n, ifelse(n %% 100 %in% 11:13, "TH", c("TH", "ST", "ND", "RD", rep("TH", 6))[n %% 10 + 1]))
st_base <- function(x) { x <- toupper(ifelse(is.na(x), "", x)); x <- gsub("\\(.*?\\)", " ", x); x <- gsub("[.,']", " ", x)
  for (t in names(TENS)) for (o in names(ORD)[1:9]) x <- gsub(paste0("\\b", t, "[- ]", o, "\\b"), sfx(TENS[[t]] + ORD[[o]]), x)
  for (o in names(ORD)) x <- gsub(paste0("\\b", o, "\\b"), sfx(ORD[[o]]), x)
  x <- gsub("\\b(\\d+)(ST|ND|RD|TH|D)?\\b", "\\1", x); x <- gsub("\\b(\\d+)\\b", "N\\1", x)
  x <- gsub("\\b(AVENUE|AVE|AV|STREET|ST|PLACE|PL|BOULEVARD|BLVD|COURT|CT|DRIVE|DR|LANE|LN|ROAD|RD|WAY|TERRACE|PROPOSED|NOT OPENED|S|N|E|W)\\b", " ", x)
  x <- gsub("\\bN(\\d+)\\b", "\\1", x); gsub("\\s+", " ", trimws(x)) }
TF <- "work/tiger/tl_2023_08031_addrfeat.shp"
if (!file.exists(TF)) { if (!requireNamespace("tigris", quietly = TRUE)) install.packages("tigris", repos = "https://cloud.r-project.org")
  dir.create("work/tiger", showWarnings = FALSE, recursive = TRUE); st_write(tigris::address_ranges("CO", "Denver", year = 2023), TF, quiet = TRUE) }
RO <- st_transform(st_read(TF, quiet = TRUE), UTM); RO$base <- st_base(RO$FULLNAME); RO <- RO[RO$base != "", ]
RO <- aggregate(RO["base"], by = list(b = RO$base), FUN = function(z) z[1]); RO$base <- RO$b; RO$b <- NULL
crossings <- function(a, b) { la <- RO[RO$base == a, ]; lb <- RO[RO$base == b, ]; if (!nrow(la) || !nrow(lb)) return(matrix(numeric(0), 0, 2))
  p <- suppressWarnings(st_intersection(st_geometry(la), st_geometry(lb))); if (!length(p)) return(matrix(numeric(0), 0, 2))
  m <- st_coordinates(st_cast(st_sfc(p), "POINT"))[, 1:2, drop = FALSE]; m[!duplicated(round(m / 15)), , drop = FALSE] }
CX <- new.env()
cand <- function(a, b) { k <- paste(sort(c(a, b)), collapse = "|")
  if (is.null(CX[[k]])) { m <- crossings(a, b); g <- if (exists("GAZ") && !is.null(GAZ) && nrow(GAZ)) as.matrix(GAZ[key == k, .(X, Y)]) else matrix(numeric(0), 0, 2)
    CX[[k]] <- rbind(m, g) }; CX[[k]] }
VOL <- st_transform(st_make_valid(st_read(file.path(A, "sanborn_volumes.geojson"), quiet = TRUE)), UTM)
VOL <- VOL[grepl("1903", VOL$edition), ]
# ---------------------------------------------------------------- fit a similarity transform per sheet (complex numbers: geo = a * px + b)
fit_sheet <- function(s, tol = 35, smin = 0.092, smax = 0.118) {   # every sheet is at 50 ft to the inch: about 0.103 m per pixel at the downloaded size
  ints <- s$intersections; if (length(ints) < 2) return(NULL)
  P <- rbindlist(lapply(ints, function(i) { st <- unlist(i$streets); md <- nz(i$modern, NULL)
    if (!is.null(md) && length(unlist(md)) == 2) st <- unlist(md)
    if (length(st) < 2 || is.null(i$x) || is.null(i$y)) return(NULL)
    data.table(a = st_base(st[1]), b = st_base(st[2]), z = complex(real = as.numeric(i$x), imaginary = -as.numeric(i$y))) }))
  P <- P[a != "" & b != "" & a != b]; if (nrow(P) < 2) return(NULL)
  C <- lapply(seq_len(nrow(P)), function(k) cand(P$a[k], P$b[k])); has <- which(lengths(C) > 0); if (length(has) < 2) return(NULL)
  vpoly <- VOL[VOL$volume == s$volume, ]; vb <- if (nrow(vpoly)) st_buffer(st_union(vpoly), 600) else NULL
  best <- NULL
  for (i in has) for (j in has) if (i < j) for (ci in seq_len(nrow(C[[i]]))) for (cj in seq_len(nrow(C[[j]]))) {
    gi <- complex(real = C[[i]][ci, 1], imaginary = C[[i]][ci, 2]); gj <- complex(real = C[[j]][cj, 1], imaginary = C[[j]][cj, 2])
    if (Mod(P$z[i] - P$z[j]) < 200) next
    a <- (gi - gj) / (P$z[i] - P$z[j]); if (Mod(a) < smin || Mod(a) > smax) next
    b <- gi - a * P$z[i]
    d <- vapply(has, function(k) { g <- a * P$z[k] + b; min(Mod(complex(real = C[[k]][, 1], imaginary = C[[k]][, 2]) - g)) }, 1)
    inl <- has[d < tol]; sc <- length(inl) - mean(pmin(d, tol)) / 1000
    if (is.null(best) || sc > best$sc) best <- list(sc = sc, a = a, b = b, inl = inl) }
  if (is.null(best) || length(best$inl) < 2) return(NULL)
  # least-squares refit on inliers (nearest candidate)
  G <- vapply(best$inl, function(k) { g <- best$a * P$z[k] + best$b; cc <- complex(real = C[[k]][, 1], imaginary = C[[k]][, 2]); cc[which.min(Mod(cc - g))] }, complex(1))
  Z <- P$z[best$inl]; if (length(Z) >= 3) { X <- cbind(Z, 1); co <- solve(Conj(t(X)) %*% X, Conj(t(X)) %*% G); a <- co[1]; b <- co[2] } else { a <- best$a; b <- best$b }
  res <- Mod(a * Z + b - G); ctr <- a * complex(real = 1612, imaginary = -1912) + b
  inside <- if (is.null(vb)) NA else lengths(st_intersects(st_sfc(st_point(c(Re(ctr), Im(ctr))), crs = UTM), vb)) > 0
  list(a = a, b = b, n_points = nrow(P), n_inliers = length(Z), rmse_m = sqrt(mean(res^2)), m_per_px = Mod(a), inside_volume = inside) }
to_geo <- function(f, x, y) { g <- f$a * complex(real = x, imaginary = -y) + f$b; cbind(Re(g), Im(g)) }
# ---------------------------------------------------------------- 1903 gazetteer from the key maps
GAZ <- NULL; KF <- Sys.glob(file.path(RD, "readings", "key_v*.json"))
if (length(KF)) {
  GAZ <- rbindlist(lapply(KF, function(f) { k <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    s <- list(volume = k$volume, intersections = k$crossings); fk <- fit_sheet(s, tol = 60, smin = 0.4, smax = 6)
    if (is.null(fk) || fk$n_inliers < 6) { message("key map ", basename(f), ": could not be fitted"); return(NULL) }
    P <- rbindlist(lapply(k$crossings, function(i) { st <- unlist(i$streets); if (length(st) < 2) return(NULL)
      data.table(a = st_base(st[1]), b = st_base(st[2]), x = as.numeric(i$x), y = as.numeric(i$y)) }))
    P <- P[a != "" & b != "" & a != b]
    # affine refit on the surviving crossings that matched (inliers of the similarity fit)
    tg <- to_geo(fk, P$x, P$y); P[, `:=`(gx = tg[, 1], gy = tg[, 2])]
    P[, d := vapply(seq_len(.N), function(r) { m <- crossings(a[r], b[r]); if (!nrow(m)) NA_real_ else min(sqrt((m[, 1] - gx[r])^2 + (m[, 2] - gy[r])^2)) }, 1)]
    P[, `:=`(tx = NA_real_, ty = NA_real_)]
    for (r in which(!is.na(P$d) & P$d < 60)) { m <- crossings(P$a[r], P$b[r]); j <- which.min((m[, 1] - P$gx[r])^2 + (m[, 2] - P$gy[r])^2); P$tx[r] <- m[j, 1]; P$ty[r] <- m[j, 2] }
    C <- P[!is.na(tx)]
    if (nrow(C) >= 6) { mx <- lm(tx ~ x + y, data = C); my <- lm(ty ~ x + y, data = C)
      P[, `:=`(X = predict(mx, P), Y = predict(my, P))]; rm_ <- sqrt(mean(c(resid(mx), resid(my))^2)) } else { P[, `:=`(X = gx, Y = gy)]; rm_ <- fk$rmse_m }
    message(sprintf("key map vol. %s: %d crossings, fitted on %d surviving ones (RMSE %.0f m)", k$volume, nrow(P), nrow(C), rm_))
    P[, .(key = vapply(seq_len(.N), function(r) paste(sort(c(a[r], b[r])), collapse = "|"), ""), X, Y, volume = k$volume)] }))
  if (!nrow(GAZ)) GAZ <- NULL
  rm(list = ls(CX), envir = CX)
}
FITS <- lapply(SH, function(s) tryCatch(fit_sheet(s), error = function(e) NULL))
# street-name check: distance from each placed block centroid to the modern line of each street that bounds it. Only streets that
# demonstrably survive here under the same name are tested: names in one of the sheet's own crossings that lands within 35 m of a
# modern crossing of the same streets once the sheet is placed (renamed streets, e.g. in Elyria or old West Denver, are skipped;
# the reader's modern names for a crossing are used where given)
MX <- new.env(); mcross <- function(a, b) { k <- paste(sort(c(a, b)), collapse = "|"); if (is.null(MX[[k]])) MX[[k]] <- crossings(a, b); MX[[k]] }
bnames <- function(b) unique(na.omit(st_base(unlist(lapply(c("N", "S", "E", "W"), function(d) nz(b$bounded_by[[d]], NA))))))
st_check <- function(s, f) { if (is.null(f)) return(c(n = 0, ok = NA_real_))
  ren <- character(0); V <- character(0)
  for (i in s$intersections) { st <- unlist(i$streets); md <- unlist(nz(i$modern, NULL)); if (length(st) < 2 || is.null(i$x) || is.null(i$y)) next
    o <- st_base(st[1:2]); m <- if (length(md) == 2) st_base(md) else o
    if (length(md) == 2) ren[o] <- m
    if (any(!nzchar(m)) || m[1] == m[2]) next
    mc <- mcross(m[1], m[2]); if (!nrow(mc)) next
    g <- to_geo(f, as.numeric(i$x), as.numeric(i$y)); if (min(sqrt((mc[, 1] - g[1])^2 + (mc[, 2] - g[2])^2)) <= 35) V <- union(V, m) }
  d <- unlist(lapply(s$blocks, function(b) { c0 <- b$centroid; if (is.null(c0$x) || is.null(c0$y)) return(NULL)
    nm <- bnames(b); nm <- ifelse(nm %in% names(ren), ren[nm], nm); nm <- unique(nm[nzchar(nm) & nm %in% V & nm %in% RO$base]); if (!length(nm)) return(NULL)
    g <- st_sfc(st_point(to_geo(f, as.numeric(c0$x), as.numeric(c0$y))[1, ]), crs = UTM)
    as.numeric(st_distance(g, RO[match(nm, RO$base), ])) }))
  c(n = length(d), ok = if (length(d)) mean(d <= 120) else NA_real_) }
SC <- t(vapply(seq_along(SH), function(k) st_check(SH[[k]], FITS[[k]]), c(n = 0, ok = 0)))
st_pass <- SC[, "n"] >= 4 & !is.na(SC[, "ok"]) & SC[, "ok"] >= 0.75
ok <- vapply(seq_along(FITS), function(k) { f <- FITS[[k]]; !is.null(f) && isTRUE(f$inside_volume) && f$rmse_m < 40 &&
  (f$n_inliers >= 3 || (f$n_inliers == 2 && f$m_per_px > 0.097 && f$m_per_px < 0.112 && st_pass[k])) }, TRUE)
message(sum(ok), " of ", length(SH), " sheets placed (", sum(vapply(FITS[ok], function(f) f$n_inliers >= 3, TRUE)), " with 3+ matching crossings; two-crossing sheets kept only if their streets check out)")
message(sprintf("street-name check on placed sheets: median %.0f%% of block-street pairs within 120 m; %d placed sheets below 75%%",
                100 * median(SC[ok, "ok"], na.rm = TRUE), sum(ok & SC[, "n"] >= 4 & SC[, "ok"] < 0.75, na.rm = TRUE)))
# ---------------------------------------------------------------- sheet footprints with links to the Library of Congress images
CAT <- fread(file.path(RD, "catalogue.csv"))
SHT <- rbindlist(lapply(seq_along(SH), function(k) { s <- SH[[k]]; f <- FITS[[k]]; img <- sub("\\.jpg$", "", sub("^1903_1904_v\\d_", "", nz(s$image, "")))
  cr <- CAT[image_id == img]
  data.table(volume = s$volume, sheet = s$sheet, image_id = img, iiif = nz(cr$iiif[1]), page = nz(cr$page[1]), placed = ok[k],
             n_inliers = if (is.null(f)) 0L else f$n_inliers, rmse_m = if (is.null(f)) NA_real_ else round(f$rmse_m, 1),
             street_pairs = SC[k, "n"], pct_streets_within_120m = round(100 * SC[k, "ok"], 1),
             blocks = length(s$blocks), dwellings = sum(vapply(s$blocks, function(b) sum(unlist(nz(b$dwellings, 0)), unlist(nz(b$flats, 0)), unlist(nz(b$shanties, 0)), na.rm = TRUE), 1)),
             industrial = sum(vapply(s$blocks, function(b) length(b$industrial), 1L)) + length(s$outside_blocks), notes = nz(s$sheet_notes, "")) }))
W0 <- 3225; H0 <- 3825
POLY <- lapply(which(ok), function(k) { f <- FITS[[k]]; s <- SH[[k]]   # outline: the area the sheet actually draws (its blocks and crossings, plus 60 m)
  px <- rbind(do.call(rbind, lapply(s$blocks, function(b) if (is.null(b$centroid$x)) NULL else c(as.numeric(b$centroid$x), as.numeric(b$centroid$y)))),
              do.call(rbind, lapply(s$intersections, function(i) if (is.null(i$x)) NULL else c(as.numeric(i$x), as.numeric(i$y)))))
  if (is.null(px) || nrow(px) < 3) { m <- to_geo(f, c(0, W0, W0, 0, 0), c(0, 0, H0, H0, 0)); return(st_polygon(list(m))) }
  g <- to_geo(f, px[, 1], px[, 2]); st_buffer(st_convex_hull(st_multipoint(g)), 60) })
SHP <- st_sf(SHT[ok], geometry = st_sfc(POLY, crs = UTM))
# image corners (top-left, top-right, bottom-left) for laying the sheet image itself on the map
CRN <- rbindlist(lapply(which(ok), function(k) { g <- to_geo(FITS[[k]], c(0, W0, 0), c(0, 0, H0))
  ll <- st_coordinates(st_transform(st_sfc(lapply(1:3, function(i) st_point(g[i, ])), crs = UTM), 4326))
  data.table(tl_lon = ll[1, 1], tl_lat = ll[1, 2], tr_lon = ll[2, 1], tr_lat = ll[2, 2], bl_lon = ll[3, 1], bl_lat = ll[3, 2]) }))
SHP <- cbind(SHP, CRN)
# ---------------------------------------------------------------- blocks
HEAVY <- c("foundry", "smelter", "chemical", "gas works", "oil/paint/tar", "oil/paint", "tannery/hides", "meat packing/stockyard", "brick/stone/pottery", "brick/stone",
           "rail shops/roundhouse", "power/electric")
HAZ <- c("foundry", "smelter", "metal working", "machine shop", "chemical", "gas works", "oil/paint/tar", "oil/paint", "tannery/hides", "meat packing/stockyard",
         "brewery/distillery", "brick/stone/pottery", "brick/stone", "rail shops/roundhouse", "power/electric")
BL <- rbindlist(lapply(seq_along(SH), function(k) { s <- SH[[k]]; if (!ok[k]) return(NULL); f <- FITS[[k]]
  rbindlist(lapply(s$blocks, function(b) { c0 <- b$centroid; if (is.null(c0$x) || is.null(c0$y)) return(NULL); g <- to_geo(f, as.numeric(c0$x), as.numeric(c0$y))
    tr <- vapply(b$industrial, function(i) tolower(nz(i$trade, "other")), ""); lab <- vapply(b$industrial, function(i) paste(na.omit(c(nz(i$name, NA), nz(i$label, NA))), collapse = " – "), "")
    fac <- sum(vapply(b$faces, function(x) as.numeric(nz(x$dwellings_facing, 0)), 1), na.rm = TRUE)
    bb <- unlist(lapply(c("N", "S", "E", "W"), function(d) nz(b$bounded_by[[d]], NA)))
    bn <- vapply(c("N", "S", "E", "W"), function(d) { v <- nz(b$bounded_by[[d]], NA); if (is.na(v)) "" else st_base(v) }, "")
    data.table(volume = s$volume, sheet = s$sheet, block_id = nz(b$block_id, ""), x = g[1], y = g[2], partial = isTRUE(b$partial),
               nN = bn[["N"]], nS = bn[["S"]], nE = bn[["E"]], nW = bn[["W"]],
               streets = { v <- st_base(bb); paste(sort(unique(v[!is.na(v) & nzchar(v)])), collapse = "/") },   # unnamed sides give "", not a street
               dwellings = sum(as.numeric(c(nz(b$dwellings, 0), nz(b$flats, 0), nz(b$shanties, 0))), na.rm = TRUE), shanties = as.numeric(nz(b$shanties, 0)),
               stores = as.numeric(nz(b$stores, 0)), n_industrial = length(tr), n_hazardous = sum(tr %in% HAZ), n_heavy = sum(tr %in% HEAVY), trades = paste(unique(tr), collapse = "; "),
               establishments = paste(lab[nzchar(lab)], collapse = "; "), dwellings_facing_industry = fac) })) }))
# merge pieces of the same block split across sheets (same streets, centroids within 90 m)
BL[, key := .I]; setorder(BL, streets, x)
grp <- integer(nrow(BL)); g <- 0L
for (i in seq_len(nrow(BL))) if (grp[i] == 0L) { g <- g + 1L; grp[i] <- g
  j <- which(grp == 0L & BL$streets == BL$streets[i] & nzchar(BL$streets[i]) & sqrt((BL$x - BL$x[i])^2 + (BL$y - BL$y[i])^2) < 90); grp[j] <- g }
BL[, grp := grp]
# block outlines from the crossings of the streets that bound the block
corner <- function(a, b, x, y) { if (!nzchar(a) || !nzchar(b) || a == b) return(NULL); m <- cand(a, b); if (!nrow(m)) return(NULL)
  d <- sqrt((m[, 1] - x)^2 + (m[, 2] - y)^2); if (min(d) > 250) NULL else m[which.min(d), ] }
block_poly <- function(x, y, nN, nS, nE, nW) {
  cn <- list(NE = corner(nN, nE, x, y), NW = corner(nN, nW, x, y), SE = corner(nS, nE, x, y), SW = corner(nS, nW, x, y))
  have <- !vapply(cn, is.null, TRUE)
  if (sum(have) == 3) { opp <- c(NE = "SW", NW = "SE", SE = "NW", SW = "NE"); nb <- list(NE = c("NW", "SE"), NW = c("NE", "SW"), SE = c("NE", "SW"), SW = c("NW", "SE"))
    k <- names(cn)[!have]; cn[[k]] <- cn[[nb[[k]][1]]] + cn[[nb[[k]][2]]] - cn[[opp[[k]]]]; have[k] <- TRUE }
  if (sum(have) == 4) { m <- do.call(rbind, cn[c("NE", "NW", "SW", "SE")])
    pg <- st_buffer(st_convex_hull(st_multipoint(m)), -12)
    if (!st_is_empty(pg)) { ar <- st_area(pg); if (ar > 1500 && ar < 80000 && st_distance(st_point(c(x, y)), pg)[1] < 40) return(list(g = pg, corners = 4L)) } }
  list(g = st_buffer(st_point(c(x, y)), 50), corners = 0L) }
BP0 <- lapply(seq_len(nrow(BL)), function(i) with(BL[i], block_poly(x, y, nN, nS, nE, nW)))
BL[, corners := vapply(BP0, `[[`, 1L, "corners")]
B <- BL[, .(x = mean(x), y = mean(y), corners = max(corners), piece = .I[which.max(corners)], sheets = paste(unique(sheet), collapse = ","), volume = volume[1], streets = streets[1],
            dwellings = if (all(partial)) sum(dwellings) else max(dwellings), shanties = max(shanties), stores = max(stores),
            n_industrial = if (all(partial)) sum(n_industrial) else max(n_industrial), n_hazardous = if (all(partial)) sum(n_hazardous) else max(n_hazardous),
            n_heavy = if (all(partial)) sum(n_heavy) else max(n_heavy), trades = paste(unique(unlist(strsplit(trades, "; "))), collapse = "; "),
            establishments = paste(unique(unlist(strsplit(establishments, "; "))), collapse = "; "), dwellings_facing_industry = max(dwellings_facing_industry)), by = grp]
B[, dwellings_facing_industry := pmin(dwellings_facing_industry, dwellings)]   # a block cannot have more facing dwellings than dwellings
B[, poly_from := fifelse(corners == 4L, "street crossings", "50 m circle (corners not found)")]
BG <- st_sfc(lapply(seq_len(nrow(B)), function(i) if (B$corners[i] == 4L) BP0[[B$piece[i]]]$g else st_buffer(st_point(c(B$x[i], B$y[i])), 50)), crs = UTM)
BS <- st_as_sf(B, coords = c("x", "y"), crs = UTM, remove = FALSE)      # centroids, for point joins (zoning, enumeration districts)
# plants on unplatted ground, placed from their outlines on the sheet
OXF <- file.path(RD, "readings", "1903_outside_xy.json")
OXY <- if (file.exists(OXF)) as.data.table(jsonlite::fromJSON(OXF)) else data.table(volume = integer(), sheet = character(), index = integer())
OXY[, sheet := as.character(sheet)]
OP <- rbindlist(lapply(which(ok), function(k) { s <- SH[[k]]; ob <- s$outside_blocks; if (!length(ob)) return(NULL); f <- FITS[[k]]
  rbindlist(lapply(seq_along(ob), function(i) { o <- ob[[i]]; r <- OXY[volume == s$volume & sheet == as.character(s$sheet) & index == i - 1L]
    if (!nrow(r) || is.na(r$x0[1])) return(NULL)
    g <- to_geo(f, c(r$x0, r$x1, r$x1, r$x0, r$x0), c(r$y0, r$y0, r$y1, r$y1, r$y0))
    data.table(volume = s$volume, sheet = s$sheet, label = nz(o$label, ""), name = nz(o$name, ""), trade = tolower(nz(o$trade, "other")), geom = list(st_polygon(list(g)))) })) }))
OPG <- if (nrow(OP)) st_sfc(OP$geom, crs = UTM) else st_sfc(crs = UTM)
if (nrow(OP)) { OP[, geom := NULL]; OP[, `:=`(hazardous = trade %in% HAZ, heavy = trade %in% HEAVY)] }
message(nrow(OP), " plants on unplatted ground placed (", sum(OP$hazardous), " hazardous)")
# edge-to-edge distance from each block to the nearest other hazardous (heavy) block or plant
dmin <- function(which_blocks, which_plants) {
  tg <- c(BG[which_blocks], OPG[which_plants]); own <- c(which(which_blocks), rep(NA_integer_, sum(which_plants)))
  if (!length(tg)) return(rep(Inf, length(BG)))
  D <- st_distance(BG, tg); D <- matrix(as.numeric(D), nrow = length(BG))
  for (j in which(!is.na(own))) D[own[j], j] <- Inf                    # a block's own trades are counted as "same block"
  apply(D, 1, min) }
B[, `:=`(d_haz_m = round(dmin(B$n_hazardous > 0, if (nrow(OP)) OP$hazardous else logical(0))), d_heavy_m = round(dmin(B$n_heavy > 0, if (nrow(OP)) OP$heavy else logical(0))))]
B[, `:=`(near_haz_150 = d_haz_m <= 150, near_heavy_150 = d_heavy_m <= 150 | n_heavy > 0, across_haz = d_haz_m <= 30)]
B[, `:=`(mixed = dwellings > 0 & n_industrial > 0, mixed_haz = dwellings > 0 & n_hazardous > 0)]
B[, exposure := fcase(mixed_haz, "Same block as a hazardous trade", dwellings > 0 & across_haz, "Across the street from a hazardous trade",
                      dwellings_facing_industry > 0 | (dwellings > 0 & n_industrial > 0), "Same block as other industry, or facing industry",
                      near_haz_150, "Within 150 m of a hazardous trade", default = "No hazardous trade within 150 m")]
# 1929 zoning
Z29 <- st_transform(st_make_valid(st_read(file.path(A, "zoning_1929.geojson"), quiet = TRUE)), UTM)
B[, zone_1929 := { w <- st_within(BS, Z29); vapply(w, function(i) if (length(i)) as.character(Z29$zone[i[1]]) else "Other districts (residence or business)", "") }]
# 1900 and 1910 enumeration districts
ED <- st_transform(st_make_valid(st_read(file.path(A, "denver_eds.geojson"), quiet = TRUE)), UTM)
for (yy in c(1900, 1910)) { e <- ED[ED$year == yy, ]; w <- st_within(BS, e); B[, (paste0("ed_", yy)) := vapply(w, function(i) if (length(i)) as.character(e$ED[i[1]]) else NA_character_, "")] }
# later sites: 1965-92 hazardous-sector manufacturers (hidden / known) within 150 m of a hazardous 1903 block
S <- fread(file.path(A, "sites.csv"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat)]
SS <- st_transform(st_as_sf(S, coords = c("lon", "lat"), crs = 4326), UTM)
SH_ <- SS[SS$radar == "Not on any list", ]; SK_ <- SS[SS$radar != "Not on any list", ]
B[, `:=`(later_hidden_150 = lengths(st_is_within_distance(BG, SH_, 150)) > 0, later_known_150 = lengths(st_is_within_distance(BG, SK_, 150)) > 0)]
if (nrow(OP)) OP[, `:=`(later_hidden_150 = lengths(st_is_within_distance(OPG, SH_, 150)) > 0, later_known_150 = lengths(st_is_within_distance(OPG, SK_, 150)) > 0)]
# ---------------------------------------------------------------- results (aggregates)
area_of <- function(v) fifelse(v == 1, "Auraria, West Denver, South Platte (vol. 1)", "North side to Elyria-Swansea (vol. 2)")
B[, area := area_of(volume)]
EXPO_ALL <- B[dwellings > 0, .(area = "All placed sheets", dwellings = sum(dwellings), pct_same_block_haz = round(100 * sum(dwellings[mixed_haz]) / sum(dwellings), 1), pct_same_block_any = round(100 * sum(dwellings[mixed]) / sum(dwellings), 1), pct_across_street_haz = round(100 * sum(dwellings[!mixed_haz & across_haz]) / sum(dwellings), 1), pct_within_150_haz = round(100 * sum(dwellings[mixed_haz | near_haz_150]) / sum(dwellings), 1), pct_same_block_heavy = round(100 * sum(dwellings[n_heavy > 0]) / sum(dwellings), 1), pct_within_150_heavy = round(100 * sum(dwellings[near_heavy_150]) / sum(dwellings), 1), facing_industry = sum(pmin(dwellings_facing_industry, dwellings)))]
EXPO <- B[dwellings > 0, .(blocks = .N, dwellings = sum(dwellings)), by = .(exposure)][, pct_dwellings := round(100 * dwellings / sum(dwellings), 1)][order(-dwellings)]
EXPO_AREA <- B[dwellings > 0, .(dwellings = sum(dwellings), pct_same_block_haz = round(100 * sum(dwellings[mixed_haz]) / sum(dwellings), 1),
                               pct_same_block_any = round(100 * sum(dwellings[mixed]) / sum(dwellings), 1),
                               pct_across_street_haz = round(100 * sum(dwellings[!mixed_haz & across_haz]) / sum(dwellings), 1),
                               pct_within_150_haz = round(100 * sum(dwellings[mixed_haz | near_haz_150]) / sum(dwellings), 1),
                               pct_same_block_heavy = round(100 * sum(dwellings[n_heavy > 0]) / sum(dwellings), 1),
                               pct_within_150_heavy = round(100 * sum(dwellings[near_heavy_150]) / sum(dwellings), 1),
                               facing_industry = sum(pmin(dwellings_facing_industry, dwellings))), by = area]
EXPO_AREA <- rbind(EXPO_AREA, EXPO_ALL)
TRADES <- B[, .(trade = unlist(strsplit(trades, "; "))), by = grp][trade != "", .N, by = trade][order(-N)]
ZONE <- B[, .(blocks = .N, dwellings = sum(dwellings), blocks_with_hazardous_trade = sum(n_hazardous > 0), blocks_with_heavy_trade = sum(n_heavy > 0), blocks_mixed_with_hazardous_trade = sum(mixed_haz), dwellings_on_heavy_blocks = sum(dwellings[n_heavy > 0])), by = zone_1929]
ZONE[, `:=`(pct_of_hazard_blocks = round(100 * blocks_with_hazardous_trade / sum(blocks_with_hazardous_trade), 1), pct_of_mixed_blocks = round(100 * blocks_mixed_with_hazardous_trade / sum(blocks_mixed_with_hazardous_trade), 1),
            pct_of_dwellings = round(100 * dwellings / sum(dwellings), 1))]
ZEXP <- B[dwellings > 0, .(dwellings = sum(dwellings)), by = .(exposure, zone_1929)][, pct_of_exposure_group := round(100 * dwellings / sum(dwellings), 1), by = exposure][order(exposure, -dwellings)]
# who lived there: 1910 enumeration districts, weighted by dwellings
E10 <- as.data.table(st_drop_geometry(ED[ED$year == 1910, c("ED", "pct_fb", "pct_black", "pct_laborers", "pct_owner_hh")]))
WHO <- merge(B[dwellings > 0 & !is.na(ed_1910), .(dwellings, exposure, ed = ed_1910)], E10[, ed := as.character(ED)], by = "ed")
WHO <- WHO[, lapply(.SD, function(v) round(weighted.mean(v, dwellings, na.rm = TRUE), 1)), by = exposure, .SDcols = c("pct_fb", "pct_black", "pct_laborers", "pct_owner_hh")]
pers <- function(d, what) d[, .(what = what, n = .N, pct_with_1965_92_site_150m = round(100 * mean(later_hidden_150 | later_known_150), 1),
                                pct_with_hidden_site_150m = round(100 * mean(later_hidden_150), 1), pct_with_known_site_150m = round(100 * mean(later_known_150), 1))]
PERSIST <- rbind(pers(B[n_hazardous > 0], "Blocks with a hazardous trade"), if (nrow(OP) && any(OP$hazardous)) pers(OP[hazardous == TRUE], "Hazardous plants on unplatted ground"))
OUTSIDE <- if (nrow(OP)) OP[, .(plants = .N), by = trade][order(-plants)] else data.table(trade = character(), plants = integer())
POLYQ <- B[, .(blocks = .N, dwellings = sum(dwellings)), by = poly_from]
COVER <- SHT[, .(sheets_read = .N, sheets_placed = sum(placed), dwellings_read = sum(dwellings), dwellings_on_placed_sheets = sum(dwellings[placed])), by = .(volume)]
COVER[, pct_dwellings_covered := round(100 * dwellings_on_placed_sheets / dwellings_read, 1)]; print(COVER)
fwrite(SHT, file.path(O, "sheets.csv")); fwrite(B[, !c("grp", "piece")], file.path(O, "blocks.csv"))
for (nm in c("EXPO", "EXPO_AREA", "TRADES", "ZONE", "ZEXP", "WHO", "PERSIST", "COVER", "OUTSIDE", "POLYQ")) fwrite(get(nm), file.path(O, paste0(tolower(nm), ".csv")))
SHP$thumb <- paste0(SHP$iiif, "/full/pct:12.5/0/default.jpg"); SHP$overlay <- paste0(SHP$iiif, "/full/pct:25/0/default.jpg")
if (file.exists(file.path(A, "sanborn_1903_sheets.geojson"))) file.remove(file.path(A, "sanborn_1903_sheets.geojson"))
st_write(st_transform(SHP, 4326), file.path(A, "sanborn_1903_sheets.geojson"), quiet = TRUE)
BP <- st_transform(st_sf(B[, .(sheets, streets, dwellings, n_industrial, n_hazardous, n_heavy, trades, establishments = substr(establishments, 1, 300), exposure, zone_1929, d_haz_m, poly_from)],
                         geometry = BG), 4326)
if (file.exists(file.path(A, "sanborn_1903_blocks.geojson"))) file.remove(file.path(A, "sanborn_1903_blocks.geojson"))
st_write(BP, file.path(A, "sanborn_1903_blocks.geojson"), quiet = TRUE)
for (nm in c("EXPO", "EXPO_AREA", "ZONE", "ZEXP", "WHO", "PERSIST", "TRADES", "COVER", "OUTSIDE")) fwrite(get(nm), file.path(A, paste0("sanborn1903_", tolower(nm), ".csv")))
if (file.exists(file.path(A, "sanborn_1903_plants.geojson"))) file.remove(file.path(A, "sanborn_1903_plants.geojson"))
if (nrow(OP)) st_write(st_transform(st_sf(OP[, .(volume, sheet, label, name, trade, hazardous)], geometry = OPG), 4326), file.path(A, "sanborn_1903_plants.geojson"), quiet = TRUE)
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# Housing and industry before zoning: Denver 1903-04 Sanborn maps", "",
             sprintf("%d sheets read, %d placed on the modern map; %s blocks with %s dwellings.", length(SH), sum(ok), format(nrow(B), big.mark = ","), format(sum(B$dwellings), big.mark = ",")), "",
             "## Coverage: dwellings on sheets placed on the map", "", kab(COVER), "", "## Dwellings by exposure (placed sheets)", "", kab(EXPO), "", "## By area", "", kab(EXPO_AREA), "", "## Trades recorded (blocks)", "", kab(TRADES), "",
             "## 1929 zoning of the 1903 blocks", "", kab(ZONE), "", kab(ZEXP), "", "## Who lived there (1910 enumeration districts, dwelling-weighted means)", "", kab(WHO), "",
             "## Persistence: 1903 hazardous blocks and plants with a 1965-92 hazardous-sector site within 150 m", "", kab(PERSIST), "",
             "## Plants on unplatted ground (placed from their outlines)", "", kab(OUTSIDE), "", "## Block outlines", "", kab(POLYQ)), file.path(O, "summary.md"))
print(SHT[, .(sheets = .N, placed = sum(placed)), by = volume]); print(EXPO); print(EXPO_AREA); print(ZONE); print(WHO); print(PERSIST); print(POLYQ)
message("wrote ", O)
