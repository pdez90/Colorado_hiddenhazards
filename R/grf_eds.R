# Denver enumeration-district boundaries 1880-1940, reconstructed from Brown University's Geographic Reference Files (R port of
# pipeline/historical/grf_eds.py; same method, same thresholds).
#
#   Rscript R/grf_eds.R [years]          e.g.  Rscript R/grf_eds.R 1900 1910
#
# Sources (in work/census/brown/, downloaded from Brown's Urban Transition project under its conditions of use, not redistributed):
#   grf/DenverCO/DenverCO_<year>.csv  one row per person 1900-1940 with the household's street, house number and ED (no coordinates)
#   singleunit1880 / multiunit1880    Brown's own geocoded 1880 buildings (for 1880 the same tessellation is run on their points)
# and work/census/denver_ed_1880_1940.csv (IPUMS full-count ED aggregates from R/fetch_ipums_fullcount.R).
# Method
#   1. every distinct address is geocoded with the project's offline TIGER/Line geocoder (R/geocode_tiger.R; Denver's modern house
#      numbering dates from 1887, so 1900+ addresses resolve on today's grid; a few renamed streets are translated);
#      only street-level geocodes are kept (range interpolation, incl. OCR-tolerant street matches; no ZIP/city centroids);
#   2. stray geocodes are dropped: farther from the ED's person-weighted median centre than max(400 m, 2.5 x the ED's median
#      distance), or with fewer than 30% (person-weighted) of their 10 nearest neighbours in the same ED;
#   3. a Voronoi tessellation of the remaining addresses is dissolved by ED and clipped to the concave hull of all addresses
#      (+120 m); each ED keeps its main body (parts under a quarter of the largest are islands from stray geocodes), and the
#      freed ground goes to the nearest ED so the districts stay space-filling, like census tracts;
#   4. the IPUMS ED totals are attached (ED labels: ENUMDIST mod 100000 for 1900-1930; 1940 SD-ED-suffix -> "225", "250A").
# Output: data/results/denver_eds/denver_eds_<year>.geojson (this project's derived product) and ed_geocoding.csv.
if (!requireNamespace("RANN", quietly = TRUE)) install.packages("RANN")
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; B <- "work/census/brown"; O <- "data/results/denver_eds"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
args <- commandArgs(trailingOnly = TRUE); YEARS <- as.integer(args[grepl("^(1880|19[0-4]0)$", args)]); if (!length(YEARS)) YEARS <- c(1880, 1900, 1910, 1920, 1930, 1940)   # ignores stray shell words (zsh passes "# comments" as arguments)
RENAME <- c(HOLLADAY = "MARKET", MCGAA = "MARKET", BDWY = "BROADWAY", WASH = "WASHINGTON", SANTA = "SANTA FE", PENNA = "PENNSYLVANIA", PENN = "PENNSYLVANIA", CALIF = "CALIFORNIA", COLO = "COLORADO")
KEEP <- "^(fuzzy_)?range_interp"
ip <- fread("work/census/denver_ed_1880_1940.csv")
bf <- function(f) { p <- c(file.path(B, f), file.path(B, basename(f))); p <- p[file.exists(p)]; if (!length(p)) stop("missing ", f); p[1] }

ipums_ed <- function(year) {
  x <- ip[YEAR == year & COUNTYICP == (if (year < 1910) 50 else 310)]   # Denver lay in Arapahoe County (ICP 50) until 1902 and is its own county
  # (ICP 310) from 1910; South Arapahoe (ICP 50 after 1902) reuses ED numbers, so the two must never be pooled by ED label
  if (year == 1940) { e <- sprintf("%07d", x$ENUMDIST); x[, ED := paste0(as.integer(substr(e, 3, 6)), c("0" = "", "1" = "A", "2" = "B", "3" = "C")[substr(e, 7, 7)])]
  } else x[, ED := as.character(ENUMDIST %% 100000)]
  cnt <- setdiff(names(x)[vapply(x, is.numeric, TRUE)], c("YEAR", "COUNTYICP", "ENUMDIST", "denver_city", grep("^(mean_|median_)", names(x), value = TRUE)))
  avg <- grep("^(mean_|median_)", names(x), value = TRUE)
  out <- x[, c(lapply(.SD, function(v) if (all(is.na(v))) NA_real_ else sum(v, na.rm = TRUE)), list(dummy = 0)), by = ED, .SDcols = cnt][, dummy := NULL]
  if (anyDuplicated(out$ED)) stop(year, ": duplicate ED labels after aggregation")
  if (length(avg)) out <- merge(out, x[, lapply(.SD, function(v) if (all(is.na(v))) NA_real_ else weighted.mean(v, pop, na.rm = TRUE)), by = ED, .SDcols = avg], by = "ED")
  out
}

