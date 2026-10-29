# R port on the real Denver ADDRFEAT: the 30 committed keys that the Python slow test checked (tests/geocoding/.cache/real/python_real_keys.json).
# Same code and coordinates as Python; 12 m (the side offset) from the committed pre-review coordinates. Skipped unless the slow pytest
# run has prepared .cache/real (work/tiger symlinks + Python results). Building the R index for Denver County takes ~10 s (cached as .rds).
suppressPackageStartupMessages({ library(testthat); library(jsonlite) })
source(file.path(ROOT, "R", "geocode_tiger.R"))

test_that("real Denver keys: identical to Python, 12 m from the committed points", {
  f <- file.path(CACHE, "real", "python_real_keys.json"); tiger <- file.path(CACHE, "real", "work", "tiger")
  skip_if_not(file.exists(f) && length(Sys.glob(file.path(tiger, "*_addrfeat.shp"))) > 0, "run pytest tests/geocoding -m slow first (needs work/tiger)")
  g <- tiger_geocoder(tiger, file.path(ROOT, "data", "geocoder", "zip_city.csv"), file.path(ROOT, "data", "geocoder", "zip_centroids.csv"),
                      cache = file.path(CACHE, "real", "tiger_index_r.rds"))
  # the cached R index must not predate the R geocoder source
  if (file.mtime(file.path(CACHE, "real", "tiger_index_r.rds")) < file.mtime(file.path(ROOT, "R", "geocode_tiger.R"))) {
    file.remove(file.path(CACHE, "real", "tiger_index_r.rds"))
    g <- tiger_geocoder(tiger, file.path(ROOT, "data", "geocoder", "zip_city.csv"), file.path(ROOT, "data", "geocoder", "zip_centroids.csv"), cache = file.path(CACHE, "real", "tiger_index_r.rds")) }
  K <- fromJSON(f, simplifyVector = FALSE); expect_equal(length(K), 30)
  d_m <- function(la1, lo1, la2, lo2) 6371000 * sqrt(((la2 - la1) * pi / 180)^2 + ((lo2 - lo1) * pi / 180 * cos(la1 * pi / 180))^2)
  for (k in K) {
    r <- geocode_one(g, k$street, k$city, k$zip); lab <- paste(k$street, k$zip)
    expect_equal(r$quality, k$quality, info = lab); expect_equal(r$quality, "range_interp", info = lab)
    expect_equal(r$lat, k$lat, tolerance = 1e-9, info = lab); expect_equal(r$lon, k$lon, tolerance = 1e-9, info = lab)
    d <- d_m(k$lat_py_old, k$lon_py_old, r$lat, r$lon); expect_true(d > 11.5 && d < 12.5, info = paste(lab, round(d, 2), "m from the committed point"))
  }
  expect_equal(geocode_one(g, "450 KALAMATH", "DENVER", "80223")$quality, "range_interp_dirzip")
  expect_lt(geocode_one(g, "450 KALAMATH", "DENVER", "80223")$lat, 39.7163)
  expect_false(startsWith(geocode_one(g, "4000 S KALAMATH", "DENVER", "80223")$quality, "range_interp"))
})
