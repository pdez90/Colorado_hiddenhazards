# Build the app's historical-census and corridor layers (aggregates only) from the analysis outputs.
#   Rscript R/app_census_layers.R            (run from the repository root, after fetch_census.R, ej_panel.R, corridors.R,
#                                             fetch_ipums_fullcount.R and denver_1880.R)
# Writes to app/data/:
#   denver_tracts_2010.geojson        Denver-core 2010 census tracts (simplified) with distance to downtown
#   denver_panel.csv                  tract x census year 1940-2020: population, % Black, % Hispanic, % foreign born, % poverty
#                                     (NHGIS, area-weighted to 2010 tracts) + hazardous / all directory firms active in the
#                                     decade ending in that year and legacy (earlier, no longer listed) hazardous firms
#   ej_panel_models.csv, ej_panel_reverse.csv      the panel-model coefficients (R/ej_panel.R)
#   corridor_cells.csv                500 m cells with any manufacturer 1961-2002: persistence class, first/last edition, sectors
#   corridor_eg.csv, corridor_transitions.csv      Ellison-Glaeser clustering by sector and edition; dominant-sector successions
#   denver_1880_eds.csv               17 Denver enumeration districts of 1880: centroid, population and composition (Brown HGIS
#                                     aggregates + IPUMS full count), hazardous firms 1878-1885 placed inside
#   denver_1880_firms.csv             those firms with coordinates; denver_1880_distance.csv, denver_1880_models.csv
#   denver_city_1880_1940.csv         Denver composition by census year from the IPUMS full count, with ED-level segregation indices
# Brown University's Urban Transition HGIS and the IPUMS full-count files are not redistributed: only ED-level aggregates (17 EDs of
# >1,000 people each) and derived coordinates leave work/.
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; A <- "app/data"; C <- "work/census"
tolonlat <- function(x, y, crs = UTM) { p <- st_transform(st_as_sf(data.frame(x, y), coords = c("x", "y"), crs = crs), 4326); cbind(lon = st_coordinates(p)[, 1], lat = st_coordinates(p)[, 2]) }

# ---------------------------------------------------------------- 1. Denver-core tracts and the 1940-2020 panel
shp10 <- c(Sys.glob(file.path(C, "co_tract_2010/*.shp")), Sys.glob(file.path(C, "*tract_2010*.shp")), Sys.glob(file.path(C, "*tract10*.shp")))
tr <- st_make_valid(st_transform(st_read(shp10[1], quiet = TRUE), UTM))
tr$GEOID <- if (any(grepl("GEOID", names(tr)))) tr[[grep("GEOID", names(tr), value = TRUE)[1]]] else sub("^G(\\d{2})0(\\d{3})0(\\d{6})$", "\\1\\2\\3", tr$GISJOIN)
DEN <- st_sfc(st_point(c(500250, 4399500)), crs = UTM)
tr$dist_km <- round(as.numeric(st_distance(st_centroid(st_geometry(tr)), DEN)) / 1000, 2)
tr <- tr[substr(tr$GEOID, 1, 5) == "08031" | (substr(tr$GEOID, 1, 5) %in% c("08001", "08005", "08059") & tr$dist_km <= 10), c("GEOID", "dist_km")]
tr$area_km2 <- round(as.numeric(st_area(tr)) / 1e6, 3)
message(nrow(tr), " Denver-core tracts")
st_write(st_transform(st_simplify(tr, dTolerance = 15), 4326), file.path(A, "denver_tracts_2010.geojson"), delete_dsn = TRUE, quiet = TRUE)

