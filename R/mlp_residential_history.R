# Where Denver's 1940 residents lived in 1910, 1920 and 1930: residential histories from the IPUMS Multigenerational Longitudinal Panel.
#
#   Rscript R/mlp_residential_history.R          (after R/censoc_denver_1940.R)
#
# Inputs (person-level, all in work/, never redistributed):
#   work/mlp/*.csv   IPUMS MLP census-to-census crosswalks (https://usa.ipums.org/usa/mlp/mlp_census_crosswalks.shtml, IPUMS login; "Stata CSV"),
#                    for 1930-1940, 1920-1940 and 1910-1940 (any that are present are used). Unzip them into work/mlp/.
#   work/census/brown/grf/DenverCO/DenverCO_<year>.csv and work/census/grf_geocoded_<year>_R.csv   1910-1930 Denver addresses (R/grf_eds.R)
#   work/censoc/denver_1940_residents.rds and censoc_denver_1940_linked.rds                        (R/censoc_denver_1940.R)
# What it does
#   1. Each 1940 Denver resident is traced to their record in each earlier census through the MLP crosswalk, and, if they lived in Denver
#      then, to their street address (same address key, geocodes and stray-geocode rule as R/grf_eds.R).
#   2. At each earlier address: hazardous trades listed in the directories in the preceding decade (within 500 m, and kernel), and in
#      1930 the 1929 zoning district.
#   3. Persistence: how many 1940 residents lived in Denver, at the same address, or within 500 m of the same place a decade or more earlier,
#      and how exposure carried over, by 1940 exposure.
#   4. Cumulative exposure: censuses (of those observed, 1910-1940) in which the person lived within 500 m of a hazardous trade, and the
#      childhood address (the earliest census at ages 0-14); both added to the CenSoc age-at-death models of R/censoc_denver_1940.R.
# Outputs (aggregates only): data/results/censoc/mlp_persistence.csv, mlp_models.csv, mlp_summary.md
for (p in c("readr", "RANN")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(sf); library(sandwich); library(lmtest) })
sf_use_s2(FALSE); UTM <- 26913; W <- "work/censoc"; O <- "data/results/censoc"; A <- "app/data"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
XW <- Sys.glob("work/mlp/*.csv"); if (!length(XW)) stop("put the IPUMS MLP crosswalks (1930-1940, 1920-1940, 1910-1940; Stata CSV) unzipped in work/mlp/")
P <- as.data.table(readRDS(file.path(W, "denver_1940_residents.rds"))); L0 <- as.data.table(readRDS(file.path(W, "censoc_denver_1940_linked.rds")))
# ---------------------------------------------------------------- 1. crosswalks, filtered to Denver's 1940 residents before reading
X <- rbindlist(lapply(XW, function(f) {
  h <- names(fread(f, nrows = 0)); hc <- grep("histid", h, ignore.case = TRUE, value = TRUE); yrs <- as.integer(regmatches(hc, regexpr("1[89][0-9]0", hc)))
  if (length(hc) != 2 || !1940 %in% yrs) { message("skipped ", basename(f), " (needs two HISTID columns, one for 1940): ", paste(h, collapse = ", ")); return(NULL) }
  y0 <- yrs[yrs != 1940]; idset <- P$HISTID; c40 <- hc[yrs == 1940]
  x <- readr::read_csv_chunked(f, readr::DataFrameCallback$new(function(ch, pos) ch[toupper(ch[[c40]]) %in% idset, hc]), chunk_size = 2e6,   # read in chunks, keep Denver's 1940 residents
                               col_types = readr::cols(.default = readr::col_character()), progress = FALSE)
  x <- as.data.table(x); setnames(x, hc, paste0("h", yrs))
  x <- x[, .(HISTID = toupper(h1940), histid_then = toupper(get(paste0("h", y0))), year = y0)]
  message(basename(f), ": ", y0, "-1940, ", format(nrow(x), big.mark = ","), " links for Denver's 1940 residents"); x[HISTID %in% P$HISTID] }))
