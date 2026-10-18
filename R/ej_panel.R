# How did environmental inequality develop in Denver? Tract panel of industrial presence x neighbourhood composition, after
# Marlow, Frickel & Elliott (2020, Sociological Forum 35:1097): a hybrid (within + between) spatial panel in which
#   change in % Black / % Hispanic / % foreign-born / % low income in a tract is related to
#   (a) change in ACTIVE manufacturing density in the tract (within-tract, fixed effects) and
#   (b) the tract's LEGACY density (sites listed in earlier directories but no longer active), which is time-invariant per panel.
# Then the reverse direction: does composition at t predict industrial entry between t and t+1?
#
#   Rscript R/ej_panel.R
#
# INPUTS: work/census/denver_tract_panel.csv and the 2010 tract shapefile, both written by Rscript R/fetch_census.R (NHGIS):
#   counts on 2010 tract boundaries - 1990-2020 population, race and Hispanic origin from NHGIS's standardised time series, everything
#   else (1970-1980 tables; 1990-2020 nativity, poverty and housing) area-weighted from each census's own tracts; shares are computed
#   after interpolation, foreign born and poverty over the universe of their own table. Study area: the 2010 tracts whose centroid is
#   within 10 km of downtown Denver (147 tracts; the same set as the app's "Denver core"), tract-years with at least 200 residents.
#
# Directory-census matching (complete editions only, config/editions.json): 1970 <- 1970 directory, 1980 <- 1980, 1990 <- 1990.
# There is no complete edition after 1992, so the within/between panel stops at 1990 (three censuses, the minimum for the design).
# The 2000, 2010 and 2020 censuses are analysed separately as legacy-site exposure: each tract's density of hazardous establishments
# listed 1983-1992 (the last complete decade, the window the app uses for 2000-2020), census by census (data/results/ej_panel_legacy_sites.csv).
# Exposure is hazardous establishments (SIC 28, 29, 30, 33, 34, 35, 37) throughout; all-manufacturer density is kept as a sensitivity. Study area: tracts within the City and County of Denver plus tracts of Adams/Arapahoe/Jefferson
# within 10 km of downtown (the historically industrial core), to avoid mixing suburbanisation with neighbourhood change.
suppressPackageStartupMessages({ library(sf); library(data.table); library(spdep); library(spatialreg); library(sandwich); library(lmtest) })
sf_use_s2(FALSE); UTM <- 26913; CDIR <- "work/census"
MATCH <- c("1970" = 1970, "1980" = 1980, "1990" = 1990); LATE <- c(2000L, 2010L, 2020L); LAST_WIN <- c(1983L, 1992L)
shp10 <- c(Sys.glob(file.path(CDIR, "*tract10*.shp")), Sys.glob(file.path(CDIR, "*tract_2010*.shp")))
nhgis_panel <- file.path(CDIR, "denver_tract_panel.csv")                      # written by R/fetch_census.R (NHGIS API)
if (!length(shp10) || !file.exists(nhgis_panel)) stop("Run Rscript R/fetch_census.R first (NHGIS API)")

# ---------------------------------------------------------------- tracts and study area
tr <- st_make_valid(st_transform(st_read(shp10[1], quiet = TRUE), UTM))
tr$GEOID <- if (any(grepl("GEOID", names(tr)))) tr[[grep("GEOID", names(tr), value = TRUE)[1]]] else sub("^G(\\d{2})0(\\d{3})0(\\d{6})$", "\\1\\2\\3", tr$GISJOIN)
DEN <- st_sfc(st_point(c(500250, 4399500)), crs = UTM)
tr$dist_km <- as.numeric(st_distance(st_centroid(st_geometry(tr)), DEN)) / 1000
tr <- tr[substr(tr$GEOID, 1, 2) == "08" & tr$dist_km <= 10, ]   # same rule as app_census_layers.R
message(nrow(tr), " tracts in the Denver core")

# ---------------------------------------------------------------- census panel (NHGIS, 2010 boundaries)
cen <- fread(nhgis_panel, colClasses = c(GEOID = "character"))[census %in% c(as.integer(names(MATCH)), LATE)]
cen <- cen[GEOID %in% tr$GEOID]
if (!"nhwht" %in% names(cen) && "white" %in% names(cen)) cen[, nhwht := white]   # NHGIS panel: race white (incl. most Hispanic residents before 1980); LTDB: non-Hispanic white
for (v in c("nhwht", "fb", "ppov", "fb_den", "ppov_den", "own", "rentocc", "mval_2020", "mrent_2020")) if (!v %in% names(cen)) set(cen, j = v, value = NA_real_)
cen[, `:=`(p_black = 100 * nhblk / pop, p_hisp = 100 * hisp / pop, p_white = 100 * nhwht / pop, p_fb = 100 * fb / fifelse(is.na(fb_den) | fb_den <= 0, pop, fb_den), p_owner = 100 * own / (own + rentocc),
           lmval = fifelse(is.finite(mval_2020) & mval_2020 > 0, log(mval_2020), NA_real_), lmrent = fifelse(is.finite(mrent_2020) & mrent_2020 > 0, log(mrent_2020), NA_real_))]
