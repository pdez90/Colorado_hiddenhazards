# R/geocode_tiger.R against the Python geocoder on the same synthetic fixture: identical quality codes and coordinates.
suppressPackageStartupMessages({ library(testthat); library(jsonlite) })
source(file.path(ROOT, "R", "geocode_tiger.R"))

test_that("parse_addr agrees with Python on the edge cases", {
  P <- fromJSON(need_cache("python_parse.json"), simplifyVector = FALSE)
  for (p in P) {
    r <- parse_addr(p$addr)
    expect_equal(if (is.na(r$num)) NULL else r$num, if (is.null(p$num)) NULL else as.numeric(p$num), info = p$addr)
    expect_equal(r$core, if (is.null(p$core)) "" else p$core, info = p$addr)
    expect_equal(r$pre, p$pre, info = p$addr); expect_equal(r$suf, p$suf, info = p$addr)
  }
})

test_that("parse_addr edge cases (direct)", {
  expect_equal(parse_addr("123N MAIN")[c("num", "core", "pre")], list(num = 123, core = "MAIN", pre = "N"))
  expect_equal(parse_addr("450S KALAMATH")$pre, "S")
  expect_equal(parse_addr("125-7 S WEBER")$num, 125)
  expect_equal(parse_addr("400 NO 5TH ST")[c("core", "pre", "suf")], list(core = "5TH", pre = "N", suf = "ST"))
  expect_equal(parse_addr("650 BROADWAY NO 5")$core, "BROADWAY")
  expect_equal(parse_addr("1234 1/2 MAIN ST")$num, 1234)
  expect_true(is.na(parse_addr("I70 FRONTAGE RD")$num))
})

g <- NULL
test_that("the index builds from the synthetic ADDRFEAT and finds the Denver grid", {
  skip_if_not(dir.exists(SYNTH), "synthetic fixture missing - run pytest tests/geocoding first")
  g <<- tiger_geocoder(file.path(SYNTH, "work", "tiger"), file.path(SYNTH, "data", "geocoder", "zip_city.csv"),
                       file.path(SYNTH, "data", "geocoder", "zip_centroids.csv"), cache = NULL)
  expect_equal(sort(g$gridzips), c("80204", "80205", "80210", "80211", "80219", "80223"))
  expect_equal(g$half[["80204|NS"]], "N"); expect_equal(g$half[["80223|NS"]], "S"); expect_equal(g$half[["80205|EW"]], "E"); expect_equal(g$half[["80219|EW"]], "W")
  expect_null(g$half[["80203|NS"]]); expect_false("80203" %in% g$gridzips)
})

test_that("interp_line offsets 12 m to the matched side", {
  co <- rbind(c(-105, 39.72), c(-105, 39.7215))
  L <- interp_line(co, 0.5, "L"); R <- interp_line(co, 0.5, "R")
  expect_equal(L[2], 39.72075); expect_equal(R[2], 39.72075)
  expect_equal(L[1], -105 - 12 / (111320 * cos(39.72 * pi / 180)), tolerance = 1e-12)
  expect_equal(R[1], -105 + 12 / (111320 * cos(39.72 * pi / 180)), tolerance = 1e-12)
})

test_that("every synthetic case gives the Python quality code and coordinates", {
  skip_if(is.null(g)); P <- fromJSON(need_cache("python_geocodes.json"), simplifyVector = FALSE)
  expect_gt(length(P), 40)
  for (p in P) {
    r <- geocode_one(g, p$street, p$city, p$zip)
    lab <- paste(p$street, p$city, p$zip, sep = " | ")
    expect_equal(r$quality, p$quality, info = lab)
    if (is.null(p$lat)) expect_true(is.na(r$lat), info = lab)
    else { expect_equal(r$lat, p$lat, tolerance = 1e-9, info = lab); expect_equal(r$lon, p$lon, tolerance = 1e-9, info = lab) }
  }
})

test_that("the review rules hold in R on their own", {
  skip_if(is.null(g))
  expect_equal(geocode_one(g, "450 KALAMATH", "DENVER", "80223")$quality, "range_interp_dirzip")
  expect_equal(geocode_one(g, "450 KALAMATH", "DENVER", "")$quality, "range_interp_dirambig_cityzips")
  expect_equal(geocode_one(g, "2350 24TH AVE", "DENVER", "80205")$quality, "range_interp_dirtype")
  expect_equal(geocode_one(g, "4000 S KALAMATH", "DENVER", "80223")$quality, "zip_centroid")
  expect_equal(geocode_one(g, "4000 N KALAMATH", "DENVER", "80223")$quality, "range_interp_cityzips_dirloose")
  expect_equal(geocode_one(g, "450 SKALAMATH", "DENVER", "80223")$quality, "range_interp_dirsplit")
  expect_equal(geocode_one(g, "2150 5 KALAMATH", "DENVER", "80204")$quality, "range_interp_trim")
  expect_equal(geocode_one(g, "3550 S BANNOCK", "DENVER", "")$quality, "range_interp_nearzips")
  a <- geocode_one(g, "450 KALAMATH", "DENVER", "80204"); b <- geocode_one(g, "451 KALAMATH", "DENVER", "80204")
  expect_equal(6371000 * abs(a$lon - b$lon) * pi / 180 * cos(a$lat * pi / 180), 24, tolerance = 0.01)
})

test_that("far(): a point near the printed ZIP's centroid is accepted (Python test_far_check_also_accepts_points_near_the_printed_zip)", {
  skip_if_not(dir.exists(SYNTH), "synthetic fixture missing - run pytest tests/geocoding first")
  g2 <- tiger_geocoder(file.path(SYNTH, "work", "tiger"), file.path(SYNTH, "data", "geocoder", "zip_city.csv"),
                       file.path(SYNTH, "data", "geocoder", "zip_centroids.csv"), max_km = 2, cache = NULL)
  r <- geocode_one(g2, "4050 KALAMATH", "DENVER", "80211")
  expect_equal(r$quality, "range_interp"); expect_equal(r$lat, 39.7708, tolerance = 1e-3)
  expect_equal(geocode_one(g2, "4050 KALAMATH", "DENVER", "")$quality, "city_centroid")
  expect_equal(geocode_one(g2, "450 S KALAMATH", "DENVER", "80211")$quality, "zip_centroid")
})

test_that("geocode_level maps codes as pipeline/build_sites.py", {
  expect_equal(geocode_level(c("range_interp", "range_interp_dirzip", "range_interp_dirambig", "fuzzy_range_interp", "range_interp_dirsplit", "street_nearest", "zip_centroid", "city_centroid", "none")),
               c("address", "address", "zip_centroid", "address_approx", "address_approx", "address_approx", "zip_centroid", "city_centroid", "none"))
})
