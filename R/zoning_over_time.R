# Denver zoning over time, 1929-today: every zoning map available in digital form, on one geography and one set of categories.
#   Rscript R/zoning_over_time.R   (after R/zoning_1925.R, R/zoning_1944.R, R/fetch_zoning_city.R; needs the 2023 layer in work/zoning_2023/)
# Maps:
#   1929   1925 ordinance as amended to 1 Jan 1929 (DPL scan; R/zoning_1925.R). Only industrial and commercial districts were classified.
#   1944   the same map as amended to 1 Apr 1944 (DPL scan; R/zoning_1944.R).
#   1955   zone map of 1 Jul 1955, Department of Zoning Administration (History Colorado scan; R/zoning_1955.R). Only the industrial
#          districts (I-1, I-2) were classified.
#   2023   Denver-metro zoning of 3 Oct 2023, C. Makarewicz (CU Denver) for the National Zoning Atlas, harmonised categories (R/zoning_2023.R).
#   today  City and County of Denver official zoning (CCD_Zoning layer 27, downloaded by R/fetch_zoning_city.R); every district carries
#          the year of the ordinance that last zoned it (ORD_YEAR) and the code it falls under (2010 Denver Zoning Code, or the 1956 code,
#          "Former Chapter 59", where land was never remapped).
# No citywide map between 1955 and 2010 has been digitised (DPL holds zoning maps and the 1925-69 Board of Adjustment records in print
# only), so the series has a gap between 1955 and 2023.
# Categories: industrial (housing not allowed: 1925 Industrial A/B; today I-A, I-B and the 1956-code I-0/I-1/I-2; NZA "Industrial");
#   industrial mixed use (Denver's I-MX districts, which allow housing; 2010 onward); commercial (1925 Commercial district; today and 2023
#   commercial and mixed-use districts that allow housing: in the city layer every "Commercial Mixed Use" district does; in the 2023 NZA
#   layer the MixedUse* categories); commercial (housing not allowed: NZA GenZone2 "Commercial", 2023 only, as in R/zoning_2023.R; kept out
#   of the housing-allowed share); residential; open space, civic and other; PUD (planned unit developments, custom rules; city layer
#   only). For 1929 and 1944 everything outside the industrial and commercial districts is "residence or business".
# Geography: (a) "land mapped in 1929 and 1944": the City and County of Denver within both historical map sheets (used whenever 1929 or 1944
#   enters a comparison); (b) the study area (Denver plus the 147 tracts within 10 km of downtown) for 2023; (c) Denver County for today.
# Outputs (data/results/zoning_over_time/; copies in app/data):
#   zoning_land_by_year.csv            km2 and % of each category, each year, on geography (a)
#   zoning_by_holc_grade_years.csv     % of each HOLC grade zoned industrial (and industrial incl. I-MX) in each year, geography (a)
#   zoning_1929_industrial_fate.csv    what the 1929 industrial land is zoned today, and when the ordinance that last zoned it passed
#   zoning_sites_by_year.csv           share of hazardous sites standing in an industrial district in each year
#   zoning_tract_paths.csv             the 147 tracts by industrial zoning in 1929 and today, with their composition 1970-2020
#   zoning_today_categories.geojson, zoning_2023_categories.geojson   category polygons (dissolved) for the site's maps
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; O <- "data/results/zoning_over_time"; A <- "app/data"; R0 <- "data/raw/zoning_1929"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
CATS <- c("Industrial", "Industrial mixed use", "Commercial or mixed use", "Commercial (housing not allowed)", "Residential", "PUD (custom district)", "Open space, civic, other", "Residence or business (1929, 1944)", "Other districts (1955)")
# ---------------------------------------------------------------- geographies
tr <- st_transform(st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE), UTM); tr$core <- as.logical(tr$core) %in% TRUE
DEN <- st_union(st_make_valid(tr[substr(tr$GEOID, 1, 5) == "08031", ]))
STUDY <- st_union(st_make_valid(tr[tr$core | substr(tr$GEOID, 1, 5) == "08031", ]))
g <- fread("data/results/zoning_1929/gcp_fit.csv"); fx <- lm(X ~ px_x + px_y, g); fy <- lm(Y ~ px_x + px_y, g)
P <- function(px, py) cbind(predict(fx, data.frame(px_x = px, px_y = py)), predict(fy, data.frame(px_x = px, px_y = py)))
SHEET <- st_sfc(st_polygon(list(rbind(P(0, 0), P(11849, 0), P(11849, 12000), P(0, 12000), P(0, 0)))), crs = UTM)
off <- fread(file.path(R0, "cells_off_1944_sheet.csv"))
if (nrow(off)) { op <- st_sfc(lapply(seq_len(nrow(off)), function(i) { c0 <- off$col[i] * 32; r0 <- off$row[i] * 32; c1 <- min(c0 + 32, 11849); r1 <- min(r0 + 32, 12000)
  st_polygon(list(rbind(P(c0, r0), P(c1, r0), P(c1, r1), P(c0, r1), P(c0, r0)))) }), crs = UTM); SHEET <- st_difference(SHEET, st_union(op)) }
