# Mortgage lending today by census tract: HMDA 2018-2021 (the years reported on 2010 tract boundaries) for Colorado, from the
# CFPB/FFIEC HMDA data browser API (public, no key). The implemented-policy counterpart to the 1938 HOLC map (cf. Xu 2022).
#   Rscript R/fetch_hmda.R
# Downloads one CSV per year (home-purchase applications that were originated or denied), caches them in work/hmda/, and writes
#   data/results/hmda_tracts_2018_2021.csv  (also copied to app/data/): per 2010 tract, applications, denials, denial rate, the same
#   for Black and for Hispanic applicants, median loan amount and median applicant income.
# Denial rate = denied / (originated + denied); applications withdrawn, incomplete or approved-but-not-accepted are excluded.
suppressPackageStartupMessages({ library(data.table) })
dir.create("work/hmda", showWarnings = FALSE, recursive = TRUE); dir.create("data/results", showWarnings = FALSE)
YEARS <- 2018:2021
L <- rbindlist(lapply(YEARS, function(y) {
  f <- sprintf("work/hmda/hmda_CO_%d_purchase.csv", y)
  if (!file.exists(f)) { url <- sprintf("https://ffiec.cfpb.gov/v2/data-browser-api/view/csv?states=CO&years=%d&actions_taken=1,3&loan_purposes=1", y)
    message("downloading HMDA ", y, " (Colorado, home purchase, originated or denied) ..."); download.file(url, f, mode = "wb", quiet = TRUE) }
  d <- fread(f, colClasses = "character"); d[, year := y]; d }), fill = TRUE)
message(nrow(L), " loan records 2018-2021")
L[, `:=`(tract = census_tract, denied = action_taken == "3", black = grepl("Black", derived_race), hisp = grepl("^Hispanic", derived_ethnicity),
         amount = suppressWarnings(as.numeric(loan_amount)), inc = suppressWarnings(as.numeric(income)))]
L <- L[!is.na(tract) & nchar(tract) == 11 & substr(tract, 1, 2) == "08"]
H <- L[, .(apps = .N, denied = sum(denied), denial_rate = round(100 * mean(denied), 1),
           black_apps = sum(black), black_denial_rate = round(100 * mean(denied[black]), 1), hisp_apps = sum(hisp), hisp_denial_rate = round(100 * mean(denied[hisp]), 1),
           pct_apps_black = round(100 * mean(black), 1), pct_apps_hisp = round(100 * mean(hisp), 1),
           median_loan_k = round(median(amount, na.rm = TRUE) / 1000), median_income_k = round(median(inc, na.rm = TRUE))), by = .(GEOID = tract)]
H[black_apps < 10, black_denial_rate := NA_real_]; H[hisp_apps < 10, hisp_denial_rate := NA_real_]
fwrite(H, "data/results/hmda_tracts_2018_2021.csv"); file.copy("data/results/hmda_tracts_2018_2021.csv", "app/data/hmda_tracts_2018_2021.csv", overwrite = TRUE)
message("wrote data/results/hmda_tracts_2018_2021.csv: ", nrow(H), " tracts; statewide denial rate ", round(100 * mean(L$denied), 1), "% (Black ", round(100 * mean(L$denied[L$black]), 1), "%, Hispanic ", round(100 * mean(L$denied[L$hisp]), 1), "%)")