cen <- fread(file.path(C, "denver_tract_panel.csv"), colClasses = c(GEOID = "character"))[GEOID %in% tr$GEOID]
cen[, `:=`(p_black = pmin(100, 100 * nhblk / pop), p_hisp = pmin(100, 100 * hisp / pop), p_fb = pmin(100, 100 * fb / pop), p_pov = pmin(100, 100 * ppov / pop))]   # area weighting can push a share a hair over 100
cen[pop < 50, c("p_black", "p_hisp", "p_fb", "p_pov") := NA_real_]
# firms active in the decade ending in each census year: 1961-2002 manufacturers' directory (all firms, hazardous flagged) and,
# before 1961, street-level pre-1960 hazardous trades.  2010 and 2020 reuse the last editions (1993-2002) and are labelled so in the app.
sites <- fread(file.path(A, "sites.csv"), colClasses = c(GEOID = "character")); sy <- fread(file.path(A, "site_years.csv"))
firms <- fread(file.path(A, "site_firms.csv"))
pts <- st_transform(st_as_sf(sites[, .(site_id, lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)
w <- st_within(pts, tr); sites$GEOID10 <- tr$GEOID[sapply(w, function(i) if (length(i)) i[1] else NA_integer_)]
fy <- merge(firms[, .(site_id, first_year, last_year, hazardous = as.logical(hazardous))], sites[, .(site_id, GEOID10)], by = "site_id")[!is.na(GEOID10)]
hist <- fread(file.path(A, "historical_sites.csv"), colClasses = c(GEOID = "character"))[precision != "town" & !is.na(lat)]
hp <- st_transform(st_as_sf(hist[, .(hfirm, lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)
w <- st_within(hp, tr); hist$GEOID10 <- tr$GEOID[sapply(w, function(i) if (length(i)) i[1] else NA_integer_)]
hist <- hist[!is.na(GEOID10)]
WIN <- list("1940" = c(1931, 1940), "1950" = c(1941, 1950), "1960" = c(1951, 1960), "1970" = c(1961, 1970), "1980" = c(1971, 1980),
            "1990" = c(1981, 1990), "2000" = c(1991, 2002), "2010" = c(1993, 2002), "2020" = c(1993, 2002))
act <- rbindlist(lapply(names(WIN), function(y) { a <- WIN[[y]]
  if (as.integer(y) <= 1960) { d <- hist[first_year <= a[2] & last_year >= a[1], .(firms_haz = .N, firms_all = NA_integer_), by = .(GEOID = GEOID10)]
  } else d <- fy[first_year <= a[2] & last_year >= a[1], .(firms_haz = sum(hazardous), firms_all = .N), by = .(GEOID = GEOID10)]
  leg <- if (as.integer(y) <= 1960) hist[last_year < a[1], .(legacy_haz = .N), by = .(GEOID = GEOID10)] else
    rbind(hist[, .(GEOID = GEOID10, hazardous = TRUE)], fy[last_year < a[1], .(GEOID = GEOID10, hazardous)])[hazardous == TRUE, .(legacy_haz = .N), by = GEOID]
  merge(merge(data.table(GEOID = tr$GEOID), d, by = "GEOID", all.x = TRUE), leg, by = "GEOID", all.x = TRUE)[, census := as.integer(y)] }))
for (v in c("firms_haz", "firms_all", "legacy_haz")) act[is.na(get(v)) & !(census <= 1960 & v == "firms_all"), (v) := 0L]
pan <- merge(cen[, .(GEOID, census, pop = round(pop), p_black = round(p_black, 1), p_hisp = round(p_hisp, 1), p_fb = round(p_fb, 1), p_pov = round(p_pov, 1))],
             act, by = c("GEOID", "census"), all = TRUE)
pan <- merge(pan, as.data.table(st_drop_geometry(tr)), by = "GEOID")
fwrite(pan[order(GEOID, census)], file.path(A, "denver_panel.csv"))
message("denver_panel.csv: ", nrow(pan), " tract-years; tracts with a census value by year: ", paste(pan[!is.na(pop), .N, by = census][order(census), paste(census, N)], collapse = ", "))
for (f in c("ej_panel_models.csv", "ej_panel_reverse.csv")) if (file.exists(file.path("data/results", f))) file.copy(file.path("data/results", f), file.path(A, f), overwrite = TRUE)

# ---------------------------------------------------------------- 2. corridors
SIC2 <- c("20"="Food","22"="Textiles","23"="Apparel","24"="Lumber & wood","25"="Furniture","26"="Paper","27"="Printing","28"="Chemicals",
          "29"="Petroleum","30"="Rubber & plastics","31"="Leather","32"="Stone, clay & glass","33"="Primary metals","34"="Fabricated metals",
          "35"="Machinery","36"="Electronics","37"="Transportation eq.","38"="Instruments","39"="Misc. manufacturing")
cells <- fread("data/results/corridors/cells_500m.csv", colClasses = c(first_sector = "character", last_sector = "character"))
ij <- do.call(rbind, strsplit(cells$cell, " ")); xy <- tolonlat((as.numeric(ij[, 1]) + 0.5) * 500, (as.numeric(ij[, 2]) + 0.5) * 500)
cells[, `:=`(lon = round(xy[, "lon"], 5), lat = round(xy[, "lat"], 5), first_sector = SIC2[first_sector], last_sector = SIC2[last_sector])]
fwrite(cells[, .(lon, lat, class, first, last, editions, max_n, ever_haz, first_sector, last_sector, n_sectors, pre1960_first, pre1960_firms, metro)], file.path(A, "corridor_cells.csv"))
file.copy("data/results/corridors/ellison_glaeser_by_sector_edition.csv", file.path(A, "corridor_eg.csv"), overwrite = TRUE)
file.copy("data/results/corridors/sector_transitions.csv", file.path(A, "corridor_transitions.csv"), overwrite = TRUE)
message("corridor_cells.csv: ", nrow(cells), " cells")

# ---------------------------------------------------------------- 3. Denver 1880 (Brown HGIS + IPUMS aggregates by ED)
edshp <- file.path(C, "brown/ed1880/ed1880.shp"); R80 <- "data/results/denver_1880"
if (file.exists(edshp) && file.exists(file.path(R80, "ed_composition_vs_firms.csv"))) {
  ed <- st_transform(st_read(edshp, quiet = TRUE), UTM); ed <- ed[grepl("Denver", ed$CityName), ]
  ctr <- st_coordinates(st_centroid(st_geometry(ed))); ll <- tolonlat(ctr[, 1], ctr[, 2])
  E <- data.table(ED = as.integer(ed$ED), lon = round(ll[, "lon"], 5), lat = round(ll[, "lat"], 5), area_km2 = round(as.numeric(st_area(ed)) / 1e6, 3))
  E <- merge(E, fread(file.path(R80, "ed_composition_vs_firms.csv")), by = "ED")
  ip <- if (file.exists(file.path(C, "denver_ed_1880_1940.csv"))) fread(file.path(C, "denver_ed_1880_1940.csv"))[YEAR == 1880 & COUNTYICP == 50] else NULL
  if (!is.null(ip)) { ip[, ED := ENUMDIST %% 1000]
    E <- merge(E, ip[, .(ED, ipums_pop = pop, ipums_pct_black = round(100 * black / pop, 1), ipums_pct_fb = round(100 * fb / pop, 1), ipums_pct_fb_europe = round(100 * fb_europe / pop, 1),
                         ipums_pct_fb_asia = round(100 * fb_asia / pop, 1), ipums_pct_laborers = round(100 * laborers / pop, 1))], by = "ED", all.x = TRUE) }
  fwrite(E[order(ED)], file.path(A, "denver_1880_eds.csv"))
  Fm <- fread(file.path(R80, "firms_1878_1885_placed.csv")); ll <- tolonlat(Fm$x, Fm$y); Fm[, `:=`(lon = round(ll[, "lon"], 5), lat = round(ll[, "lat"], 5), x = NULL, y = NULL)]
  fwrite(Fm, file.path(A, "denver_1880_firms.csv"))
  file.copy(file.path(R80, "residents_by_distance.csv"), file.path(A, "denver_1880_distance.csv"), overwrite = TRUE)
  file.copy(file.path(R80, "person_models.csv"), file.path(A, "denver_1880_models.csv"), overwrite = TRUE)
  message("Denver 1880: ", nrow(E), " EDs, ", nrow(Fm), " placed firms")
} else message("Denver 1880 layer skipped (needs work/census/brown/ed1880 and data/results/denver_1880)")

# ---------------------------------------------------------------- 4. Denver 1880-1940 from the IPUMS full count (city totals + ED segregation)
ipf <- file.path(C, "denver_ed_1880_1940.csv")
if (file.exists(ipf)) {
  ip <- fread(ipf)
  # Denver: IPUMS CITY 1710 where coded; else the County of Denver (ICP 310, from 1902) or Arapahoe County (ICP 50) in 1880 and 1900
  ip <- ip[(if ("denver" %in% names(ip)) denver == TRUE else denver_city > 0.5 | COUNTYICP == 310 | (YEAR < 1910 & COUNTYICP == 50))]
  if (!"laborers" %in% names(ip)) ip[, laborers := NA_integer_]
  dis <- function(a, b) { a <- a[!is.na(a)]; b <- b[!is.na(b)]; if (!sum(a) || !sum(b)) return(NA_real_); round(0.5 * sum(abs(a / sum(a) - b / sum(b))), 3) }
  city <- ip[, .(EDs = .N, pop = sum(pop), pct_black = round(100 * sum(black) / sum(pop), 2), pct_fb = round(100 * sum(fb) / sum(pop), 1),
                 pct_fb_mexico = round(100 * sum(fb_mexico) / sum(pop), 2), pct_fb_europe = round(100 * sum(fb_europe) / sum(pop), 1), pct_fb_asia = round(100 * sum(fb_asia) / sum(pop), 2),
                 pct_hispanic = round(100 * sum(hisp) / sum(pop), 2), pct_foreign_parentage = round(100 * sum(foreign_parentage) / sum(pop), 1),
                 pct_laborers = round(100 * sum(laborers, na.rm = TRUE) / sum(pop), 1),
                 dissim_black = dis(black, pop - black), dissim_fb = dis(fb, pop - fb), dissim_hisp = dis(hisp, pop - hisp), dissim_laborers = dis(laborers, pop - laborers),
                 geography = fifelse(YEAR[1] < 1910, "Arapahoe County (Denver was ~90% of it)", "City and County of Denver")), by = .(census = YEAR)][order(census)]
  fwrite(city, file.path(A, "denver_city_1880_1940.csv")); print(city[, .(census, EDs, pop, pct_black, pct_fb, pct_hispanic, dissim_black, dissim_fb)])
} else message("denver_city_1880_1940.csv skipped (run R/fetch_ipums_fullcount.R)")
