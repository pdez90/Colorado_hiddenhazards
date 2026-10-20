# Land actually in industrial use, 1937-1997: the USGS historical land-use maps of the northern Front Range.
#   Rscript R/landuse_1937_1997.R     (after R/zoning_over_time.R; place the four rasters in work/usgs_landuse/north/)
# Source: Drummond, M.A., Stier, M.P., Diffendorfer, J.E. (2019) Data release for the Historical land use and land cover for assessing the
# northern Colorado Front Range urban landscape. U.S. Geological Survey, https://doi.org/10.5066/P995RGC9 (public domain). 1 m rasters for
# 1937, 1957, 1977 and 1997, interpreted by hand from aerial photographs and historical maps (minimum mapping unit about 1 ha), 37-46
# classes. Only the "north" rasters (zip 1937to1997_north_front_range_tifs.zip, unzipped into work/usgs_landuse/north/) carry the detailed
# classes; the "full extent" set has 8 broad classes without industry. The north rasters end at about latitude 39.62, so a sliver of
# far-south Denver is not covered: shares are computed on mapped land only, and the covered share of each tract is reported. Used for Denver by Ibsen et al. (2025, PLoS ONE 20: e0317988) to compare HOLC grades.
# What this adds: what was on the ground, as opposed to what the zoning allowed (1929, 1944, today) or where the directories placed a firm.
# Classes are grouped: industrial (light, heavy, petrochemical refinery, commercial/light industry), waste and extraction (landfill,
# quarries, gravel pits), transportation (ground transportation, airports; includes the freeways), commercial (retail, office, mixed urban),
# residential single family, residential multifamily, institutional (schools, institutions, cemeteries, utilities), and open land
# (agriculture, parks, golf, water, natural cover, bare).
# The 1 m rasters are cropped to the study area, grouped, and aggregated to 10 m cells (majority class) for all calculations and to
# 20 m for the site's maps.
# Outputs (data/results/landuse/, copies in app/data):
#   landuse_by_year.csv              km2 and % of covered land by group, study area and the land mapped in 1929/1944
#   landuse_by_holc_grade.csv        % of each HOLC grade by group and year (compare Ibsen et al. 2025, Table 1)
#   landuse_vs_zoning.csv            1929 industrial zoning against industrial use in 1937, 1957, 1977, 1997
#   landuse_sites.csv                share of hazardous sites on industrial land (within 30 m) in each year, by regulatory status
#   landuse_site_transitions.csv     land use under the 1965-92 sites in 1977 and 1997
#   landuse_tracts.csv               tract industrial-use share by year; landuse_tract_paths.csv composition by industrial path 1957 -> 1997
#   landuse_<year>_20m.tif           grouped classes for the maps (app/data)
suppressPackageStartupMessages({ library(terra); library(sf); library(data.table) })
sf_use_s2(FALSE); terraOptions(memfrac = 0.5, progress = 0); UTM <- 26913
O <- "data/results/landuse"; A <- "app/data"; W <- "work/usgs_landuse/north"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
YRS <- c(1937, 1957, 1977, 1997)
GRP <- c("Industrial", "Waste and extraction", "Transportation", "Commercial", "Residential, single family", "Residential, multifamily", "Institutional", "Open land")
group_of <- function(x) { x <- tolower(x); fcase(
  grepl("industr|refiner", x), 1L, grepl("landfill|quarr|strip ?mine|gravel", x), 2L, grepl("transport|airport|ariport|railroad", x), 3L,
  grepl("retail|office|mixed urban|commercial", x), 4L, grepl("single family", x), 5L, grepl("multi.?family|mobile", x), 6L,
  grepl("institution|school|cemetery|communication|utilit", x), 7L, !is.na(x), 8L, default = NA_integer_) }
