# Reproduce the spatial and statistical core of the analysis in R.
#   Rscript R/run_all.R
#
# What R reproduces (each step is checked against the Python pipeline; see R/README.md):
#   1. geocoding   R/geocode_tiger.R   offline TIGER/Line 2023 address-range geocoder        (identical to Python on all keys)
#   2. sites       R/build_sites.R     30 m site clusters + matching to EPA/CDPHE inventories ("Not on any list")
#   3. exposures   R/build_exposures.R kernel-density exposures at block groups -> tracts
#   4. models      R/health_models.R   tract models (OLS HC3 + spatial error)
#                  R/mortality_bg.R    block-group mortality (needs restricted death counts; skipped if absent)
# What stays in Python: OCR of the scanned directories, parsing, SIC assignment and linking firms across editions
# (pipeline/*.py). Their outputs are the hand-off files read here: work/inv/records_linked.csv and work/inv/reg.csv.
source("R/geocode_tiger.R")
stopifnot(file.exists("work/inv/records_linked.csv"), file.exists("work/inv/reg.csv"))
if (!length(Sys.glob("work/tiger/*_addrfeat.shp"))) fetch_tiger_addrfeat("work/tiger", 2023)

message("== 1. geocoding")
recs <- fread("work/inv/records_linked.csv", colClasses = c(zip5 = "character"), na.strings = NULL)
keys <- unique(recs[, .(geo_key, street = street_n, city = city_g, zip = zip5)], by = "geo_key")
keys[is.na(street), street := ""]; keys[is.na(city), city := ""]; keys[is.na(zip), zip := ""]
g <- tiger_geocoder("work/tiger", "data/geocoder/zip_city.csv", "data/geocoder/zip_centroids.csv")
res <- geocode_many(g, as.data.frame(keys), "street", "city", "zip")
dir.create("work/geo", showWarnings = FALSE)
fwrite(res[, c("geo_key", "lat", "lon", "geo_quality")], "work/geo/tiger_results_R.csv")

run <- function(f, ...) { message("== ", f); status <- system2("Rscript", c(f, ...)); if (status != 0) stop(f, " failed") }
run("R/build_sites.R", "work/geo/tiger_results_R.csv")
if (file.exists("work/health/enviroscreen_v2_blockgroups.geojson")) {
  run("R/build_exposures.R", "work/inv/sites_app_R.csv", "work/inv/records_sites_R.csv"); run("R/health_models.R")
  if (file.exists("work/health/deaths_bg_year.csv")) run("R/mortality_bg.R", "work/inv/sites_app_R.csv", "work/inv/records_sites_R.csv")
}