COMMON <- st_make_valid(st_intersection(SHEET, DEN)); common_km2 <- as.numeric(st_area(COMMON)) / 1e6
message(sprintf("Land mapped in 1929 and 1944 within Denver County: %.1f km2 (of %.1f)", common_km2, as.numeric(st_area(DEN)) / 1e6))
# ---------------------------------------------------------------- the four maps as category polygons
hist_cat <- function(f, yr) { z <- st_make_valid(st_transform(st_read(f, quiet = TRUE), UTM))
  z$cat <- ifelse(grepl("Industrial", z$zone), "Industrial", "Commercial or mixed use"); z <- aggregate(z[, "cat"], list(cat = z$cat), function(x) x[1])[, "cat"]; z$year <- yr; z }
Z29 <- hist_cat(file.path(A, "zoning_1929.geojson"), "1929"); Z44 <- hist_cat(file.path(A, "zoning_1944.geojson"), "1944")
Z55 <- st_make_valid(st_transform(st_read(file.path(A, "zoning_1955.geojson"), quiet = TRUE), UTM)); Z55$cat <- "Industrial"
Z55 <- aggregate(Z55[, "cat"], list(cat = Z55$cat), function(x) x[1])[, "cat"]; Z55$year <- "1955"
city <- st_make_valid(st_transform(st_read("work/zoning_city/denver_zoning_current.geojson", quiet = TRUE), UTM))
city_cat <- function(zone_district, zone_dist_type) fcase(grepl("^I-MX", zone_district), "Industrial mixed use", zone_dist_type == "Industrial", "Industrial",
                  zone_dist_type == "Commercial Mixed Use", "Commercial or mixed use", zone_dist_type == "Residential", "Residential",
                  zone_dist_type == "PUD", "PUD (custom district)", default = "Open space, civic, other")
city$cat <- city_cat(city$ZONE_DISTRICT, city$ZONE_DIST_TYPE)
city_date <- tryCatch(readLines("work/zoning_city/download_date.txt")[1], error = function(e) "today")
nza <- st_read("work/zoning_2023/ALL_DenverMSA_10.3.23.shp", quiet = TRUE, wkt_filter = st_as_text(st_transform(st_buffer(STUDY, 100), 32613)))
nza <- st_make_valid(st_transform(nza, UTM))
nza_cat <- function(local_zon, genzone2) fcase(grepl("^I-MX", local_zon), "Industrial mixed use", genzone2 == "Industrial", "Industrial", grepl("^MixedUse", genzone2), "Commercial or mixed use",
                 genzone2 == "Commercial", "Commercial (housing not allowed)",
                 grepl("^Residential|^MobileHome", genzone2), "Residential", default = "Open space, civic, other")
nza$cat <- nza_cat(nza$Local_zon, nza$GenZone2)
diss <- function(z, clip, yr) { z <- suppressWarnings(st_intersection(z[, "cat"], clip)); z <- aggregate(z[, "cat"], list(cat = z$cat), function(x) x[1])[, "cat"]; z$year <- yr; st_make_valid(z) }
ZT <- diss(city, DEN, "today"); Z23 <- diss(nza, STUDY, "2023")
# ---------------------------------------------------------------- 1. land by year on the land mapped in 1929 and 1944
land <- function(z, yr) { it <- suppressWarnings(st_intersection(z, COMMON)); d <- data.table(cat = it$cat, km2 = as.numeric(st_area(it)) / 1e6)[, .(km2 = sum(km2)), by = cat]
  if (yr %in% c("1929", "1944")) d <- rbind(d, data.table(cat = "Residence or business (1929, 1944)", km2 = common_km2 - sum(d$km2)))
  if (yr == "1955") d <- rbind(d, data.table(cat = "Other districts (1955)", km2 = common_km2 - sum(d$km2)))
  d[, `:=`(year = yr, pct = 100 * km2 / common_km2)] }
