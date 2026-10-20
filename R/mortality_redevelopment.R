# Did living near a former hazardous site matter until the site was rebuilt? Block mortality 2000-2019 in the Denver study area.
#   Rscript R/mortality_redevelopment.R                      (CO_HIA folder at ~/Downloads/CO_HIA)
#   Rscript R/mortality_redevelopment.R /path/to/CO_HIA
# Restricted inputs stay on this machine and are read in place, never copied into the project (as R/mortality_block.R):
#   CO_HIA/co_deaths_official.csv   Colorado death records 2000-2020 (yr, fipscoor, tract, bgroup, block, all_cause, natural_cause)
#   CO_HIA/block_noyr.gpkg          2010 census blocks with yearly population (pop_2000-2020) and PM2.5 (pm_1998-2020)
# Public inputs: data/results/site_fate/site_fate_denver.csv and site_fate_denver_pre1960.csv (R/site_fate.R): every geocoded Denver site
# matched to its assessor parcel, with the year the parcel's main structure was built.
# Design
#   A site counts as rebuilt from the year its parcel's current structure was built, when that is after the site's last directory
#   listing (the old works were replaced); otherwise it is still standing. For each block and year, the Gaussian kernel (500 m
#   bandwidth, 2 km cutoff, as in R/mortality_block.R) of the sites still standing, by group: 1965-92 hazardous-sector manufacturers on
#   no current inventory ("hidden"), the same on an inventory ("known"), and street-level hazardous trades of 1891-1956. Each is scaled
#   by the SD across blocks of the group's full kernel (standing or not), so a coefficient is the change in mortality when one SD of
#   nearby sites goes from standing to rebuilt.
#   Poisson with block and year fixed effects, an offset for the block's population that year, yearly PM2.5 as a control, errors
#   clustered by tract (fixest::fepois). With block fixed effects, only changes within a block over time count: the redevelopments.
#   Event study: blocks with a site within 400 m rebuilt in 2003-2016 (the first such rebuild), against blocks within 400 m of a site
#   that stood throughout 2000-2019, by years since the rebuild (year -1 = reference).
#   Years whose death records match the 2010 blocks for less than 90% of deaths are dropped (and listed).
# Caveat: rebuilding brings new residents; the offset follows the population, but not its age, so a fall in deaths after a rebuild can
# be younger newcomers rather than a cleaner neighbourhood.
# Output (rate ratios, sample sizes and study-area totals only; no block counts): data/results/health/mortality_redevelopment_models.csv,
# mortality_redevelopment_event.csv, mortality_redevelopment_summary.md.
if (!requireNamespace("fixest", quietly = TRUE)) install.packages("fixest")
if (!requireNamespace("RANN", quietly = TRUE)) install.packages("RANN")
suppressPackageStartupMessages({ library(sf); library(data.table) })
sf_use_s2(FALSE); UTM <- 26913; YRS <- 2000:2019
args <- commandArgs(trailingOnly = TRUE); HIA <- path.expand(if (length(args)) args[1] else "~/Downloads/CO_HIA")
stopifnot(file.exists(file.path(HIA, "co_deaths_official.csv")), file.exists(file.path(HIA, "block_noyr.gpkg")))
O <- "data/results/health"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
# ---------------------------------------------------------------- 1. study-area blocks, yearly population and deaths
den_tr <- st_read("app/data/co_tracts_2010.geojson", quiet = TRUE); den_tr <- den_tr$GEOID[as.logical(den_tr$core) %in% TRUE | substr(den_tr$GEOID, 1, 5) == "08031"]
B <- st_read(file.path(HIA, "block_noyr.gpkg"), quiet = TRUE); B$bck <- formatC(as.character(B$bck), width = 15, flag = "0")
B <- B[substr(B$bck, 1, 11) %in% den_tr, ]; B <- st_transform(st_make_valid(B), UTM)
CXY <- st_coordinates(st_point_on_surface(st_geometry(B)))
BD <- as.data.table(st_drop_geometry(B))[, c("bck", paste0("pop_", YRS), paste0("pm_", YRS)), with = FALSE]
PN <- melt(BD, id.vars = "bck", measure.vars = list(paste0("pop_", YRS), paste0("pm_", YRS)), value.name = c("pop", "pm25"), variable.name = "k")
PN[, year := YRS[as.integer(k)]][, k := NULL]
X <- fread(file.path(HIA, "co_deaths_official.csv"), colClasses = "character", select = c("yr", "fipscoor", "tract", "bgroup", "block", "all_cause", "natural_cause"))
X <- X[as.integer(yr) %in% YRS]; X[, `:=`(bck = paste0("08", fipscoor, tract, bgroup, block), year = as.integer(yr))]
allb <- formatC(as.character(st_read(file.path(HIA, "block_noyr.gpkg"), quiet = TRUE, query = "SELECT bck FROM block_noyr")$bck), width = 15, flag = "0")
MR <- X[, .(deaths = .N, pct_matched = round(100 * mean(bck %in% allb), 1)), by = year][order(year)]
KEEPY <- MR[pct_matched >= 90, year]; message("years kept (90%+ of deaths on a 2010 block): ", paste(range(KEEPY), collapse = "-"), "; dropped: ", paste(setdiff(YRS, KEEPY), collapse = " "))
DE <- X[bck %in% B$bck, .(deaths_all = sum(all_cause == "1"), deaths_nat = sum(natural_cause == "1")), by = .(bck, year)]
PN <- merge(PN[year %in% KEEPY], DE, by = c("bck", "year"), all.x = TRUE); PN[is.na(deaths_all), deaths_all := 0L]; PN[is.na(deaths_nat), deaths_nat := 0L]
PN <- PN[!is.na(pop) & pop >= 1]; PN[, tract := substr(bck, 1, 11)]
# ---------------------------------------------------------------- 2. sites and when they were rebuilt
rb <- function(d, grp) { d <- d[!is.na(lat) & !is.na(lon) & !is.na(year_built)]
  d[, .(group = grp, lon, lat, rebuilt = fifelse(year_built > last_year, as.numeric(year_built), Inf))] }
