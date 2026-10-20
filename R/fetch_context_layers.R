# Download the contamination, emissions, urban-renewal, lead and health layers used by R/context_layers.R.
#
#   Rscript R/fetch_context_layers.R
#
# Everything goes to work/context/ (git-ignored; re-downloadable). Sources (all public):
#   petroleum_releases.csv       Colorado Division of Oil & Public Safety, Petroleum Releases 1986- (data.colorado.gov iimu-7683)
#   tank_facilities.csv          Regulated Storage Tank Facilities (data.colorado.gov iazk-c8xj)
#   tri/tri_<year>_CO.csv        EPA Toxics Release Inventory basic data files, Colorado, 1987- (data.epa.gov)
#   aqs_denver.csv               EPA AQS annual concentration by monitor, 1980-, Denver-metro counties (aqs.epa.gov airdata)
#   ur_projects.geojson, ur_non_spatial.csv   Renewing Inequality urban-renewal projects (University of Richmond DSL; CC BY-NC)
#   superfund_ou_co.geojson      EPA Superfund operable-unit boundaries, Colorado (EPA public feature service)
#   lead_risk_tracts.geojson     CDPHE modelled childhood lead-risk decile by census tract, 2018 (CDPHE CoHealth Maps)
#   places_tracts_co.csv         CDC PLACES census-tract health estimates, Colorado (data.cdc.gov yjkw-uj5s, 2024 release)
#   usaleep_co.csv               NCHS US Small-area Life Expectancy Estimates, 2010-2015, Colorado tracts
# Re-running skips files already downloaded (delete one to refresh it).
options(timeout = 1800)
for (p in c("data.table", "jsonlite")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages(library(data.table))
D <- "work/context"; dir.create(file.path(D, "tri"), showWarnings = FALSE, recursive = TRUE)
get <- function(url, f, mode = "wb") { d <- file.path(D, f); if (file.exists(d) && file.size(d) > 0) return(invisible(d))
  message("downloading ", f); ok <- tryCatch({ download.file(url, d, mode = mode, quiet = TRUE); TRUE }, error = function(e) { message("  failed: ", conditionMessage(e)); FALSE })
  if (!ok && file.exists(d)) file.remove(d); invisible(if (ok) d else NULL) }
# ---------------------------------------------------------------- Colorado petroleum releases and tank facilities (Socrata)
get("https://data.colorado.gov/resource/iimu-7683.csv?$limit=200000", "petroleum_releases.csv")
get("https://data.colorado.gov/resource/iazk-c8xj.csv?$limit=200000", "tank_facilities.csv")
# ---------------------------------------------------------------- EPA TRI basic data, Colorado, each year
for (y in 1987:(as.integer(format(Sys.Date(), "%Y")) - 1))
  get(sprintf("https://data.epa.gov/efservice/downloads/tri/mv_tri_basic_download/%d_CO/csv", y), sprintf("tri/tri_%d_CO.csv", y))
message(length(Sys.glob(file.path(D, "tri", "*.csv"))), " TRI year files")
# ---------------------------------------------------------------- EPA AQS annual means by monitor, Denver-metro counties
aqsf <- file.path(D, "aqs_denver.csv")
if (!file.exists(aqsf)) {
  CTY <- c("001", "005", "014", "031", "035", "059")      # Adams, Arapahoe, Broomfield, Denver, Douglas, Jefferson
  A <- rbindlist(lapply(1980:(as.integer(format(Sys.Date(), "%Y")) - 1), function(y) {
    z <- tempfile(fileext = ".zip"); ok <- tryCatch({ download.file(sprintf("https://aqs.epa.gov/aqsweb/airdata/annual_conc_by_monitor_%d.zip", y), z, mode = "wb", quiet = TRUE); TRUE }, error = function(e) FALSE)
    if (!ok) { message("  AQS ", y, ": not available"); return(NULL) }
    x <- fread(cmd = paste("unzip -p", shQuote(z)), colClasses = c(`State Code` = "character", `County Code` = "character", `Site Num` = "character"))
    unlink(z); x <- x[`State Code` == "08" & `County Code` %in% CTY]
    message("  AQS ", y, ": ", nrow(x), " monitor-pollutant rows")
    x[, .(year = Year, state = `State Code`, county = `County Code`, site = `Site Num`, parameter_code = `Parameter Code`, poc = POC, latitude = Latitude, longitude = Longitude,
          parameter = `Parameter Name`, duration = `Sample Duration`, standard = `Pollutant Standard`, units = `Units of Measure`, event = `Event Type`,
          obs_pct = `Observation Percent`, completeness = `Completeness Indicator`, mean = `Arithmetic Mean`, site_name = `Local Site Name`)] }), fill = TRUE)
  fwrite(A, aqsf) }
# ---------------------------------------------------------------- Renewing Inequality (urban renewal)
R0 <- "https://raw.githubusercontent.com/americanpanorama/Renewing_Inequality_Data/master/Data/"
get(paste0(R0, "ur_projects.geojson"), "ur_projects.geojson"); get(paste0(R0, "non_spatial_data.csv"), "ur_non_spatial.csv"); get(paste0(R0, "codebook.csv"), "ur_codebook.csv")
# ---------------------------------------------------------------- EPA Superfund operable units, Colorado
get("https://services.arcgis.com/cJ9YHowT8TU7DUyn/arcgis/rest/services/FAC_Superfund_Operable_Unit_Boundaries_EPA_Public/FeatureServer/0/query?where=STATE_CODE%3D%27CO%27&outFields=EPA_ID,SITE_NAME,SITE_FEATURE_NAME,SITE_FEATURE_DESCRIPTION,NPL_STATUS_CODE,CITY_NAME,FEATURE_INFO_URL&outSR=4326&f=geojson",
    "superfund_ou_co.geojson")
# ---------------------------------------------------------------- CDPHE childhood lead risk (tracts)
get("https://www.cohealthmaps.dphe.state.co.us/arcgis/rest/services/DCEED/Childhood_Lead_Risk_EPHT_2018/MapServer/0/query?where=1%3D1&outFields=FIPS,County_Nam,Dec_Wsqrt&outSR=4326&f=geojson",
    "lead_risk_tracts.geojson")
# ---------------------------------------------------------------- CDC PLACES and NCHS USALEEP (tracts)
get("https://data.cdc.gov/resource/yjkw-uj5s.csv?stateabbr=CO&$limit=5000", "places_tracts_co.csv")
get("https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/NVSS/USALEEP/CSV/CO_A.CSV", "usaleep_co.csv")
writeLines(format(Sys.Date()), file.path(D, "download_date.txt"))
f <- list.files(D, recursive = TRUE); message("work/context now has ", length(f), " files:"); print(f[!grepl("^tri/", f)])
