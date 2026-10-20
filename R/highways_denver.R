# Where and when Denver's freeways were built, and what they ran through.
#   Rscript R/highways_denver.R     (after R/fetch_highways.R, R/zoning_over_time.R and R/landuse_1937_1997.R)
# Sources: OpenHistoricalMap (dated alignments of motorways, trunk and primary roads around Denver, with start_date and end_date, including
# alignments since moved or removed; work/highways/ohm_denver_highways.geojson), cross-checked against the NBER interstate opening dates
# (Baum-Snow; FHWA PR-511, route x county x milepost segments with year-month opened; work/highways/openings/openings/highway10122.dta).
# OpenHistoricalMap is volunteer-mapped: dates come from its contributors' sources (often CDOT histories) and are checked here against
# NBER where the two overlap (interstates in Denver County).
# Outputs (data/results/highways/, copies in app/data):
#   highways_denver.geojson            freeway and major-road alignments in and around the study area with start and end years (for the maps)
#   highways_km_by_decade.csv          km of freeway (motorway) opened per decade in the study area
#   highways_nber_check.csv            NBER first/last opening by interstate in Denver County vs the OHM start years
#   highways_by_holc_grade.csv         km of freeway built 1950-1979 through each 1938 HOLC grade, and share of each grade within 250 m
#   highways_by_zoning_1929.csv        km of those freeways through 1929 industrial, commercial and other land
#   highways_tracts.csv                tracts crossed by a freeway built 1950-1979 vs not: population and composition 1950-1990
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; O <- "data/results/highways"; A <- "app/data"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
yr <- function(x) suppressWarnings(as.integer(substr(gsub("^~", "", x), 1, 4)))
tr <- st_transform(st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE), UTM); tr$core <- as.logical(tr$core) %in% TRUE
STUDY <- st_union(st_make_valid(tr[tr$core | substr(tr$GEOID, 1, 5) == "08031", ]))
# ---------------------------------------------------------------- alignments
H <- st_transform(st_read("work/highways/ohm_denver_highways.geojson", quiet = TRUE), UTM)
H$start_year <- yr(H$start_date); H$end_year <- yr(H$end_date)
H$ref_clean <- toupper(gsub("[- ]+", " ", H$ref)); H$ref_clean <- sub("^I ", "I-", H$ref_clean)
H$kind <- ifelse(grepl("^motorway", H$highway), "Freeway", "Major road")
H <- H[lengths(st_intersects(H, st_buffer(STUDY, 3000))) > 0, ]
HS <- suppressWarnings(st_intersection(H, STUDY)); HS$km <- as.numeric(st_length(HS)) / 1000
out <- st_transform(H[, c("name", "ref_clean", "highway", "kind", "start_year", "end_year")], 4326)
f <- file.path(O, "highways_denver.geojson"); if (file.exists(f)) file.remove(f); st_write(out, f, quiet = TRUE)
# ---------------------------------------------------------------- 1. km by decade
FW <- HS[HS$kind == "Freeway" & !grepl("_link", HS$highway), ]
R1 <- as.data.table(st_drop_geometry(FW))[!is.na(start_year), .(km_opened = round(sum(km), 1)), by = .(decade = 10 * (start_year %/% 10))][order(decade)]
R1[, km_cumulative := cumsum(km_opened)]
rem <- as.data.table(st_drop_geometry(FW))[!is.na(end_year), .(km_removed = round(sum(km), 1)), by = .(decade = 10 * (end_year %/% 10))]
R1 <- merge(R1, rem, by = "decade", all = TRUE); R1[is.na(km_opened), km_opened := 0]; R1[is.na(km_removed), km_removed := 0]
fwrite(R1, file.path(O, "highways_km_by_decade.csv")); print(R1)
# ---------------------------------------------------------------- 2. NBER cross-check (Denver County interstates)
nb <- as.data.table(haven::read_dta("work/highways/openings/openings/highway10122.dta"))[state == "COLORADO" & county == 31]
nb[, open_year := 1900 + open %/% 100]; nb[, route := paste0("I-", rte %/% 10)]
R2 <- nb[, .(nber_miles = round(sum(seg) / 100, 1), nber_first_opened = min(open_year), nber_last_opened = max(open_year)), by = route]
den <- st_union(st_make_valid(tr[substr(tr$GEOID, 1, 5) == "08031", ]))
HD <- suppressWarnings(st_intersection(H[H$kind == "Freeway" & !grepl("_link", H$highway), ], den))
oh <- as.data.table(st_drop_geometry(HD))[, km := as.numeric(st_length(HD)) / 1000][grepl("^I-", ref_clean), .(ohm_km = round(sum(km), 1), ohm_first = min(start_year, na.rm = TRUE), ohm_last = max(start_year, na.rm = TRUE)), by = .(route = sub(";.*", "", ref_clean))]
R2 <- merge(R2, oh, by = "route", all = TRUE); fwrite(R2, file.path(O, "highways_nber_check.csv")); print(R2)
# ---------------------------------------------------------------- 3. HOLC grades and 1929 zoning
B <- FW[!is.na(FW$start_year) & FW$start_year >= 1950 & FW$start_year <= 1979, ]
Hh <- st_make_valid(st_transform(st_read(file.path(A, "holc_denver.geojson"), quiet = TRUE), UTM)); Hh <- Hh[Hh$grade %in% c("A", "B", "C", "D"), ]
Hh <- aggregate(Hh[, "grade"], list(grade = Hh$grade), function(x) x[1])[, "grade"]; Hh$area_km2 <- as.numeric(st_area(Hh)) / 1e6
x <- suppressWarnings(st_intersection(B[, "start_year"], Hh)); km_g <- data.table(grade = x$grade, km = as.numeric(st_length(x)) / 1000)[, .(km_through = round(sum(km), 1)), by = grade]
buf <- st_union(st_buffer(B, 250)); y <- suppressWarnings(st_intersection(Hh, buf))
near <- data.table(grade = y$grade, near_km2 = as.numeric(st_area(y)) / 1e6)
R3 <- merge(merge(data.table(grade = Hh$grade, area_km2 = round(Hh$area_km2, 1)), km_g, by = "grade", all.x = TRUE), near, by = "grade", all.x = TRUE)
R3[is.na(km_through), km_through := 0]; R3[is.na(near_km2), near_km2 := 0]; R3[, `:=`(km_per_km2 = round(km_through / area_km2, 2), pct_within_250m = round(100 * near_km2 / area_km2, 1), near_km2 = NULL)]
fwrite(R3, file.path(O, "highways_by_holc_grade.csv")); print(R3)
Z <- st_make_valid(st_transform(st_read(file.path(A, "zoning_1929.geojson"), quiet = TRUE), UTM)); Z$cls <- ifelse(grepl("Industrial", Z$zone), "1929 industrial district", "1929 commercial district")
zi <- suppressWarnings(st_intersection(B[, "start_year"], Z[, "cls"])); zk <- data.table(cls = zi$cls, km = as.numeric(st_length(zi)) / 1000)[, .(km = sum(km)), by = cls]
g <- fread("data/results/zoning_1929/gcp_fit.csv"); fx <- lm(X ~ px_x + px_y, g); fy <- lm(Y ~ px_x + px_y, g)
P <- function(px, py) cbind(predict(fx, data.frame(px_x = px, px_y = py)), predict(fy, data.frame(px_x = px, px_y = py)))
SHEET <- st_sfc(st_polygon(list(rbind(P(0, 0), P(11849, 0), P(11849, 12000), P(0, 12000), P(0, 0)))), crs = UTM)
on <- suppressWarnings(st_intersection(B[, "start_year"], SHEET)); tot <- sum(as.numeric(st_length(on))) / 1000
R4 <- rbind(zk, data.table(cls = "residence or business district (rest of the 1929 map)", km = tot - sum(zk$km)))[, `:=`(km = round(km, 1), pct = round(100 * km / tot, 1))]
lnd <- rbind(data.table(cls = "Land on the 1929 map (km2)", km = as.numeric(st_area(SHEET)) / 1e6), data.table(cls = "1929 industrial (km2)", km = sum(as.numeric(st_area(Z[Z$cls == "1929 industrial district", ]))) / 1e6))
R4[, share_of_land := round(100 * c(sum(as.numeric(st_area(Z[Z$cls == "1929 industrial district", ]))), sum(as.numeric(st_area(Z[Z$cls == "1929 commercial district", ]))), NA) / as.numeric(st_area(SHEET)), 1)[match(cls, c("1929 industrial district", "1929 commercial district", "x"))]]
fwrite(R4, file.path(O, "highways_by_zoning_1929.csv")); print(R4)
# ---------------------------------------------------------------- 4. tracts crossed
core <- tr[tr$core, "GEOID"]; hit <- lengths(st_intersects(core, B)) > 0
T <- data.table(GEOID = core$GEOID, crossed = ifelse(hit, "Crossed by a freeway built 1950-1979", "Not crossed"))
Pn <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character"))[census %in% c(1950, 1960, 1970, 1980, 1990) & !is.na(pop)]
M <- merge(Pn, T, by = "GEOID"); keep <- M[, .N, by = GEOID][N == 5, GEOID]; M <- M[GEOID %in% keep]
wm <- function(v, w) round(weighted.mean(v, w, na.rm = TRUE), 1)
R5 <- M[, .(tracts = uniqueN(GEOID), residents = sum(pop), pct_hispanic = wm(p_hisp, pop), pct_black = wm(p_black, pop), pct_owner_occupied = wm(p_owner, pop)), by = .(crossed, census)][order(crossed, census)]
R5[, pop_index_1950_100 := round(100 * residents / residents[census == 1950]), by = crossed]
fwrite(R5, file.path(O, "highways_tracts.csv")); print(R5)
file.copy(list.files(O, "\\.(csv|geojson)$", full.names = TRUE), A, overwrite = TRUE)
# ---------------------------------------------------------------- 5. before and after: tracts lined up on their own freeway's opening
# Treated: study tracts that a freeway (motorway, not ramps) opened 1950-1979 passes within 250 m of; the tract's opening year is the
# earliest such opening, and its "last census before" is the census year at or before that opening. Comparison: study tracts with no
# freeway within 1 km before 1990. For each treated tract and census, the gap from the mean of the comparison tracts in that census is
# taken, and gaps are averaged by decades since the opening (event time), relative to the last census before (event time 0).
FW2 <- FW[!is.na(FW$start_year), ]
d250 <- st_is_within_distance(core, FW2, 250); open_yr <- vapply(d250, function(i) if (length(i)) min(FW2$start_year[i]) else NA_real_, 0)
d1k <- st_is_within_distance(core, FW2[FW2$start_year < 1990, ], 1000)
dt <- as.numeric(st_distance(st_centroid(st_geometry(core)), st_transform(st_sfc(st_point(c(-104.9903, 39.7392)), crs = 4326), st_crs(core)))) / 1000
E <- data.table(GEOID = core$GEOID, open_year = open_yr, near1k_pre1990 = lengths(d1k) > 0, km_downtown = round(dt, 2))
E[, group := fifelse(!is.na(open_year) & open_year >= 1950 & open_year <= 1979, "treated", fifelse(!near1k_pre1990, "comparison", "other"))]
E[group == "treated", base_census := 10 * floor(open_year / 10)]
Pa0 <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character"))[census >= 1940 & !is.na(pop) & pop > 0]
V <- c("p_hisp", "p_black", "p_white", "p_owner", "p_pov")
# two comparison sets: all tracts with no freeway within 1 km, and only those as close to downtown as the treated tracts (within the treated tracts' median distance)
dmax <- median(E[group == "treated", km_downtown])
ev <- function(cmp_ids, label) {
  Pa <- merge(Pa0, E[, .(GEOID, group, base_census)], by = "GEOID")
  cmp <- Pa[GEOID %in% cmp_ids, c(list(c_pop = sum(pop)), lapply(.SD, function(x) weighted.mean(x, pop, na.rm = TRUE))), by = census, .SDcols = V]
  setnames(cmp, V, paste0("c_", V))
  Tr <- merge(Pa[group == "treated"], cmp, by = "census"); Tr[, event := (census - base_census) / 10]; Tr <- Tr[event >= -2 & event <= 4]
  Tr <- merge(Tr, Tr[event == 0, .(GEOID, pop0 = pop, c_pop0 = c_pop)], by = "GEOID")
  g <- function(a, b, w) { x <- weighted.mean(a - b, w, na.rm = TRUE); if (is.nan(x)) NA_real_ else round(x, 1) }
  Tr[, .(comparison = label, tracts = uniqueN(GEOID), pop_index = round(100 * sum(pop) / sum(pop0), 1), comparison_pop_index = round(100 * mean(c_pop / c_pop0), 1),
         gap_hispanic = g(p_hisp, c_p_hisp, pop), gap_black = g(p_black, c_p_black, pop), gap_white = g(p_white, c_p_white, pop),
         gap_owner = g(p_owner, c_p_owner, pop), gap_poverty = g(p_pov, c_p_pov, pop)), by = .(decades_since_opening = event)][order(decades_since_opening)] }
R6 <- rbind(ev(E[group == "comparison", GEOID], "All tracts with no freeway within 1 km"),
            ev(E[group == "comparison" & km_downtown <= dmax, GEOID], sprintf("Same, within %.1f km of downtown", dmax)))
fwrite(R6, file.path(O, "highways_event_study.csv")); print(R6, nrows = 50); print(E[, .N, by = group]); print(E[group == "comparison" & km_downtown <= dmax, .N])
fwrite(E[, .(GEOID, group, open_year, km_downtown)], file.path(O, "highways_tract_groups.csv"))
file.copy(file.path(O, c("highways_event_study.csv", "highways_tract_groups.csv")), A, overwrite = TRUE)