# ---------------------------------------------------------------- geographies
tr <- st_transform(st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE), UTM); tr$core <- as.logical(tr$core) %in% TRUE
STUDY <- st_union(st_make_valid(tr[tr$core | substr(tr$GEOID, 1, 5) == "08031", ]))
DEN <- st_union(st_make_valid(tr[substr(tr$GEOID, 1, 5) == "08031", ]))
# ---------------------------------------------------------------- rasters: crop, group, aggregate
ext_s <- ext(vect(st_buffer(STUDY, 200)))
R10 <- list(); CLS <- list(); CACHE <- "work/usgs_landuse/landuse_groups_10m.tif"
if (file.exists(CACHE)) { S10c <- rast(CACHE); for (k in seq_along(YRS)) R10[[as.character(YRS[k])]] <- S10c[[k]] }
for (y in YRS) { if (!is.null(R10[[as.character(y)]])) next
  r <- rast(file.path(W, sprintf("%d_lulc_front_range_north.tif", y))); r <- crop(r, ext_s)
  vat <- as.data.table(foreign::read.dbf(file.path(W, sprintf("%d_lulc_front_range_north.tif.vat.dbf", y))))[, .(Value, Class_Name = as.character(Class_Name))]
  vat[Class_Name == "", Class_Name := NA]; vat[, g := group_of(Class_Name)]; CLS[[as.character(y)]] <- vat[!is.na(Class_Name), .(year = y, Value, Class_Name, group = GRP[g])]
  levels(r) <- NULL; g <- classify(r, as.matrix(vat[, .(Value, g)]), others = NA)
  R10[[as.character(y)]] <- aggregate(g, fact = 10, fun = "modal", na.rm = TRUE)
  message(y, ": cropped and aggregated") }
if (length(CLS)) fwrite(rbindlist(CLS)[, .N, by = .(year, Class_Name, group)][order(year, group, Class_Name)][, N := NULL], file.path(O, "landuse_class_groups.csv"))
S10 <- rast(R10); names(S10) <- paste0("y", YRS); cell_km2 <- prod(res(S10)) / 1e6
if (!file.exists(CACHE)) writeRaster(S10, CACHE, datatype = "INT1U", gdal = c("COMPRESS=DEFLATE"))
for (y in YRS) { a <- aggregate(R10[[as.character(y)]], fact = 2, fun = "modal", na.rm = TRUE); f <- file.path(O, sprintf("landuse_%d_20m.tif", y))
  writeRaster(a, f, overwrite = TRUE, datatype = "INT1U", gdal = c("COMPRESS=DEFLATE")) }
# helper: % by group within a polygon set (one row per polygon id x year)
share_by <- function(polys, id) { v <- vect(polys); m <- terra::extract(S10, v, ID = TRUE)
  d <- melt(as.data.table(m), id.vars = "ID", variable.name = "year", value.name = "g")[, year := as.integer(sub("y", "", year))]
  d[, unit := polys[[id]][ID]]; d[, .(covered_km2 = .N * cell_km2, n = .N), by = .(unit, year, g)][is.na(g), covered_km2 := 0] }   # g is constant within each group, so count rows
