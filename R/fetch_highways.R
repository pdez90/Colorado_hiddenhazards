# Download historical highway data for the Denver analysis.
#   Rscript R/fetch_highways.R
# Sources (NBER "Transportation Economics in the 21st Century" highway data, https://www.nber.org/research/data/transportation-economics-21st-century-highway-data):
#   openings.zip                       interstate segment opening dates and route replacement (Baum-Snow / NBER)
#   corridors.zip                      corridor-level completion
#   1947-Interstate-Highway-Plan.zip   the 1947 interstate plan (shapefile)
#   PR-511 (data/*.dta)                highway miles built 1950-1990 by funding type, from the FHWA PR-511 reports
# plus TIGER/Line 2023 primary roads for Colorado (present-day freeway geometry, to which opening dates are attached), and
# OpenHistoricalMap (https://www.openhistoricalmap.org; ODbL/CC0 contributions) dated highway alignments around Denver: motorway, trunk
# and primary ways with their start_date / end_date, including alignments since moved or removed (e.g. the I-70 viaduct).
# Files go to work/highways/ (re-downloadable, kept out of git). The script lists what each archive contains.
dir.create("work/highways", showWarnings = FALSE, recursive = TRUE); options(timeout = 1200)
B <- "https://www.nber.org/data/transportation/HighwayData/"
get <- function(u, f) { d <- file.path("work/highways", f); if (!file.exists(d)) { message("downloading ", f); download.file(u, d, mode = "wb", quiet = TRUE) }; d }
for (f in c("openings.zip", "corridors.zip", "1947-Interstate-Highway-Plan.zip")) { z <- get(paste0(B, f), f)
  ex <- file.path("work/highways", sub("\\.zip$", "", f)); dir.create(ex, showWarnings = FALSE); unzip(z, exdir = ex)
  message(f, ": "); print(list.files(ex, recursive = TRUE)) }
idx <- tryCatch(readLines(paste0(B, "data/"), warn = FALSE), error = function(e) character())
dta <- unique(regmatches(idx, regexpr("[A-Za-z0-9_\\-]+\\.dta", idx)))
for (f in dta) get(paste0(B, "data/", f), file.path("pr511", f) |> (\(p) { dir.create("work/highways/pr511", showWarnings = FALSE); p })())
message("PR-511 files: ", paste(dta, collapse = ", "))
if (requireNamespace("tigris", quietly = TRUE)) {
  pr <- tigris::primary_roads(year = 2023); co <- tigris::states(year = 2023, cb = TRUE); co <- co[co$STUSPS == "CO", ]
  pr <- sf::st_intersection(sf::st_transform(pr, 4269), sf::st_transform(co, 4269)[, "STUSPS"])
  f <- "work/highways/tiger_2023_primary_roads_CO.geojson"; if (file.exists(f)) file.remove(f); sf::st_write(pr, f, quiet = TRUE); message(nrow(pr), " primary-road segments in Colorado") }
# OpenHistoricalMap: dated major roads in a box around Denver (Overpass API)
q <- '[out:json][timeout:180];(way["highway"~"^(motorway|trunk|primary|motorway_link|trunk_link)$"](39.55,-105.15,39.95,-104.75););out tags geom;'
ohm <- tryCatch({ r <- httr::POST("https://overpass-api.openhistoricalmap.org/api/interpreter", body = list(data = q), encode = "form", httr::timeout(300))
  jsonlite::fromJSON(httr::content(r, as = "text", encoding = "UTF-8"), simplifyVector = FALSE)$elements }, error = function(e) { message("OHM: ", conditionMessage(e)); list() })
if (length(ohm)) {
  tg <- function(e, k) if (!is.null(e$tags[[k]])) e$tags[[k]] else NA_character_
  ways <- Filter(function(e) length(e$geometry) >= 2, ohm)
  g <- sf::st_sfc(lapply(ways, function(e) sf::st_linestring(do.call(rbind, lapply(e$geometry, function(p) c(p$lon, p$lat))))), crs = 4326)
  O <- sf::st_sf(ohm_id = vapply(ways, function(e) as.character(e$id), ""), name = vapply(ways, tg, "", "name"), ref = vapply(ways, tg, "", "ref"),
                 highway = vapply(ways, tg, "", "highway"), start_date = vapply(ways, tg, "", "start_date"), end_date = vapply(ways, tg, "", "end_date"), geometry = g)
  f <- "work/highways/ohm_denver_highways.geojson"; if (file.exists(f)) file.remove(f); sf::st_write(O, f, quiet = TRUE)
  message(nrow(O), " OpenHistoricalMap ways; with a start date: ", sum(!is.na(O$start_date))) }
writeLines(format(Sys.Date()), "work/highways/download_date.txt")
