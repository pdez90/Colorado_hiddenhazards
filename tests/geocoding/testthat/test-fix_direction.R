# R/fix_direction_geocodes.R: conflict() on synthetic listings (Denver grid baselines, 500 m tolerance, street-level points only).
suppressPackageStartupMessages({ library(testthat); library(data.table) })
old <- setwd(ROOT); source("R/fix_direction_geocodes.R"); setwd(old)

test_that("dir_of reads the printed direction", {
  expect_equal(dir_of(c("4000 S KALAMATH", "4000 SOUTH KALAMATH", "4000 S. KALAMATH", "4000S KALAMATH", "4000 KALAMATH", "1500 E 1ST AVE", "100 WEST 38TH", NA)),
               c("S", "S", "S", "", "", "E", "W", ""))
})

test_that("conflict: wrong side of Ellsworth / Broadway, Denver, street level only", {
  L <- data.table(street = c("4000 S KALAMATH", "4000 N KALAMATH", "4000 S KALAMATH", "4000 S KALAMATH", "1500 W 5TH AVE", "1500 E 5TH AVE", "4000 KALAMATH", "4000 S KALAMATH", "100 S BROADWAY"),
                  city   = c("DENVER", "DENVER", "Denver", "DENVER", "DENVER", "DENVER", "DENVER", "ENGLEWOOD", "DENVER"),
                  lat    = c(39.77, 39.77, 39.7190, 39.70, 39.73, 39.73, 39.77, 39.77, 39.7140),
                  lon    = c(-105.0, -105.0, -105.0, -105.0, -104.98, -105.0, -105.0, -105.0, -104.9875),
                  level  = c("address", "address", "address", "address_approx", "address", "address", "address", "address", "address"))
  expect_equal(conflict(L$street, L$city, L$lat, L$lon, L$level),
               c(TRUE,      # S street 6 km north of Ellsworth
                 FALSE,     # N street north: fine
                 FALSE,     # 300 m north of Ellsworth: within the 500 m tolerance
                 FALSE,     # south: fine (approximate level still checked)
                 TRUE,      # W avenue east of Broadway
                 TRUE,      # E avenue 1 km west of Broadway
                 FALSE,     # no printed direction
                 FALSE,     # not Denver
                 FALSE))    # on the baselines
  expect_false(conflict("4000 S KALAMATH", "DENVER", 39.77, -105.0, "zip_centroid"))     # not a street-level point
  expect_false(conflict("4000 S KALAMATH", "DENVER", NA_real_, NA_real_, "address"))
})

test_that("rd(): reading strips OCR quote characters, so a read-write round trip is stable (fread misreads fields that start or end with escaped quotes)", {
  f <- tempfile(fileext = ".csv")
  writeLines(c("site_id,hazard_firms,n", 'S1,"8.""""""""""""""""""""""""""""""""""""""""""" S$ PRODUC (1984)",1', 'S2,"ELM LUBRICANTS INC """"COAT (1976)",2', 'S3,PLAIN CO (1970),3'), f)
  a <- rd(f); expect_false(any(grepl('"', a$hazard_firms, fixed = TRUE))); expect_equal(a$n, 1:3)
  fwrite(a, f); b <- rd(f); expect_equal(a, b)
  fwrite(b, f); expect_equal(rd(f), a)
  unlink(f)
})