R1 <- rbindlist(lapply(list(list(Z29, "1929"), list(Z44, "1944"), list(Z55, "1955"), list(Z23, "2023"), list(ZT, "today")), function(x) land(x[[1]], x[[2]])))
R1[, cat := factor(cat, CATS)]; R1 <- R1[order(year, cat)][, `:=`(km2 = round(km2, 2), pct = round(pct, 1))]
fwrite(R1, file.path(O, "zoning_land_by_year.csv")); print(dcast(R1, cat ~ year, value.var = "pct", fill = 0))
# ---------------------------------------------------------------- 2. HOLC grades
H <- st_make_valid(st_transform(st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE), UTM)); H <- H[H$grade %in% c("A", "B", "C", "D"), "grade"]
HC <- suppressWarnings(st_intersection(H, COMMON)); ga <- data.table(grade = HC$grade, km2 = as.numeric(st_area(HC)) / 1e6)[, .(grade_km2 = sum(km2)), by = grade]
R2 <- rbindlist(lapply(list(list(Z29, "1929"), list(Z44, "1944"), list(Z55, "1955"), list(Z23, "2023"), list(ZT, "today")), function(x) {
  it <- suppressWarnings(st_intersection(x[[1]][x[[1]]$cat %in% c("Industrial", "Industrial mixed use"), ], HC))
  data.table(grade = it$grade, cat = it$cat, km2 = as.numeric(st_area(it)) / 1e6)[, .(industrial = sum(km2[cat == "Industrial"]), industrial_mx = sum(km2)), by = grade][, year := x[[2]]] }))
R2 <- merge(CJ(grade = ga$grade, year = c("1929", "1944", "1955", "2023", "today")), R2, by = c("grade", "year"), all.x = TRUE)
for (v in c("industrial", "industrial_mx")) set(R2, which(is.na(R2[[v]])), v, 0)
R2 <- merge(R2, ga, by = "grade")[, `:=`(pct_industrial = round(100 * industrial / grade_km2, 1), pct_industrial_incl_imx = round(100 * industrial_mx / grade_km2, 1))]
R2 <- R2[, .(grade, year, grade_km2 = round(grade_km2, 1), pct_industrial, pct_industrial_incl_imx)][order(grade, year)]
fwrite(R2, file.path(O, "zoning_by_holc_grade_years.csv")); print(dcast(R2, grade ~ year, value.var = "pct_industrial"))
# ---------------------------------------------------------------- 3. what became of the 1929 industrial land, and when
I29 <- st_make_valid(st_intersection(st_union(Z29[Z29$cat == "Industrial", ]), DEN)); i29_km2 <- as.numeric(st_area(I29)) / 1e6
cz <- suppressWarnings(st_intersection(city[, c("cat", "ORD_YEAR", "ZCODE_VERSION")], I29))
F <- data.table(cat = cz$cat, ord = cz$ORD_YEAR, code = cz$ZCODE_VERSION, km2 = as.numeric(st_area(cz)) / 1e6)
F[, when := fcase(code == 1956 & cat == "Industrial", "still under the 1956 code", ord < 1970, "ordinance 1956-1969", ord < 1980, "1970s", ord < 1990, "1980s", ord < 2000, "1990s",
                  ord < 2010, "2000-2009", ord == 2010, "2010 (citywide new code)", ord < 2020, "2011-2019", default = "2020 or later")]
R3a <- F[, .(km2 = round(sum(km2), 2)), by = cat][, pct := round(100 * km2 / sum(km2), 1)][order(-km2)]
R3b <- F[cat != "Industrial", .(km2 = sum(km2)), by = when][, pct_of_rezoned := round(100 * km2 / sum(km2), 1)][, km2 := round(km2, 2)]
R3b <- R3b[order(match(when, c("ordinance 1956-1969", "1970s", "1980s", "1990s", "2000-2009", "2010 (citywide new code)", "2011-2019", "2020 or later")))]
R3 <- rbind(R3a[, .(part = "zoned today", group = cat, km2, pct)], R3b[, .(part = "no longer industrial: year of the ordinance that last zoned it", group = when, km2, pct = pct_of_rezoned)])
R3 <- rbind(data.table(part = "1929 industrial land in Denver County", group = "all", km2 = round(i29_km2, 2), pct = 100), R3)
fwrite(R3, file.path(O, "zoning_1929_industrial_fate.csv")); print(R3)
# ---------------------------------------------------------------- 4. sites
ED_OK <- c(1965:1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992)
S <- fread(file.path(A, "sites.csv"), colClasses = c(GEOID = "character"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat)]
S <- S[site_id %in% fread(file.path(A, "site_years.csv"))[year %in% ED_OK, site_id]]
Hs <- fread(file.path(A, "historical_sites.csv"), colClasses = c(GEOID = "character"))[fe_hazard %in% c(TRUE, "True") & precision != "town" & !is.na(lat)]
pts <- function(d, lab) { p <- st_transform(st_as_sf(d, coords = c("lon", "lat"), crs = 4326), UTM); p <- p[lengths(st_intersects(p, COMMON)) > 0, ]; p$series <- lab; p[, "series"] }
SP <- rbind(pts(S, "Hazardous-sector manufacturers 1965-1992"), pts(Hs, "Hazardous trades before 1960 (street level)"))
zon_at <- function(z) { j <- st_join(SP[, "series"], z[, "cat"], left = TRUE); j <- j[!duplicated(attr(j, "row.names") %/% 1), ]; j$cat }
R4 <- rbindlist(lapply(list(list(Z29, "1929"), list(Z44, "1944"), list(Z55, "1955"), list(Z23, "2023"), list(ZT, "today")), function(x) {
  k <- st_intersects(SP, x[[1]]); cat <- vapply(k, function(i) if (length(i)) x[[1]]$cat[i[1]] else NA_character_, "")
  data.table(series = SP$series, cat = cat)[, .(sites = .N, pct_industrial = round(100 * mean(cat %in% "Industrial"), 1), pct_industrial_incl_imx = round(100 * mean(cat %in% c("Industrial", "Industrial mixed use")), 1),
                                                pct_housing_allowed = if (x[[2]] %in% c("1929", "1944", "1955")) NA_real_ else round(100 * mean(cat %in% c("Industrial mixed use", "Commercial or mixed use", "Residential")), 1)), by = series][, year := x[[2]]] }))
