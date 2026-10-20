# Further analyses of Denver's 1940 residents linked to death records (CenSoc). Run after R/censoc_denver_1940.R.
#
#   Rscript R/censoc_extensions.R
#
# Inputs (person-level, all in work/, never redistributed):
#   work/censoc/censoc_denver_1940_linked.rds   linked residents with their 1940 address exposures (R/censoc_denver_1940.R)
#   work/censoc/denver_1940_residents.rds       every 1940 resident with the same exposures (same script)
#   work/censoc/censoc_numident_geography_supplement_v1.csv   CenSoc-Numident place of death (from CenSoc_Numident.zip)
# Analyses (same models as the main script: OLS of age at death, birth-year fixed effects, sex where both sexes are present, CenSoc
# weights, 1940 person and household controls, errors clustered by 1940 enumeration district):
#   1. childhood   the exposures by age in 1940 (0-14, 15-29, 30 and over)
#   2. stayers     Numident: who died in the Denver metro; is a 1940 industrial address associated with leaving; models among stayers
#   3. work/home   men's own 1940 industry (hazardous sectors, any manufacturing) and the household head's, alongside the address exposures
#   4. groups      by Hispanic origin and race, and by tenure
#   5. linkage     share of 1940 residents linked to a death record, by exposure (linkage reflects both matching and dying inside the window)
#   6. Gompertz    hazard ratios from the doubly-truncated Gompertz model (gompertztrunc), CenSoc's recommended check on OLS
#   7. highways and displacement: within 100 m of a major road already open in 1940; 75-500 m from a freeway opened 1950-1979 (traffic);
#                  1940 addresses on land later cleared: within 75 m of a freeway opened 1950-1979 (app/data/highways_denver.geojson), or
#                  residential in 1937 and 1957 but transport, commercial, industrial or institutional by 1977 (USGS land use,
#                  app/data/landuse_YYYY_20m.tif). Compared with residents of the same 1940 enumeration district (ED fixed effects).
#                  An intention-to-treat contrast: we know where people lived in 1940, not whether they still lived there when it was cleared.
# Outputs (aggregates only): data/results/censoc/censoc_ext_*.csv and censoc_extensions_summary.md
for (p in c("gompertztrunc", "sandwich", "lmtest")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages({ library(data.table); library(sandwich); library(lmtest); library(sf); library(terra) })
sf_use_s2(FALSE)
W <- "work/censoc"; O <- "data/results/censoc"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
if (!file.exists(file.path(W, "denver_1940_residents.rds"))) stop("run Rscript R/censoc_denver_1940.R first (it now also saves work/censoc/denver_1940_residents.rds)")
L0 <- as.data.table(readRDS(file.path(W, "censoc_denver_1940_linked.rds"))); P <- as.data.table(readRDS(file.path(W, "denver_1940_residents.rds")))
if (!"haz_job" %in% names(L0)) L0 <- merge(L0, P[, .(histid = HISTID, haz_job, manuf_job, h_haz_job, h_manuf)], by = "histid", all.x = TRUE)
FL <- c(DMF = "Men, deaths 1975-2020 (CenSoc-DMF)", Numident = "Men and women, deaths at 65+ 1988-2005 (CenSoc-Numident)")
L0[, src := fifelse(grepl("^Numident", file), "Numident", "DMF")]
# ---------------------------------------------------------------- shared preparation (as R/censoc_denver_1940.R)
prep <- function(L) {
  L <- L[!is.na(x) & !is.na(byear) & !is.na(death_age) & gq == 0]
  L[, `:=`(hc_q = factor(fifelse(is.na(hc_q), 0L, hc_q)), h_hs_m = as.numeric(is.na(h_hs)), h_hs = fifelse(is.na(h_hs), 0, h_hs),
           h_sei_m = as.numeric(is.na(h_sei)), h_sei = fifelse(is.na(h_sei), 0, h_sei), mover_m = as.numeric(is.na(mover)), mover = fifelse(is.na(mover), 0, mover),
           owner = fifelse(is.na(owner), 0, owner), w = weight, female = as.numeric(sex == 2))]
  L <- L[!is.na(w) & w > 0]
  L[, `:=`(haz_kz = haz_k / sd(haz_k), hidden_kz = hidden_k / sd(hidden_k), known_kz = known_k / sd(known_k), ind10 = ind37 / 10, com10 = com37 / 10,
           holc_D = as.numeric(holc == "D"), holc_C = as.numeric(holc == "C"), holc_ungraded = as.numeric(holc == "ungraded"), zone_ind = as.numeric(zone29 == "industrial"),
           agegrp = cut(AGE, c(-1, 14, 29, 200), labels = c("0-14 in 1940", "15-29 in 1940", "30+ in 1940")), h_haz_job = fifelse(is.na(h_haz_job), 0, h_haz_job))]
  L }
L <- prep(L0)
CTRL <- c("black", "hisp", "fb", "fb_mex", "born_co", "mover", "mover_m", "owner", "hc_q", "h_hs", "h_hs_m", "h_sei", "h_sei_m")
EXP <- list(`1929 industrial district` = "zone_ind", `Industrial land within 250 m, 1937 (per 10 points)` = "ind10", `Hazardous trade within 500 m (to 1940)` = "haz_500",
            `HOLC grade D (vs A/B)` = c("holc_D", "holc_C", "holc_ungraded"), `Placebo: commercial land within 250 m (per 10 points)` = "com10")
fit <- function(d, terms, report, ctrl = CTRL, extra = character()) {
  ctrl <- setdiff(ctrl, extra); ctrl <- ctrl[vapply(ctrl, function(v) length(unique(d[[v]])) > 1, TRUE)]
  if (any(vapply(report, function(v) length(unique(d[[v]])) < 2, TRUE)) || nrow(d) < 200) return(NULL)
  f <- as.formula(paste("death_age ~", paste(c(terms, ctrl), collapse = " + "), "+ factor(byear)", if (length(unique(d$female)) > 1) "+ female"))
  m <- tryCatch(lm(f, data = d, weights = w), error = function(e) NULL); if (is.null(m)) return(NULL)
  ct <- coeftest(m, vcov. = vcovCL(m, cluster = ~ED, type = "HC1"))
  rbindlist(lapply(intersect(report, rownames(ct)), function(t) data.table(term = t, years = round(ct[t, 1], 3), lo = round(ct[t, 1] - 1.96 * ct[t, 2], 3),
    hi = round(ct[t, 1] + 1.96 * ct[t, 2], 3), p = signif(ct[t, 4], 3), n = nobs(m)))) }
by_subset <- function(d, label_col, subsets) rbindlist(lapply(names(subsets), function(s) { ds <- d[eval(subsets[[s]])]
  rbindlist(lapply(names(EXP), function(e) { r <- fit(ds, EXP[[e]], EXP[[e]][1]); if (is.null(r)) NULL else r[, c(label_col, "exposure") := list(s, e)] })) }))
lab <- function(r, src) if (is.null(r) || !nrow(r)) NULL else r[, people := FL[[src]]]
# ---------------------------------------------------------------- 1. childhood exposure
R1 <- rbindlist(lapply(names(FL), function(s) lab(by_subset(L[src == s], "age_in_1940", list(`0-14 in 1940` = quote(AGE <= 14), `15-29 in 1940` = quote(AGE >= 15 & AGE <= 29), `30+ in 1940` = quote(AGE >= 30))), s)))
fwrite(R1, file.path(O, "censoc_ext_childhood.csv")); message("1. childhood"); print(R1[, .(people = substr(people, 1, 12), age_in_1940, exposure = substr(exposure, 1, 30), years, lo, hi, p, n)])
# ---------------------------------------------------------------- 2. stayers and leavers (Numident place of death)
GF <- file.path(W, "censoc_numident_geography_supplement_v1.csv"); R2 <- NULL; R2b <- NULL
if (file.exists(GF)) {
  G <- fread(GF, select = c("HISTID", "death_fips", "death_state"), colClasses = c(HISTID = "character", death_fips = "character"))
  G[, histid := toupper(HISTID)]; METRO <- sprintf("08%03d", c(1, 5, 14, 31, 35, 59))   # Adams, Arapahoe, Broomfield, Denver, Douglas, Jefferson
  N <- merge(L[src == "Numident"], G[, .(histid, death_fips = fifelse(is.na(suppressWarnings(as.integer(death_fips))), NA_character_, sprintf("%05d", suppressWarnings(as.integer(death_fips)))), death_state)], by = "histid", all.x = TRUE)
  N[, `:=`(died_metro = as.numeric(death_fips %in% METRO), died_denver = as.numeric(death_fips == "08031"), died_colorado = as.numeric(toupper(death_state) == "CO"))]
  R2b <- N[!is.na(death_fips), .(people = .N, pct_died_denver_metro = round(100 * weighted.mean(died_metro, w), 1), pct_died_denver_county = round(100 * weighted.mean(died_denver, w), 1),
                                 pct_died_colorado = round(100 * weighted.mean(died_colorado, w), 1)), by = .(group = fifelse(zone29 == "industrial", "1940 address in a 1929 industrial district",
                                 fifelse(ind37 >= 10, "10%+ industrial land within 250 m", "other 1940 addresses")))]
  # does a 1940 industrial address predict dying in the metro? (linear probability, same controls; reported as percentage points)
  st <- rbindlist(lapply(names(EXP), function(e) { d <- N[!is.na(death_fips)]; ctrl <- CTRL[vapply(CTRL, function(v) length(unique(d[[v]])) > 1, TRUE)]
    m <- lm(as.formula(paste("died_metro ~", paste(c(EXP[[e]], ctrl), collapse = " + "), "+ factor(byear) + female")), data = d, weights = w)
    ct <- coeftest(m, vcov. = vcovCL(m, cluster = ~ED, type = "HC1")); t <- EXP[[e]][1]
    data.table(exposure = e, analysis = "Died in the Denver metro (percentage points)", years = round(100 * ct[t, 1], 2), lo = round(100 * (ct[t, 1] - 1.96 * ct[t, 2]), 2),
               hi = round(100 * (ct[t, 1] + 1.96 * ct[t, 2]), 2), p = signif(ct[t, 4], 3), n = nobs(m)) }))
  sy <- by_subset(N, "analysis", list(`Age at death, people who died in the Denver metro` = quote(died_metro == 1), `Age at death, people who died elsewhere` = quote(died_metro == 0 & !is.na(death_fips))))
  R2 <- rbind(st, sy, fill = TRUE)
  fwrite(R2, file.path(O, "censoc_ext_stayers.csv")); fwrite(R2b, file.path(O, "censoc_ext_stayers_shares.csv")); message("2. stayers"); print(R2b); print(R2[, .(analysis = substr(analysis, 1, 40), exposure = substr(exposure, 1, 30), years, lo, hi, p, n)])
} else message("2. skipped: unzip censoc_numident_geography_supplement_v1.csv from CenSoc_Numident.zip into work/censoc/")
# ---------------------------------------------------------------- 3. work and home
tg <- function(r, a, m) if (is.null(r)) NULL else r[, `:=`(analysis = a, model = m)]
R3 <- rbindlist(lapply(names(FL), function(s) { d <- L[src == s]; out <- list()
  dm <- d[female == 0 & AGE >= 18 & LABFORCE == 2]                              # men in the 1940 labour force: their own industry
  out[[1]] <- tg(fit(dm, "haz_job", "haz_job"), "Own job in a hazardous industry (men in the 1940 labour force)", "job only")
  out[[2]] <- tg(fit(dm, "manuf_job", "manuf_job"), "Own job in manufacturing (men in the 1940 labour force)", "job only")
  for (e in c("zone_ind", "ind10", "haz_500")) out[[length(out) + 1]] <- tg(fit(dm, c(e, "haz_job"), c(e, "haz_job")), "Men in the 1940 labour force: address and own job together", e)
  out[[length(out) + 1]] <- tg(fit(d, "h_haz_job", "h_haz_job"), "Household head in a hazardous industry (everyone)", "job only")
  for (e in c("zone_ind", "ind10", "haz_500")) out[[length(out) + 1]] <- tg(fit(d, c(e, "h_haz_job"), c(e, "h_haz_job")), "Everyone: address and household head's job together", e)
  lab(rbindlist(out, fill = TRUE), s) }), fill = TRUE)
R3[, term := c(haz_job = "own job: hazardous industry", manuf_job = "own job: manufacturing", h_haz_job = "head's job: hazardous industry", zone_ind = "1929 industrial district",
               ind10 = "industrial land within 250 m (per 10 points)", haz_500 = "hazardous trade within 500 m")[term]]
fwrite(R3, file.path(O, "censoc_ext_work_home.csv")); message("3. work and home"); print(R3[, .(people = substr(people, 1, 12), analysis = substr(analysis, 1, 34), term, years, lo, hi, p, n)])
# ---------------------------------------------------------------- 4. groups
R4 <- rbindlist(lapply(names(FL), function(s) lab(by_subset(L[src == s], "group", list(`Hispanic` = quote(hisp == 1), `Black` = quote(black == 1),
        `White, not Hispanic` = quote(black == 0 & hisp == 0 & RACE == 1), `Renting household` = quote(owner == 0), `Owner household` = quote(owner == 1))), s)))
fwrite(R4, file.path(O, "censoc_ext_groups.csv")); message("4. groups"); print(R4[, .(people = substr(people, 1, 12), group, exposure = substr(exposure, 1, 30), years, lo, hi, p, n)])
# ---------------------------------------------------------------- 5. who is linked
lk <- unique(L0[, .(HISTID = histid, src)]); P[, `:=`(linked_dmf = HISTID %in% lk[src == "DMF", HISTID], linked_num = HISTID %in% lk[src == "Numident", HISTID])]
Pe <- P[!is.na(x) & GQ < 3 & AGE <= 50]                                                # ages that could die inside either window
Pe[, grp := fifelse(zone29 == "industrial", "1929 industrial district", fifelse(!is.na(ind37) & ind37 >= 10, "10%+ industrial land within 250 m", "other addresses"))]
R5 <- rbind(Pe[SEX == 1, .(people = "Men aged 0-50 in 1940", n_1940 = .N, pct_linked_dmf = round(100 * mean(linked_dmf), 2), pct_linked_numident = round(100 * mean(linked_num), 2)), by = grp],
            Pe[SEX == 2, .(people = "Women aged 0-50 in 1940", n_1940 = .N, pct_linked_dmf = NA_real_, pct_linked_numident = round(100 * mean(linked_num), 2)), by = grp],
            Pe[, .(people = "Everyone aged 0-50 in 1940", n_1940 = .N, pct_linked_dmf = NA_real_, pct_linked_numident = round(100 * mean(linked_num), 2)), by = .(grp = paste("HOLC", fifelse(is.na(holc), "ungraded", holc)))])
lp <- function(yname, d) { d <- copy(d); d[, `:=`(hc_q = factor(fifelse(is.na(hc_q), 0L, hc_q)), h_hs_m = as.numeric(is.na(h_hs)), h_hs = fifelse(is.na(h_hs), 0, h_hs), h_sei_m = as.numeric(is.na(h_sei)),
    h_sei = fifelse(is.na(h_sei), 0, h_sei), mover_m = as.numeric(is.na(mover)), mover = fifelse(is.na(mover), 0, mover), owner = fifelse(is.na(owner), 0, owner),
    zone_ind = as.numeric(zone29 == "industrial"), ind10 = ind37 / 10, yv = as.numeric(get(yname)))]
  ctrl <- CTRL[vapply(CTRL, function(v) length(unique(d[[v]])) > 1, TRUE)]
  rbindlist(lapply(c("zone_ind", "ind10", "haz_500"), function(e) { m <- lm(as.formula(paste("yv ~", e, "+", paste(ctrl, collapse = " + "), "+ factor(AGE)", if (length(unique(d$SEX)) > 1) "+ factor(SEX)")), data = d)
    ct <- coeftest(m, vcov. = vcovCL(m, cluster = ~ED, type = "HC1"))
    data.table(outcome = yname, term = e, pct_points = round(100 * ct[e, 1], 3), lo = round(100 * (ct[e, 1] - 1.96 * ct[e, 2]), 3), hi = round(100 * (ct[e, 1] + 1.96 * ct[e, 2]), 3), p = signif(ct[e, 4], 3), n = nobs(m)) })) }
R5m <- rbind(lp("linked_dmf", Pe[SEX == 1]), lp("linked_num", Pe))
fwrite(R5, file.path(O, "censoc_ext_linkage_shares.csv")); fwrite(R5m, file.path(O, "censoc_ext_linkage_models.csv")); message("5. linkage"); print(R5); print(R5m)
# ---------------------------------------------------------------- 6. Gompertz hazard ratios
GW <- list(DMF = c(1975, 2005), Numident = c(1988, 2005))   # DMF coverage is most complete through 2005
R6 <- rbindlist(lapply(names(FL), function(s) { d <- as.data.frame(L[src == s & dyear >= GW[[s]][1] & dyear <= GW[[s]][2]])
  rbindlist(lapply(names(EXP), function(e) { ctrl <- CTRL[vapply(CTRL, function(v) length(unique(d[[v]])) > 1, TRUE)]
    f <- as.formula(paste("death_age ~", paste(c(EXP[[e]], sub("^hc_q$", "as.factor(hc_q)", ctrl)), collapse = " + "), if (s == "Numident") "+ as.factor(female)"))
    lt <- GW[[s]][1]; rt <- GW[[s]][2]
    g <- tryCatch(if (s == "Numident") gompertztrunc::gompertz_mle(f, left_trunc = lt, right_trunc = rt, data = d, weights = w, lower_age_bound = 65)
                  else gompertztrunc::gompertz_mle(f, left_trunc = lt, right_trunc = rt, data = d, weights = w),
                  error = function(err) { message(s, " ", e, ": ", conditionMessage(err)); NULL })
    if (is.null(g)) return(NULL); r <- as.data.table(g$results)[parameter == EXP[[e]][1]]
    ex <- tryCatch(as.data.table(gompertztrunc::convert_hazards_to_ex(g$results, age = 65, use_model_estimates = TRUE))[parameter == EXP[[e]][1]], error = function(err) NULL)
    out <- data.table(people = FL[[s]], window = paste(GW[[s]], collapse = "-"), exposure = e, hr = round(r$hr, 3), hr_lower = round(r$hr_lower, 3), hr_upper = round(r$hr_upper, 3),
                      converged = g$optim_fit$convergence == 0, n = nrow(d))
    if (!is.null(ex) && nrow(ex)) out[, `:=`(e65_years = round(ex$e65, 2), e65_lower = round(ex$e65_lower, 2), e65_upper = round(ex$e65_upper, 2))]
    out })) }), fill = TRUE)
fwrite(R6, file.path(O, "censoc_ext_gompertz.csv")); message("6. Gompertz"); print(R6)
# ---------------------------------------------------------------- 7. displacement: 1940 addresses on land later cleared
A <- "app/data"; UTM <- 26913
hw0 <- st_transform(st_read(file.path(A, "highways_denver.geojson"), quiet = TRUE), UTM)
mr <- hw0[hw0$kind == "Major road" & !is.na(hw0$start_year) & hw0$start_year <= 1940, ]   # major roads (trunk, primary) already open in 1940
hw <- hw0; hw <- hw[hw$kind == "Freeway" & !grepl("_link", hw$highway) & !is.na(hw$start_year) & hw$start_year >= 1950 & hw$start_year <= 1979, ]
disp <- function(d) { pts <- st_as_sf(d[, .(x, y)], coords = c("x", "y"), crs = UTM)
  d[, fw_row := as.numeric(lengths(st_is_within_distance(pts, hw, 75)) > 0)]
  d[, fw_near := as.numeric(fw_row == 0 & lengths(st_is_within_distance(pts, hw, 500)) > 0)]
  d[, major_road_100 := if (nrow(mr)) as.numeric(lengths(st_is_within_distance(pts, mr, 100)) > 0) else NA_real_]
  lu <- lapply(c(1937, 1957, 1977), function(yy) { r <- rast(file.path(A, sprintf("landuse_%d_20m.tif", yy))); extract(r, project(vect(pts), crs(r)))[, 2] })
  d[, `:=`(lu37 = lu[[1]], lu57 = lu[[2]], lu77 = lu[[3]])]
  d[, cleared := as.numeric(lu37 %in% 5:6 & lu57 %in% 5:6 & lu77 %in% c(1:4, 7))]   # 5-6 residential; 1 industrial, 2 waste, 3 transport, 4 commercial, 7 institutional
  d[is.na(lu37) | is.na(lu77), cleared := NA_real_]
  d[, displaced := as.numeric(fw_row == 1 | cleared %in% 1)]; d }
L <- disp(L); P7 <- disp(P[!is.na(x) & GQ < 3])
R7s <- P7[, .(residents_1940 = .N, pct_hispanic = round(100 * mean(hisp), 1), pct_black = round(100 * mean(black), 1), pct_foreign_born = round(100 * mean(fb), 1),
              pct_owner = round(100 * mean(owner, na.rm = TRUE), 1)), by = .(address = fcase(fw_row == 1, "in a later freeway's path (within 75 m)", cleared %in% 1, "on land cleared by 1977 (USGS)",
              fw_near == 1, "75-500 m from a later freeway", default = "elsewhere"))]
fitfe <- function(d, term, fe) { ctrl <- CTRL[vapply(CTRL, function(v) length(unique(d[[v]])) > 1, TRUE)]
  f <- as.formula(paste("death_age ~", term, "+", paste(ctrl, collapse = " + "), "+ factor(byear)", if (length(unique(d$female)) > 1) "+ female", if (fe) "+ factor(ED)"))
  m <- lm(f, data = d, weights = w); ct <- coeftest(m, vcov. = vcovCL(m, cluster = ~ED, type = "HC1"))
  data.table(term = term, ed_fixed_effects = fe, years = round(ct[term, 1], 3), lo = round(ct[term, 1] - 1.96 * ct[term, 2], 3), hi = round(ct[term, 1] + 1.96 * ct[term, 2], 3),
             p = signif(ct[term, 4], 3), n = nobs(m), n_exposed = sum(d[[term]] == 1, na.rm = TRUE)) }
R7 <- rbindlist(lapply(names(FL), function(s) { d <- L[src == s]
  rbindlist(lapply(c("fw_row", "fw_near", "cleared", "displaced", "major_road_100"), function(t) rbindlist(lapply(c(FALSE, TRUE), function(fe) { dd <- d[!is.na(get(t))]
    if (sum(dd[[t]] == 1) < 30) return(NULL); fitfe(dd, t, fe) }))))[, people := FL[[s]]] }), fill = TRUE)
R7[, term := c(fw_row = "1940 address in a later freeway's path (within 75 m)", fw_near = "1940 address 75-500 m from a later freeway (traffic, not cleared)", cleared = "1940 address on residential land cleared by 1977", displaced = "in a freeway's path or cleared", major_road_100 = "1940 address within 100 m of a major road open in 1940")[term]]
fwrite(R7s, file.path(O, "censoc_ext_displacement_who.csv")); fwrite(R7, file.path(O, "censoc_ext_displacement.csv")); message("7. highways and displacement"); print(R7s); print(R7)
# ---------------------------------------------------------------- summary
kab <- function(x) { if (is.null(x) || !nrow(x)) return("(not run)"); x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# CenSoc: further analyses of Denver's 1940 residents", "", "Years of age at death (95% CI) unless stated; OLS with birth-year fixed effects, 1940 controls, CenSoc weights, errors clustered by 1940 ED.", "",
             "## 1. By age in 1940", "", kab(R1), "", "## 2. Stayers and leavers (Numident)", "", kab(R2b), "", kab(R2), "", "## 3. Work and home", "", kab(R3), "",
             "## 4. Groups", "", kab(R4), "", "## 5. Who is linked (share of 1940 residents with a death record in the window)", "", kab(R5), "", kab(R5m), "",
             "## 6. Gompertz hazard ratios (and change in life expectancy at 65, years)", "", kab(R6), "",
             "## 7. Highways and displacement", "", kab(R7s), "", kab(R7)), file.path(O, "censoc_extensions_summary.md"))
message("wrote ", O)
