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
# derived measures: name = c(numerator, denominator); computed where the IPUMS aggregation (R/fetch_ipums_fullcount.R) provides both
MEAS <- list(pct_black = c("black", "pop"), pct_white = c("white", "pop"), pct_fb = c("fb", "pop"), pct_fb_mexico = c("fb_mexico", "pop"), pct_fb_europe = c("fb_europe", "pop"),
             pct_fb_asia = c("fb_asia", "pop"), pct_fb_canada = c("fb_canada", "pop"), pct_hisp = c("hisp", "pop"), pct_foreign_parentage = c("foreign_parentage", "pop"),
             pct_laborers = c("laborers", "pop"), pct_recent_immig = c("recent_immig", "pop"), pct_naturalized = c("naturalized", "fb"), pct_noncitizen = c("noncitizen", "fb"),
             pct_mt_spanish = c("mt_spanish", "pop"), pct_mt_german = c("mt_german", "pop"), pct_mt_italian = c("mt_italian", "pop"), pct_no_english = c("no_english", "pop"),
             pct_children = c("children", "pop"), pct_aged = c("aged", "pop"), pct_male = c("males", "pop"), pct_married = c("married", "adults15"),
             pct_illiterate = c("illiterate", "lit_universe"), pct_in_school = c("in_school", "school_universe"), pct_hs_grad = c("hs_grad", "educ_universe"),
             pct_unemployed = c("unemployed", "in_labforce"), pct_haz_industry = c("haz_industry", "employed"), pct_manufacturing = c("manufacturing", "employed"), pct_railroad = c("railroad", "employed"),
             pct_owner_hh = c("owner_hh", "tenure_hh"), pct_mortgaged = c("mortgaged_hh", "owner_hh"), pct_radio = c("radio_hh", "radio_universe"), pct_boarders = c("boarders", "pop"),
             pct_group_quarters = c("group_quarters", "pop"), pct_movers = c("movers", "mover_universe"), pct_movers_other_state = c("movers_other_state", "mover_universe"),
             pct_veterans = c("veterans", "adults"), children_per_mother = c("children_ever_born", "mothers"))
AVG <- c("mean_sei", "mean_occscore", "median_wage", "median_value", "median_rent")
derive <- function(E) { for (k in c(unique(unlist(MEAS)), AVG)) if (k %in% names(E)) E[[k]] <- as.numeric(E[[k]])   # GeoJSON turns all-NA columns into logicals
  for (m in names(MEAS)) { n <- MEAS[[m]][1]; d <- MEAS[[m]][2]
    E[[m]] <- if (all(c(n, d) %in% names(E))) { v <- (if (grepl("^pct_", m)) 100 else 1) * E[[n]] / E[[d]]; v[!is.finite(v) | E[[d]] < 20] <- NA_real_; v } else NA_real_ }
  for (a in AVG) if (!a %in% names(E)) E[[a]] <- NA_real_; E }