fwrite(R4, file.path(O, "zoning_sites_by_year.csv")); print(R4)
# ---------------------------------------------------------------- 5. tracts: industrial in 1929 and today
core <- tr[tr$core, "GEOID"]; core$km2 <- as.numeric(st_area(core)) / 1e6
on <- suppressWarnings(st_intersection(core, COMMON)); onsh <- data.table(GEOID = on$GEOID, on_km2 = as.numeric(st_area(on)) / 1e6)[, .(on_km2 = sum(on_km2)), by = GEOID]
sh <- function(z) { it <- suppressWarnings(st_intersection(core, z[z$cat == "Industrial", ])); data.table(GEOID = it$GEOID, a = as.numeric(st_area(it)) / 1e6)[, .(a = sum(a)), by = GEOID] }
T <- merge(as.data.table(st_drop_geometry(core)), onsh, by = "GEOID", all.x = TRUE)
T <- merge(T, sh(Z29)[, .(GEOID, ind29 = a)], by = "GEOID", all.x = TRUE); T <- merge(T, sh(ZT)[, .(GEOID, indnow = a)], by = "GEOID", all.x = TRUE)
for (v in c("on_km2", "ind29", "indnow")) set(T, which(is.na(T[[v]])), v, 0)
T <- T[on_km2 / km2 >= 0.5]   # tracts at least half on both historical sheets and in Denver County
T[, `:=`(s29 = ind29 / km2, snow = indnow / km2)]
T[, path := factor(fcase(s29 >= 0.2 & snow >= 0.2, "Industrial in 1929 and today", s29 >= 0.2, "Industrial in 1929, not today", snow >= 0.2, "Industrial today, not in 1929", default = "Neither"),
                   levels = c("Industrial in 1929 and today", "Industrial in 1929, not today", "Industrial today, not in 1929", "Neither"))]
Pn <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character"))[census %in% c(1970, 1990, 2020) & !is.na(pop) & pop >= 200]
M <- merge(Pn, T[, .(GEOID, path)], by = "GEOID")
wm <- function(v, w) round(weighted.mean(v, w, na.rm = TRUE), 1)
R5 <- M[, .(tracts = uniqueN(GEOID), residents = sum(pop), pct_hispanic = wm(p_hisp, pop), pct_black = wm(p_black, pop), pct_white = wm(p_white, pop), pct_poverty = wm(p_pov, pop),
            pct_owner_occupied = wm(p_owner, pop)), by = .(path, census)][order(path, census)]
fwrite(R5, file.path(O, "zoning_tract_paths.csv")); print(R5); print(T[, .N, by = path])
# ---------------------------------------------------------------- map layers and copies
wr <- function(z, f) { z <- st_transform(st_simplify(z, dTolerance = 4, preserveTopology = TRUE), 4326); z$km2 <- round(as.numeric(st_area(st_transform(z, UTM))) / 1e6, 2)
  if (file.exists(f)) file.remove(f); st_write(z, f, quiet = TRUE) }
wr(ZT, file.path(O, "zoning_today_categories.geojson")); wr(Z23, file.path(O, "zoning_2023_categories.geojson"))
writeLines(c(sprintf("city zoning downloaded %s", city_date), sprintf("land mapped in 1929 and 1944 within Denver County: %.1f km2", common_km2)), file.path(O, "zoning_over_time_notes.txt"))
file.copy(list.files(O, "\\.(csv|geojson|txt)$", full.names = TRUE), A, overwrite = TRUE)
