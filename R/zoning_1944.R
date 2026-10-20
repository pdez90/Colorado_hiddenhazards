# Denver's zoning districts in 1929 and 1944: did the industrial and commercial districts change around the 1938 HOLC map?
#   Rscript R/zoning_1944.R        (after R/zoning_1925.R and R/holc_covenants.R)
# Source: the same Denver Public Library building-zone map, "as adopted February 1925", in its revision to 1 January 1929 and its
# revision to 1 April 1944. The 1944 cells (data/raw/zoning_1929/zone_cells_1944.csv, on the 1929 cell grid) come from
# pipeline/zoning/classify_zoning_1944.py: the 1944 sheet registered to the 1929 scan, one texture classifier trained on the 1929 labels
# applied to both years, every cluster of disagreement of a block or more (12+ cells, ~41 m cells) reviewed by eye on side-by-side
# crops, and only visibly redrawn districts accepted (data/raw/zoning_1929/changes_1944_review.csv: 226 candidates, 118 reviewed,
# 9 accepted). Changes smaller than about a block, and the hand-coloured amendments drawn on the 1944 copy after printing, are not included.
# Cells are placed with the same control-point fit as 1929 (data/results/zoning_1929/gcp_fit.csv).
# Outputs (data/results/zoning_1944/, copies in app/data): zoning_1944.geojson; zoning_1929_1944_change.geojson (the cells that changed);
# zoning_1929_vs_1944.csv (km2 by district and year); zoning_change_by_holc_grade.csv (industrial and commercial km2 in each HOLC grade,
# 1929 and 1944); zoning_changes_1944.csv (one row per accepted change: what it was, what it became, where).
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; R0 <- "data/raw/zoning_1929"; O <- "data/results/zoning_1944"; A <- "app/data"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
g <- fread("data/results/zoning_1929/gcp_fit.csv"); fx <- lm(X ~ px_x + px_y, g); fy <- lm(Y ~ px_x + px_y, g)
P <- function(px, py) cbind(predict(fx, data.frame(px_x = px, px_y = py)), predict(fy, data.frame(px_x = px, px_y = py)))
cellpoly <- function(d) st_sfc(lapply(seq_len(nrow(d)), function(i) { r <- d[i]
  st_polygon(list(rbind(P(r$px_x0, r$px_y0), P(r$px_x1, r$px_y0), P(r$px_x1, r$px_y1), P(r$px_x0, r$px_y1), P(r$px_x0, r$px_y0)))) }), crs = UTM)
off <- fread(file.path(R0, "cells_off_1944_sheet.csv"))[, k := paste(col, row)]
c29 <- fread(file.path(R0, "zone_cells_1929.csv"))[!paste(col, row) %in% off$k]   # compare only where the 1944 sheet exists
c44 <- fread(file.path(R0, "zone_cells_1944.csv"))
dissolve <- function(d, yr) { zs <- sort(unique(d$zone)); pg <- cellpoly(d)
  st_sf(year = yr, zone = zs, geometry = do.call(c, lapply(zs, function(z) st_make_valid(st_union(pg[d$zone == z]))))) }
