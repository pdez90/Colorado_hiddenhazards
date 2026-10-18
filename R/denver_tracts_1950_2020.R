# Denver after the full count: the district analyses of 1880-1940 carried forward on census tracts, 1950-2020.
#   Rscript R/denver_tracts_1950_2020.R      (after app_census_layers.R, which writes app/data/tract_panel.csv)
# Microdata are sealed for 72 years, so after 1940 (1950 is released but Brown's address files stop at 1940) the finest public unit is
# the tract. For the 147 tracts of the Denver core (2010 tracts within 10 km of downtown; earlier censuses interpolated, see
# fetch_census.R; tract-years with at least 200 residents) and each
# census 1950-2020 this script computes, exactly as denver_eds_analysis.R does for districts:
#   - the hazardous firms of the decade ending at the census (business-directory trades to 1960, manufacturers' directory sites from
#     1970 from the complete editions only; 2000, 2010 and 2020 use the last complete directory decade, 1983-1992) and each tract's
#     distance to the nearest one;
#   - composition of tracts with vs without a firm, and the dissimilarity index;
#   - population-weighted regressions of each measure on log distance (HC1 SE);
#   - the share of the decade's firms in the tracts housing the top population quartile on each measure;
#   - the same models on FIXED sets of tracts (tracts with population and a Black share in every census from 1950, 1960 or 1970), because
#     the tracted area grows (only the city of Denver in 1940-50, 164 core tracts with data in 1960, ~180 from 1970), so the all-tract
#     series compares different places across censuses. Written to denver_tracts_models_fixed.csv and denver_tracts_shares_fixed.csv.
# Outputs: data/results/denver_tracts/{denver_tracts_models.csv, denver_tracts_shares.csv, denver_tracts_groups.csv} and app/data/
#   denver_tracts.geojson (+ the three csvs), read by the Denver tab for 1950-2020.
suppressPackageStartupMessages({ library(sf); library(data.table); library(sandwich); library(lmtest) })
sf_use_s2(FALSE); UTM <- 26913; A <- "app/data"; O <- "data/results/denver_tracts"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
TR <- st_make_valid(st_transform(st_read(file.path(A, "co_tracts_2010.geojson"), quiet = TRUE), UTM)); TR <- TR[TR$core %in% c(TRUE, "TRUE"), c("GEOID")]
pan <- fread(file.path(A, "tract_panel.csv"), colClasses = c(GEOID = "character"))[GEOID %in% TR$GEOID & census >= 1950]; if (!"p_white" %in% names(pan)) pan[, p_white := NA_real_]
MEAS <- c(p_white = "White % (race)", p_black = "Black %", p_hisp = "Hispanic %", p_fb = "Foreign born %", p_pov = "Below poverty %", p_owner = "Owner-occupied %", mval_2020 = "Median home value (2020 $)", mrent_2020 = "Median rent (2020 $)")
# firms of the decade
hist <- fread(file.path(A, "historical_sites.csv"))[precision != "town" & !is.na(lat) & fe_hazard %in% c(TRUE, "True")]
sites <- fread(file.path(A, "sites.csv"))[!is.na(lat) & fe_hazard %in% c(TRUE, "True")]
pt <- function(d) st_transform(st_as_sf(d, coords = c("lon", "lat"), crs = 4326), UTM)
WIN <- list("1950" = c(1941, 1950), "1960" = c(1951, 1960), "1970" = c(1961, 1970), "1980" = c(1971, 1980), "1990" = c(1981, 1990), "2000" = c(1983, 1992), "2010" = c(1983, 1992), "2020" = c(1983, 1992))
firms_of <- function(y) { a <- WIN[[as.character(y)]]; if (y <= 1960) pt(hist[first_year <= a[2] & last_year >= a[1], .(lon, lat, name, years = years, sector = sectors)]) else pt(sites[first_year <= a[2] & last_year >= a[1], .(lon, lat, name = address, years = paste(first_year, last_year, sep = "-"), sector = fe_sectors)]) }
ctr <- st_centroid(st_geometry(TR)); CBD <- st_sfc(st_point(c(500250, 4399500)), crs = UTM)   # downtown point used in every script
analyse <- function(pan) {
res <- lapply(names(WIN), function(yc) { y <- as.integer(yc); f <- firms_of(y); if (!nrow(f)) return(NULL)
  d <- pan[census == y]; d <- merge(data.table(GEOID = TR$GEOID, idx = seq_len(nrow(TR))), d, by = "GEOID")
  d$firms <- lengths(st_intersects(TR, f))[d$idx]; d$dist_m <- as.numeric(st_distance(ctr[d$idx], st_union(f))); d$dist_cbd <- pmax(as.numeric(st_distance(ctr[d$idx], CBD)), 100)
  d <- d[!is.na(pop) & pop >= 200]; d[, has := firms > 0]
  # groups
  wm <- function(x, w) if (all(is.na(x))) NA_real_ else weighted.mean(x, w, na.rm = TRUE)
  G <- d[, .(group = ifelse(has[1], "Tracts with hazardous firms", "Tracts without"), EDs = .N, population = sum(pop)), by = has][order(-has)]
  for (m in names(MEAS)) G[[m]] <- d[, .(v = wm(get(m), pop)), by = has][order(-has)]$v
  G[, has := NULL]
  bl <- d[!is.na(p_black)]; dis <- if (nrow(bl)) { b <- bl$p_black / 100 * bl$pop; o <- bl$pop - b; 0.5 * sum(abs(b / sum(b) - o / sum(o))) } else NA_real_
  G <- rbind(G, data.table(group = "dissimilarity (all tracts)", EDs = nrow(d), population = sum(d$pop), p_black = round(dis, 3)), fill = TRUE); G[, census := y]
  # distance models
  M <- rbindlist(lapply(names(MEAS), function(m) { dd <- d[!is.na(get(m)) & dist_m > 0]; if (nrow(dd) < 20 || sd(dd[[m]]) == 0) return(NULL)
    dd$y <- dd[[m]]; if (m %in% c("mval_2020", "mrent_2020")) dd$y <- log(dd$y); dd <- dd[is.finite(y)]; if (nrow(dd) < 20 || sd(dd$y) == 0) return(NULL)
    fit <- lm(y ~ log(dist_m), dd, weights = pop); ct <- coeftest(fit, vcov. = vcovHC(fit, type = "HC1"))
    fit2 <- lm(y ~ log(dist_m) + log(dist_cbd), dd, weights = pop); c2 <- coeftest(fit2, vcov. = vcovHC(fit2, type = "HC1"))   # nearness to firms vs nearness to the centre
    data.table(census = y, outcome = if (m %in% c("mval_2020", "mrent_2020")) paste0("log_", m) else m, b_per_log_m = ct[2, 1], se = ct[2, 2], p = ct[2, 4], EDs = nrow(dd), firms = nrow(f),
               b_cbd_ctrl = c2[2, 1], se_cbd_ctrl = c2[2, 2], p_cbd_ctrl = c2[2, 4]) }))
  # shares in the top population quartile
  S <- rbindlist(lapply(names(MEAS), function(m) { dd <- d[!is.na(get(m))][order(-get(m))]; if (nrow(dd) < 8) return(NULL); cp <- cumsum(dd$pop) / sum(dd$pop); top <- cp <= 0.25 | seq_len(nrow(dd)) == 1
    dd2 <- dd[order(get(m))]; cp2 <- cumsum(dd2$pop) / sum(dd2$pop); bot <- cp2 <= 0.25 | seq_len(nrow(dd2)) == 1
    data.table(census = y, measure = m, firms = sum(dd$firms), share_firms_top_quartile = round(100 * sum(dd$firms[top]) / max(sum(dd$firms), 1), 1), share_firms_bottom_quartile = round(100 * sum(dd2$firms[bot]) / max(sum(dd$firms), 1), 1), share_pop_top_quartile = round(100 * sum(dd$pop[top]) / sum(dd$pop), 1)) }))
  list(G = G, M = M, S = S, D = d[, c("GEOID", "census", "pop", names(MEAS), "firms", "dist_m"), with = FALSE]) })
res <- Filter(Negate(is.null), res)
G <- rbindlist(lapply(res, `[[`, "G"), fill = TRUE); M <- rbindlist(lapply(res, `[[`, "M")); S <- rbindlist(lapply(res, `[[`, "S")); D <- rbindlist(lapply(res, `[[`, "D"))
# pooled model with census effects
P <- rbindlist(lapply(names(MEAS), function(m) { dd <- D[!is.na(get(m)) & dist_m > 0]; dd$y <- dd[[m]]; if (m %in% c("mval_2020", "mrent_2020")) dd$y <- log(dd$y); if (nrow(dd) < 40) return(NULL)
  dd <- dd[is.finite(y)]; if (nrow(dd) < 40) return(NULL); fit <- lm(y ~ log(dist_m) + factor(census), dd, weights = pop); ct <- coeftest(fit, vcov. = vcovHC(fit, type = "HC1"))
  data.table(census = 0L, outcome = if (m %in% c("mval_2020", "mrent_2020")) paste0("log_", m) else m, b_per_log_m = ct[2, 1], se = ct[2, 2], p = ct[2, 4], EDs = nrow(dd), firms = NA_integer_) }))
M <- rbind(M, P, fill = TRUE)
list(G = G, M = M, S = S, D = D) }
out <- analyse(pan); G <- out$G; M <- out$M; S <- out$S; D <- out$D
for (k in names(MEAS)) G[[k]] <- round(G[[k]], 2)
fwrite(M, file.path(O, "denver_tracts_models.csv")); fwrite(S, file.path(O, "denver_tracts_shares.csv")); fwrite(G, file.path(O, "denver_tracts_groups.csv"))
file.copy(file.path(O, c("denver_tracts_models.csv", "denver_tracts_shares.csv", "denver_tracts_groups.csv")), A, overwrite = TRUE)
GJ <- merge(TR, D, by = "GEOID"); GJ$dist_m <- round(GJ$dist_m); f <- file.path(A, "denver_tracts.geojson"); if (file.exists(f)) file.remove(f)
st_write(st_transform(st_simplify(GJ, dTolerance = 15), 4326), f, quiet = TRUE)
message("wrote ", f, ": ", nrow(GJ), " tract-censuses, ", uniqueN(D$census), " censuses")
print(dcast(M[census > 0, .(census, outcome, b = round(b_per_log_m, 2))], outcome ~ census, value.var = "b"))
print(dcast(S[, .(census, measure, share_firms_top_quartile)], measure ~ census, value.var = "share_firms_top_quartile"))
# fixed tract sets
FX <- lapply(c(1950L, 1960L, 1970L), function(y0) { p0 <- pan[census >= y0]
  keep <- p0[!is.na(pop) & pop >= 200 & !is.na(p_black), .N, by = GEOID][N == uniqueN(p0$census)]$GEOID
  o <- analyse(p0[GEOID %in% keep]); lab <- sprintf("fixed %d-2020 (%d tracts)", y0, length(keep))
  list(M = o$M[, set := lab], S = o$S[, set := lab]) })
MF <- rbindlist(lapply(FX, `[[`, "M")); SF <- rbindlist(lapply(FX, `[[`, "S"))
fwrite(MF, file.path(O, "denver_tracts_models_fixed.csv")); fwrite(SF, file.path(O, "denver_tracts_shares_fixed.csv"))
file.copy(file.path(O, c("denver_tracts_models_fixed.csv", "denver_tracts_shares_fixed.csv")), A, overwrite = TRUE)
print(dcast(MF[census > 0 & outcome %in% c("p_hisp", "p_black", "p_white"), .(set, outcome, census, b = round(b_per_log_m, 2))], set + outcome ~ census, value.var = "b"))
