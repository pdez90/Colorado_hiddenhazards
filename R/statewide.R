# Colorado beyond Denver: where hazardous industry was, who lived beside it, and the other graded cities.
#   Rscript R/statewide.R      (after R/county_panel_1880_1940.R, R/app_census_layers.R and R/holc_covenants.R, which fetches the
#                               Mapping Inequality crosswalk into work/holc)
# Same rules as the Denver analysis: Frickel & Elliott hazardous sectors only; the 13 complete manufacturers' directory editions;
# street-located sites only; one population minimum (200); fixed sets of tracts for anything compared over time.
#   1. Counties 1880-1940: share of the state's listed hazardous trades by region and census, and across counties the correlation of
#      trades per 1,000 residents with the foreign-born, Hispanic and laborer shares (each census's own counties).
#   2. Regions 1965-1992: share of located hazardous-sector manufacturers by region in each complete edition, against population shares.
#   3. Tracts 1980-2020, all of Colorado: the 1,159 tracts with 200+ residents in every census from 1990 (and 955 from 1980), regressing
#      each composition measure on the tract's log density of hazardous firms of the decade, with log population density and county
#      fixed effects (HC1), for the state and by region; 2000-2020 use the 1983-92 sites (legacy, as in Denver).
#   4. The other graded cities: Mapping Inequality has Pueblo's HOLC map (A-D) and local appraisal maps of Colorado Springs, Greeley,
#      Fort Collins, Grand Junction, Boulder, Longmont and Fort Morgan with their own grade names. Grades are put on one three-step
#      scale (best / middle / worst; business, industrial and fire districts kept apart) and, for each city, hazardous-sector
#      manufacturers per km2 per edition (1965-80, 1981-92) and tract location quotients by dominant grade, 1970-2020, are tabulated.
# Outputs: data/results/statewide/*.csv and statewide_summary.md; copies in app/data.
suppressPackageStartupMessages({ library(sf); library(data.table); library(sandwich); library(lmtest) })
sf_use_s2(FALSE); UTM <- 26913; O <- "data/results/statewide"; A <- "app/data"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
ED_OK <- c(1965:1968, 1970, 1973, 1974, 1977, 1980, 1983, 1988, 1990, 1992)
REG <- function(fips3) fcase(fips3 == "031", "Denver", fips3 %in% c("001", "005", "014", "035", "059"), "Denver suburbs",
                             fips3 == "041", "Colorado Springs (El Paso)", fips3 == "101", "Pueblo", fips3 %in% c("013", "069", "123"), "Boulder, Larimer, Weld",
                             fips3 == "077", "Grand Junction (Mesa)", default = "rest of Colorado")
# ---------------------------------------------------------------- 1. counties 1880-1940
CP <- fread("data/results/county_panel_1880_1940.csv", colClasses = c(fips = "character"))
CP[, fips3 := substr(fips, 3, 5)]
MINING <- c("065", "047", "019", "111", "091", "119", "117", "053", "093", "015", "113", "079")   # Lake, Gilpin, Clear Creek, San Juan, Ouray, Teller, Summit, Hinsdale, Park, Chaffee, San Miguel, Mineral
SOUTH <- c("021", "023", "055", "071", "105", "109", "003")                                     # Conejos, Costilla, Huerfano, Las Animas, Rio Grande, Saguache, Alamosa
# Arapahoe County held Denver only until 1902 (the 1880 and 1900 censuses); from 1910 Arapahoe is a suburban county and falls in "rest of Colorado"
CP[, region := fcase(fips3 == "031" | (fips3 == "005" & census <= 1900), "Denver (Arapahoe before 1902)", fips3 %in% MINING, "mining counties",
                     fips3 == "101", "Pueblo", fips3 %in% SOUTH, "southern Hispano counties", default = "rest of Colorado")]
