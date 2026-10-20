# Download the contamination, emissions, urban-renewal, lead and health layers used by R/context_layers.R.
#
#   Rscript R/fetch_context_layers.R
#
# Everything goes to work/context/ (git-ignored; re-downloadable). Sources (all public):
#   petroleum_releases.csv       Colorado Division of Oil & Public Safety, Petroleum Releases 1986- (data.colorado.gov iimu-7683)
#   tank_facilities.csv          Regulated Storage Tank Facilities (data.colorado.gov iazk-c8xj)
#   tri/tri_<year>_CO.csv        EPA Toxics Release Inventory basic data files, Colorado, 1987- (data.epa.gov)
#   aqs_denver.csv               EPA AQS annual summaries by monitor, 1980-, Denver-metro counties (AQS Data Mart API; free key in ~/.Renviron)
#   ur_projects.geojson, ur_non_spatial.csv   Renewing Inequality urban-renewal projects (University of Richmond DSL; CC BY-NC)
#   superfund_ou_co.geojson      EPA Superfund operable-unit boundaries, Colorado (EPA public feature service)
#   lead_risk_tracts.geojson     CDPHE modelled childhood lead-risk decile by census tract, 2018 (CDPHE CoHealth Maps)
#   places_tracts_co.csv         CDC PLACES census-tract health estimates, Colorado (data.cdc.gov yjkw-uj5s, 2024 release)
#   usaleep_co.csv               NCHS US Small-area Life Expectancy Estimates, 2010-2015, Colorado tracts
#   sanborn_<years>.geojson      Library of Congress Sanborn volume extents for Denver, 1887-1951 (ArcGIS feature services, GMD_LOC)
#   denver_neighborhoods.geojson Denver statistical neighbourhoods (Denver Open Data)
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
CTY <- c("001", "005", "014", "031", "035", "059")      # Adams, Arapahoe, Broomfield, Denver, Douglas, Jefferson
if (!file.exists(aqsf) || file.size(aqsf) == 0) {
  # EPA AQS Data Mart API (annual summaries for the Denver-Aurora-Lakewood CBSA, 19740). Needs a free account: set AQS_EMAIL and AQS_KEY
  # in ~/.Renviron (never in the project). The key is never printed.
  em <- Sys.getenv("AQS_EMAIL"); ky <- Sys.getenv("AQS_KEY")
  if (!nzchar(em) || !nzchar(ky)) message("AQS: set AQS_EMAIL and AQS_KEY in ~/.Renviron to download air-quality data") else {
    if (!requireNamespace("httr", quietly = TRUE)) install.packages("httr", repos = "https://cloud.r-project.org")
    PARAMS <- list(c("14129", "11101", "42401", "42602", "42101"), c("44201", "81102", "88101", "45201"))   # lead (TSP), TSP, SO2, NO2, CO | ozone, PM10, PM2.5, benzene
    A <- rbindlist(lapply(1980:(as.integer(format(Sys.Date(), "%Y")) - 1), function(y) rbindlist(lapply(PARAMS, function(pp) {
      Sys.sleep(5)                                                                   # the API asks for at least 5 s between requests
      r <- tryCatch(httr::GET("https://aqs.epa.gov/data/api/annualData/byCBSA", httr::timeout(300),
                              query = list(email = em, key = ky, param = paste(pp, collapse = ","), bdate = sprintf("%d0101", y), edate = sprintf("%d1231", y), cbsa = "19740")),
                    error = function(e) NULL)
      if (is.null(r) || httr::status_code(r) != 200) { message("  AQS ", y, ": HTTP ", if (is.null(r)) "error" else httr::status_code(r)); return(NULL) }
      x <- jsonlite::fromJSON(httr::content(r, as = "text", encoding = "UTF-8"))$Data
      if (is.null(x) || !length(x) || !nrow(x)) return(NULL); x <- as.data.table(x)[county_code %in% CTY]
      x[, .(year, state = state_code, county = county_code, site = site_number, parameter_code, poc, latitude, longitude, parameter, duration = sample_duration,
            standard = pollutant_standard, units = units_of_measure, event = event_type, obs_pct = observation_percent, completeness = NA_character_,
            mean = arithmetic_mean, site_name = local_site_name)] }), fill = TRUE)), fill = TRUE)
    if (nrow(A)) { fwrite(A, aqsf); message("AQS: ", nrow(A), " monitor-year rows, ", min(A$year), "-", max(A$year)) } else message("AQS: nothing downloaded") } }
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
# ---------------------------------------------------------------- Sanborn volume extents for Denver (Library of Congress, Geography & Map Division)
for (ed in c("1887", "1890_1893", "1903_1904", "1929_1930", "1950_1951")) {
  f <- sprintf("sanborn_%s.geojson", ed); if (file.exists(file.path(D, f))) next
  svc <- sprintf("https://services5.arcgis.com/ohAFyIFvXFRGcC67/arcgis/rest/services/Denver_%s/FeatureServer", ed)
  lid <- tryCatch(jsonlite::fromJSON(paste0(svc, "?f=json"))$layers$id[1], error = function(e) NA)
  if (is.na(lid)) { message("  Sanborn ", ed, ": service not found"); next }
  get(sprintf("%s/%s/query?where=1%%3D1&outFields=TITLE,DESCRIPTION,VolYear&outSR=4326&f=geojson", svc, lid), f) }
# ---------------------------------------------------------------- Denver statistical neighbourhoods (for the Superfund soil table)
get("https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/ArcGIS/rest/services/Enriched_Statistical_Neighborhood/FeatureServer/0/query?where=1%3D1&outFields=NBHD_ID,NBHD_NAME&outSR=4326&f=geojson",
    "denver_neighborhoods.geojson")
writeLines(format(Sys.Date()), file.path(D, "download_date.txt"))
f <- list.files(D, recursive = TRUE); message("work/context now has ", length(f), " files:"); print(f[!grepl("^tri/", f)])