CORE <- c("pct_black", "pct_fb", "pct_fb_mexico", "pct_hisp", "pct_laborers"); EXTRA <- c("pct_owner_hh", "median_rent", "mean_sei", "pct_haz_industry", "pct_recent_immig", "pct_movers", "pct_illiterate", "pct_boarders")
sf_use_s2(FALSE); UTM <- 26913; O <- "data/results/denver_eds"; A <- "app/data"
hist <- fread("app/data/historical_sites.csv")[precision != "town" & !is.na(lat) & town == "DENVER"]
hp <- st_transform(st_as_sf(hist[, .(hfirm, name, first_year, last_year, sectors, lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)
f80 <- fread("data/results/denver_1880/firms_1878_1885_placed.csv")[how != "street only"]
all_E <- list(); all_F <- list(); groups <- list(); models <- list(); shares <- list()
for (yr in c(1880, 1900, 1910, 1920, 1930, 1940)) {
  f <- file.path(O, sprintf("denver_eds_%d.geojson", yr)); if (!file.exists(f)) { message(yr, ": no ED polygons yet"); next }
  E <- st_transform(st_read(f, quiet = TRUE), UTM); E <- E[!is.na(E$pop) & E$pop > 0, ]
  Fp <- if (yr == 1880) st_as_sf(f80[, .(name, sector, year, x, y)], coords = c("x", "y"), crs = UTM) else {
    h <- hp[hp$first_year <= yr & hp$last_year >= yr - 9, ]; st_sf(name = h$name, sector = h$sectors, year = h$first_year, geometry = st_geometry(h)) }
  w <- st_within(Fp, E); k <- unlist(w); E$firms <- 0L; if (length(k)) { tf <- table(k); E$firms[as.integer(names(tf))] <- as.integer(tf) }
  ctr <- st_centroid(st_geometry(E)); E$dist_m <- if (nrow(Fp)) as.numeric(apply(st_distance(ctr, Fp), 1, min)) else NA_real_
  E <- derive(E); d <- as.data.table(st_drop_geometry(E))
  dis <- function(a, b) 0.5 * sum(abs(a / sum(a) - b / sum(b)))
  wm <- function(v, w) { ok <- !is.na(v); if (!any(ok)) NA_real_ else weighted.mean(v[ok], w[ok]) }
  GV <- c(CORE, EXTRA)
  g <- d[, c(list(EDs = .N, population = sum(pop)), lapply(.SD, wm, w = pop)), by = .(group = fifelse(firms > 0, "EDs with hazardous firms", "EDs without")), .SDcols = GV][, census := yr]
  dd <- as.list(c(EDs = nrow(d), population = sum(d$pop), pct_black = dis(d$black, d$pop - d$black), pct_fb = dis(d$fb, d$pop - d$fb), pct_fb_mexico = dis(d$fb_mexico, d$pop - d$fb_mexico),
                  pct_hisp = dis(d$hisp, d$pop - d$hisp), pct_laborers = dis(d$laborers, d$pop - d$laborers)))
  for (v in EXTRA) dd[[v]] <- NA_real_
  g <- rbind(g, data.table(group = "dissimilarity (all mapped EDs)", as.data.table(dd), census = yr), fill = TRUE)
  groups[[length(groups) + 1]] <- g
  if (nrow(Fp) >= 3) for (v in c(CORE, EXTRA)) { if (sum(!is.na(d[[v]])) < 10) next
    m <- lm(as.formula(paste(v, "~ log(dist_m + 50)")), d[!is.na(get(v))], weights = pop); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1"))
    models[[length(models) + 1]] <- data.table(census = yr, outcome = v, b_per_log_m = ct[2, 1], se = ct[2, 2], p = ct[2, 4], EDs = nrow(d), firms = nrow(Fp)) }
  # where were the firms? share of the decade's firms in the districts that make up the top population quartile on each measure (25% = proportional)
  for (v in c(CORE, "pct_owner_hh", "median_rent", "mean_sei")) { if (sum(!is.na(d[[v]])) < 10 || sum(d$firms) == 0) next
    o <- d[!is.na(get(v))][order(-get(v))]; o[, cum := cumsum(pop) / sum(pop)]; top <- o$ED[o$cum <= 0.25 | seq_len(nrow(o)) == 1]; bot <- rev(o$ED)[cumsum(rev(o$pop)) / sum(o$pop) <= 0.25]
    shares[[length(shares) + 1]] <- data.table(census = yr, measure = v, firms = sum(d$firms), share_firms_top_quartile = round(100 * sum(d$firms[d$ED %in% top]) / sum(d$firms), 1),
                                               share_firms_bottom_quartile = round(100 * sum(d$firms[d$ED %in% bot]) / sum(d$firms), 1), share_pop_top_quartile = round(100 * sum(d$pop[d$ED %in% top]) / sum(d$pop), 1)) }
  d[, census := yr]; all_E[[length(all_E) + 1]] <- E
  if (nrow(Fp)) { ll <- st_coordinates(st_transform(Fp, 4326)); all_F[[length(all_F) + 1]] <- data.table(census = yr, name = Fp$name, sector = Fp$sector, listed = Fp$year, lon = round(ll[, 1], 5), lat = round(ll[, 2], 5)) }
  message(yr, ": ", nrow(E), " EDs with population, ", nrow(Fp), " firms (", sum(E$firms > 0), " EDs with a firm)")
}
if (!length(all_E)) stop("no ED polygons in data/results/denver_eds/ - run Rscript R/grf_eds.R first")
G <- rbindlist(groups); M <- rbindlist(models)
# pooled: census fixed effects, ED-clustered SE not needed (one obs per ED-year); HC1
D <- rbindlist(lapply(all_E, function(E) as.data.table(st_drop_geometry(E))[, c("year", "ED", "pop", "dist_m", CORE, EXTRA), with = FALSE][, census := year]))
for (v in c(CORE, EXTRA)) { dd <- D[!is.na(dist_m) & !is.na(get(v))]; if (nrow(dd) < 30) next
  fml <- if (uniqueN(dd$census) > 1) paste(v, "~ log(dist_m + 50) + factor(census)") else paste(v, "~ log(dist_m + 50)")   # measures a single census provides (e.g. 1935 residence) get no census effects
  m <- lm(as.formula(fml), dd, weights = pop); ct <- coeftest(m, vcov. = vcovHC(m, type = "HC1"))
  M <- rbind(M, data.table(census = 0L, outcome = v, b_per_log_m = ct[2, 1], se = ct[2, 2], p = ct[2, 4], EDs = nrow(dd), firms = NA_integer_)) }
fwrite(G, file.path(O, "ed_year_groups.csv")); fwrite(M, file.path(O, "ed_distance_models.csv")); S <- rbindlist(shares); fwrite(S, file.path(O, "ed_firm_shares.csv")); file.copy(file.path(O, "ed_firm_shares.csv"), A, overwrite = TRUE)
# app layers
KEEP <- c("year", "ED", "pop", "households", "firms", "dist_m", names(MEAS), AVG, "addresses", "persons_geocoded", "area_km2")
GE <- do.call(rbind, lapply(all_E, function(E) { for (k in KEEP) if (!k %in% names(E)) E[[k]] <- NA_real_; st_transform(st_simplify(E[, KEEP], dTolerance = 8), 4326) }))
for (v in c(names(MEAS), AVG, "area_km2")) GE[[v]] <- round(as.numeric(GE[[v]]), 2); GE$dist_m <- round(as.numeric(GE$dist_m))   # all-NA columns come back from GeoJSON as logical
GE <- GE[, c(KEEP[sapply(KEEP, function(k) any(!is.na(GE[[k]])))], "geometry")]        # drop measures no census provides
f <- file.path(A, "denver_eds.geojson"); if (file.exists(f)) file.remove(f); st_write(GE, f, quiet = TRUE); fwrite(rbindlist(all_F), file.path(A, "denver_eds_firms.csv"))
file.copy(file.path(O, c("ed_year_groups.csv", "ed_distance_models.csv")), A, overwrite = TRUE)
md <- c("# Denver 1880-1940 by enumeration district", "", "## EDs with vs without a hazardous-trade firm (population-weighted %), and dissimilarity across EDs", "",
        "| census | group | EDs | population | % Black | % foreign born | % Mexican-born | % Hispanic | % laborers |", "|---|---|---|---|---|---|---|---|---|",
        sprintf("| %d | %s | %d | %s | %.2f | %.1f | %.2f | %.2f | %.1f |", G$census, G$group, G$EDs, format(G$population, big.mark = ","), G$pct_black, G$pct_fb, G$pct_fb_mexico, G$pct_hisp, G$pct_laborers), "",
        if (any(!is.na(G$pct_owner_hh))) c("## Housing, work and mobility by group (where the census provides them)", "", "| census | group | % owner households | median rent | mean SEI | % in hazardous industries | % recent immigrants | % moved since 1935 | % illiterate | % boarders |", "|---|---|---|---|---|---|---|---|---|---|",
          sprintf("| %d | %s | %s | %s | %s | %s | %s | %s | %s | %s |", G$census, G$group, round(G$pct_owner_hh, 1), round(G$median_rent), round(G$mean_sei, 1), round(G$pct_haz_industry, 1), round(G$pct_recent_immig, 1), round(G$pct_movers, 1), round(G$pct_illiterate, 1), round(G$pct_boarders, 1)), "") else NULL,
        "## ED-level models: percentage points per log-metre of distance from the ED centroid to the nearest hazardous firm (pop-weighted, HC1 SE; census 0 = pooled with census effects)", "",
        "| census | outcome | b | SE | p | EDs | firms |", "|---|---|---|---|---|---|---|",
        sprintf("| %s | %s | %.3f | %.3f | %.3g | %d | %s |", ifelse(M$census == 0, "pooled", M$census), M$outcome, M$b_per_log_m, M$se, M$p, M$EDs, ifelse(is.na(M$firms), "", M$firms)))
writeLines(md, file.path(O, "denver_eds_summary.md")); cat(md, sep = "\n")