X <- unique(X, by = c("HISTID", "year"))
# ---------------------------------------------------------------- 2. earlier Denver addresses and exposures there
Hs <- fread(file.path(A, "historical_sites.csv"))[town == "DENVER" & precision != "town" & !is.na(lat) & fe_hazard %in% c(TRUE, "True")]
hxy <- st_coordinates(st_transform(st_as_sf(Hs[, .(lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM))
Z <- st_make_valid(st_transform(st_read(file.path(A, "zoning_1929.geojson"), quiet = TRUE), UTM))
addr_year <- function(yr) {
  G <- fread(sprintf("work/census/brown/grf/DenverCO/DenverCO_%d.csv", yr), colClasses = "character", select = c("histid", "b_ed", "b_hn", "b_stfull"))
  G[, num := ifelse(grepl("[0-9]", b_hn), suppressWarnings(as.integer(sub("^[^0-9]*([0-9]+).*$", "\\1", b_hn))), NA_integer_)]
  G[, addr := fifelse(!is.na(num) & nzchar(b_stfull), paste(num, trimws(gsub("[^A-Z0-9 ]", "", toupper(b_stfull)))), NA_character_)]
  C <- fread(sprintf("work/census/grf_geocoded_%d_R.csv", yr), colClasses = c(addr = "character"))[grepl("^(fuzzy_)?range_interp", q) & !is.na(lat)]
  G <- merge(G[, .(histid_then = toupper(histid), ED = b_ed, addr)], C[, .(addr, lat, lon)], by = "addr", all.x = TRUE)
  xy <- st_coordinates(st_transform(st_as_sf(G[!is.na(lat), .(lon, lat)], coords = c("lon", "lat"), crs = 4326), UTM)); G[!is.na(lat), `:=`(x = xy[, 1], y = xy[, 2])]
  G[!is.na(x), `:=`(mx = median(x), my = median(y)), by = ED]; G[, dd := sqrt((x - mx)^2 + (y - my)^2)]
  G[!is.na(dd), thr := if (.N >= 5) max(400, 2.5 * median(dd)) else 600, by = ED]; G[!is.na(dd) & dd > thr, c("x", "y") := NA_real_]
  G <- G[!is.na(x)]; hk <- hxy[Hs$first_year <= yr & Hs$last_year >= yr - 9, , drop = FALSE]
  if (nrow(hk)) { nn <- RANN::nn2(hk, as.matrix(G[, .(x, y)]), k = min(nrow(hk), 100), searchtype = "radius", radius = 2000); d <- nn$nn.dists; d[nn$nn.idx == 0] <- NA
    G[, `:=`(haz_500_then = as.numeric(rowSums(d <= 500, na.rm = TRUE) > 0), haz_k_then = rowSums(exp(-0.5 * (d / 500)^2), na.rm = TRUE))] } else G[, `:=`(haz_500_then = 0, haz_k_then = 0)]
  if (yr == 1930) { zp <- st_as_sf(G[, .(x, y)], coords = c("x", "y"), crs = UTM); G[, zone_ind_then := as.numeric(lengths(st_within(zp, Z[grepl("Industrial", Z$zone), ])) > 0)]
  } else G[, zone_ind_then := NA_real_]
  G[!duplicated(histid_then), .(histid_then, year = yr, x_then = x, y_then = y, haz_500_then, haz_k_then, zone_ind_then)] }
YRS <- intersect(sort(unique(X$year)), c(1910, 1920, 1930))
AH <- rbindlist(lapply(YRS, addr_year))
Hh <- merge(X, AH, by = c("histid_then", "year"), all.x = TRUE)
Hh <- merge(Hh, P[, .(HISTID, AGE, x, y, haz_500, zone29, ind37)], by = "HISTID")
Hh[, `:=`(in_denver_then = !is.na(x_then), moved_m = sqrt((x - x_then)^2 + (y - y_then)^2))]
# ---------------------------------------------------------------- 3. persistence
grp40 <- function(d) d[, g40 := fcase(zone29 == "industrial", "1929 industrial district", !is.na(ind37) & ind37 >= 10, "10%+ industrial land within 250 m", default = "other 1940 addresses")]
grp40(P); grp40(Hh)
PS <- rbindlist(lapply(YRS, function(yr) { el <- P[!is.na(x) & GQ < 3 & AGE >= 1940 - yr]                   # born by then (yr, not y: y is a coordinate column)
  h <- Hh[year == yr]
  el[, linked := HISTID %in% h$HISTID]
  r <- merge(el[, .(HISTID, g40, linked)], h[, .(HISTID, in_denver_then, moved_m, haz_500_then)], by = "HISTID", all.x = TRUE)
  r[, .(census = yr, residents_1940 = .N, pct_linked = round(100 * mean(linked), 1), pct_in_denver_then_of_linked = round(100 * mean(in_denver_then[linked]), 1),
        pct_within_100m_of_1940_address = round(100 * mean(moved_m[linked & in_denver_then %in% TRUE] <= 100), 1),
        pct_within_1km = round(100 * mean(moved_m[linked & in_denver_then %in% TRUE] <= 1000), 1),
        pct_near_hazardous_trade_then = round(100 * mean(haz_500_then[linked & in_denver_then %in% TRUE]), 1)), by = .(address_1940 = g40)] }))
fwrite(PS, file.path(O, "mlp_persistence.csv")); print(PS)
# ---------------------------------------------------------------- 4. cumulative and childhood exposure in the CenSoc models
CU <- Hh[in_denver_then == TRUE, .(censuses_observed_before = .N, censuses_near_haz_before = sum(haz_500_then)), by = HISTID]
CH <- Hh[in_denver_then == TRUE & AGE - (1940 - year) <= 14][order(year)][!duplicated(HISTID), .(HISTID, child_year = year, child_haz_500 = haz_500_then, child_haz_k = haz_k_then)]
L <- merge(L0, CU, by.x = "histid", by.y = "HISTID", all.x = TRUE); L <- merge(L, CH, by.x = "histid", by.y = "HISTID", all.x = TRUE)
L[, `:=`(censuses_near_haz = fifelse(is.na(censuses_near_haz_before), 0, censuses_near_haz_before) + haz_500, censuses_observed = fifelse(is.na(censuses_observed_before), 0, censuses_observed_before) + 1)]
L <- L[!is.na(x) & !is.na(byear) & !is.na(death_age) & gq == 0 & !is.na(weight) & weight > 0]
L[, `:=`(hc_q = factor(fifelse(is.na(hc_q), 0L, hc_q)), h_hs_m = as.numeric(is.na(h_hs)), h_hs = fifelse(is.na(h_hs), 0, h_hs), h_sei_m = as.numeric(is.na(h_sei)),
         h_sei = fifelse(is.na(h_sei), 0, h_sei), mover_m = as.numeric(is.na(mover)), mover = fifelse(is.na(mover), 0, mover), owner = fifelse(is.na(owner), 0, owner),
         w = weight, female = as.numeric(sex == 2), src = fifelse(grepl("^Numident", file), "Numident", "DMF"))]
CTRL <- c("black", "hisp", "fb", "fb_mex", "born_co", "mover", "mover_m", "owner", "hc_q", "h_hs", "h_hs_m", "h_sei", "h_sei_m")
fit <- function(d, terms, label) { d <- d[complete.cases(d[, ..terms])]; if (nrow(d) < 200 || length(unique(d[[terms[1]]])) < 2) return(NULL)
  ctrl <- CTRL[vapply(CTRL, function(v) length(unique(d[[v]])) > 1, TRUE)]
  m <- lm(as.formula(paste("death_age ~", paste(c(terms, ctrl), collapse = " + "), "+ factor(byear)", if (length(unique(d$female)) > 1) "+ female")), data = d, weights = w)
  ct <- coeftest(m, vcov. = vcovCL(m, cluster = ~ED, type = "HC1")); t <- terms[1]
  data.table(model = label, term = t, years = round(ct[t, 1], 3), lo = round(ct[t, 1] - 1.96 * ct[t, 2], 3), hi = round(ct[t, 1] + 1.96 * ct[t, 2], 3), p = signif(ct[t, 4], 3), n = nobs(m)) }
R <- rbindlist(lapply(c("DMF", "Numident"), function(s) { d <- L[src == s]; dt <- d[censuses_observed >= 2]
  rbindlist(list(
    fit(dt, c("censuses_near_haz", "censuses_observed"), "Censuses (1910-1940) living within 500 m of a hazardous trade, people traced to an earlier Denver address"),
    fit(dt, c("haz_500", "censuses_observed"), "1940 address only, same people (comparison)"),
    fit(d[!is.na(child_haz_500)], c("child_haz_500", "haz_500"), "Childhood address (ages 0-14, 1910-1930) within 500 m of a hazardous trade, with the 1940 address"),
    fit(d[!is.na(child_haz_500)], c("haz_500", "child_haz_500"), "1940 address, with the childhood address"))
  )[, people := if (s == "DMF") "Men, deaths 1975-2020" else "Men and women, deaths at 65+ 1988-2005"] }), fill = TRUE)
fwrite(R, file.path(O, "mlp_models.csv")); print(R)
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# Residential histories of Denver's 1940 residents (IPUMS MLP)", "", "## Persistence", "", kab(PS), "", "## Age at death and exposure over the life course (years, 95% CI)", "", kab(R)),
           file.path(O, "mlp_summary.md")); message("wrote ", O)
