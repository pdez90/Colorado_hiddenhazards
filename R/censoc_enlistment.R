# Young men's height, weight and schooling at WWII Army enlistment, by where they lived in Denver in 1940 (CenSoc enlistment records).
#
#   Rscript R/censoc_enlistment.R          (after R/censoc_denver_1940.R)
#
# Inputs (person-level, all in work/, never redistributed):
#   work/censoc/denver_1940_residents.rds                 every 1940 Denver resident with the address exposures (R/censoc_denver_1940.R)
#   work/censoc/censoc_enlistment_census_1940_v1.1.csv    CenSoc Enlistment-Census-1940: WWII Army enlistment records (c. 1938-1947) linked
#                                                         to the 1940 census by HISTID (from CenSoc_armyenlistment.zip)
# Exposures at the 1940 address as in R/censoc_denver_1940.R, plus a major road (trunk or primary) already open in 1940 within 100 m.
# Outcomes, measured at enlistment: height (inches; recorded only for enlistments before March 1943), weight (pounds; before March 1943),
# body-mass index, and years of schooling. The AGCT field is not used (it mixes weight, test scores and other codes).
# Sample: men in Denver in 1940, born 1905-1927, who enlisted from civilian life. OLS with birth-year and enlistment-year fixed effects,
# the same 1940 person and household controls as R/censoc_denver_1940.R, errors clustered by 1940 enumeration district; also for boys
# aged 0-17 in 1940, whose height and weight reflect childhood conditions. Who enlisted is shown too: men rejected on health grounds never
# appear in these records, which biases the comparisons towards zero if industrial neighbourhoods produced more rejections.
# Outputs (aggregates only): data/results/censoc/enlistment_models.csv, enlistment_shares.csv, enlistment_summary.md
suppressPackageStartupMessages({ library(data.table); library(sandwich); library(lmtest); library(sf) })
sf_use_s2(FALSE)
W <- "work/censoc"; O <- "data/results/censoc"; dir.create(O, showWarnings = FALSE, recursive = TRUE)
EF <- file.path(W, "censoc_enlistment_census_1940_v1.1.csv")
if (!file.exists(EF)) stop("unzip censoc_enlistment_census_1940_v1.1.csv from CenSoc_armyenlistment.zip into work/censoc/")
P <- as.data.table(readRDS(file.path(W, "denver_1940_residents.rds")))
E <- fread(EF, select = c("HISTID", "byear", "date_of_enlistment", "education", "height", "weight_before_march_1943", "source"), colClasses = c(HISTID = "character"), na.strings = c("NA", ""))
E[, HISTID := toupper(HISTID)]; E <- E[HISTID %in% P$HISTID][order(date_of_enlistment)][!duplicated(HISTID)]
E[, `:=`(enl_year = as.integer(substr(date_of_enlistment, 1, 4)), educ_years = c(`1` = 8, `3` = 9, `4` = 10, `5` = 11, `6` = 12, `7` = 13, `8` = 14, `9` = 15, `10` = 16, `11` = 17)[as.character(education)])]
E[, `:=`(weight = weight_before_march_1943, bmi = fifelse(!is.na(height) & !is.na(weight_before_march_1943), 703 * weight_before_march_1943 / height^2, NA_real_))]
M <- merge(P[SEX == 1 & !is.na(x) & GQ < 3], E[, .(HISTID, e_byear = byear, enl_year, source, educ_years, height, weight, bmi)], by = "HISTID", all.x = TRUE)
hw0 <- st_transform(st_read("app/data/highways_denver.geojson", quiet = TRUE), 26913)
mr <- hw0[hw0$kind == "Major road" & !is.na(hw0$start_year) & hw0$start_year <= 1940, ]          # major roads already open in 1940
M[, major_road_100 := as.numeric(lengths(st_is_within_distance(st_as_sf(M[, .(x, y)], coords = c("x", "y"), crs = 26913), mr, 100)) > 0)]
M[, byear := 1940L - AGE]; M <- M[byear >= 1905 & byear <= 1927]
M[, enlisted := as.numeric(!is.na(enl_year))]
M[, `:=`(hc_q = factor(fifelse(is.na(hc_q), 0L, hc_q)), h_hs_m = as.numeric(is.na(h_hs)), h_hs = fifelse(is.na(h_hs), 0, h_hs), h_sei_m = as.numeric(is.na(h_sei)),
         h_sei = fifelse(is.na(h_sei), 0, h_sei), mover_m = as.numeric(is.na(mover)), mover = fifelse(is.na(mover), 0, mover), owner = fifelse(is.na(owner), 0, owner),
         zone_ind = as.numeric(zone29 == "industrial"), ind10 = ind37 / 10, com10 = com37 / 10, holc_D = as.numeric(holc == "D"), holc_C = as.numeric(holc == "C"),
         holc_ungraded = as.numeric(holc == "ungraded"), haz_kz = haz_k / sd(haz_k, na.rm = TRUE))]