geocode_year <- function(year, g) {
  d <- fread(file.path(B, sprintf("grf/DenverCO/DenverCO_%d.csv", year)), colClasses = "character", select = c("b_ed", "b_hn", "b_stfull", "b_race", "b_hh"))
  d[, num := ifelse(grepl("[0-9]", b_hn), suppressWarnings(as.integer(sub("^[^0-9]*([0-9]+).*$", "\\1", b_hn))), NA_integer_)]
  d <- d[!is.na(num) & !is.na(b_stfull) & b_stfull != "" & !is.na(b_ed) & b_ed != ""]
  d[, addr := paste(num, trimws(gsub("[^A-Z0-9 ]", "", toupper(b_stfull))))]
  A <- d[, .(persons = .N, black = sum(b_race == "2"), ED = names(which.max(table(b_ed))), households = uniqueN(b_hh)), by = addr]
  cache <- sprintf("work/census/grf_geocoded_%d_R.csv", year)
  if (file.exists(cache)) C <- fread(cache, colClasses = c(addr = "character")) else {
    st <- A$addr; for (k in names(RENAME)) st <- gsub(paste0("\\b", k, "\\b"), RENAME[[k]], st)
    C <- geocode_many(g, data.frame(addr = A$addr, street = st, city = "DENVER", zip = ""), "street", "city", "zip")
    C <- as.data.table(C)[, .(addr, lat, lon, q = geo_quality)]; fwrite(C, cache) }
  A <- merge(A, C, by = "addr", all.x = TRUE); A[, ok := grepl(KEEP, q) & !is.na(lat)]
  list(d = d, A = A)
}

ed_polygons <- function(P) {                      # P: sf points (UTM) with ED, persons, black
  xy <- st_coordinates(P); P$x <- xy[, 1]; P$y <- xy[, 2]; dt <- as.data.table(st_drop_geometry(P)); dt[, i := .I]
  dt[, w := pmin(pmax(persons, 1), 50)]
  dt[, `:=`(cx = median(rep(x, w)), cy = median(rep(y, w))), by = ED]; dt[, dd := sqrt((x - cx)^2 + (y - cy)^2)]
  dt[, thr := if (.N >= 5) max(400, 2.5 * median(dd)) else 600, by = ED]; dt <- dt[dd <= thr]
  # neighbourhood smoothing (10 nearest neighbours, person-weighted share in the same ED)
  nn <- RANN::nn2(dt[, .(x, y)], k = min(11, nrow(dt)))$nn.idx[, -1, drop = FALSE]
  agree <- vapply(seq_len(nrow(dt)), function(i) { j <- nn[i, ]; sum(dt$w[j][dt$ED[j] == dt$ED[i]]) / sum(dt$w[j]) }, 0)
  dt <- dt[agree >= 0.3]
  pts <- st_as_sf(dt, coords = c("x", "y"), crs = UTM)
  hull <- st_buffer(st_concave_hull(st_union(pts), ratio = 0.25), 120)
  cells <- st_collection_extract(st_voronoi(st_union(pts), envelope = st_as_sfc(st_bbox(st_buffer(hull, 500)))), "POLYGON")
  cells <- st_sf(geometry = cells); k <- st_intersects(cells, pts); cells$ED <- dt$ED[vapply(k, function(z) if (length(z)) z[1] else NA_integer_, 0L)]
  cells <- cells[!is.na(cells$ED), ]; cells <- st_set_geometry(cells, st_intersection(st_geometry(cells), hull))
  E <- aggregate(cells, by = list(ED = cells$ED), FUN = function(z) z[1])[, "ED"]; E <- st_sf(ED = E$ED, geometry = st_make_valid(st_geometry(E)))
  main_parts <- function(gm) { if (!inherits(gm, "MULTIPOLYGON")) return(gm); parts <- st_cast(st_sfc(gm, crs = UTM), "POLYGON"); a <- as.numeric(st_area(parts)); st_union(parts[a >= 0.25 * max(a)])[[1]] }
  st_geometry(E) <- st_sfc(lapply(st_geometry(E), main_parts), crs = UTM)
  freed <- st_difference(hull, st_union(st_geometry(E)))
  if (length(freed) && !st_is_empty(freed)) { pieces <- st_cast(st_sfc(freed, crs = UTM), "POLYGON"); pieces <- pieces[as.numeric(st_area(pieces)) > 1]
    for (p in pieces) { k <- which.min(as.numeric(st_distance(st_geometry(E), st_sfc(p, crs = UTM)))); st_geometry(E)[k] <- st_union(st_geometry(E)[k], st_sfc(p, crs = UTM)) } }
  st_geometry(E) <- st_make_valid(st_geometry(E))
  stats <- dt[, .(addresses = .N, persons_geocoded = sum(persons), black_geocoded = sum(black)), by = ED]
  E <- merge(E, stats, by = "ED", all.x = TRUE); E$area_km2 <- as.numeric(st_area(E)) / 1e6
  list(E = E, used = nrow(dt))
}

