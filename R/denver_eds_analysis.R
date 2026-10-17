# Denver 1880-1940 by enumeration district: who lived in the districts with hazardous trades?
#   Rscript R/denver_eds_analysis.R        (after R/grf_eds.R or pipeline/historical/grf_eds.py, and R/denver_1880.R)
# For every census: the reconstructed ED polygons (data/results/denver_eds/) with the IPUMS full-count composition, the hazardous-trade
# firms of the preceding decade placed inside them (1878-85 firms on Brown's 1880 grid for 1880; street-level pre-1960 directory firms
# listed in [year-9, year] for 1900-1940), and each ED centroid's distance to the nearest firm. Then
#   * EDs with vs without a firm (population-weighted composition) and the dissimilarity index across EDs,
#   * ED-level models: share ~ log distance to the nearest firm, weighted by population, per census and pooled with census effects.
# Outputs: data/results/denver_eds/{ed_year_groups.csv, ed_distance_models.csv, denver_eds_summary.md} and the app layers
#   app/data/denver_eds.geojson (all years) + app/data/denver_eds_firms.csv.
suppressPackageStartupMessages({ library(sf); library(data.table); library(sandwich); library(lmtest) })
sf_use_s2(FALSE); UTM <- 26913; O <- "data/results/denver_eds"; A <- "app/data"
hist <- fread("app/data/historical_sites.csv")[precision != "town" & !is.na(lat) & town == "DENVER"]
hp <- st_transform(st_as_sf(hist[, .(hfirm, name, first_year, last_year, sectors, lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)
f80 <- fread("data/results/denver_1880/firms_1878_1885_placed.csv")[how != "street only"]
all_E <- list(); all_F <- list(); groups <- list(); models <- list()
for (yr in c(1880, 1900, 1910, 1920, 1930, 1940)) {
  f <- file.path(O, sprintf("denver_eds_%d.geojson", yr)); if (!file.exists(f)) { message(yr, ": no ED polygons yet"); next }
  E <- st_transform(st_read(f, quiet = TRUE), UTM); E <- E[!is.na(E$pop) & E$pop > 0, ]
  Fp <- if (yr == 1880) st_as_sf(f80[, .(name, sector, year, x, y)], coords = c("x", "y"), crs = UTM) else {
    h <- hp[hp$first_year <= yr & hp$last_year >= yr - 9, ]; st_sf(name = h$name, sector = h$sectors, year = h$first_year, geometry = st_geometry(h)) }
  w <- st_within(Fp, E); k <- unlist(w); E$firms <- 0L; if (length(k)) { tf <- table(k); E$firms[as.integer(names(tf))] <- as.integer(tf) }
  ctr <- st_centroid(st_geometry(E)); E$dist_m <- if (nrow(Fp)) as.numeric(apply(st_distance(ctr, Fp), 1, min)) else NA_real_
  E$pct_black <- 100 * E$black / E$pop; E$pct_fb <- 100 * E$fb / E$pop; E$pct_fb_mexico <- 100 * E$fb_mexico / E$pop; E$pct_hisp <- 100 * E$hisp / E$pop
  E$pct_laborers <- 100 * E$laborers / E$pop; E$pct_foreign_parentage <- 100 * E$foreign_parentage / E$pop
  d <- as.data.table(st_drop_geometry(E))
  dis <- function(a, b) 0.5 * sum(abs(a / sum(a) - b / sum(b)))
  g <- d[, .(EDs = .N, population = sum(pop), pct_black = weighted.mean(pct_black, pop), pct_fb = weighted.mean(pct_fb, pop), pct_fb_mexico = weighted.mean(pct_fb_mexico, pop),
             pct_hisp = weighted.mean(pct_hisp, pop), pct_laborers = weighted.mean(pct_laborers, pop)), by = .(group = fifelse(firms > 0, "EDs with hazardous firms", "EDs without"))][, census := yr]
  g <- rbind(g, data.table(group = "dissimilarity (all mapped EDs)", EDs = nrow(d), population = sum(d$pop), pct_black = dis(d$black, d$pop - d$black), pct_fb = dis(d$fb, d$pop - d$fb),
                           pct_fb_mexico = dis(d$fb_mexico, d$pop - d$fb_mexico), pct_hisp = dis(d$hisp, d$pop - d$hisp), pct_laborers = dis(d$laborers, d$pop - d$laborers), census = yr))
  groups[[length(groups) + 1]] <- g
  if (nrow(Fp) >= 3) for (v in c("pct_black", "pct_fb", "pct_fb_mexico", "pct_hisp", "pct_laborers")) {
    m <- lm(as.formula(paste(v, "~ log(dist_m + 50)")), d, weights = pop); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1"))
    models[[length(models) + 1]] <- data.table(census = yr, outcome = v, b_per_log_m = ct[2, 1], se = ct[2, 2], p = ct[2, 4], EDs = nrow(d), firms = nrow(Fp)) }
  d[, census := yr]; all_E[[length(all_E) + 1]] <- E
  if (nrow(Fp)) { ll <- st_coordinates(st_transform(Fp, 4326)); all_F[[length(all_F) + 1]] <- data.table(census = yr, name = Fp$name, sector = Fp$sector, listed = Fp$year, lon = round(ll[, 1], 5), lat = round(ll[, 2], 5)) }
  message(yr, ": ", nrow(E), " EDs with population, ", nrow(Fp), " firms (", sum(E$firms > 0), " EDs with a firm)")
}
if (!length(all_E)) stop("no ED polygons in data/results/denver_eds/ - run Rscript R/grf_eds.R first")
G <- rbindlist(groups); M <- rbindlist(models)
# pooled: census fixed effects, ED-clustered SE not needed (one obs per ED-year); HC1
D <- rbindlist(lapply(all_E, function(E) as.data.table(st_drop_geometry(E))[, .(census = year, ED, pop, dist_m, pct_black, pct_fb, pct_fb_mexico, pct_hisp, pct_laborers)]))
for (v in c("pct_black", "pct_fb", "pct_fb_mexico", "pct_hisp", "pct_laborers")) { dd <- D[!is.na(dist_m) & !is.na(get(v))]
  m <- lm(as.formula(paste(v, "~ log(dist_m + 50) + factor(census)")), dd, weights = pop); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1"))
  M <- rbind(M, data.table(census = 0L, outcome = v, b_per_log_m = ct[2, 1], se = ct[2, 2], p = ct[2, 4], EDs = nrow(dd), firms = NA_integer_)) }
fwrite(G, file.path(O, "ed_year_groups.csv")); fwrite(M, file.path(O, "ed_distance_models.csv"))
# app layers
GE <- do.call(rbind, lapply(all_E, function(E) st_transform(st_simplify(E[, c("year", "ED", "pop", "firms", "dist_m", "pct_black", "pct_fb", "pct_fb_mexico", "pct_hisp", "pct_laborers", "pct_foreign_parentage", "addresses", "persons_geocoded", "area_km2")], dTolerance = 8), 4326)))
for (v in c("pct_black", "pct_fb", "pct_fb_mexico", "pct_hisp", "pct_laborers", "pct_foreign_parentage", "area_km2")) GE[[v]] <- round(GE[[v]], 2); GE$dist_m <- round(GE$dist_m)
f <- file.path(A, "denver_eds.geojson"); if (file.exists(f)) file.remove(f); st_write(GE, f, quiet = TRUE); fwrite(rbindlist(all_F), file.path(A, "denver_eds_firms.csv"))
file.copy(file.path(O, c("ed_year_groups.csv", "ed_distance_models.csv")), A, overwrite = TRUE)
md <- c("# Denver 1880-1940 by enumeration district", "", "## EDs with vs without a hazardous-trade firm (population-weighted %), and dissimilarity across EDs", "",
        "| census | group | EDs | population | % Black | % foreign born | % Mexican-born | % Hispanic | % laborers |", "|---|---|---|---|---|---|---|---|---|",
        sprintf("| %d | %s | %d | %s | %.2f | %.1f | %.2f | %.2f | %.1f |", G$census, G$group, G$EDs, format(G$population, big.mark = ","), G$pct_black, G$pct_fb, G$pct_fb_mexico, G$pct_hisp, G$pct_laborers), "",
        "## ED-level models: percentage points per log-metre of distance from the ED centroid to the nearest hazardous firm (pop-weighted, HC1 SE; census 0 = pooled with census effects)", "",
        "| census | outcome | b | SE | p | EDs | firms |", "|---|---|---|---|---|---|---|",
        sprintf("| %s | %s | %.3f | %.3f | %.3g | %d | %s |", ifelse(M$census == 0, "pooled", M$census), M$outcome, M$b_per_log_m, M$se, M$p, M$EDs, ifelse(is.na(M$firms), "", M$firms)))
writeLines(md, file.path(O, "denver_eds_summary.md")); cat(md, sep = "\n")
