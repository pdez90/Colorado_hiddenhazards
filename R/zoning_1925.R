# Denver's first zoning ordinance (February 1925) as it stood in January 1929: industrial and commercial districts, georeferenced.
#   Rscript R/zoning_1925.R        (after holc_covenants.R has written app/data/holc_denver.geojson; rerun holc_covenants.R afterwards to use the control)
# Source: "Building Zone Map, City and County of Denver, as adopted by the City Council February 1925, revised to January 1, 1929",
# Denver Public Library Western History Collection, CG4314 .D4 G44 1929 (free download; the 1944 revision is CG4314 .G44 1944). The scan is
# a monochrome hatched map: the 13 districts are drawn as hatch patterns (Residence A-E, Business A-C, Commercial A-C, Industrial A-B).
# A texture classifier (python, in work/zoning on the author's machine; see data/raw/zoning_1929/zone_classification_overlay.jpg for the
# result drawn over the scan) labelled 32-pixel cells of the 11,849 x 12,000 scan as Industrial A ("/" hatch without lot lines, or thick
# "/" hatch), Industrial B ("\" hatch) or Commercial (dense cross-hatch); everything else is residential or business. The cells are in
# data/raw/zoning_1929/zone_cells_1929.csv. This script
#   1. georeferences the scan with the 16 candidate control points (13 resolve to TIGER intersections) (street intersections and park corners read off the scan, data/raw/zoning_1929/
#      gcps_1929.csv) whose real positions come from TIGER road intersections (tigris), by an affine fit in UTM 13N (RMSE printed);
#   2. writes the zoned cells as dissolved polygons, data/results/zoning_1929/zoning_1929.geojson (+ app/data copy);
#   3. computes the share of each HOLC area, 1930/1940 enumeration district and 2010 core tract that was zoned industrial and commercial
#      in 1929, data/results/zoning_1929/zoning_shares_{holc,eds,tracts}.csv, read by holc_covenants.R as a control; a "strict" share drops the
#      cells classified only by the platted thick-hatch rule (Industrial A vs Residence E ambiguity) for the sensitivity check.
# Known limits: Residence E (apartment, thick "/" hatch) and Industrial A share a hatch and are told apart only by lot lines, so a few
# platted Industrial A blocks (Sun Valley, Valverde) and the unplatted hatched land north-east of the city are the least certain cells.
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; R0 <- "data/raw/zoning_1929"; O <- "data/results/zoning_1929"; A <- "app/data"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
cells <- fread(file.path(R0, "zone_cells_1929.csv")); gc <- fread(file.path(R0, "gcps_1929.csv"))
# ---- 1. control points: TIGER road intersections
if (!requireNamespace("tigris", quietly = TRUE)) stop("install.packages('tigris')")
options(tigris_use_cache = TRUE)
RD <- do.call(rbind, lapply(c("Denver", "Jefferson", "Adams", "Arapahoe"), function(cty) tryCatch(tigris::roads("CO", cty, year = 2023, progress_bar = FALSE)[, "FULLNAME"], error = function(e) NULL)))
RD <- st_transform(RD, UTM)
xy <- function(s1, s2) { a <- RD[RD$FULLNAME == s1, ]; b <- RD[RD$FULLNAME == s2, ]; if (!nrow(a) || !nrow(b)) return(NULL)
  p <- suppressWarnings(st_intersection(st_union(a), st_union(b))); p <- st_cast(p, "POINT"); if (!length(p)) NULL else st_coordinates(p) }