SF <- fread("data/results/site_fate/site_fate_denver.csv")
S <- rbind(rb(SF[radar == "Not on any list"], "hidden"), rb(SF[radar != "Not on any list"], "known"),
           rb(fread("data/results/site_fate/site_fate_denver_pre1960.csv"), "pre1960"))
sxy <- st_coordinates(st_transform(st_as_sf(S, coords = c("lon", "lat"), crs = 4326), UTM))
nn <- RANN::nn2(sxy, CXY, k = min(nrow(S), 400), searchtype = "radius", radius = 2000)
W <- data.table(b = rep(seq_len(nrow(CXY)), ncol(nn$nn.idx)), s = as.vector(nn$nn.idx), d = as.vector(nn$nn.dists))[s > 0]
W[, `:=`(w = exp(-0.5 * (d / 500)^2), bck = B$bck[b], group = S$group[s], rebuilt = S$rebuilt[s])]
SC <- W[, .(k = sum(w)), by = .(bck, group)]; SC <- dcast(SC, bck ~ group, value.var = "k", fill = 0)
SDS <- vapply(c("hidden", "known", "pre1960"), function(g) sd(c(SC[[g]], rep(0, length(B$bck) - nrow(SC)))), 1)
# standing kernel per block-year
for (g in names(SDS)) { Wg <- W[group == g]
  st <- rbindlist(lapply(KEEPY, function(t) Wg[rebuilt > t, .(k = sum(w)), by = bck][, year := t]))
  PN <- merge(PN, st[, c("bck", "year", "k")], by = c("bck", "year"), all.x = TRUE); PN[is.na(k), k := 0]
  PN[, (paste0("standing_", g)) := k / SDS[[g]]][, k := NULL] }
