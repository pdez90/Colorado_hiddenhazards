# Contamination, emissions, urban renewal, lead and health around Denver's historical industrial sites.
#
#   Rscript R/context_layers.R          (after Rscript R/fetch_context_layers.R)
#
# Inputs: work/context/ (R/fetch_context_layers.R) and the project's own layers in app/data/ and data/results/site_fate/.
# What it does
#   1. Petroleum releases (1986-) and regulated tank facilities near every historical site: within 50 m of the geocoded address
#      (the precision of the directories' street addresses), by series, inventory status and today's use of the parcel.
#   2. TRI releases 1987-: facility-years in the Denver study area (air, on-site, total, carcinogens, in pounds); totals by year and by the
#      1938 HOLC grade of the facility's location; facilities within 100 m of a historical site.
#   3. Measured air quality 1980-: annual means across Denver-metro monitors by pollutant (EPA AQS).
#   4. Urban renewal: Denver's federal urban-renewal projects (Renewing Inequality): families in the project area (white, non-white;
#      the latest figure the federal reports give), substandard dwellings, acres and planned reuse, and the
#      historical hazardous sites inside each project.
#   5. Superfund operable units in the study area (incl. Vasquez Boulevard/I-70 residential soils) and CDPHE's modelled childhood
#      lead-risk decile by tract.
#   6. Health today by tract: CDC PLACES (2024 release) and life expectancy 2010-15 (USALEEP), compared across tracts by their industrial
#      history (1965-92 known and hidden sites, pre-1960 hazardous trades, industrial land in 1937).
#   8-10. Sanborn volume extents and a digitising worklist; Vasquez Blvd/I-70 soil results by neighbourhood (ROD 2003); urban-renewal
#      case studies (area-weighted census composition inside each project, 1940-1990).
#   7. Sanborn fire-insurance map links for every street-level pre-1960 site (the nearest digitised Library of Congress edition, 1887-1904;
#      1929-1951 editions are on ProQuest through the Denver Public Library).
# Outputs: data/results/context/*.csv and copies of the map layers in app/data/ (all from public sources).
for (p in c("data.table", "sf", "terra", "RANN", "jsonlite")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(sf); library(terra) })
sf_use_s2(FALSE); UTM <- 26913; W <- "work/context"; A <- "app/data"; O <- "data/results/context"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
if (!dir.exists(W)) stop("run Rscript R/fetch_context_layers.R first")
toUTM <- function(d, lon = "lon", lat = "lat") st_transform(st_as_sf(d, coords = c(lon, lat), crs = 4326, remove = FALSE), UTM)
TR <- st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE); STUDY_IDS <- TR$GEOID[as.logical(TR$core) %in% TRUE | substr(TR$GEOID, 1, 5) == "08031"]
STUDY <- st_union(st_make_valid(st_transform(TR[TR$GEOID %in% STUDY_IDS, ], UTM)))
in_study <- function(s) lengths(st_intersects(s, STUDY)) > 0
HOLC <- st_make_valid(st_transform(st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE), UTM)); HOLC <- HOLC[HOLC$grade %in% c("A", "B", "C", "D"), "grade"]
grade_of <- function(s) { w <- st_within(s, HOLC); vapply(w, function(i) if (length(i)) HOLC$grade[i[1]] else "ungraded", "") }
# ---------------------------------------------------------------- the historical sites
S <- fread(file.path(A, "sites.csv"))[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx") & !is.na(lat) & !is.na(lon)]
SF <- fread("data/results/site_fate/site_fate_denver.csv")[, .(site_id, use_now)]
S <- merge(S, SF, by = "site_id", all.x = TRUE)
S <- S[, .(id = site_id, series = "Hazardous-sector manufacturers 1965-1992", status = fifelse(radar == "Not on any list", "on no current inventory", "on a current inventory"),
           name = hazard_firms, address, first_year, last_year, use_now, lat, lon)]
H <- fread(file.path(A, "historical_sites.csv"))[fe_hazard %in% c(TRUE, "True") & precision != "town" & !is.na(lat) & town == "DENVER"]
HF <- fread("data/results/site_fate/site_fate_denver_pre1960.csv")[, .(hfirm, use_now)]
H <- merge(H, HF, by = "hfirm", all.x = TRUE)
H2 <- H[, .(id = hfirm, series = "Hazardous trades before 1960 (street level)", status = "pre-1960", name, address = street, first_year, last_year, use_now, lat, lon)]
ALL <- rbind(S, H2); ALL[is.na(use_now), use_now := "not matched to a parcel"]
PS <- toUTM(ALL); ALL[, study := in_study(PS)]
nearby <- function(pts, tgt, r) { if (!nrow(tgt)) return(list(n = rep(0L, nrow(pts)), idx = vector("list", nrow(pts))))
  w <- st_is_within_distance(pts, tgt, r); list(n = lengths(w), idx = w) }
# ---------------------------------------------------------------- 1. petroleum releases and tank facilities
PR <- fread(file.path(W, "petroleum_releases.csv"))
PR <- PR[!is.na(latitude) & !is.na(longitude) & latitude != 0][, `:=`(release_year = as.integer(substr(release_date, 1, 4)), closure_year = as.integer(substr(closure_date, 1, 4)))]
PRs <- toUTM(PR, "longitude", "latitude"); PR[, study := in_study(PRs)]
TF <- fread(file.path(W, "tank_facilities.csv"))[!is.na(latitude) & !is.na(longitude) & latitude != 0]
TFs <- toUTM(TF, "longitude", "latitude")
pr <- nearby(PS, PRs, 50); tf <- nearby(PS, TFs, 50)
ALL[, `:=`(petroleum_releases_50m = pr$n, tank_facility_50m = as.numeric(tf$n > 0))]
ALL[, first_release_year := vapply(pr$idx, function(i) if (length(i)) as.numeric(min(PR$release_year[i], na.rm = TRUE)) else NA_real_, 1)]
ALL[, open_releases_50m := vapply(pr$idx, function(i) sum(!grepl("closed|nfa|no further", tolower(PR$status[i]))), 1L)]
ALL[, release_ids := vapply(pr$idx, function(i) paste(head(PR$release_number[i], 5), collapse = "; "), "")]
SUM1 <- ALL[study == TRUE, .(sites = .N, pct_petroleum_release_50m = round(100 * mean(petroleum_releases_50m > 0), 1), pct_open_release = round(100 * mean(open_releases_50m > 0), 1),
                             pct_tank_facility_50m = round(100 * mean(tank_facility_50m > 0), 1)), by = .(series, status)][order(series, status)]
SUM1b <- ALL[study == TRUE, .(sites = .N, pct_petroleum_release_50m = round(100 * mean(petroleum_releases_50m > 0), 1), pct_tank_facility_50m = round(100 * mean(tank_facility_50m > 0), 1)),
             by = .(series, today = use_now)][sites >= 10][order(series, -sites)]
fwrite(SUM1, file.path(O, "petroleum_by_status.csv")); fwrite(SUM1b, file.path(O, "petroleum_by_use_now.csv")); print(SUM1); print(SUM1b)
# map layer: releases in the study area
fwrite(PR[study == TRUE, .(release_number, facility_id, site_name, address, city, status, release_year, closure_year, release_source, release_cause, lat = latitude, lon = longitude,
                            link = release_record_link)], file.path(A, "petroleum_releases_study.csv"))
# ---------------------------------------------------------------- 2. TRI 1987-
tf_files <- Sys.glob(file.path(W, "tri", "tri_*_CO.csv"))
TRI <- rbindlist(lapply(tf_files, function(f) { x <- tryCatch(fread(f, colClasses = "character"), error = function(e) NULL); if (is.null(x) || !nrow(x)) return(NULL)
  n <- names(x); pick <- function(re) { k <- grep(re, n, ignore.case = TRUE, value = TRUE); if (length(k)) x[[k[1]]] else rep(NA_character_, nrow(x)) }
  num <- function(v) suppressWarnings(as.numeric(gsub(",", "", v)))
  data.table(year = as.integer(pick("(^|\\. )YEAR$")), trifd = pick("TRIFD|TRI FACILITY ID"), name = pick("FACILITY NAME"), address = pick("STREET ADDRESS"), city = pick("(^|\\. )CITY$"),
             lat = num(pick("LATITUDE")), lon = num(pick("LONGITUDE")), chemical = pick("(^|\\. )CHEMICAL$"), carcinogen = pick("CARCINOGEN"),
             air = rowSums(cbind(num(pick("FUGITIVE AIR")), num(pick("STACK AIR"))), na.rm = TRUE), onsite = num(pick("ON-SITE RELEASE TOTAL")), total = num(pick("TOTAL RELEASES")), unit = pick("UNIT OF MEASURE")) }), fill = TRUE)
if (nrow(TRI)) {
  TRI <- TRI[!is.na(lat) & !is.na(lon)]
  for (v in c("air", "onsite", "total")) TRI[is.na(get(v)), (v) := 0]
  TRI[grepl("gram", tolower(unit)), c("air", "onsite", "total") := .(air / 453.592, onsite / 453.592, total / 453.592)]   # dioxins are reported in grams
  FY <- TRI[, .(name = name[1], address = address[1], city = city[1], lat = lat[1], lon = lon[1], chemicals = uniqueN(chemical), air_lb = sum(air), onsite_lb = sum(onsite), total_lb = sum(total),
                carcinogen_air_lb = sum(air[toupper(carcinogen) %in% c("YES", "Y", "TRUE")])), by = .(trifd, year)]
  FYs <- toUTM(FY); FY[, `:=`(study = in_study(FYs), holc = grade_of(FYs))]
  FY <- FY[study == TRUE][, study := NULL]
  w <- st_is_within_distance(toUTM(FY), PS[ALL$study, ], 100); FY[, near_historical_site := lengths(w) > 0]
  fwrite(FY, file.path(A, "tri_facility_years_study.csv"))
  TT <- FY[, .(facilities = uniqueN(trifd), air_lb = round(sum(air_lb)), onsite_lb = round(sum(onsite_lb)), carcinogen_air_lb = round(sum(carcinogen_air_lb))), by = year][order(year)]
  TG <- FY[, .(facilities = uniqueN(trifd), air_lb = round(sum(air_lb))), by = .(year, holc)][order(year, holc)]
  TN <- FY[, .(facility_years = .N, facilities = uniqueN(trifd), air_lb = round(sum(air_lb))), by = .(near_historical_site)]
  fwrite(TT, file.path(O, "tri_by_year.csv")); fwrite(TG, file.path(O, "tri_by_year_holc.csv")); fwrite(TN, file.path(O, "tri_near_sites.csv"))
  file.copy(file.path(O, c("tri_by_year.csv", "tri_by_year_holc.csv")), A, overwrite = TRUE); print(TT); print(TN)
  ALL[, tri_facility_100m := lengths(st_is_within_distance(PS, toUTM(FY[!duplicated(trifd)]), 100)) > 0]
} else message("no TRI files read (check work/context/tri/)")
# ---------------------------------------------------------------- 3. AQS
if (file.exists(file.path(W, "aqs_denver.csv")) && file.size(file.path(W, "aqs_denver.csv")) > 0) {
AQ <- fread(file.path(W, "aqs_denver.csv"))
KEEP <- c("Lead (TSP) LC" = "Lead (TSP)", "Total Suspended Particulate (TSP)" = "Total suspended particulates", "Sulfur dioxide" = "Sulfur dioxide",
          "Nitrogen dioxide (NO2)" = "Nitrogen dioxide", "Carbon monoxide" = "Carbon monoxide", "Ozone" = "Ozone", "PM10 Total 0-10um STP" = "PM10", "PM2.5 - Local Conditions" = "PM2.5",
          "Benzene" = "Benzene")
AQ <- AQ[parameter %in% names(KEEP)]
AQ[, pref := fifelse(event %in% c("No Events", "Events Excluded"), 1L, 2L)]
AQ <- AQ[order(pref)][, .SD[standard == standard[1] | is.na(standard)], by = .(parameter)]       # one standard/metric per pollutant
AQ <- AQ[!duplicated(paste(year, county, site, parameter_code, poc))]
AT <- AQ[, .(monitors = uniqueN(paste(county, site)), mean = round(mean(mean, na.rm = TRUE), 4), units = units[1]), by = .(pollutant = KEEP[parameter], year)][order(pollutant, year)]
fwrite(AT, file.path(O, "aqs_denver_by_year.csv")); file.copy(file.path(O, "aqs_denver_by_year.csv"), A, overwrite = TRUE)
fwrite(AQ[!duplicated(paste(county, site)), .(county, site, site_name, latitude, longitude)], file.path(A, "aqs_monitors_denver.csv"))
print(AT[, .(first = min(year), last = max(year), years = .N), by = pollutant])
} else message("no AQS file: air-quality trends skipped")
# ---------------------------------------------------------------- 4. urban renewal
UR <- st_read(file.path(W, "ur_projects.geojson"), quiet = TRUE); UR <- UR[tolower(UR$city) == "denver" & tolower(UR$state) == "co", ]
NS <- fread(file.path(W, "ur_non_spatial.csv"))[tolower(city) == "denver" & tolower(state) == "co"]
# the federal reports give running totals each period: keep the latest reported value per project and item
NS[, v := suppressWarnings(as.numeric(value))]; NS[, qn := match(tolower(quarter), c("march", "june", "september", "december"))]
lastv <- function(k, nm) { x <- NS[cat == k & !is.na(v)][order(project_id, year, qn)][, .(v = v[.N]), by = project_id]; setnames(x, "v", nm); x }
URt <- Reduce(function(a, b) merge(a, b, by = "project_id", all = TRUE), list(
  NS[, .(first_year = min(year, na.rm = TRUE), last_year = max(year, na.rm = TRUE), project_name = project[1]), by = project_id],
  lastv("white families", "white_families"), lastv("non-white families", "nonwhite_families"), lastv("total families", "total_families"),
  lastv("dwelling units- sub-standard", "substandard_dwellings"), lastv("dwelling units- standard", "standard_dwellings"),
  lastv("proposed reuse of project land- total", "acres"), lastv("proposed reuse of project land- industrial", "acres_to_industrial"),
  lastv("proposed reuse of project land- residential", "acres_to_residential"), lastv("proposed reuse of project land- commercial", "acres_to_commercial")))
URt[is.na(total_families) & (!is.na(white_families) | !is.na(nonwhite_families)), total_families := rowSums(cbind(white_families, nonwhite_families), na.rm = TRUE)]
URs <- st_make_valid(st_transform(UR, UTM))
URs$historical_sites_inside <- lengths(st_intersects(URs, PS[ALL$series == "Hazardous trades before 1960 (street level)", ]))
URs$sites_1965_92_inside <- lengths(st_intersects(URs, PS[ALL$series != "Hazardous trades before 1960 (street level)", ]))
URs <- merge(URs, URt[, !"project_name"], by = "project_id", all.x = TRUE)
URs$boundary_confidence <- ifelse(URs$conf == 0, "mapped boundary", "approximate boundary")
URo <- st_transform(URs[, c("project_id", "project", "boundary_confidence", "total_families", "white_families", "nonwhite_families", "substandard_dwellings", "acres", "acres_to_industrial", "first_year", "last_year",
                            "historical_sites_inside", "sites_1965_92_inside")], 4326)
if (file.exists(file.path(A, "urban_renewal_denver.geojson"))) file.remove(file.path(A, "urban_renewal_denver.geojson"))
st_write(URo, file.path(A, "urban_renewal_denver.geojson"), quiet = TRUE)
URall <- merge(URt, data.table(project_id = URs$project_id, mapped = TRUE), by = "project_id", all.x = TRUE)
fwrite(URall[order(-total_families)], file.path(O, "urban_renewal_denver.csv")); file.copy(file.path(O, "urban_renewal_denver.csv"), A, overwrite = TRUE); print(URall)
ALL[, urban_renewal_project := { j <- st_intersects(PS, URs); vapply(j, function(i) if (length(i)) URs$project[i[1]] else NA_character_, "") }]
# ---------------------------------------------------------------- 5. Superfund operable units and childhood lead risk
OU <- st_make_valid(st_read(file.path(W, "superfund_ou_co.geojson"), quiet = TRUE)); OUu <- st_transform(OU, UTM)
OU <- OU[lengths(st_intersects(OUu, st_buffer(STUDY, 2000))) > 0, ]
if (file.exists(file.path(A, "superfund_ou_study.geojson"))) file.remove(file.path(A, "superfund_ou_study.geojson"))
st_write(OU, file.path(A, "superfund_ou_study.geojson"), quiet = TRUE); message(nrow(OU), " Superfund operable-unit polygons in or near the study area")
ALL[, superfund_unit := { j <- st_intersects(PS, st_transform(OU, UTM)); vapply(j, function(i) if (length(i)) paste(OU$SITE_NAME[i[1]], OU$SITE_FEATURE_NAME[i[1]], sep = ": ") else NA_character_, "") }]
LR <- st_read(file.path(W, "lead_risk_tracts.geojson"), quiet = TRUE)
LR <- data.table(GEOID = sprintf("%011s", as.character(LR$FIPS)), lead_risk_decile = as.numeric(LR$Dec_Wsqrt))
LR[, GEOID := gsub(" ", "0", GEOID)]
# ---------------------------------------------------------------- 6. health by tract
PL <- fread(file.path(W, "places_tracts_co.csv"), colClasses = c(tractfips = "character", countyfips = "character"))
MEAS <- c(casthma = "Current asthma", copd = "COPD", chd = "Coronary heart disease", diabetes = "Diabetes", bphigh = "High blood pressure", depression = "Depression",
          cancer = "Cancer (non-skin)", csmoking = "Current smoking", obesity = "Obesity", lpa = "No leisure-time physical activity", access2 = "No health insurance")
cols <- intersect(paste0(names(MEAS), "_crudeprev"), names(PL))
HT <- PL[, c("tractfips", "totalpopulation", cols), with = FALSE]; setnames(HT, "tractfips", "GEOID"); setnames(HT, cols, sub("_crudeprev$", "", cols))
LE <- fread(file.path(W, "usaleep_co.csv"), colClasses = "character"); ln <- names(LE)
gcol <- grep("^Tract ID$|TRACT", ln, ignore.case = TRUE, value = TRUE)[1]; ecol <- grep("^e\\(0\\)$|e\\(0\\)", ln, value = TRUE)[1]
LE <- LE[, .(GEOID = get(gcol), life_expectancy = as.numeric(get(ecol)))]
# PLACES may use 2020 tracts: if most study tracts (2010) are missing, move 2020-tract estimates to the 2010 tract containing each
# 2020 tract's interior point (population-weighted means)
if (mean(STUDY_IDS %in% HT$GEOID) < 0.7 && requireNamespace("tigris", quietly = TRUE)) {
  t20 <- st_transform(tigris::tracts("CO", year = 2020, cb = TRUE, progress_bar = FALSE), UTM); t20 <- t20[t20$GEOID %in% HT$GEOID, ]
  j <- st_within(st_point_on_surface(st_geometry(t20)), st_transform(TR, UTM)); map <- data.table(g20 = t20$GEOID, GEOID = vapply(j, function(i) if (length(i)) TR$GEOID[i[1]] else NA_character_, ""))
  HT <- merge(HT, map, by.x = "GEOID", by.y = "g20")[!is.na(GEOID.y)]; HT[, GEOID := GEOID.y][, GEOID.y := NULL]
  m <- setdiff(names(HT), c("GEOID", "totalpopulation")); HT[, totalpopulation := as.numeric(totalpopulation)]
  HT <- HT[, c(list(totalpopulation = sum(totalpopulation)), lapply(.SD, function(v) weighted.mean(v, totalpopulation, na.rm = TRUE))), by = GEOID, .SDcols = m]
  message("PLACES: 2020 tracts moved onto 2010 tracts") }
HT <- merge(HT, LE, by = "GEOID", all = TRUE); HT <- merge(HT, LR, by = "GEOID", all = TRUE)
HT <- HT[GEOID %in% STUDY_IDS]
message(sprintf("health measures for %d of %d study tracts (PLACES %d, life expectancy %d, lead risk %d)", nrow(HT), length(STUDY_IDS),
                sum(!is.na(HT[[names(MEAS)[1]]])), sum(!is.na(HT$life_expectancy)), sum(!is.na(HT$lead_risk_decile))))
# tract industrial history on the same (2010) tracts
T10 <- st_make_valid(st_transform(TR[TR$GEOID %in% STUDY_IDS, ], UTM))
cnt <- function(mask) lengths(st_intersects(T10, PS[mask, ]))
hist_t <- data.table(GEOID = T10$GEOID, known_1965_92 = cnt(ALL$status == "on a current inventory"), hidden_1965_92 = cnt(ALL$status == "on no current inventory"),
                     pre1960_trades = cnt(ALL$status == "pre-1960"))
lu <- if (file.exists(file.path(A, "landuse_tracts.csv"))) fread(file.path(A, "landuse_tracts.csv"), colClasses = c(GEOID = "character"))[year == 1937, .(GEOID, industrial_1937 = 100 * industrial_use_share)] else NULL
if (!is.null(lu)) hist_t <- merge(hist_t, lu, by = "GEOID", all.x = TRUE)
HT <- merge(HT, hist_t, by = "GEOID", all.x = TRUE)
HT[, history := fcase(known_1965_92 >= 3, "3+ known historical sites", hidden_1965_92 >= 3, "3+ hidden sites (few known)", pre1960_trades >= 3, "3+ pre-1960 trades only",
                      default = "fewer historical sites")]
fwrite(HT, file.path(A, "health_tracts_study.csv")); fwrite(HT, file.path(O, "health_tracts_study.csv"))
mcols <- intersect(c(names(MEAS), "life_expectancy", "lead_risk_decile"), names(HT))
HB <- HT[!is.na(totalpopulation), c(list(tracts = .N, population = sum(as.numeric(totalpopulation), na.rm = TRUE)),
                                    lapply(.SD, function(v) round(weighted.mean(v, as.numeric(totalpopulation), na.rm = TRUE), 1))), by = history, .SDcols = mcols]
fwrite(HB, file.path(O, "health_by_history.csv")); file.copy(file.path(O, "health_by_history.csv"), A, overwrite = TRUE); print(HB)
# ---------------------------------------------------------------- 7. Sanborn links
LOC <- data.table(year = c(1887, 1890, 1890, 1893, 1903, 1903, 1904, 1904),
                  label = c("1887", "1890 vol. 1", "1890 vol. 2", "1893 vol. 3", "1903 vol. 1", "1903 vol. 2", "1904 vol. 3", "1904"),
                  url = sprintf("https://www.loc.gov/item/sanborn00985_%03d/", c(1, 2, 3, 4, 5, 6, 7, 8)))
ALL[, sanborn := fifelse(status == "pre-1960" & first_year <= 1915, sprintf("Library of Congress Sanborn editions nearest in time: %s",
                         vapply(first_year, function(y) { k <- LOC[order(abs(year - y))][1:3]; paste(sprintf("<a href='%s' target='_blank'>%s</a>", k$url, k$label), collapse = ", ") }, "")),
                         "1929–1951 Sanborn editions: Denver Public Library (ProQuest Digital Sanborn Maps, library card)")]
# ---------------------------------------------------------------- 8. Sanborn volumes (Library of Congress extents) and a digitising worklist
SBF <- Sys.glob(file.path(W, "sanborn_*.geojson"))
SB <- do.call(rbind, lapply(SBF, function(f) { x <- st_read(f, quiet = TRUE); ed <- sub("^sanborn_(.*)\\.geojson$", "\\1", basename(f))
  x$edition <- gsub("_", "\u2013", ed); x$volume <- suppressWarnings(as.integer(sub("\\D*(\\d+).*", "\\1", x$TITLE))); x$year <- x$VolYear
  x[, c("edition", "volume", "year", "DESCRIPTION")] }))
LOCV <- c("1887.1" = "001", "1890\u20131893.1" = "002", "1890\u20131893.2" = "003", "1890\u20131893.3" = "004", "1903\u20131904.1" = "005", "1903\u20131904.2" = "006", "1903\u20131904.3" = "007")
if (!is.null(SB) && nrow(SB)) {
  k <- paste(SB$edition, ifelse(SB$edition == "1887", 1L, SB$volume), sep = ".")
  SB$link <- ifelse(k %in% names(LOCV), sprintf("https://www.loc.gov/item/sanborn00985_%s/", LOCV[k]),
                    ifelse(SB$edition %in% c("1929\u20131930", "1950\u20131951"), "https://history.denverlibrary.org/research-tool/sanborn-fire-insurance-maps",
                           "https://www.loc.gov/collections/sanborn-maps/?q=denver+colorado"))
  SB$online <- ifelse(SB$edition %in% c("1929\u20131930", "1950\u20131951"), "ProQuest Digital Sanborn Maps (Denver Public Library card)", "Library of Congress (free, online)")
  SB$DESCRIPTION <- NULL
  if (file.exists(file.path(A, "sanborn_volumes.geojson"))) file.remove(file.path(A, "sanborn_volumes.geojson"))
  st_write(st_make_valid(SB), file.path(A, "sanborn_volumes.geojson"), quiet = TRUE)
  SBu <- st_make_valid(st_transform(SB, UTM))
  vol_at <- function(ed) { w <- st_within(PS, SBu[SBu$edition == ed, ]); v <- SBu$volume[SBu$edition == ed]; vapply(w, function(i) if (length(i)) as.character(v[i[1]]) else NA_character_, "") }
  ALL[, `:=`(sanborn_1903 = vol_at("1903\u20131904"), sanborn_1929 = vol_at("1929\u20131930"), sanborn_1951 = vol_at("1950\u20131951"))]
  ALL[, sanborn := paste0(sanborn, fifelse(is.na(sanborn_1929) & is.na(sanborn_1951), "", sprintf("<br>Sanborn volumes covering this address: 1929\u201330 vol. %s · 1950\u201351 vol. %s (ProQuest, Denver Public Library)",
                                                                                           fifelse(is.na(sanborn_1929), "\u2013", sanborn_1929), fifelse(is.na(sanborn_1951), "\u2013", sanborn_1951))))]
  WL <- ALL[study == TRUE & (use_now %in% c("Residential", "Civic / school / health", "Park / open space") | (status == "on no current inventory" & use_now == "Vacant"))]
  WL <- WL[, .(priority = fcase(use_now == "Civic / school / health", 1L, use_now == "Residential", 2L, use_now == "Park / open space", 3L, default = 4L), id, series, status, name, address,
               first_year, last_year, use_now, sanborn_1903_volume = sanborn_1903, sanborn_1929_volume = sanborn_1929, sanborn_1951_volume = sanborn_1951,
               petroleum_releases_50m)][order(priority, series, address)]
  fwrite(WL, file.path(O, "sanborn_worklist.csv")); message(nrow(WL), " sites on the Sanborn worklist (now residential, school, park, or vacant hidden sites)")
}
# ---------------------------------------------------------------- 8b. What the Sanborn sheets show at each checked site (hand-recorded observations; no map images are kept here)
SOF <- "data/raw/sanborn/sanborn_observations_batch1.csv"
if (file.exists(SOF)) {
  SO <- fread(SOF, colClasses = list(character = "sheet"))
  SO[, popup := sprintf("<br><b>Sanborn check</b> (%s vol. 1, sheet %s): %s%s<br><i>%s</i>", sanborn_edition, sheet, tolower(use_on_sheet),
                        fifelse(hazard_features %in% c("", "none") | grepl("^none", hazard_features), "", paste0(" · drawn/labelled: ", hazard_features)), verdict)]
  ALL[SO, on = "id", sanborn := paste0(sanborn, i.popup)]
  SV <- SO[, .N, by = .(series_status, verdict)][, pct := round(100 * N / sum(N), 1), by = series_status][order(series_status, -N)]
  fwrite(SV, file.path(O, "sanborn_validation_summary.csv")); print(SV)
}
# ---------------------------------------------------------------- 9. Vasquez Boulevard/I-70 residential soils by neighbourhood (ROD 2003, Table 3)
ROD <- fread("data/raw/vbi70/rod2003_table3_residential_soils.csv"); file.copy("data/raw/vbi70/rod2003_table3_residential_soils.csv", file.path(A, "vbi70_rod2003_soils.csv"), overwrite = TRUE)
if (file.exists(file.path(W, "denver_neighborhoods.geojson"))) {
  NB <- st_read(file.path(W, "denver_neighborhoods.geojson"), quiet = TRUE); NB <- NB[NB$NBHD_NAME %in% c("Clayton", "Cole", "Elyria Swansea", "Globeville"), ]
  row_html <- function(n) { r <- ROD[neighborhood == n]; sprintf("<b>%s</b>: %s yards sampled · lead 95th percentile %s ppm (max %s) · arsenic 95th percentile %s ppm (max %s)",
                                                              n, r$properties_sampled, r$lead_95th_pct_ppm, r$lead_max_ppm, r$arsenic_95th_pct_ppm, r$arsenic_max_ppm) }
  NB$soil_html <- vapply(NB$NBHD_NAME, function(n) if (n == "Elyria Swansea") paste(row_html("Elyria"), row_html("Swansea"), sep = "<br>") else row_html(n), "")
  if (file.exists(file.path(A, "vbi70_neighborhoods.geojson"))) file.remove(file.path(A, "vbi70_neighborhoods.geojson"))
  st_write(st_make_valid(NB[, c("NBHD_NAME", "soil_html")]), file.path(A, "vbi70_neighborhoods.geojson"), quiet = TRUE) }
# ---------------------------------------------------------------- 10. urban-renewal case studies: who lived there, census by census (area-weighted 2010 tracts)
TP <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character"))[census <= 1990 & !is.na(pop)]
T10a <- st_make_valid(st_transform(TR[, "GEOID"], UTM)); T10a$a_t <- as.numeric(st_area(T10a))
IX <- suppressWarnings(st_intersection(URs[, "project"], T10a)); IX$share <- as.numeric(st_area(IX)) / IX$a_t
IX <- data.table(project = IX$project, GEOID = IX$GEOID, share = IX$share)[share > 0.001]
UC <- merge(IX, TP, by = "GEOID", allow.cartesian = TRUE)[, w := pop * share]
UC <- UC[, .(residents_est = round(sum(w)), pct_hispanic = round(weighted.mean(p_hisp, w, na.rm = TRUE), 1), pct_black = round(weighted.mean(p_black, w, na.rm = TRUE), 1),
             pct_owner = round(weighted.mean(p_owner, w, na.rm = TRUE), 1), pct_poverty = round(weighted.mean(p_pov, w, na.rm = TRUE), 1)), by = .(project, census)][order(project, census)]
for (v in c("pct_hispanic", "pct_black", "pct_owner", "pct_poverty")) UC[is.nan(get(v)), (v) := NA_real_]
fwrite(UC, file.path(O, "urban_renewal_composition.csv")); file.copy(file.path(O, "urban_renewal_composition.csv"), A, overwrite = TRUE); print(UC)
URs$petroleum_releases_inside <- lengths(st_intersects(URs, PRs[PR$study, ]))
fwrite(data.table(project = URs$project, petroleum_releases_inside = URs$petroleum_releases_inside, historical_sites_inside = URs$historical_sites_inside, sites_1965_92_inside = URs$sites_1965_92_inside),
       file.path(A, "urban_renewal_sites.csv"))
# ---------------------------------------------------------------- per-site record for the map popups
fwrite(ALL[study == TRUE, .(id, series, status, petroleum_releases_50m, open_releases_50m, first_release_year, tank_facility_50m,
                            tri_facility_100m = if ("tri_facility_100m" %in% names(ALL)) tri_facility_100m else NA, urban_renewal_project, superfund_unit, sanborn)],
       file.path(A, "site_context.csv"))
SUMALL <- ALL[study == TRUE, .(sites = .N, pct_petroleum_release_50m = round(100 * mean(petroleum_releases_50m > 0), 1), pct_tank_facility_50m = round(100 * mean(tank_facility_50m > 0), 1),
                               pct_tri_100m = if ("tri_facility_100m" %in% names(ALL)) round(100 * mean(tri_facility_100m), 1) else NA_real_,
                               in_urban_renewal_project = sum(!is.na(urban_renewal_project)), in_superfund_unit = sum(!is.na(superfund_unit))), by = .(series, status)]
fwrite(SUMALL, file.path(O, "site_context_summary.csv")); file.copy(file.path(O, "site_context_summary.csv"), A, overwrite = TRUE); print(SUMALL)
file.copy(file.path(O, c("petroleum_by_status.csv", "petroleum_by_use_now.csv")), A, overwrite = TRUE)
message("wrote ", O, " and the app layers in ", A)
