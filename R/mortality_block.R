# Block-level mortality and historical hazardous sites, Colorado 2015-2019.
#   Rscript R/mortality_block.R                      (CO_HIA folder at ~/Downloads/CO_HIA)
#   Rscript R/mortality_block.R /path/to/CO_HIA      (or give its path)
# Restricted inputs stay on this machine and are read in place, never copied into the project:
#   CO_HIA/co_deaths_official.csv   Colorado death records (yr, fipscoor, tract, bgroup, block, all_cause, natural_cause)
#   CO_HIA/block_noyr.gpkg          2010 census blocks with yearly population (pop_2000-2020) and PM2.5 (pm_1998-2020)
# Public inputs: 2010 Census SF1 sex by age (P12) for Colorado blocks, fetched once from IPUMS NHGIS with the same key as R/fetch_census.R
# (IPUMS_API_KEY) into work/census/blocks_2010_age.csv (shares only); tract composition (app/data/tract_panel.csv, 2020) and EnviroScreen
# 2.0 tract indicators (app/data/enviroscreen_tracts.geojson); the project's sites, TRI and cleanup layers.
# Design, as R/mortality_bg.R but at the block: deaths 2015-2019 per 2010 block; negative binomial with county fixed effects and an offset
# for log person-years (sum of yearly block population 2015-2019); standard errors clustered by tract. Controls: % 65 and over and its
# square, % under 5 (block, 2010), log population density (block), mean PM2.5 2015-2019 (block); tract % in poverty, % Hispanic, % Black,
# % owner-occupied (2020) and EnviroScreen low income, less than high school, linguistic isolation and proximity to hazardous-waste and
# Superfund sites (2020 tracts, joined at the block centroid). Exposures: Gaussian kernel density (500 m bandwidth, 2 km cutoff) around
# each block centroid of hidden hazardous sites (no match in the searched inventories), high-confidence hidden sites, known historical
# sites, pre-1960 hazardous trades (street level), TRI facilities, cleanup sites, and a placebo of non-hazardous manufacturers; each
# standardised (log1p, z-score) over the blocks modelled.
# Samples: all Colorado blocks with 100+ person-years, and the Denver study area (City and County of Denver plus the 147 tracts within
# 10 km of downtown).
# Output: data/results/health/mortality_block_models.csv (rate ratios per SD, 95% CI, p; sample sizes and statewide death totals only;
# no block or small-area counts) and mortality_block_summary.md.
suppressPackageStartupMessages({ library(sf); library(data.table); library(MASS); library(sandwich); library(lmtest) })
sf_use_s2(FALSE); UTM <- 26913; YRS <- 2015:2019
args <- commandArgs(trailingOnly = TRUE); HIA <- path.expand(if (length(args)) args[1] else "~/Downloads/CO_HIA")
stopifnot(file.exists(file.path(HIA, "co_deaths_official.csv")), file.exists(file.path(HIA, "block_noyr.gpkg")))
O <- "data/results/health"; dir.create(O, showWarnings = FALSE, recursive = TRUE); dir.create("work/census", showWarnings = FALSE, recursive = TRUE)
# ---------------------------------------------------------------- 1. block age structure (public, 2010 SF1 P12)
AGEF <- "work/census/blocks_2010_age.csv"
if (!file.exists(AGEF)) {
  suppressPackageStartupMessages(library(ipumsr))
  key <- Sys.getenv("IPUMS_API_KEY"); if (!nzchar(key)) stop("set IPUMS_API_KEY (as for R/fetch_census.R)"); set_ipums_api_key(key, overwrite = TRUE, save = FALSE)
  md <- get_metadata("nhgis", dataset = "2010_SF1a", data_table = "P12"); v <- as.data.table(md$variables)
  code <- md$nhgis_code; message("2010 SF1 P12 = NHGIS ", code)
  old <- v[grepl("65 and 66|67 to 69|70 to 74|75 to 79|80 to 84|85 years and over", description), nhgis_code]
  young <- v[grepl("Under 5 years", description), nhgis_code]; tot <- v[grepl("^Total$", description), nhgis_code][1]
  if (length(old) != 12 || length(young) != 2 || is.na(tot)) stop("unexpected P12 layout")
  ex <- submit_extract(define_extract_agg("nhgis", description = "Colorado 2010 blocks sex by age", datasets = ds_spec("2010_SF1a", data_tables = "P12", geog_levels = "block"),
                                          geographic_extents = "080"))
  ex <- wait_for_extract(ex); f <- download_extract(ex, download_dir = "work/census", overwrite = TRUE)
  d <- as.data.table(read_nhgis(f, verbose = FALSE))
  d[, bck := sprintf("%s%s%s%s", STATEA, COUNTYA, TRACTA, BLOCKA)]
  d[, `:=`(pop2010 = get(tot), pct_65plus = 100 * rowSums(.SD[, old, with = FALSE]) / pmax(get(tot), 1), pct_under5 = 100 * rowSums(.SD[, young, with = FALSE]) / pmax(get(tot), 1))]
  fwrite(d[, .(bck, pop2010, pct_65plus = round(pct_65plus, 2), pct_under5 = round(pct_under5, 2))], AGEF); file.remove(f) }
