# R/build_sites.R and R/fuzz.R: name matching identical to rapidfuzz, match_basis precedence, clustering parity rule.
suppressPackageStartupMessages({ library(testthat); library(jsonlite); library(data.table) })
old <- setwd(ROOT); source("R/build_sites.R"); setwd(old)      # sources R/fuzz.R itself; TESTING skips the pipeline run

test_that("fuzz scores equal rapidfuzz", {
  P <- fromJSON(need_cache("python_fuzz.json"), simplifyVector = FALSE)
  for (p in P) {
    expect_equal(fz_ratio(p$a, p$b), p$ratio, tolerance = 1e-9, info = paste(p$a, "|", p$b))
    expect_equal(fz_token_sort_ratio(p$a, p$b), p$token_sort, tolerance = 1e-9, info = paste(p$a, "|", p$b))
    expect_equal(fz_token_set_ratio(p$a, p$b), p$token_set, tolerance = 1e-9, info = paste(p$a, "|", p$b))
  }
})

test_that("name_match: two shared informative words or a near-identical whole name", {
  expect_false(name_match("CRYSTAL CHEMICAL", "CRYSTAL")); expect_false(name_match("SERUM LABORATORIES", "SERUM"))
  expect_true(name_match("ACME PLATING WORKS", "ACME PLATING")); expect_true(name_match("ACME PLATING WORKS", "PLATING WORKS ACME"))
  expect_true(name_match("ACME PLATNG WORKS", "ACME PLATING WORKS")); expect_false(name_match("ACME PLATING", "ACME ELECTROPLATING"))
  expect_false(name_match("", "ACME")); expect_false(name_match("ROCKY MOUNTAIN STEEL", "ROCKY MOUNTAIN NEWS"))
  expect_true(name_match("ROCKY MOUNTAIN STEEL", "ROCKY MOUNTAIN STEEL MILLS"))
})

test_that("nn, norm_street and match_basis as in Python", {
  expect_equal(nn("The Colorado Springs Chemical Co., Inc."), "CHEMICAL"); expect_equal(nn("Denver Precision Castings of Colorado"), "")
  expect_equal(norm_street("450 Kalamath Street"), "450 KALAMATH ST"); expect_equal(norm_street("123 South Main Avenue"), "123 S MAIN AVE")
  expect_equal(match_basis(c("prox", "boundary", "entity")), "same entity (name or address)")
  expect_equal(match_basis(c("prox", "boundary")), "inside a cleanup boundary"); expect_equal(match_basis("prox"), "nearby record only"); expect_equal(match_basis(character()), "none")
})

test_that("clustering: 30 m components with the across-the-street parity rule", {
  lat0 <- 39.72; lon0 <- -105; dlat <- function(m) m / 111320; dlon <- function(m) m / (111320 * cos(lat0 * pi / 180))
  P <- data.table(lat = c(lat0, lat0, lat0 + dlat(3), lat0 + dlat(3), lat0 + dlat(200)), lon = c(lon0 - dlon(12), lon0 + dlon(12), lon0 - dlon(12), lon0 + dlon(12), lon0),
                  base = c("KALAMATH", "KALAMATH", "KALAMATH", "KALAMATH", "KALAMATH"), num = c(450, 451, 452, 453, 470))
  P <- P[order(lat)]; m <- cluster_points(P)
  k <- function(n) m[P$num == n]
  expect_equal(k(450), k(452)); expect_equal(k(451), k(453)); expect_false(k(450) == k(451)); expect_false(k(470) == k(450))
  # a point of another street between the sides bridges them
  Q <- data.table(lat = c(lat0, lat0, lat0), lon = c(lon0 - dlon(12), lon0 + dlon(12), lon0), base = c("KALAMATH", "KALAMATH", "W 5TH"), num = c(450, 451, 100))
  expect_equal(length(unique(cluster_points(Q[order(lat)]))), 1)
  # numberless or different-direction points link
  R <- data.table(lat = c(lat0, lat0), lon = c(lon0, lon0 + dlon(20)), base = c("KALAMATH", "S KALAMATH"), num = c(450, 451))
  expect_equal(length(unique(cluster_points(R))), 1)
})