cen[, ppov := 100 * ppov / fifelse(is.na(ppov_den) | ppov_den <= 0, pop, ppov_den)]   # persons below poverty over the poverty universe (total population in 1970)

# ---------------------------------------------------------------- industrial presence per tract per census year
L <- fread("data/results/CO_directory_listings_1961-2002.csv", colClasses = c(sic = "character"))
L <- L[geo_level %in% c("address", "address_approx") & !is.na(lat)]
L[, haz := fe_hazard %in% c(TRUE, "True")]   # Frickel & Elliott hazardous sectors, the definition used everywhere
pts <- st_transform(st_as_sf(L, coords = c("lon", "lat"), crs = 4326), UTM)
wi <- st_within(pts, tr); L$GEOID <- tr$GEOID[sapply(wi, function(i) if (length(i)) i[1] else NA_integer_)]   # NA outside the core
L <- L[!is.na(GEOID)]
ind <- rbindlist(lapply(names(MATCH), function(y) { yr <- MATCH[[y]]
  act <- L[year == yr, .(active = uniqueN(estab_id), active_haz = uniqueN(estab_id[haz])), by = GEOID]
  leg <- L[year < yr, .(estab_id, GEOID, haz)]; leg <- leg[!estab_id %in% L[year == yr]$estab_id]
  leg <- unique(leg)[, .(legacy = .N, legacy_haz = sum(haz)), by = GEOID]
  merge(act, leg, by = "GEOID", all = TRUE)[, census := as.integer(y)] }), fill = TRUE)
cen_late <- cen[census %in% LATE]; cen <- cen[census %in% as.integer(names(MATCH))]
pan <- merge(cen, ind, by = c("GEOID", "census"), all.x = TRUE)
for (v in c("active", "active_haz", "legacy", "legacy_haz")) pan[is.na(get(v)), (v) := 0]
pan <- merge(pan, data.table(GEOID = tr$GEOID, area_km2 = as.numeric(st_area(tr)) / 1e6, dist_km = tr$dist_km), by = "GEOID")
pan[, `:=`(active_d = active_haz / area_km2, legacy_d = legacy_haz / area_km2, active_all_d = active / area_km2, legacy_all_d = legacy / area_km2, pop_d = pop / area_km2)]
pan <- pan[pop >= 200]
fwrite(pan, "data/results/ej_panel_denver.csv")

# ---------------------------------------------------------------- hybrid spatial panel (Marlow et al. 2020)
# within: tract-demeaned active density; between: tract mean active density and the 1970-era legacy density (time-invariant).
pan <- pan[order(GEOID, census)]
pan[, `:=`(act_w = log1p(active_d) - mean(log1p(active_d)), act_b = mean(log1p(active_d)), leg_b = log1p(legacy_d[census == min(census)])), by = GEOID]
pan[, popd_w := log1p(pop_d) - mean(log1p(pop_d)), by = GEOID]
tr_p <- tr[match(unique(pan$GEOID), tr$GEOID), ]
w <- nb2listw(poly2nb(tr_p, queen = TRUE), style = "W", zero.policy = TRUE)
res <- list()
OUTS <- c("p_black", "p_hisp", "p_white", "p_fb", "ppov", "p_owner", "lmval", "lmrent")
pan[, `:=`(actA_w = log1p(active_all_d) - mean(log1p(active_all_d)), actA_b = mean(log1p(active_all_d)), legA_b = log1p(legacy_all_d[census == min(census)])), by = GEOID]
for (yv in OUTS) { if (!yv %in% names(pan) || all(is.na(pan[[yv]])) || sum(!is.na(pan[[yv]])) < 60 || uniqueN(pan$census[!is.na(pan[[yv]])]) < 3) next   # needs at least three censuses for the within/between design
  d <- pan[!is.na(get(yv))]
  fo <- as.formula(paste(yv, "~ act_w + act_b + leg_b + popd_w + dist_km + factor(census)"))
  ols <- lm(fo, d)
  V <- sandwich::vcovCL(ols, cluster = d$GEOID)                    # tract-clustered SE for the pooled hybrid model
  cf <- lmtest::coeftest(ols, vcov. = V)
  # spatial dependence check and a spatial error fit on the cross-section of tract means (the between part)
  mt <- d[, .(y = mean(get(yv)), act_b = act_b[1], leg_b = leg_b[1], dist_km = dist_km[1]), by = GEOID]
  wm <- nb2listw(poly2nb(tr[match(mt$GEOID, tr$GEOID), ], queen = TRUE), style = "W", zero.policy = TRUE)
  sem <- errorsarlm(y ~ act_b + leg_b + dist_km, data = mt, listw = wm, zero.policy = TRUE); sc <- summary(sem)$Coef
  res[[yv]] <- rbind(data.table(outcome = yv, model = "hybrid panel, tract-clustered SE", term = rownames(cf)[2:4], b = cf[2:4, 1], se = cf[2:4, 2], p = cf[2:4, 4], n = nrow(d), tracts = uniqueN(d$GEOID)),
                     data.table(outcome = yv, model = sprintf("between tracts, spatial error (lambda %.2f)", sem$lambda), term = rownames(sc)[2:3], b = sc[2:3, 1], se = sc[2:3, 2], p = sc[2:3, 4], n = nrow(mt), tracts = nrow(mt)))
  # sensitivity: all manufacturers instead of hazardous sectors
  oA <- lm(as.formula(paste(yv, "~ actA_w + actA_b + legA_b + popd_w + dist_km + factor(census)")), d); cA <- lmtest::coeftest(oA, vcov. = sandwich::vcovCL(oA, cluster = d$GEOID))
  res[[paste0(yv, "_all")]] <- data.table(outcome = yv, model = "sensitivity: all manufacturers, tract-clustered SE", term = c("act_w", "act_b", "leg_b"), b = cA[2:4, 1], se = cA[2:4, 2], p = cA[2:4, 4], n = nrow(d), tracts = uniqueN(d$GEOID))
}
R1 <- rbindlist(res); fwrite(R1, "data/results/ej_panel_models.csv")
# the same within/between associations census by census (the pooled coefficients above average over 1970-2010)
res_d <- list()
for (yv in OUTS) for (cy in sort(unique(pan$census))) { d <- pan[!is.na(get(yv)) & census == cy]; if (nrow(d) < 40 || sd(d$act_w) == 0) next
  ols <- lm(as.formula(paste(yv, "~ act_w + act_b + leg_b + popd_w + dist_km")), d); cf <- lmtest::coeftest(ols, vcov. = sandwich::vcovHC(ols, type = "HC1"))
  res_d[[length(res_d) + 1]] <- data.table(outcome = yv, census = cy, term = rownames(cf)[2:4], b = cf[2:4, 1], se = cf[2:4, 2], p = cf[2:4, 4], tracts = nrow(d)) }