# ---------------------------------------------------------------- 1. land by year
g <- fread("data/results/zoning_1929/gcp_fit.csv"); fx <- lm(X ~ px_x + px_y, g); fy <- lm(Y ~ px_x + px_y, g)
P <- function(px, py) cbind(predict(fx, data.frame(px_x = px, px_y = py)), predict(fy, data.frame(px_x = px, px_y = py)))
SHEET <- st_sfc(st_polygon(list(rbind(P(0, 0), P(11849, 0), P(11849, 12000), P(0, 12000), P(0, 0)))), crs = UTM)
COMMON <- st_make_valid(st_intersection(SHEET, DEN))
geos <- st_sf(unit = c("Study area", "Denver County, land on the 1929 zoning map"), geometry = c(STUDY, COMMON))
L <- share_by(geos, "unit")[!is.na(g)][, km2 := covered_km2][, .(km2 = sum(km2)), by = .(unit, year, g)]
L[, pct := 100 * km2 / sum(km2), by = .(unit, year)][, group := factor(GRP[g], GRP)]
R1 <- L[, .(unit, year, group, km2 = round(km2, 2), pct = round(pct, 1))][order(unit, year, group)]
fwrite(R1, file.path(O, "landuse_by_year.csv")); print(dcast(R1[unit == "Study area"], group ~ year, value.var = "pct"))
# ---------------------------------------------------------------- 2. HOLC grades
H <- st_make_valid(st_transform(st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE), UTM)); H <- H[H$grade %in% c("A", "B", "C", "D"), ]
H <- aggregate(H[, "grade"], list(grade = H$grade), function(x) x[1])[, "grade"]
G <- share_by(H, "grade")[!is.na(g)][, .(km2 = sum(covered_km2)), by = .(grade = unit, year, g)][, pct := round(100 * km2 / sum(km2), 1), by = .(grade, year)]
G[, group := factor(GRP[g], GRP)]; R2 <- G[, .(grade, year, group, pct)][order(grade, group, year)]
fwrite(R2, file.path(O, "landuse_by_holc_grade.csv")); print(dcast(R2[group %in% c("Industrial", "Residential, single family", "Transportation")], grade + group ~ year, value.var = "pct"))
# ---------------------------------------------------------------- 3. zoning against use
Z29 <- st_make_valid(st_transform(st_read(file.path(A, "zoning_1929.geojson"), quiet = TRUE), UTM))
ZI <- st_sf(unit = "1929 industrial district", geometry = st_union(Z29[grepl("Industrial", Z29$zone), ]))
ZC <- st_sf(unit = "1929 commercial district", geometry = st_union(Z29[!grepl("Industrial", Z29$zone), ]))
ZR <- st_sf(unit = "rest of the land on the 1929 map", geometry = st_difference(COMMON, st_union(Z29)))
zz <- rbind(ZI, ZC, ZR); Zs <- share_by(zz, "unit")[!is.na(g)][, .(km2 = sum(covered_km2)), by = .(unit, year, g)]
Zs[, pct_in_use := round(100 * km2 / sum(km2), 1), by = .(unit, year)]
R3a <- Zs[g == 1, .(zoning = unit, year, industrial_use_km2 = round(km2, 2), pct_of_zone_in_industrial_use = pct_in_use)]
ind37 <- Zs[g == 1, .(km2 = sum(km2)), by = .(unit, year)][, share_of_all_industrial_use := round(100 * km2 / sum(km2), 1), by = year]
R3 <- merge(R3a, ind37[, .(zoning = unit, year, share_of_all_industrial_use)], by = c("zoning", "year"))[order(year, zoning)]
fwrite(R3, file.path(O, "landuse_vs_zoning.csv")); print(R3)
# ---------------------------------------------------------------- 4. sites
ED_OK <- c(1965:1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992)
S <- fread(file.path(A, "sites.csv"), colClasses = c(GEOID = "character"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat)]
S <- S[site_id %in% fread(file.path(A, "site_years.csv"))[year %in% ED_OK, site_id]]
Hs <- fread(file.path(A, "historical_sites.csv"), colClasses = c(GEOID = "character"))[fe_hazard %in% c(TRUE, "True") & precision != "town" & !is.na(lat)]
near_ind <- function(d) { p <- st_transform(st_as_sf(d, coords = c("lon", "lat"), crs = 4326), UTM); p <- p[lengths(st_intersects(p, STUDY)) > 0, ]
  b <- vect(st_buffer(p, 30)); m <- terra::extract(S10, b, fun = function(v, ...) if (all(is.na(v))) NA_real_ else as.numeric(any(v == 1, na.rm = TRUE)), ID = FALSE)
  cen <- terra::extract(S10, vect(p), ID = FALSE); list(p = p, ind = as.data.table(m), at = as.data.table(cen)) }