CTRL <- c("black", "hisp", "fb", "fb_mex", "born_co", "mover", "mover_m", "owner", "hc_q", "h_hs", "h_hs_m", "h_sei", "h_sei_m")
EXP <- list(`1929 industrial district` = "zone_ind", `Industrial land within 250 m, 1937 (per 10 points)` = "ind10", `Hazardous trade within 500 m (to 1940)` = "haz_500",
            `Hazardous trades to 1940, kernel (per SD)` = "haz_kz", `HOLC grade D (vs A/B)` = c("holc_D", "holc_C", "holc_ungraded"),
            `Major road open in 1940 within 100 m` = "major_road_100", `Placebo: commercial land within 250 m (per 10 points)` = "com10")
OUT <- c(height = "Height (inches)", weight = "Weight (pounds)", bmi = "Body-mass index", educ_years = "Years of schooling at enlistment", enlisted = "Enlisted (percentage points)")
fit <- function(d, yv, terms, fe = "factor(byear) + factor(enl_year)") { d <- d[!is.na(get(yv))]; for (t in terms) d <- d[!is.na(get(t))]
  if (nrow(d) < 150 || length(unique(d[[terms[1]]])) < 2) return(NULL)
  ctrl <- CTRL[vapply(CTRL, function(v) length(unique(d[[v]])) > 1, TRUE)]
  m <- lm(as.formula(paste(yv, "~", paste(c(terms, ctrl), collapse = " + "), "+", fe)), data = d); ct <- coeftest(m, vcov. = vcovCL(m, cluster = ~ED, type = "HC1"))
  k <- if (yv == "enlisted") 100 else 1; t <- terms[1]
  data.table(estimate = round(k * ct[t, 1], 3), lo = round(k * (ct[t, 1] - 1.96 * ct[t, 2]), 3), hi = round(k * (ct[t, 1] + 1.96 * ct[t, 2]), 3), p = signif(ct[t, 4], 3), n = nobs(m),
             outcome_mean = round(k * mean(d[[yv]]), 2)) }
SUB <- list(`Men born 1905-1927` = quote(TRUE), `Boys aged 0-17 in 1940` = quote(AGE <= 17))
R <- rbindlist(lapply(names(SUB), function(s) rbindlist(lapply(names(OUT), function(o) rbindlist(lapply(names(EXP), function(e) {
  d <- if (o == "enlisted") M[eval(SUB[[s]])] else M[enlisted == 1 & source == 0][eval(SUB[[s]])]
  r <- fit(d, o, EXP[[e]], if (o == "enlisted") "factor(byear)" else "factor(byear) + factor(enl_year)")
  if (is.null(r)) NULL else r[, `:=`(sample = s, outcome = OUT[[o]], exposure = e)] }))))))
setcolorder(R, c("sample", "outcome", "exposure"))
SH <- M[, .(men_1940 = .N, pct_enlisted = round(100 * mean(enlisted), 1), mean_height = round(mean(height[source %in% 0], na.rm = TRUE), 2),
            mean_weight = round(mean(weight[source %in% 0], na.rm = TRUE), 1), mean_school_years = round(mean(educ_years[source %in% 0], na.rm = TRUE), 2),
            with_height = sum(!is.na(height) & source %in% 0)),
        by = .(address_1940 = fcase(zone29 == "industrial", "1929 industrial district", !is.na(ind37) & ind37 >= 10, "10%+ industrial land within 250 m", default = "other addresses"))]
fwrite(R, file.path(O, "enlistment_models.csv")); fwrite(SH, file.path(O, "enlistment_shares.csv")); print(SH); print(R[, .(sample = substr(sample, 1, 6), outcome = substr(outcome, 1, 14), exposure = substr(exposure, 1, 28), estimate, lo, hi, p, n)])
kab <- function(x) { x <- as.data.frame(x); c(paste("|", paste(names(x), collapse = " | "), "|"), paste0(strrep("|---", ncol(x)), "|"),
  apply(x, 1, function(r) paste("|", paste(ifelse(is.na(r), "", trimws(r)), collapse = " | "), "|"))) }
writeLines(c("# WWII Army enlistment records: Denver men of 1940", "", "## By 1940 address", "", kab(SH), "",
             "## Differences at enlistment (95% CI); enlisted in percentage points", "", kab(R)), file.path(O, "enlistment_summary.md"))
message("wrote ", O)