AGE <- fread(AGEF, colClasses = c(bck = "character"))
# ---------------------------------------------------------------- 2. blocks, deaths
B <- st_read(file.path(HIA, "block_noyr.gpkg"), quiet = TRUE)
B$bck <- formatC(as.character(B$bck), width = 15, flag = "0"); B <- st_transform(st_make_valid(B), UTM)
BD <- as.data.table(st_drop_geometry(B))[, c("bck", paste0("pop_", YRS), paste0("pm_", YRS)), with = FALSE]
BD[, `:=`(pyears = rowSums(.SD[, paste0("pop_", YRS), with = FALSE], na.rm = TRUE), pm25 = rowMeans(.SD[, paste0("pm_", YRS), with = FALSE], na.rm = TRUE))]
BD[, area_km2 := as.numeric(st_area(B)) / 1e6]
X <- fread(file.path(HIA, "co_deaths_official.csv"), colClasses = "character", select = c("yr", "fipscoor", "tract", "bgroup", "block", "all_cause", "natural_cause"))
X <- X[as.integer(yr) %in% YRS]; X[, bck := paste0("08", fipscoor, tract, bgroup, block)]
DE <- X[, .(deaths_all = sum(all_cause == "1"), deaths_nat = sum(natural_cause == "1")), by = bck]
matched <- mean(DE$bck %in% BD$bck); message(sprintf("%.1f%% of 2015-2019 deaths' blocks found among the 2010 blocks", 100 * sum(DE$deaths_all[DE$bck %in% BD$bck]) / sum(DE$deaths_all)))
D <- merge(BD, DE, by = "bck", all.x = TRUE); D[is.na(deaths_all), deaths_all := 0L]; D[is.na(deaths_nat), deaths_nat := 0L]
D <- merge(D, AGE, by = "bck", all.x = TRUE); D[, `:=`(tract = substr(bck, 1, 11), county = substr(bck, 3, 5))]
D[, log_density := log1p((pyears / length(YRS)) / pmax(area_km2, 1e-4))]
# ---------------------------------------------------------------- 3. tract covariates
TP <- fread("app/data/tract_panel.csv", colClasses = c(GEOID = "character"))[census == 2020, .(tract = GEOID, t_pov = p_pov, t_hisp = p_hisp, t_black = p_black, t_owner = p_owner, core = as.logical(core) %in% TRUE)]
D <- merge(D, TP, by = "tract", all.x = TRUE)
cen <- st_point_on_surface(st_geometry(B)); CXY <- st_coordinates(cen); names_idx <- match(D$bck, B$bck)
ES <- st_transform(st_read("app/data/enviroscreen_tracts.geojson", quiet = TRUE), UTM)
j <- st_intersects(cen, ES); ei <- vapply(j, function(i) if (length(i)) i[1] else NA_integer_, 1L)
esv <- c("low_income", "less_than_hs", "linguistic_isolation", "prox_hazwaste_pctl", "prox_npl_pctl")
for (v in esv) D[[paste0("es_", v)]] <- suppressWarnings(as.numeric(ES[[v]]))[ei[names_idx]]
den_tr <- st_read("app/data/co_tracts_2010.geojson", quiet = TRUE); den_tr <- den_tr[as.logical(den_tr$core) %in% TRUE | substr(den_tr$GEOID, 1, 5) == "08031", ]
D[, study_area := tract %in% den_tr$GEOID]
# ---------------------------------------------------------------- 4. exposures
pts <- function(d) { d <- d[!is.na(lat) & !is.na(lon)]; st_coordinates(st_transform(st_as_sf(d, coords = c("lon", "lat"), crs = 4326), UTM)) }
S0 <- fread("app/data/sites.csv"); S <- S0[fe_hazard %in% c(TRUE, "True") & geo_level %in% c("address", "address_approx")]
H <- fread("app/data/historical_sites.csv")[fe_hazard %in% c(TRUE, "True") & precision != "town"]
L <- fread("data/results/CO_directory_listings_1961-2002.csv", select = c("lat", "lon", "geo_level", "fe_hazard", "ext_hazard", "site_id"))
nh <- L[geo_level == "address" & !(fe_hazard %in% c(TRUE, "True") | ext_hazard %in% c(TRUE, "True")) & !(site_id %in% S0$site_id)][!duplicated(paste(round(lat, 4), round(lon, 4)))]
SX <- pts(S); NX <- pts(nh); far <- vapply(seq_len(nrow(NX)), function(i) min(sqrt((SX[, 1] - NX[i, 1])^2 + (SX[, 2] - NX[i, 2])^2)) > 100, TRUE); NX <- NX[far, , drop = FALSE]
groups <- list(hidden = pts(S[radar == "Not on any list"]), hidden_hiconf = pts(S[radar == "Not on any list" & confidence == "high"]), known_hist = pts(S[radar != "Not on any list"]),
               pre1960 = pts(H), tri = pts(fread("app/data/tri_facilities.csv")), cleanup = pts(fread("app/data/cleanup_sites.csv")), placebo = NX)