P <- lapply(seq_len(nrow(gc)), function(i) xy(gc$street1[i], gc$street2[i]))
miss <- which(vapply(P, is.null, TRUE)); if (length(miss)) message("no TIGER intersection for: ", paste(sprintf("%s & %s", gc$street1[miss], gc$street2[miss]), collapse = "; "))
# first pass on the unambiguous (single-point) control points, then pick the nearest candidate for the rest
single <- which(vapply(P, function(p) !is.null(p) && nrow(p) == 1, TRUE))
fit <- function(idx, XY) { d <- data.frame(px = gc$px_x[idx], py = gc$px_y[idx], X = XY[, 1], Y = XY[, 2]); list(x = lm(X ~ px + py, d), y = lm(Y ~ px + py, d)) }
XY1 <- do.call(rbind, P[single]); f1 <- fit(single, XY1)
pred <- function(f, px, py) cbind(predict(f$x, data.frame(px = px, py = py)), predict(f$y, data.frame(px = px, py = py)))
use <- setdiff(seq_len(nrow(gc)), miss); XY <- t(vapply(use, function(i) { p <- P[[i]]; if (nrow(p) == 1) return(as.numeric(p[1, 1:2])); q <- pred(f1, gc$px_x[i], gc$px_y[i]); k <- which.min((p[, 1] - q[1])^2 + (p[, 2] - q[2])^2); as.numeric(p[k, 1:2]) }, numeric(2)))
f <- fit(use, XY); res <- sqrt((residuals(f$x))^2 + (residuals(f$y))^2)
message(length(use), " control points; residuals (m): ", paste(round(res), collapse = " "), "; RMSE ", round(sqrt(mean(res^2))), " m; scale ", round(1 / sqrt(abs(coef(f$x)["px"] * coef(f$y)["py"] - coef(f$x)["py"] * coef(f$y)["px"])), 3), " px/m")
bad <- which(res > 3 * median(res) & res > 120); if (length(bad)) { message("dropping outliers: ", paste(sprintf("%s & %s (%d m)", gc$street1[use[bad]], gc$street2[use[bad]], round(res[bad])), collapse = "; ")); use <- use[-bad]; XY <- XY[-bad, ]; f <- fit(use, XY); res <- sqrt(residuals(f$x)^2 + residuals(f$y)^2); message("refit RMSE ", round(sqrt(mean(res^2))), " m") }
fwrite(data.table(gc[use], X = XY[, 1], Y = XY[, 2], residual_m = round(res, 1)), file.path(O, "gcp_fit.csv"))
# ---- 2. cells -> polygons in UTM
corner <- function(px, py) pred(f, px, py)
polys <- lapply(seq_len(nrow(cells)), function(i) { c0 <- cells[i]; m <- rbind(corner(c0$px_x0, c0$px_y0), corner(c0$px_x1, c0$px_y0), corner(c0$px_x1, c0$px_y1), corner(c0$px_x0, c0$px_y1), corner(c0$px_x0, c0$px_y0)); st_polygon(list(m)) })
zones <- sort(unique(cells$zone)); Z <- st_sf(zone = zones, geometry = do.call(c, lapply(zones, function(z) st_make_valid(st_union(st_sfc(polys[cells$zone == z], crs = UTM))))))
Z$km2 <- round(as.numeric(st_area(Z)) / 1e6, 2)
Z$class <- ifelse(grepl("Industrial", Z$zone), "Industrial", "Commercial")
print(st_drop_geometry(Z))
f_out <- file.path(O, "zoning_1929.geojson"); if (file.exists(f_out)) file.remove(f_out); st_write(st_transform(Z, 4326), f_out, quiet = TRUE); file.copy(f_out, A, overwrite = TRUE)
ZI <- st_union(Z[Z$class == "Industrial", ]); ZC <- st_union(Z[Z$class == "Commercial", ])
# strict industrial layer: drop the cells classified only by the "thick '/' hatch with lot lines" rule (Industrial A or Residence E; uncertain)
unc <- if ("uncertain" %in% names(cells)) cells$uncertain == 1 else rep(FALSE, nrow(cells))
ZIs <- if (any(!unc & grepl("Industrial", cells$zone))) st_make_valid(st_union(st_sfc(polys[!unc & grepl("Industrial", cells$zone)], crs = UTM))) else ZI
message(sum(unc), " uncertain cells (", round(100 * mean(unc[grepl("Industrial", cells$zone)])), "% of industrial cells) excluded from the strict layer")
# extent of the map sheet (the scan's corners through the affine fit): units less than half inside it have no 1929 zoning value (NA),
# rather than 0, so places the map does not cover are not counted as unzoned
EXT <- st_sfc(st_polygon(list(rbind(corner(0, 0), corner(11849, 0), corner(11849, 12000), corner(0, 12000), corner(0, 0)))), crs = UTM)
share <- function(g) { g <- st_make_valid(st_transform(g, UTM)); a <- as.numeric(st_area(g))
  inx <- numeric(length(g)); it0 <- suppressWarnings(st_intersection(g, EXT)); if (length(it0)) inx[attr(it0, "idx")[, 1]] <- as.numeric(st_area(it0)); outside <- inx / a < 0.5
  f <- function(zz) { it <- suppressWarnings(st_intersection(g, zz)); s <- numeric(length(g)); if (length(it)) s[attr(it, "idx")[, 1]] <- as.numeric(st_area(it)); s }
  out <- data.table(area_km2 = round(a / 1e6, 3), share_industrial_1929 = round(f(ZI) / a, 3), share_industrial_1929_strict = round(f(ZIs) / a, 3), share_commercial_1929 = round(f(ZC) / a, 3))
  out[outside, c("share_industrial_1929", "share_industrial_1929_strict", "share_commercial_1929") := NA_real_]; out }
# ---- 3. shares by HOLC area, ED and tract
H <- st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE); hs <- cbind(as.data.table(st_drop_geometry(H))[, .(area_id, grade)], share(st_geometry(H)))
fwrite(hs, file.path(O, "zoning_shares_holc.csv")); print(hs[grade %in% c("A", "B", "C", "D"), .(areas = .N, km2 = sum(area_km2), pct_industrial_1929 = round(100 * sum(share_industrial_1929 * area_km2) / sum(area_km2), 1), pct_commercial_1929 = round(100 * sum(share_commercial_1929 * area_km2) / sum(area_km2), 1)), by = grade][order(grade)])
es <- rbindlist(lapply(c(1900, 1910, 1920, 1930, 1940), function(yr) { fe <- sprintf("data/results/denver_eds/denver_eds_%d.geojson", yr); if (!file.exists(fe)) return(NULL); E <- st_read(fe, quiet = TRUE); cbind(data.table(census = yr, ED = as.character(E$ED)), share(st_geometry(E))) }))
fwrite(es, file.path(O, "zoning_shares_eds.csv"))
TRg <- st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE); TRg <- TRg[TRg$core %in% c(TRUE, "TRUE"), ]; ts <- cbind(data.table(GEOID = TRg$GEOID), share(st_geometry(TRg)))
fwrite(ts, file.path(O, "zoning_shares_tracts.csv")); file.copy(file.path(O, c("zoning_shares_holc.csv", "zoning_shares_tracts.csv")), A, overwrite = TRUE)
message("industrial 1929: ", round(as.numeric(st_area(ZI)) / 1e6, 1), " km2; commercial: ", round(as.numeric(st_area(ZC)) / 1e6, 1), " km2; tracts with any industrial zoning: ", sum(ts$share_industrial_1929 > 0), " of ", nrow(ts))