SUM <- S[, .(sites = .N, rebuilt_in_window = sum(rebuilt >= min(KEEPY) & rebuilt <= max(KEEPY)), rebuilt_before = sum(rebuilt < min(KEEPY)), standing_throughout = sum(rebuilt > max(KEEPY))), by = group]
print(SUM)
# ---------------------------------------------------------------- 3. fixed-effects Poisson
library(fixest)
tidy <- function(m, model, outcome) { ct <- coeftable(m); data.table(model = model, outcome = outcome, term = rownames(ct), rr = round(exp(ct[, 1]), 4),
  lo = round(exp(ct[, 1] - 1.96 * ct[, 2]), 4), hi = round(exp(ct[, 1] + 1.96 * ct[, 2]), 4), p = signif(ct[, 4], 3), n_obs = nobs(m)) }
R <- list()
for (y in c("deaths_nat", "deaths_all")) {
  R[[length(R) + 1]] <- tidy(fepois(as.formula(paste(y, "~ standing_hidden + standing_known + standing_pre1960 + pm25 | bck + year")), PN, offset = ~log(pop), cluster = ~tract),
                              "All three groups together", y)
  for (g in names(SDS)) R[[length(R) + 1]] <- tidy(fepois(as.formula(paste0(y, " ~ standing_", g, " + pm25 | bck + year")), PN, offset = ~log(pop), cluster = ~tract),
                                                   paste("One group:", g), y) }
R <- rbindlist(R)[term != "pm25"]
R[, term := sub("standing_", "", term)]; fwrite(R, file.path(O, "mortality_redevelopment_models.csv")); print(R)
# ---------------------------------------------------------------- 4. event study around the first rebuild within 400 m
near <- W[d <= 400]
ev <- near[rebuilt >= 2003 & rebuilt <= 2016, .(event = min(rebuilt)), by = bck]
ctl <- setdiff(near[rebuilt > max(KEEPY), unique(bck)], near[rebuilt >= min(KEEPY) & rebuilt <= max(KEEPY), unique(bck)])
E <- merge(PN[bck %in% c(ev$bck, ctl)], ev, by = "bck", all.x = TRUE)
E[, rel := fifelse(is.na(event), -1000, year - event)]
E[, evb := fcase(rel == -1000, "never", rel <= -4, "-4 or earlier", rel >= 4, "4 or later", rep(TRUE, .N), as.character(rel))]
E[evb == "never", evb := "-1"]                       # never-rebuilt blocks sit in the reference bin
LV <- c("-4 or earlier", "-3", "-2", "-1", "0", "1", "2", "3", "4 or later"); E[, evb := factor(evb, LV)]
ES <- list()
for (y in c("deaths_nat", "deaths_all")) { m <- fepois(as.formula(paste(y, "~ i(evb, ref = '-1') + pm25 | bck + year")), E, offset = ~log(pop), cluster = ~tract)
  ES[[y]] <- tidy(m, "Event study: first rebuild within 400 m", y)[grepl("evb", term)][, years_since_rebuild := sub("evb::", "", term)] }
ES <- rbindlist(ES)[, .(outcome, years_since_rebuild, rr, lo, hi, p, n_obs)]
ES[, `:=`(rebuilt_blocks = uniqueN(E[!is.na(event), bck]), comparison_blocks = length(ctl))]
fwrite(ES, file.path(O, "mortality_redevelopment_event.csv")); print(ES)
# ---------------------------------------------------------------- 5. summary
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
md <- c("# Former hazardous sites, before and after they were rebuilt: block mortality 2000-2019, Denver study area", "",
        sprintf("%s blocks, %s block-years, %s natural-cause deaths, years %s.", format(uniqueN(PN$bck), big.mark = ","), format(nrow(PN), big.mark = ","),
                format(sum(PN$deaths_nat), big.mark = ","), paste(range(KEEPY), collapse = "-")), "", "## Death records matched to 2010 blocks, by year", "", kab(MR[, .(year, pct_matched)]), "",
        "## Sites", "", kab(SUM), "", "## Rate ratio per SD of nearby sites still standing (block and year fixed effects)", "", kab(R), "",
        "## Event study (rate ratio relative to the year before the rebuild)", "", kab(ES))
writeLines(md, file.path(O, "mortality_redevelopment_summary.md")); message("wrote ", O)