Z29 <- dissolve(c29, 1929); Z44 <- dissolve(c44, 1944)
km <- function(Z) data.table(zone = Z$zone, km2 = round(as.numeric(st_area(Z)) / 1e6, 2))
T1 <- merge(km(Z29), km(Z44), by = "zone", suffixes = c("_1929", "_1944"))[, change_km2 := round(km2_1944 - km2_1929, 2)]
print(T1); fwrite(T1, file.path(O, "zoning_1929_vs_1944.csv"))
f44 <- file.path(O, "zoning_1944.geojson"); if (file.exists(f44)) file.remove(f44); st_write(st_transform(Z44, 4326), f44, quiet = TRUE)
# ---- the accepted changes
key <- function(d) paste(d$col, d$row)
m <- merge(c29[, .(col, row, px_x0, px_y0, px_x1, px_y1, z29 = zone)], c44[, .(col, row, px_x0, px_y0, px_x1, px_y1, z44 = zone)], by = c("col", "row", "px_x0", "px_y0", "px_x1", "px_y1"), all = TRUE)
m[is.na(z29), z29 := "residence or business"]; m[is.na(z44), z44 := "residence or business"]
ch <- m[z29 != z44]
rv <- fread(file.path(R0, "changes_1944_review.csv"))[accept == 1]
ch[, change := paste(z29, "->", z44)]
CH <- st_sf(ch[, .(change)], geometry = cellpoly(ch)); CH <- aggregate(CH, by = list(change = CH$change), FUN = function(x) x[1])[, "change"]
CH$km2 <- round(as.numeric(st_area(CH)) / 1e6, 3)
fc <- file.path(O, "zoning_1929_1944_change.geojson"); if (file.exists(fc)) file.remove(fc); st_write(st_transform(CH, 4326), fc, quiet = TRUE)
print(st_drop_geometry(CH))
# ---- by HOLC grade
H <- st_make_valid(st_transform(st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE), UTM))
H <- H[H$grade %in% c("A", "B", "C", "D"), "grade"]
by_grade <- function(Z) { it <- suppressWarnings(st_intersection(Z[, c("year", "zone")], H)); data.table(year = it$year, zone = it$zone, grade = it$grade, km2 = as.numeric(st_area(it)) / 1e6) }
T2 <- rbind(by_grade(Z29), by_grade(Z44))[, cls := ifelse(grepl("Industrial", zone), "industrial", "commercial")][, .(km2 = round(sum(km2), 2)), by = .(grade, cls, year)]
T2 <- dcast(T2, grade + cls ~ year, value.var = "km2", fill = 0)
# denominator: the grade's land on both sheets (the 1929 scan's extent less the cells the 1944 sheet does not cover), as in holc_zoning_by_grade.csv
EXT <- st_sfc(st_polygon(list(rbind(P(0, 0), P(11849, 0), P(11849, 12000), P(0, 12000), P(0, 0)))), crs = UTM)
offp <- fread(file.path(R0, "cells_off_1944_sheet.csv"))[, `:=`(px_x0 = col * 32, px_y0 = row * 32, px_x1 = pmin((col + 1) * 32, 11849), px_y1 = pmin((row + 1) * 32, 12000))]
if (nrow(offp)) EXT <- st_difference(EXT, st_union(cellpoly(offp)))
HE <- suppressWarnings(st_intersection(H, EXT))
ga <- data.table(grade = HE$grade, km2 = as.numeric(st_area(HE)) / 1e6)[, .(grade_km2 = sum(km2)), by = grade]
T2 <- merge(T2, ga, by = "grade")[, `:=`(pct_1929 = round(100 * `1929` / grade_km2, 1), pct_1944 = round(100 * `1944` / grade_km2, 1))]
setnames(T2, c("1929", "1944"), c("km2_1929", "km2_1944")); T2[, grade_km2 := round(grade_km2, 2)]
print(T2); fwrite(T2, file.path(O, "zoning_change_by_holc_grade.csv"))
cell_km2 <- as.numeric(st_area(cellpoly(c29[1]))) / 1e6
# ---- one row per accepted change, with its HOLC grade
# nearest avenue and street to each change (TIGER/Line 2023 address features for Denver County, already used by the geocoder)
RD <- st_transform(st_read("work/tiger/tl_2023_08031_addrfeat.shp", quiet = TRUE)[, "FULLNAME"], UTM); RD <- RD[!is.na(RD$FULLNAME), ]
near <- function(pt) { cand <- RD[lengths(st_intersects(RD, st_buffer(pt, 400))) > 0, ]; d <- as.numeric(st_distance(pt, cand)); nm <- unique(cand$FULLNAME[order(d)])
  a <- nm[grepl(" (Ave|Pl|Pkwy|Blvd)$", nm)][1]; s2 <- nm[grepl(" (St|Ct|Way|Dr)$", nm)][1]; paste(na.omit(c(a, s2)), collapse = " & ") }
rows <- rbindlist(lapply(seq_len(nrow(rv)), function(i) { r <- rv[i]
  pt <- st_sfc(st_point(P(mean(c(r$col0, r$col1 + 1)) * 32, mean(c(r$row0, r$row1 + 1)) * 32)), crs = UTM)
  gr <- H$grade[lengths(st_intersects(H, pt)) > 0]; ll <- st_coordinates(st_transform(pt, 4326))
  data.table(id = r$id, cells = r$cells, km2 = round(r$cells * cell_km2, 3), from_1929 = r$zone_1929_majority, to_1944 = ifelse(r$zone_1944 == "none", "residence or business", r$zone_1944),
             holc_grade = if (length(gr)) gr[1] else "ungraded", near = near(pt), lon = round(ll[1], 5), lat = round(ll[2], 5), note = r$note) }))
# the same redrawn area can be found twice (as "industrial removed" and "commercial added"): keep one row per area
bb <- rv[, .(id, row0, row1, col0, col1)]; ov <- function(a, b) { w <- max(0, min(a$col1, b$col1) - max(a$col0, b$col0) + 1); h <- max(0, min(a$row1, b$row1) - max(a$row0, b$row0) + 1)
  w * h / min((a$col1 - a$col0 + 1) * (a$row1 - a$row0 + 1), (b$col1 - b$col0 + 1) * (b$row1 - b$row0 + 1)) }
drop <- c(); for (i in seq_len(nrow(rv))) for (j in seq_len(nrow(rv))) if (i < j && rv$zone_1944[i] == rv$zone_1944[j] && ov(bb[i], bb[j]) > 0.8) drop <- c(drop, if (rv$cells[i] >= rv$cells[j]) rv$id[j] else rv$id[i])
rows <- rows[!id %in% drop]
print(rows[, .(id, cells, from_1929, to_1944, holc_grade, near)]); fwrite(rows, file.path(O, "zoning_changes_1944.csv"))
file.copy(file.path(O, c("zoning_1944.geojson", "zoning_1929_1944_change.geojson", "zoning_1929_vs_1944.csv", "zoning_change_by_holc_grade.csv", "zoning_changes_1944.csv")), A, overwrite = TRUE)