kd <- function(P) { if (!nrow(P)) return(rep(0, nrow(CXY))); cell <- 2000; key <- function(x, y) paste(floor(x / cell), floor(y / cell))
  bins <- split(seq_len(nrow(P)), key(P[, 1], P[, 2])); gx <- floor(CXY[, 1] / cell); gy <- floor(CXY[, 2] / cell); out <- numeric(nrow(CXY))
  for (dx in -1:1) for (dy in -1:1) { k <- paste(gx + dx, gy + dy); for (kk in intersect(unique(k), names(bins))) { i <- which(k == kk); p <- P[bins[[kk]], , drop = FALSE]
    for (q in seq_len(nrow(p))) { dd <- sqrt((CXY[i, 1] - p[q, 1])^2 + (CXY[i, 2] - p[q, 2])^2); out[i] <- out[i] + ifelse(dd <= 2000, exp(-0.5 * (dd / 500)^2), 0) } } }
  out }
for (k in names(groups)) { v <- kd(groups[[k]]); D[[paste0("k_", k)]] <- v[names_idx]; message("exposure: ", k) }
# ---------------------------------------------------------------- 5. models
D <- D[pyears >= 100 & !is.na(pct_65plus) & is.finite(pm25) & !is.na(t_pov)]
for (v in esv) { x <- D[[paste0("es_", v)]]; x[is.na(x)] <- median(x, na.rm = TRUE); D[[paste0("es_", v)]] <- x }
D[, log_py := log(pyears)]; D[, county := factor(county)]
CTRL <- "pct_65plus + I(pct_65plus^2) + pct_under5 + log_density + pm25 + t_pov + t_hisp + t_black + t_owner + es_low_income + es_less_than_hs + es_linguistic_isolation + es_prox_hazwaste_pctl + es_prox_npl_pctl"
fit_set <- function(DD, label, fe = TRUE) {
  z <- function(x) { x <- log1p(x); (x - mean(x)) / sd(x) }; for (k in names(groups)) DD[[paste0("z_", k)]] <- z(DD[[paste0("k_", k)]])
  base <- paste(CTRL, if (fe && uniqueN(DD$county) > 1) "+ county" else "")
  REG <- " + z_tri + z_cleanup"
  specs <- c("M1 controls" = base, "M2 + regulated (TRI, cleanup)" = paste0(base, REG), "M3 + known historical" = paste0(base, REG, " + z_known_hist"),
             "M4 + hidden" = paste0(base, REG, " + z_known_hist + z_hidden"), "M4 hidden high-confidence" = paste0(base, REG, " + z_known_hist + z_hidden_hiconf"),
             "M5 + pre-1960 trades" = paste0(base, REG, " + z_known_hist + z_hidden + z_pre1960"), "Placebo: non-hazardous manufacturers" = paste0(base, REG, " + z_placebo"),
             "M4 + placebo" = paste0(base, REG, " + z_known_hist + z_hidden + z_placebo"))
  rows <- list()
  for (y in c("deaths_nat", "deaths_all")) {
    th <- tryCatch(glm.nb(as.formula(paste(y, "~", specs[["M4 + placebo"]], "+ offset(log_py)")), data = DD, control = glm.control(maxit = 100))$theta, error = function(e) 1)
    for (nm in names(specs)) {
      m <- glm(as.formula(paste(y, "~", specs[[nm]], "+ offset(log_py)")), data = DD, family = negative.binomial(th))
      ct <- coeftest(m, vcov. = vcovCL(m, cluster = DD$tract, type = "HC1"))
      for (v in intersect(c("z_hidden", "z_hidden_hiconf", "z_known_hist", "z_pre1960", "z_placebo", "z_tri", "z_cleanup"), rownames(ct)))
        rows[[length(rows) + 1]] <- data.table(sample = label, outcome = ifelse(y == "deaths_nat", "natural causes", "all causes"), model = nm, term = sub("z_", "", v),
          rr = round(exp(ct[v, 1]), 4), lo = round(exp(ct[v, 1] - 1.96 * ct[v, 2]), 4), hi = round(exp(ct[v, 1] + 1.96 * ct[v, 2]), 4), p = signif(ct[v, 4], 3),
          blocks = nrow(DD), tracts = uniqueN(DD$tract), aic = round(AIC(m), 1)) }
    message(label, ": ", y, " done") }
  rbindlist(rows) }