source("R/geocode_tiger.R"); g <- NULL; log <- list()
for (year in YEARS) {
  if (year == 1880) {
    Bld <- do.call(rbind, lapply(c("singleunit", "multiunit"), function(k) st_transform(st_read(bf(sprintf("%s1880/%s1880.shp", k, k)), quiet = TRUE)[, c("Match_addr", "enumdist", "poptotB")], UTM)))
    Bld <- Bld[grepl("Denver, CO", Bld$Match_addr), ]
    P <- st_sf(ED = as.character(as.integer(Bld$enumdist)), persons = ifelse(is.na(Bld$poptotB), 1, Bld$poptotB), black = 0, geometry = st_geometry(Bld)); n_addr <- n_ok <- nrow(P)
  } else {
    if (is.null(g)) g <- tiger_geocoder("work/tiger", "data/geocoder/zip_city.csv", "data/geocoder/zip_centroids.csv")
    r <- geocode_year(year, g); A <- r$A; n_addr <- nrow(A); n_ok <- sum(A$ok)
    message(sprintf("%d: %s persons at %s addresses; %s geocoded at street level (%.1f%% of persons)", year, format(nrow(r$d), big.mark = ","), format(n_addr, big.mark = ","), format(n_ok, big.mark = ","), 100 * sum(A$persons[A$ok]) / sum(A$persons)))
    Ak <- A[ok == TRUE]; P <- st_transform(st_as_sf(Ak[, .(ED, persons, black, lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)
  }
  res <- ed_polygons(P); IE <- ipums_ed(year); E <- merge(res$E, IE, by = "ED", all.x = TRUE); E$year <- year
  ctot <- sum(ip[YEAR == year & COUNTYICP == (if (year < 1910) 50 else 310)]$pop); mtot <- sum(E$pop, na.rm = TRUE)
  message(sprintf("%d: mapped ED population %s of the county's %s (%.1f%%)", year, format(mtot, big.mark = ","), format(ctot, big.mark = ","), 100 * mtot / ctot))
  if (mtot > 1.001 * ctot) stop(year, ": mapped EDs hold more people than the county - ED labels are being pooled")
  f <- file.path(O, sprintf("denver_eds_%d.geojson", year)); if (file.exists(f)) file.remove(f); st_write(st_transform(E, 4326), f, quiet = TRUE)
  message(sprintf("%d: %d ED polygons (%d with IPUMS totals), %s addresses used; median ED area %.2f km2", year, nrow(E), sum(!is.na(E$pop)), format(res$used, big.mark = ","), median(E$area_km2)))
  log[[length(log) + 1]] <- data.table(year = year, addresses = n_addr, geocoded = n_ok, used = res$used, eds = nrow(E), median_area_km2 = round(median(E$area_km2), 3))
}
fwrite(rbindlist(log), file.path(O, "ed_geocoding_R.csv"))