ss <- near_ind(S); hh <- near_ind(Hs)
status <- ifelse(ss$p$radar == "Not on any list", "on no current inventory", "on a current inventory")
R4 <- rbind(
  rbindlist(lapply(YRS, function(y) data.table(series = "Hazardous-sector manufacturers 1965-1992", status = c("all", "on no current inventory", "on a current inventory"), year = y,
    sites = c(sum(!is.na(ss$ind[[paste0("y", y)]])), sum(!is.na(ss$ind[[paste0("y", y)]]) & status == "on no current inventory"), sum(!is.na(ss$ind[[paste0("y", y)]]) & status == "on a current inventory")),
    pct_on_industrial_land = round(100 * c(mean(ss$ind[[paste0("y", y)]], na.rm = TRUE), mean(ss$ind[[paste0("y", y)]][status == "on no current inventory"], na.rm = TRUE), mean(ss$ind[[paste0("y", y)]][status == "on a current inventory"], na.rm = TRUE)), 1)))),
  rbindlist(lapply(YRS, function(y) data.table(series = "Hazardous trades before 1960 (street level)", status = "all", year = y, sites = sum(!is.na(hh$ind[[paste0("y", y)]])),
    pct_on_industrial_land = round(100 * mean(hh$ind[[paste0("y", y)]], na.rm = TRUE), 1)))))
fwrite(R4, file.path(O, "landuse_sites.csv")); print(R4)
tt <- data.table(u77 = GRP[ss$at$y1977], u97 = GRP[ss$at$y1997])[!is.na(u77) & !is.na(u97)]
R5 <- tt[, .N, by = .(land_use_1977 = u77, land_use_1997 = u97)][, pct_of_1977_group := round(100 * N / sum(N), 1), by = land_use_1977][order(land_use_1977, -N)]
fwrite(R5, file.path(O, "landuse_site_transitions.csv")); print(R5[land_use_1977 == "Industrial"])
# ---------------------------------------------------------------- 5. tracts
core <- tr[tr$core, "GEOID"]
Tt <- share_by(core, "GEOID")
TT <- Tt[, .(covered = sum(covered_km2[!is.na(g)]), all = sum(n) * cell_km2, ind = sum(covered_km2[g %in% 1])), by = .(GEOID = unit, year)][, `:=`(cover = covered / all, ind_share = ind / covered)]
fwrite(TT[, .(GEOID, year, covered_share = round(cover, 3), industrial_use_share = round(ind_share, 4))], file.path(O, "landuse_tracts.csv"))
w <- dcast(TT[cover >= 0.9], GEOID ~ year, value.var = "ind_share"); w <- w[complete.cases(w)]
w[, path := factor(fcase(`1957` >= 0.1 & `1997` >= 0.1, "Industrial land in 1957 and 1997", `1957` >= 0.1, "Industrial in 1957, not 1997", `1997` >= 0.1, "Industrial by 1997, not 1957", default = "Little industrial land"),
                   levels = c("Industrial land in 1957 and 1997", "Industrial in 1957, not 1997", "Industrial by 1997, not 1957", "Little industrial land"))]
Pn <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character"))[census %in% c(1960, 1980, 2000, 2020) & !is.na(pop) & pop >= 200]
M <- merge(Pn, w[, .(GEOID, path)], by = "GEOID"); wm <- function(v, x) round(weighted.mean(v, x, na.rm = TRUE), 1)
R6 <- M[, .(tracts = uniqueN(GEOID), residents = sum(pop), pct_hispanic = wm(p_hisp, pop), pct_black = wm(p_black, pop), pct_white = wm(p_white, pop), pct_poverty = wm(p_pov, pop), pct_owner_occupied = wm(p_owner, pop)), by = .(path, census)][order(path, census)]
fwrite(R6, file.path(O, "landuse_tract_paths.csv")); print(R6); print(w[, .N, by = path])
file.copy(list.files(O, "\\.(csv|tif)$", full.names = TRUE), A, overwrite = TRUE)
