# Download Denver's public property records for the hedonic price model (R/hedonic_denver.R).
#
#   Rscript R/fetch_denver_property.R
#
# Source: City and County of Denver Open Data (Assessor), ArcGIS feature services, public records:
#   sales.csv      Real Property Sales and Transfers, 2015- (one row per recorded transfer; PARID, date, price, instrument, class)
#   parcels.csv    Parcels: schedule number, situs coordinates (State Plane CO Central, ft; EPSG 2877), property class, year built, area, units
#   res_chars.csv  Residential characteristics: above-grade area, basement, bedrooms, baths, stories, style, year built, land area, market neighbourhood
#   owners.csv     Parcels again, with owner name and mailing address (for R/ownership_denver.R)
# Grantor/grantee names are dropped from the sales. Owner names are public records but are used only to group parcels into owners;
# all files stay in work/property/ (git-ignored) and only aggregates are published.
# Re-running skips files already downloaded (delete one to refresh it).
for (p in c("data.table", "jsonlite")) if (!requireNamespace(p, quietly = TRUE)) install.packages(p, repos = "https://cloud.r-project.org")
suppressPackageStartupMessages(library(data.table))
D <- "work/property"; dir.create(D, showWarnings = FALSE, recursive = TRUE)
B <- "https://services1.arcgis.com/zdB7qR0BtYrg0Xpl/arcgis/rest/services/"
pull <- function(svc, fields, f, where = "1=1", page = 2000) {
  out <- file.path(D, f); if (file.exists(out) && file.size(out) > 0) return(invisible(fread(out, colClasses = "character")))
  n <- jsonlite::fromJSON(sprintf("%s%s/query?where=%s&returnCountOnly=true&f=json", B, svc, URLencode(where, reserved = TRUE)))$count
  message(f, ": ", n, " records")
  res <- vector("list", ceiling(n / page)); off <- 0; k <- 0
  repeat {
    u <- sprintf("%s%s/query?where=%s&outFields=%s&returnGeometry=false&orderByFields=OBJECTID&resultOffset=%d&resultRecordCount=%d&f=json",
                 B, svc, URLencode(where, reserved = TRUE), paste(fields, collapse = ","), off, page)
    j <- NULL; for (t in 1:4) { j <- tryCatch(jsonlite::fromJSON(u), error = function(e) NULL); if (!is.null(j$features)) break; Sys.sleep(5 * t) }
    if (is.null(j$features) || !length(j$features)) break
    k <- k + 1; res[[k]] <- as.data.table(j$features$attributes); off <- off + nrow(res[[k]])
    if (k %% 20 == 0) message("  ", off, " / ", n)
    if (!isTRUE(j$exceededTransferLimit) && nrow(res[[k]]) < page) break
  }
  x <- rbindlist(res, fill = TRUE); fwrite(x, out); message("  wrote ", out, " (", nrow(x), " rows)"); invisible(x)
}
pull("ODC_real_property_sales_and_transfers/FeatureServer/51",
     c("OBJECTID", "PARID", "RECEPTION_NUM", "INSTRUMENT", "SALE_YEAR", "SALE_MONTHDAY", "RECEPTION_DATE", "SALE_PRICE", "CLASS", "D_CLASS", "D_CLASS_N", "NBHD_1", "NBHD_1_CN"), "sales.csv")
pull("ODC_PROP_PARCELS_A/FeatureServer/245",
     c("OBJECTID", "SCHEDNUM", "SITUS_X_COORD", "SITUS_Y_COORD", "PROP_CLASS", "D_CLASS", "D_CLASS_CN", "ZONE_10", "LAND_AREA", "RES_ORIG_YEAR_BUILT", "RES_ABOVE_GRADE_AREA",
       "COM_ORIG_YEAR_BUILT", "COM_GROSS_AREA", "TOT_UNITS", "APPRAISED_LAND_VALUE", "APPRAISED_IMP_VALUE", "APPRAISED_TOTAL_VALUE"), "parcels.csv")
pull("ODC_real_property_residential_characteristics/FeatureServer/50",
     c("OBJECTID", "PARID", "CD", "OFCARD", "PROP_CLASS", "D_CLASS_CN", "LAND_SQFT", "AREA_ABG", "BSMT_AREA", "FBSMT_SQFT", "GRD_AREA", "STORY", "STYLE_CN", "BED_RMS",
       "FULL_B", "HLF_B", "CCYRBLT", "CCAGE_RM", "UNITS", "NBHD_1", "NBHD_1_CN"), "res_chars.csv")
pull("ODC_PROP_PARCELS_A/FeatureServer/245",
     c("OBJECTID", "SCHEDNUM", "OWNER_NAME", "OWNER_ADDRESS_LINE1", "OWNER_ADDRESS_LINE2", "OWNER_CITY", "OWNER_STATE", "OWNER_ZIP", "SITUS_ADDRESS_LINE1", "SITUS_ZIP",
       "SITUS_X_COORD", "SITUS_Y_COORD", "PROP_CLASS", "D_CLASS", "D_CLASS_CN", "TOT_UNITS", "RES_ORIG_YEAR_BUILT", "COM_ORIG_YEAR_BUILT"), "owners.csv")
writeLines(format(Sys.Date()), file.path(D, "download_date.txt"))
message("work/property: ", paste(list.files(D), collapse = ", "))
