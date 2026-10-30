# Denver's industrial zone districts on the zone map of 1 July 1955
#   Rscript R/zoning_1955.R      (after pipeline/zoning/classify_zoning_1955.py; then Rscript R/zoning_over_time.R)
# Source: "Zone map, City and County of Denver", prepared by the Department of Zoning Administration, July 1, 1955 (History Colorado,
# Stephen H. Hart Research Center, rG4314 .D4G44 1955 .D4; credit: History Colorado-Denver, Colorado). The scan is licensed for this
# publication only and is not in the repository; the classified cells (data/raw/zoning_1955/zone_cells_1955.csv) are.
# The map is the first after the 1925 ordinance's Building Zone Map (1929, 1944 revisions) and shows the I-0, I-1 and I-2 industrial
# districts of the zoning code in force in 1955; only I-1 and I-2 districts appear. Cells come from the texture classifier in
# pipeline/zoning/classify_zoning_1955.py (accuracy on 60 random cells near industrial land: 58 correct).
# Placement: 23 street intersections read off the scan (data/raw/zoning_1955/gcps_1955.csv), their positions from TIGER/Line 2023
# address features (UTM 13N); a second-order polynomial (scan pixels -> UTM) fits them with RMSE about 13 m (leave-one-out about 17 m).
# Outputs (data/results/zoning_1955/, copies in app/data): gcp_fit_1955.csv (residuals, affine and polynomial), zoning_1955.geojson
# (I-1 and I-2 districts, dissolved), zoning_1955_km2.csv.
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; R0 <- "data/raw/zoning_1955"; O <- "data/results/zoning_1955"; A <- "app/data"; CELL <- 16
dir.create(O, showWarnings = FALSE, recursive = TRUE)
g <- fread(file.path(R0, "gcps_1955.csv"))
fit <- function(d) list(x = lm(X ~ px_x + px_y + I(px_x^2) + I(px_x * px_y) + I(px_y^2), d), y = lm(Y ~ px_x + px_y + I(px_x^2) + I(px_x * px_y) + I(px_y^2), d))
F2 <- fit(g); fa <- list(x = lm(X ~ px_x + px_y, g), y = lm(Y ~ px_x + px_y, g))
res <- function(f, d) sqrt((predict(f$x, d) - d$X)^2 + (predict(f$y, d) - d$Y)^2)
loo <- vapply(seq_len(nrow(g)), function(i) res(fit(g[-i]), g[i]), 0)
G <- g[, .(px_x, px_y, street1, street2, note, X, Y, residual_affine_m = round(res(fa, g), 1), residual_poly2_m = round(res(F2, g), 1), loo_poly2_m = round(loo, 1))]
fwrite(G, file.path(O, "gcp_fit_1955.csv"))
message(sprintf("control points: %d; RMSE affine %.1f m, polynomial %.1f m, leave-one-out %.1f m", nrow(g), sqrt(mean(G$residual_affine_m^2)), sqrt(mean(G$residual_poly2_m^2)), sqrt(mean(loo^2))))
P <- function(px, py) { d <- data.frame(px_x = px, px_y = py); cbind(predict(F2$x, d), predict(F2$y, d)) }
cells <- fread(file.path(R0, "zone_cells_1955.csv"))
rect <- function(r) { x0 <- r$col0 * CELL; x1 <- (r$col1 + 1) * CELL; y0 <- r$row * CELL; y1 <- (r$row + 1) * CELL
  xs <- c(seq(x0, x1, length.out = max(2, r$col1 - r$col0 + 2)), rep(x1, 2), seq(x1, x0, length.out = max(2, r$col1 - r$col0 + 2)), x0)
  ys <- c(rep(y0, max(2, r$col1 - r$col0 + 2)), y0, y1, rep(y1, max(2, r$col1 - r$col0 + 2)), y0)
  st_polygon(list(P(xs, ys))) }
pg <- st_sfc(lapply(seq_len(nrow(cells)), function(i) rect(cells[i])), crs = UTM)
Z <- st_sf(year = 1955, zone = sort(unique(cells$zone)), geometry = do.call(c, lapply(sort(unique(cells$zone)), function(z) st_make_valid(st_union(st_buffer(pg[cells$zone == z], 0.5))))))
Z$district <- ifelse(Z$zone == "I-1", "I-1 general industrial", "I-2 heavy industrial")
Z$km2 <- round(as.numeric(st_area(Z)) / 1e6, 2); print(st_drop_geometry(Z))
fwrite(as.data.table(st_drop_geometry(Z))[, .(zone, district, km2)], file.path(O, "zoning_1955_km2.csv"))
f <- file.path(O, "zoning_1955.geojson"); if (file.exists(f)) file.remove(f)
st_write(st_transform(st_simplify(Z, dTolerance = 3, preserveTopology = TRUE), 4326), f, quiet = TRUE)
file.copy(list.files(O, "\\.(csv|geojson)$", full.names = TRUE), A, overwrite = TRUE)