fwrite(rbindlist(res_d), "data/results/ej_panel_by_decade.csv")
# reverse direction: does composition at t predict new industrial entry by t+1?
pan[, `:=`(entry_next = data.table::shift(active_haz, -1) - active_haz), by = GEOID]   # net change in active hazardous establishments by the next census
R2 <- rbindlist(lapply(OUTS, function(xv) { if (!xv %in% names(pan) || all(is.na(pan[[xv]])) || sum(!is.na(pan[[xv]])) < 60 || uniqueN(pan$census[!is.na(pan[[xv]])]) < 3) return(NULL)
  d <- pan[!is.na(entry_next) & !is.na(get(xv))]; m <- lm(as.formula(paste("entry_next ~", xv, "+ log1p(active_d) + popd_w + dist_km + factor(census)")), d)
  cf <- summary(m)$coefficients; data.table(predictor = xv, b = cf[2, 1], se = cf[2, 2], p = cf[2, 4], n = nrow(d)) }))
fwrite(R2, "data/results/ej_panel_reverse.csv")

# ---------------------------------------------------------------- 2000-2020: legacy-site exposure (no complete directory after 1992)
# density of hazardous establishments listed in 1983-1992 per tract; cross-sectional association with each later census, HC1 SE.
LW <- L[year >= LAST_WIN[1] & year <= LAST_WIN[2] & haz == TRUE, .(late_haz = uniqueN(estab_id)), by = GEOID]
pl <- merge(cen_late, LW, by = "GEOID", all.x = TRUE)[is.na(late_haz), late_haz := 0]
pl <- merge(pl, data.table(GEOID = tr$GEOID, area_km2 = as.numeric(st_area(tr)) / 1e6, dist_km = tr$dist_km), by = "GEOID")[pop >= 200]
pl[, `:=`(late_d = late_haz / area_km2, pop_d = pop / area_km2)]
R3 <- rbindlist(lapply(OUTS, function(yv) rbindlist(lapply(LATE, function(cy) { d <- pl[census == cy & !is.na(get(yv))]; if (nrow(d) < 40) return(NULL)
  m <- lm(as.formula(paste(yv, "~ log1p(late_d) + log1p(pop_d) + dist_km")), d); cf <- lmtest::coeftest(m, vcov. = sandwich::vcovHC(m, type = "HC1"))
  data.table(outcome = yv, census = cy, term = "log hazardous density 1983-1992", b = cf[2, 1], se = cf[2, 2], p = cf[2, 4], tracts = nrow(d)) }))))
fwrite(R3, "data/results/ej_panel_legacy_sites.csv"); print(R3)
file.copy(file.path("data/results", c("ej_panel_models.csv", "ej_panel_reverse.csv", "ej_panel_by_decade.csv", "ej_panel_legacy_sites.csv")), "app/data", overwrite = TRUE)
print(R1); print(R2)
message("Note: 2010 and 2020 nativity and poverty are ACS 5-year estimates (2008-12, 2016-20) with sampling error.")
