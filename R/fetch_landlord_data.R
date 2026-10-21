# Data for the landlord analyses (R/ownership_denver.R, R/housing_conditions_denver.R).
#
#   Rscript R/fetch_landlord_data.R              all of the below
#   Rscript R/fetch_landlord_data.R registry     only the Colorado business registry (the slow one: about 3 million entities)
#
#   1. Colorado Secretary of State, Business Entities in Colorado (data.colorado.gov, dataset 4ykn-tg5h; public): entity names, principal
#      addresses and registered agents -> work/registry/co_business_entities.csv (git-ignored; agents are named people).
#   2. Census 2020 ZCTA gazetteer (internal points) -> data/raw/acs/zcta_gazetteer_2020.csv
#   3. ACS 2018-2022 5-year estimates by ZCTA: median household income (B19013), population and non-Hispanic white population (B03002)
#      -> data/raw/acs/zcta_acs.csv. Uses CENSUS_API_KEY from ~/.Renviron if set (works without one at low volume).
#   4. Eviction Lab (Princeton), eviction filings and judgments by census tract, 2000-2018 ("proprietary valid" file: counts from
#      court records purchased from vendors, kept only where the Lab judged them complete) -> work/evictionlab/ (Colorado rows only).
#      Cite: Gromis, Fellows, Hendrickson et al. (2022), Estimating eviction prevalence across the United States, PNAS 119(21).
options(timeout = 3600)
for (p in c("data.table", "jsonlite")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages(library(data.table))
args <- commandArgs(trailingOnly = TRUE); only_reg <- "registry" %in% args
for (d in c("work/registry", "data/raw/acs", "work/evictionlab")) dir.create(d, showWarnings = FALSE, recursive = TRUE)
# ---------------------------------------------------------------- 1. business registry, in pages
REG <- "work/registry/co_business_entities.csv"
COLS <- c("entityid", "entityname", "entitystatus", "entitytype", "jurisdictonofformation", "entityformdate", "principaladdress1", "principaladdress2",
          "principalcity", "principalstate", "principalzipcode", "agentfirstname", "agentmiddlename", "agentlastname", "agentorganizationname",
          "agentprincipaladdress1", "agentprincipalzipcode")
if (!file.exists(REG)) {
  pages <- list(); off <- 0; n <- 500000
  repeat {
    u <- sprintf("https://data.colorado.gov/resource/4ykn-tg5h.csv?$select=%s&$order=entityid&$limit=%d&$offset=%d", paste(COLS, collapse = ","), n, off)
    f <- tempfile(fileext = ".csv"); ok <- tryCatch({ download.file(u, f, quiet = TRUE, mode = "wb"); TRUE }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) { Sys.sleep(10); ok <- tryCatch({ download.file(u, f, quiet = TRUE, mode = "wb"); TRUE }, error = function(e) FALSE, warning = function(w) FALSE) }
    if (!ok) stop("registry download failed at offset ", off, "; run again")
    d <- fread(f, colClasses = "character"); file.remove(f)
    message(sprintf("  registry rows %s-%s", format(off + 1, big.mark = ","), format(off + nrow(d), big.mark = ",")))
    if (!nrow(d)) break
    pages[[length(pages) + 1]] <- d; off <- off + nrow(d); if (nrow(d) < n) break
  }
  R <- rbindlist(pages, fill = TRUE); for (cc in setdiff(COLS, names(R))) R[, (cc) := ""]
  for (cc in COLS) set(R, which(is.na(R[[cc]])), cc, "")
  fwrite(R[, ..COLS], REG); message("registry: ", format(nrow(R), big.mark = ","), " entities -> ", REG)
} else message("registry already downloaded: ", REG)
if (only_reg) quit(save = "no")
# ---------------------------------------------------------------- 2. ZCTA internal points
GZ <- "data/raw/acs/zcta_gazetteer_2020.csv"
if (!file.exists(GZ)) {
  z <- tempfile(fileext = ".zip"); download.file("https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_zcta_national.zip", z, mode = "wb", quiet = TRUE)
  g <- fread(unzip(z, exdir = tempdir())[1], colClasses = c(GEOID = "character")); setnames(g, trimws(names(g)))
  fwrite(g[, .(zcta = GEOID, lat = INTPTLAT, lon = INTPTLONG)], GZ); message("ZCTA points: ", nrow(g))
}
# ---------------------------------------------------------------- 3. ACS by ZCTA
AC <- "data/raw/acs/zcta_acs.csv"
if (!file.exists(AC)) {
  key <- Sys.getenv("CENSUS_API_KEY")
  u <- paste0("https://api.census.gov/data/2022/acs/acs5?get=B19013_001E,B03002_001E,B03002_003E&for=zip%20code%20tabulation%20area:*", if (nzchar(key)) paste0("&key=", key) else "")
  j <- jsonlite::fromJSON(u); a <- as.data.table(j[-1, , drop = FALSE]); setnames(a, j[1, ])
  num <- function(x) { v <- suppressWarnings(as.numeric(x)); v[!is.na(v) & v < 0] <- NA; v }               # the API codes missing as large negatives
  a <- a[, .(zcta = `zip code tabulation area`, med_hh_income = num(B19013_001E), pop = num(B03002_001E), white_nh = num(B03002_003E))]
  a[, pct_white_nh := round(100 * white_nh / pop, 1)]
  fwrite(a[, .(zcta, med_hh_income, pct_white_nh, pop)], AC); message("ACS ZCTAs: ", nrow(a))
}
# ---------------------------------------------------------------- 4. Eviction Lab, Colorado tracts and counties
S3 <- "https://eviction-lab-data-downloads.s3.amazonaws.com/"
EV <- list(tract = paste0(S3, c("data-for-analysis/tract_proprietary_valid_2000_2018.csv", "estimating-eviction-prevalance-across-us/tract_proprietary_valid_2000_2018.csv",
                                "estimating-eviction-prevalance-across-us/tract_proprietary_2000_2018.csv")),
           county = paste0(S3, c("data-for-analysis/county_proprietary_valid_2000_2018.csv", "estimating-eviction-prevalance-across-us/county_proprietary_valid_2000_2018.csv")))
for (k in names(EV)) { out <- sprintf("work/evictionlab/%s_proprietary_valid_2000_2018_CO.csv", k); if (file.exists(out)) next
  f <- tempfile(fileext = ".csv"); ok <- FALSE
  for (u in EV[[k]]) { ok <- tryCatch({ download.file(u, f, mode = "wb", quiet = TRUE); TRUE }, error = function(e) FALSE, warning = function(w) FALSE)
    if (ok) { message("Eviction Lab ", k, ": ", u); break } else message("Eviction Lab ", k, " file not reachable: ", u) }
  if (!ok) next
  d <- fread(f, colClasses = "character"); file.remove(f); message("Eviction Lab ", k, " columns: ", paste(names(d), collapse = ", "))
  idc <- names(d)[grepl("^(id|geoid|fips|cofips|GEOID)$", names(d), ignore.case = TRUE)][1]
  d <- d[substr(sprintf("%s", get(idc)), 1, 2) == "08" | (nchar(get(idc)) %in% c(10, 4) & substr(get(idc), 1, 1) == "8")]   # Colorado (FIPS 08; leading zero sometimes dropped)
  fwrite(d, out); message("  ", nrow(d), " Colorado rows -> ", out) }
message("done")