R1 <- CP[!is.na(pop), .(trades = sum(firms_haz), pop = sum(pop)), by = .(census, region)][, `:=`(pct_trades = round(100 * trades / sum(trades), 1), pct_pop = round(100 * pop / sum(pop), 1)), by = census][order(census, region)]
fwrite(R1, file.path(O, "county_regions_1880_1940.csv"))
R1c <- CP[!is.na(pop) & pop >= 1000, { r <- function(v) round(cor(log1p(1000 * firms_haz / pop), get(v), use = "complete.obs"), 2)
  .(counties = .N, r_foreign_born = r("pct_fb"), r_hispanic = r("pct_hisp"), r_laborers = r("pct_laborers"), r_black = r("pct_black")) }, by = census]
fwrite(R1c, file.path(O, "county_correlations_1880_1940.csv"))
# ---------------------------------------------------------------- 2. regions 1965-1992
S <- fread(file.path(A, "sites.csv"), colClasses = c(GEOID = "character"))[fe_hazard %in% c(TRUE, "True") & !is.na(lat) & geo_level %in% c("address", "address_approx")]
SY <- fread(file.path(A, "site_years.csv"))[year %in% ED_OK]; SY <- merge(SY, S[, .(site_id, GEOID, lat, lon)], by = "site_id")
SY[, region := REG(substr(GEOID, 3, 5))]
pan <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character")); pan[, region := REG(substr(GEOID, 3, 5))]
pop90 <- pan[census == 1990 & !is.na(pop), .(pop1990 = sum(pop)), by = region][, pct_pop_1990 := round(100 * pop1990 / sum(pop1990), 1)]
R2 <- SY[, .(sites = uniqueN(site_id)), by = .(year, region)][, pct := round(100 * sites / sum(sites), 1), by = year]
R2w <- merge(dcast(R2, region ~ year, value.var = "pct", fill = 0), pop90[, .(region, pct_pop_1990)], by = "region")
fwrite(R2w, file.path(O, "regional_shares_1965_1992.csv"))
# ---------------------------------------------------------------- 3. tracts 1980-2020, all of Colorado
P <- pan[!is.na(pop) & pop >= 200]
fix90 <- P[census >= 1990, .N, by = GEOID][N == 4, GEOID]; fix80 <- P[census >= 1980, .N, by = GEOID][N == 5, GEOID]
P[, `:=`(lfirm = log1p(firms_haz / area_km2), ldens = log(pop / area_km2), county = substr(GEOID, 3, 5))]
OUT <- c(p_hisp = "% Hispanic", p_black = "% Black", p_white = "% White", p_fb = "% foreign born", p_pov = "% below poverty", p_owner = "% owner-occupied")
fitm <- function(d, v) { d <- d[!is.na(get(v))]; if (nrow(d) < 30 || uniqueN(d$lfirm) < 5) return(NULL)
  fo <- as.formula(paste(v, "~ lfirm + ldens", if (uniqueN(d$county) > 1) "+ factor(county)" else ""))
  m <- lm(fo, d, weights = pop); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1")); data.table(b = ct["lfirm", 1], se = ct["lfirm", 2], p = ct["lfirm", 4], tracts = nrow(d)) }
R3 <- rbindlist(lapply(list(list("tracts with data 1990-2020", fix90, 1990), list("tracts with data 1980-2020", fix80, 1980)), function(s)
  rbindlist(lapply(c("Colorado", unique(P$region)), function(rg) rbindlist(lapply(seq(s[[3]], 2020, 10), function(y) rbindlist(lapply(names(OUT), function(v) {
    d <- P[GEOID %in% s[[2]] & census == y & (rg == "Colorado" | region == rg)]; r <- fitm(d, v); if (is.null(r)) NULL else r[, `:=`(set = s[[1]], region = rg, census = y, outcome = OUT[[v]])] }))))))))
setcolorder(R3, c("set", "region", "outcome", "census")); fwrite(R3, file.path(O, "tract_associations_1980_2020.csv"))
# ---------------------------------------------------------------- 4. the other graded cities
X <- st_read("work/holc/mapping-inequality-census-crosswalk/MIv3Areas_2010TractCrosswalk.geojson", quiet = TRUE)
X <- X[X$state == "CO", ]; X$grade[is.na(X$grade)] <- ""
lab <- tolower(trimws(ifelse(nzchar(X$grade), X$grade, X$cat)))
X$step <- fcase(lab %in% c("a", "b") | grepl("^(1st|first|best|good)", lab), "best", lab == "c" | grepl("^(2nd|second|medium|fair)", lab), "middle",
                lab == "d" | grepl("^(3rd|third|4th|fourth|poor)", lab), "worst", default = "business, industrial or fire district")
X$step[X$city == "Pueblo" & X$grade == "B"] <- "middle"; X$step[X$city == "Pueblo" & X$grade == "A"] <- "best"   # Pueblo: A best, B-C middle, D worst
X$step[X$city == "Pueblo" & X$grade == "C"] <- "middle"
X <- st_make_valid(st_transform(X, UTM))
ar <- do.call(rbind, lapply(split(X, X$area_id), function(x) st_sf(area_id = x$area_id[1], city = x$city[1], step = x$step[1], label = x$label[1], geometry = st_union(st_geometry(x)))))
ar$km2 <- as.numeric(st_area(ar)) / 1e6
pts <- st_transform(st_as_sf(unique(SY[, .(site_id, year, lon, lat)]), coords = c("lon", "lat"), crs = 4326), UTM)
jn <- as.data.table(st_drop_geometry(st_join(pts, ar[, c("area_id", "city", "step")], left = FALSE)))
per <- function(y) fifelse(y <= 1980, "1965-1980", "1981-1992")
G4 <- as.data.table(st_drop_geometry(ar))[, .(areas = .N, km2 = sum(km2)), by = .(city, step)]
F4 <- jn[, .(listings = .N), by = .(city, step, period = per(year))]
ne <- c("1965-1980" = 9, "1981-1992" = 4)
R4 <- merge(G4, F4, by = c("city", "step"), all.x = TRUE)[is.na(listings), `:=`(listings = 0L, period = "1965-1980")]
R4 <- R4[, .(areas, km2 = round(km2, 2), period, firms_per_km2_per_edition = round(listings / ne[period] / km2, 3)), by = .(city, step)]
R4 <- dcast(R4, city + step + areas + km2 ~ period, value.var = "firms_per_km2_per_edition", fill = 0)
fwrite(R4, file.path(O, "graded_cities_firm_density.csv"))
xw <- as.data.table(st_drop_geometry(X))[, .(share = sum(pct_tract)), by = .(GEOID = GEOID10, city, step)]
dom <- xw[step != "business, industrial or fire district", .(step = step[which.max(share)], covered = sum(share)), by = .(GEOID, city)][covered >= 0.4]
TP <- merge(pan[!is.na(pop) & pop >= 200, .(GEOID, census, pop, p_hisp, p_black, p_pov)], dom, by = "GEOID")
TP <- TP[census >= 1970]
city_tot <- TP[, .(cH = weighted.mean(p_hisp, pop, na.rm = TRUE), cB = weighted.mean(p_black, pop, na.rm = TRUE), cP = weighted.mean(p_pov, pop, na.rm = TRUE)), by = .(city, census)]
R5 <- TP[, .(tracts = .N, pct_hisp = weighted.mean(p_hisp, pop, na.rm = TRUE), pct_black = weighted.mean(p_black, pop, na.rm = TRUE), pct_pov = weighted.mean(p_pov, pop, na.rm = TRUE)), by = .(city, step, census)]
R5 <- merge(R5, city_tot, by = c("city", "census"))[, `:=`(lq_hisp = round(pct_hisp / cH, 2), lq_black = round(pct_black / cB, 2), lq_poverty = round(pct_pov / cP, 2))][, c("cH", "cB", "cP") := NULL]
for (v in c("pct_hisp", "pct_black", "pct_pov")) set(R5, j = v, value = round(R5[[v]], 2)); setorder(R5, city, step, census)
fwrite(R5, file.path(O, "graded_cities_tract_lq_1970_2020.csv"))
file.copy(list.files(O, "\\.csv$", full.names = TRUE), A, overwrite = TRUE)
print(R1); print(R1c); print(R2w); print(R3[set == "tracts with data 1990-2020" & outcome %in% c("% Hispanic", "% below poverty", "% Black")][, .(region, outcome, census, b = round(b, 2), p = signif(p, 2), tracts)])
print(R4); print(R5[city != "Denver" & census %in% c(1970, 1990, 2020)])
