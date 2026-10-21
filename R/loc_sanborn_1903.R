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
# Measures (dwellings = D-marked buildings, incl. flats and shanties; heavy trades = foundries, smelters, chemical, gas, oil/paint/tar, tanneries,
# packing houses and stockyards, brick and pottery kilns, rail shops and power plants; hazardous adds metal working and machine shops,
# breweries and distilleries):
#   share of dwellings on a block with industry; with a hazardous trade (foundry, smelter, metal and machine works, chemical, gas works,
#   oil/paint/tar, tannery/hides, meat packing and stockyards, brewery/distillery, brick/pottery, rail shops, power plants); facing one
#   across a street; within 150 m of a hazardous block; by the block's 1929 zoning (Industrial A/B, Commercial, or residential use
#   districts) and by the 1900 and 1910 enumeration district it fell in.
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
# where a crossing no longer exists (streets vacated for the Auraria campus, rail yards, the Platte valley), use the crossing of the two
# streets' straight-line extensions, if both surviving streets are straight (PCA residual < 25 m) and the point lies within 1.5 km of both
LINE <- new.env()
st_line_fit <- function(b) { if (!is.null(LINE[[b]])) return(LINE[[b]]); g <- st_geometry(RO[RO$base == b, ]); if (!length(g)) return(NULL)
  m <- st_coordinates(g)[, 1:2, drop = FALSE]; if (nrow(m) < 2) return(NULL); ctr <- colMeans(m); pc <- prcomp(m, center = TRUE)
  res <- sqrt(mean(pc$x[, 2]^2)); out <- if (res < 25) list(c = ctr, d = pc$rotation[, 1], g = g) else NULL; LINE[[b]] <- out; out }
extended <- function(a, b) { la <- st_line_fit(a); lb <- st_line_fit(b); if (is.null(la) || is.null(lb)) return(matrix(numeric(0), 0, 2))
  M <- cbind(la$d, -lb$d); if (abs(det(M)) < 0.2) return(matrix(numeric(0), 0, 2))
  t <- solve(M, lb$c - la$c); p <- la$c + t[1] * la$d; pt <- st_sfc(st_point(p), crs = UTM)
  if (min(st_distance(pt, la$g)) > 1500 || min(st_distance(pt, lb$g)) > 1500) return(matrix(numeric(0), 0, 2)); matrix(p, 1, 2) }
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
ok <- vapply(FITS, function(f) !is.null(f) && isTRUE(f$inside_volume) && f$rmse_m < 40 && (f$n_inliers >= 3 || (f$n_inliers == 2 && f$m_per_px > 0.097 && f$m_per_px < 0.112)), TRUE)
message(sum(ok), " of ", length(SH), " sheets placed (", sum(vapply(FITS[ok], function(f) f$n_inliers >= 3, TRUE)), " with 3+ matching crossings)")
# ---------------------------------------------------------------- sheet footprints with links to the Library of Congress images
CAT <- fread(file.path(RD, "catalogue.csv"))
SHT <- rbindlist(lapply(seq_along(SH), function(k) { s <- SH[[k]]; f <- FITS[[k]]; img <- sub("\\.jpg$", "", sub("^1903_1904_v\\d_", "", nz(s$image, "")))
  cr <- CAT[image_id == img]
  data.table(volume = s$volume, sheet = s$sheet, image_id = img, iiif = nz(cr$iiif[1]), page = nz(cr$page[1]), placed = ok[k],
             n_inliers = if (is.null(f)) 0L else f$n_inliers, rmse_m = if (is.null(f)) NA_real_ else round(f$rmse_m, 1),
             blocks = length(s$blocks), dwellings = sum(vapply(s$blocks, function(b) sum(unlist(nz(b$dwellings, 0)), unlist(nz(b$flats, 0)), unlist(nz(b$shanties, 0)), na.rm = TRUE), 1)),
             industrial = sum(vapply(s$blocks, function(b) length(b$industrial), 1L)) + length(s$outside_blocks), notes = nz(s$sheet_notes, "")) }))
