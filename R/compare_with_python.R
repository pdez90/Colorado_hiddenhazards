# Re-geocode the directory addresses in R and compare with the published (Python) geocodes.
#   Rscript R/compare_with_python.R            # all 36,852 unique address keys (~1 hour)
#   Rscript R/compare_with_python.R 3000       # random sample of 3,000 keys
# Needs work/tiger (R: fetch_tiger_addrfeat()) and data/geocoder/*.csv (in the repository).
# Writes data/geocoder/r_vs_python.csv and prints agreement.
source("R/geocode_tiger.R")
args <- commandArgs(trailingOnly = TRUE)
keys <- fread("data/geocoder/geocode_keys_with_python_results.csv", colClasses = "character", na.strings = NULL)
if (length(args)) { set.seed(1); keys <- keys[sample(.N, min(.N, as.integer(args[1])))] }
t0 <- Sys.time()
g <- tiger_geocoder("work/tiger", "data/geocoder/zip_city.csv", "data/geocoder/zip_centroids.csv")
message("index built in ", round(difftime(Sys.time(), t0, units = "mins"), 1), " min")
res <- geocode_many(g, as.data.frame(keys), "street", "city", "zip")
res$lat_py <- as.numeric(res$lat_py); res$lon_py <- as.numeric(res$lon_py)
res$dist_m <- 6371000 * sqrt(((res$lat - res$lat_py) * pi / 180)^2 + ((res$lon - res$lon_py) * pi / 180 * cos(res$lat_py * pi / 180))^2)
res$same_quality <- res$geo_quality == res$quality_py
both <- !is.na(res$lat) & !is.na(res$lat_py)
fwrite(res, "data/geocoder/r_vs_python.csv")
cat(sprintf("keys: %d\nidentical quality code: %.2f%%\nboth located: %d; within 1 m: %.2f%%; within 10 m: %.2f%%; max %.1f m\nlocated by one only: %d\n",
            nrow(res), 100 * mean(res$same_quality), sum(both), 100 * mean(res$dist_m[both] <= 1), 100 * mean(res$dist_m[both] <= 10),
            max(c(0, res$dist_m[both])), sum(xor(!is.na(res$lat), !is.na(res$lat_py)))))
print(head(res[!res$same_quality | (both & res$dist_m > 1), c("street", "city", "zip", "geo_quality", "quality_py", "dist_m")], 20))
