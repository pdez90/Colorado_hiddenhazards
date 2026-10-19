# Statewide 1880-1940: Colorado counties from the IPUMS full count (county x census year composition) against the hazardous trades
# of the pre-1960 business directories, on each census's own county boundaries (NHGIS, fetched by R/fetch_census.R, extract F).
#   Rscript R/county_panel_1880_1940.R
# Inputs: work/census/denver_ed_1880_1940.csv (R/fetch_ipums_fullcount.R: every Colorado ED, not just Denver), work/census/*/*county_<year>*.shp,
#         app/data/historical_sites.csv (pre-1960 firms, town- or street-level points).
# Output: app/data/co_counties_1880_1940.geojson (simplified polygons, one row per county and census) and data/results/county_panel_1880_1940.csv.
# County codes: IPUMS COUNTYICP = FIPS x 10 = NHGIS NHGISCTY (e.g. 310 = Denver 08031; Denver County exists from 1902, so 1880/1900 Denver is Arapahoe, 50).
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; W <- "work/census"
ip <- fread(file.path(W, "denver_ed_1880_1940.csv"))
C <- ip[, .(EDs = .N, pop = sum(pop), black = sum(black), fb = sum(fb), fb_mexico = sum(fb_mexico), fb_europe = sum(fb_europe), fb_asia = sum(fb_asia), hisp = sum(hisp),
            foreign_parentage = sum(foreign_parentage), laborers = sum(laborers, na.rm = TRUE)), by = .(census = YEAR, icp = COUNTYICP)]
C[, `:=`(fips = sprintf("08%03d", icp %/% 10), pct_black = round(100 * black / pop, 2), pct_fb = round(100 * fb / pop, 1), pct_fb_mexico = round(100 * fb_mexico / pop, 2),
         pct_hisp = round(100 * hisp / pop, 2), pct_laborers = round(100 * laborers / pop, 1))]
hist <- fread("app/data/historical_sites.csv")[!is.na(lat) & fe_hazard %in% c(TRUE, "True")]   # Frickel & Elliott hazardous trades only, as everywhere
hp <- st_transform(st_as_sf(hist[, .(hfirm, first_year, last_year, lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)
out <- list(); tab <- list()
for (yr in c(1880, 1900, 1910, 1920, 1930, 1940)) {
  shp <- Sys.glob(file.path(W, "*", sprintf("US_county_%d.shp", yr)))   # county boundaries only (not the tract-county files); if (!length(shp)) { message(yr, ": county boundaries missing (run R/fetch_census.R)"); next }
  S <- st_make_valid(st_transform(st_read(shp[1], quiet = TRUE), UTM)); S <- S[substr(S$GISJOIN, 1, 3) == "G08", ]
  S$icp <- as.integer(S$NHGISCTY); S$name <- if ("NHGISNAM" %in% names(S)) S$NHGISNAM else S$GISJOIN
  w <- st_within(hp[hp$first_year <= yr & hp$last_year >= yr - 9, ], S); f <- data.table(k = unlist(w))[, .(firms_haz = .N), by = k]
  S$firms_haz <- 0L; S$firms_haz[f$k] <- f$firms_haz
  D <- merge(as.data.table(st_drop_geometry(S))[, .(icp, name, firms_haz)], C[census == yr], by = "icp", all.x = TRUE)[, census := yr]
  D[, note := fifelse(is.na(pop), "no population in the full count for this county-year", "")]
  tab[[length(tab) + 1]] <- D
  G <- merge(S[, c("icp", "geometry")], D, by = "icp"); out[[length(out) + 1]] <- st_transform(st_simplify(G, dTolerance = 300), 4326)
  message(yr, ": ", nrow(S), " counties, ", sum(!is.na(D$pop)), " with full-count totals, ", sum(D$firms_haz), " firm placements")
}
if (length(out)) {
  G <- do.call(rbind, out); f <- "app/data/co_counties_1880_1940.geojson"; if (file.exists(f)) file.remove(f); st_write(G, f, quiet = TRUE)
  fwrite(rbindlist(tab)[order(census, name)], "data/results/county_panel_1880_1940.csv"); message("wrote ", f)
}