W0 <- 3225; H0 <- 3825
POLY <- lapply(which(ok), function(k) { f <- FITS[[k]]; s <- SH[[k]]   # outline: the area the sheet actually draws (its blocks and crossings, plus 60 m)
  px <- rbind(do.call(rbind, lapply(s$blocks, function(b) if (is.null(b$centroid$x)) NULL else c(as.numeric(b$centroid$x), as.numeric(b$centroid$y)))),
              do.call(rbind, lapply(s$intersections, function(i) if (is.null(i$x)) NULL else c(as.numeric(i$x), as.numeric(i$y)))))
  if (is.null(px) || nrow(px) < 3) { m <- to_geo(f, c(0, W0, W0, 0, 0), c(0, 0, H0, H0, 0)); return(st_polygon(list(m))) }
  g <- to_geo(f, px[, 1], px[, 2]); st_buffer(st_convex_hull(st_multipoint(g)), 60) })
SHP <- st_sf(SHT[ok], geometry = st_sfc(POLY, crs = UTM))
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
    data.table(volume = s$volume, sheet = s$sheet, block_id = nz(b$block_id, ""), x = g[1], y = g[2], partial = isTRUE(b$partial),
               streets = paste(sort(unique(na.omit(st_base(bb)))), collapse = "/"),
               dwellings = sum(as.numeric(c(nz(b$dwellings, 0), nz(b$flats, 0), nz(b$shanties, 0))), na.rm = TRUE), shanties = as.numeric(nz(b$shanties, 0)),
               stores = as.numeric(nz(b$stores, 0)), n_industrial = length(tr), n_hazardous = sum(tr %in% HAZ), n_heavy = sum(tr %in% HEAVY), trades = paste(unique(tr), collapse = "; "),
               establishments = paste(lab[nzchar(lab)], collapse = "; "), dwellings_facing_industry = fac) })) }))
# merge pieces of the same block split across sheets (same streets, centroids within 90 m)
BL[, key := .I]; setorder(BL, streets, x)
grp <- integer(nrow(BL)); g <- 0L
for (i in seq_len(nrow(BL))) if (grp[i] == 0L) { g <- g + 1L; grp[i] <- g
  j <- which(grp == 0L & BL$streets == BL$streets[i] & nzchar(BL$streets[i]) & sqrt((BL$x - BL$x[i])^2 + (BL$y - BL$y[i])^2) < 90); grp[j] <- g }
BL[, grp := grp]
B <- BL[, .(x = mean(x), y = mean(y), sheets = paste(unique(sheet), collapse = ","), volume = volume[1], streets = streets[1],
            dwellings = if (all(partial)) sum(dwellings) else max(dwellings), shanties = max(shanties), stores = max(stores),
            n_industrial = max(n_industrial), n_hazardous = max(n_hazardous), n_heavy = max(n_heavy), trades = paste(unique(unlist(strsplit(trades, "; "))), collapse = "; "),
            establishments = paste(unique(unlist(strsplit(establishments, "; "))), collapse = "; "), dwellings_facing_industry = max(dwellings_facing_industry)), by = grp]
BS <- st_as_sf(B, coords = c("x", "y"), crs = UTM, remove = FALSE)
haz_pts <- BS[BS$n_hazardous > 0, ]
B[, near_haz_150 := lengths(st_is_within_distance(BS, haz_pts, 150)) > 0]
heavy_pts <- BS[BS$n_heavy > 0, ]; B[, near_heavy_150 := lengths(st_is_within_distance(BS, heavy_pts, 150)) > 0]
B[, `:=`(mixed = dwellings > 0 & n_industrial > 0, mixed_haz = dwellings > 0 & n_hazardous > 0)]
B[, exposure := fcase(mixed_haz, "Same block as a hazardous trade", dwellings_facing_industry > 0 | (dwellings > 0 & n_industrial > 0), "Same block as other industry, or facing industry",
                      near_haz_150, "Within 150 m of a hazardous trade", default = "No industry within 150 m")]
