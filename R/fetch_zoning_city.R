# Download the City and County of Denver's official zoning layer (current districts, with the ordinance year of each).
#   Rscript R/fetch_zoning_city.R
# Source: City and County of Denver open data, feature service CCD_Zoning, layer 27 ("Zoning"; no key). Each polygon carries the zone
# district (ZONE_DISTRICT), its type (Residential, Mixed Use, Industrial, ...), the code it falls under (ZCODE_VERSION 2010, or 1956 for
# land still under the Former Chapter 59 code), and the year of the ordinance that last zoned it (ORD_YEAR).
# Output: work/zoning_city/denver_zoning_current.geojson (public data; kept out of git because it is re-downloadable and changes with
# each rezoning) and work/zoning_city/download_date.txt. Rerun to refresh.
suppressPackageStartupMessages({ library(sf); library(jsonlite) })
dir.create("work/zoning_city", showWarnings = FALSE, recursive = TRUE)
B <- "https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/ArcGIS/rest/services/CCD_Zoning/FeatureServer/27/query"
n <- fromJSON(paste0(B, "?where=1%3D1&returnCountOnly=true&f=json"))$count
FLD <- "OBJECTID,ZCODE_VERSION,ZONE_DISTRICT,ZONE_DISTRICT_GROUP,ZONE_DIST_TYPE,ZONE_DESCRIPTION,NBHD_CONTEXT,ORD_NUM,ORD_YEAR,PUD_NUM,PUD_STD_ZONE_DIST"
pages <- lapply(seq(0, n - 1, by = 1000), function(o) {
  u <- sprintf("%s?where=1%%3D1&outFields=%s&outSR=4326&orderByFields=OBJECTID&resultOffset=%d&resultRecordCount=1000&f=geojson", B, FLD, o)
  f <- tempfile(fileext = ".geojson"); download.file(u, f, quiet = TRUE); st_read(f, quiet = TRUE) })
Z <- do.call(rbind, pages); stopifnot(nrow(Z) == n)
out <- "work/zoning_city/denver_zoning_current.geojson"; if (file.exists(out)) file.remove(out); st_write(Z, out, quiet = TRUE)
writeLines(format(Sys.Date()), "work/zoning_city/download_date.txt")
message(nrow(Z), " zoning polygons written to ", out); print(table(Z$ZONE_DIST_TYPE)); print(table(Z$ZCODE_VERSION))