R <- rbind(fit_set(copy(D), "Colorado, all blocks with 100+ person-years"), fit_set(copy(D[study_area == TRUE]), "Denver study area"))
tot <- data.table(sample = c("Colorado, all blocks with 100+ person-years", "Denver study area"),
                  deaths_all = c(sum(D$deaths_all), sum(D[study_area == TRUE]$deaths_all)), deaths_nat = c(sum(D$deaths_nat), sum(D[study_area == TRUE]$deaths_nat)))
fwrite(R, file.path(O, "mortality_block_models.csv")); fwrite(tot, file.path(O, "mortality_block_totals.csv"))
md <- R[term %in% c("hidden", "hidden_hiconf", "known_hist", "pre1960", "placebo") & model %in% c("M4 + hidden", "M4 hidden high-confidence", "M5 + pre-1960 trades", "M3 + known historical", "Placebo: non-hazardous manufacturers")]
writeLines(c("# Block-level mortality 2015-2019 and historical hazardous sites", "", "Rate ratio per SD of kernel density (95% CI); negative binomial, county FE, tract-clustered SE.", "",
  paste("|", paste(c("sample", "outcome", "model", "term", "RR", "95% CI", "p"), collapse = " | "), "|"), "|---|---|---|---|---|---|---|",
  md[, sprintf("| %s | %s | %s | %s | %.3f | %.3f-%.3f | %s |", sample, outcome, model, term, rr, lo, hi, format(p, digits = 2))]), file.path(O, "mortality_block_summary.md"))
print(md[outcome == "natural causes", .(sample, model, term, rr, lo, hi, p)])