# 1929 zoning
Z29 <- st_transform(st_make_valid(st_read(file.path(A, "zoning_1929.geojson"), quiet = TRUE)), UTM)
B[, zone_1929 := { w <- st_within(BS, Z29); vapply(w, function(i) if (length(i)) as.character(Z29$zone[i[1]]) else "Other districts (residence or business)", "") }]
# 1900 and 1910 enumeration districts
ED <- st_transform(st_make_valid(st_read(file.path(A, "denver_eds.geojson"), quiet = TRUE)), UTM)
for (yy in c(1900, 1910)) { e <- ED[ED$year == yy, ]; w <- st_within(BS, e); B[, (paste0("ed_", yy)) := vapply(w, function(i) if (length(i)) as.character(e$ED[i[1]]) else NA_character_, "")] }
# later sites: 1965-92 hazardous-sector manufacturers (hidden / known) within 150 m of a hazardous 1903 block
S <- fread(file.path(A, "sites.csv"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat)]
SS <- st_transform(st_as_sf(S, coords = c("lon", "lat"), crs = 4326), UTM)
B[, `:=`(later_hidden_150 = lengths(st_is_within_distance(BS, SS[SS$radar == "Not on any list", ], 150)) > 0,
         later_known_150 = lengths(st_is_within_distance(BS, SS[SS$radar != "Not on any list", ], 150)) > 0)]
# ---------------------------------------------------------------- results (aggregates)
area_of <- function(v, x, y) fifelse(v == 1, "Volume 1: Auraria, West Denver, South Platte", "Volume 2: north side, Platte valley to Elyria-Swansea")
B[, area := area_of(volume)]
EXPO_ALL <- B[dwellings > 0, .(area = "All sheets read", dwellings = sum(dwellings), pct_same_block_haz = round(100 * sum(dwellings[mixed_haz]) / sum(dwellings), 1), pct_same_block_any = round(100 * sum(dwellings[mixed]) / sum(dwellings), 1), pct_within_150_haz = round(100 * sum(dwellings[mixed_haz | near_haz_150]) / sum(dwellings), 1), pct_same_block_heavy = round(100 * sum(dwellings[n_heavy > 0]) / sum(dwellings), 1), pct_within_150_heavy = round(100 * sum(dwellings[near_heavy_150]) / sum(dwellings), 1), facing_industry = sum(pmin(dwellings_facing_industry, dwellings)))]
EXPO <- B[dwellings > 0, .(blocks = .N, dwellings = sum(dwellings)), by = .(exposure)][, pct_dwellings := round(100 * dwellings / sum(dwellings), 1)][order(-dwellings)]
EXPO_AREA <- B[dwellings > 0, .(dwellings = sum(dwellings), pct_same_block_haz = round(100 * sum(dwellings[mixed_haz]) / sum(dwellings), 1),
                               pct_same_block_any = round(100 * sum(dwellings[mixed]) / sum(dwellings), 1),
                               pct_within_150_haz = round(100 * sum(dwellings[mixed_haz | near_haz_150]) / sum(dwellings), 1),
                               pct_same_block_heavy = round(100 * sum(dwellings[n_heavy > 0]) / sum(dwellings), 1),
                               pct_within_150_heavy = round(100 * sum(dwellings[near_heavy_150]) / sum(dwellings), 1),
                               facing_industry = sum(pmin(dwellings_facing_industry, dwellings))), by = area]
EXPO_AREA <- rbind(EXPO_AREA, EXPO_ALL)
TRADES <- B[, .(trade = unlist(strsplit(trades, "; "))), by = grp][trade != "", .N, by = trade][order(-N)]
ZONE <- B[, .(blocks = .N, dwellings = sum(dwellings), blocks_with_hazardous_trade = sum(n_hazardous > 0), blocks_with_heavy_trade = sum(n_heavy > 0), mixed_blocks = sum(mixed_haz), dwellings_on_heavy_blocks = sum(dwellings[n_heavy > 0])), by = zone_1929]
ZONE[, `:=`(pct_of_hazard_blocks = round(100 * blocks_with_hazardous_trade / sum(blocks_with_hazardous_trade), 1), pct_of_mixed_blocks = round(100 * mixed_blocks / sum(mixed_blocks), 1),
            pct_of_dwellings = round(100 * dwellings / sum(dwellings), 1))]
ZEXP <- B[dwellings > 0, .(dwellings = sum(dwellings)), by = .(exposure, zone_1929)][, pct_of_exposure_group := round(100 * dwellings / sum(dwellings), 1), by = exposure][order(exposure, -dwellings)]
# who lived there: 1910 enumeration districts, weighted by dwellings
E10 <- as.data.table(st_drop_geometry(ED[ED$year == 1910, c("ED", "pct_fb", "pct_black", "pct_laborers", "pct_owner_hh")]))
WHO <- merge(B[dwellings > 0 & !is.na(ed_1910), .(dwellings, exposure, ed = ed_1910)], E10[, ed := as.character(ED)], by = "ed")
WHO <- WHO[, lapply(.SD, function(v) round(weighted.mean(v, dwellings, na.rm = TRUE), 1)), by = exposure, .SDcols = c("pct_fb", "pct_black", "pct_laborers", "pct_owner_hh")]
PERSIST <- B[n_hazardous > 0, .(hazardous_blocks_1903 = .N, pct_with_1965_92_site_150m = round(100 * mean(later_hidden_150 | later_known_150), 1),
                                pct_with_hidden_site_150m = round(100 * mean(later_hidden_150), 1), pct_with_known_site_150m = round(100 * mean(later_known_150), 1))]
fwrite(SHT, file.path(O, "sheets.csv")); fwrite(B[, !c("grp")], file.path(O, "blocks.csv"))
for (nm in c("EXPO", "EXPO_AREA", "TRADES", "ZONE", "ZEXP", "WHO", "PERSIST")) fwrite(get(nm), file.path(O, paste0(tolower(nm), ".csv")))
SHP$thumb <- paste0(SHP$iiif, "/full/pct:12.5/0/default.jpg")
if (file.exists(file.path(A, "sanborn_1903_sheets.geojson"))) file.remove(file.path(A, "sanborn_1903_sheets.geojson"))
st_write(st_transform(SHP, 4326), file.path(A, "sanborn_1903_sheets.geojson"), quiet = TRUE)
BP <- st_transform(st_as_sf(B[, .(sheets, streets, dwellings, n_industrial, n_hazardous, n_heavy, trades, establishments = substr(establishments, 1, 300), exposure, zone_1929, x, y)],
                            coords = c("x", "y"), crs = UTM), 4326)
if (file.exists(file.path(A, "sanborn_1903_blocks.geojson"))) file.remove(file.path(A, "sanborn_1903_blocks.geojson"))
st_write(BP, file.path(A, "sanborn_1903_blocks.geojson"), quiet = TRUE)
for (nm in c("EXPO", "EXPO_AREA", "ZONE", "ZEXP", "WHO", "PERSIST", "TRADES")) fwrite(get(nm), file.path(A, paste0("sanborn1903_", tolower(nm), ".csv")))
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# Housing and industry before zoning: Denver 1903-04 Sanborn maps", "",
             sprintf("%d sheets read, %d placed on the modern map; %s blocks with %s dwellings.", length(SH), sum(ok), format(nrow(B), big.mark = ","), format(sum(B$dwellings), big.mark = ",")), "",
             "## Dwellings by exposure", "", kab(EXPO), "", "## By area", "", kab(EXPO_AREA), "", "## Trades recorded (blocks)", "", kab(TRADES), "",
             "## 1929 zoning of the 1903 blocks", "", kab(ZONE), "", kab(ZEXP), "", "## Who lived there (1910 enumeration districts, dwelling-weighted means)", "", kab(WHO), "",
             "## Persistence: 1903 hazardous blocks with a 1965-92 hazardous-sector site within 150 m", "", kab(PERSIST)), file.path(O, "summary.md"))
print(SHT[, .(sheets = .N, placed = sum(placed)), by = volume]); print(EXPO); print(EXPO_AREA); print(ZONE); print(WHO); print(PERSIST)
message("wrote ", O)
