suppressPackageStartupMessages({ library(spdep) })
ECO <- script_env("corridors.R"); EH <- script_env("health_models.R"); EJ <- script_env("ej_panel.R")

test_that("corridors eg(): the permutation p-value is seeded, so repeated calls agree; a concentrated sector has a high gamma", {
  cell_all <- rep(c("a", "b", "c", "d"), each = 25); cell_sec <- rep("a", 20)
  r1 <- ECO$eg(cell_all, cell_sec, nperm = 199); r2 <- ECO$eg(cell_all, cell_sec, nperm = 199)
  expect_identical(r1, r2)
  expect_true(r1["gamma"] > 0.5); expect_true(r1["p"] <= 0.01)
  spread <- rep(c("a", "b", "c", "d"), each = 5); r3 <- ECO$eg(cell_all, spread, nperm = 199)
  expect_true(r3["gamma"] < r1["gamma"]); expect_true(r3["p"] > 0.5)
})

test_that("corridors eg() restores nothing odd: a later sample() in the session is not fixed by the seed", {
  ECO$eg(rep(c("a", "b"), 50), rep("a", 10), nperm = 9); s1 <- sample(1e6, 1); ECO$eg(rep(c("a", "b"), 50), rep("a", 10), nperm = 9); s2 <- sample(1e6, 1)
  expect_equal(s1, s2)   # eg() sets the seed each time it runs, so what follows it is also reproducible
})

# three squares whose shared edges do not quite meet (the app tracts were simplified one by one), in metres and in degrees
gap_polys <- function(gap, crs) sf::st_sf(id = 1:3, geometry = sf::st_sfc(sq(0, 0, 1), sq(1 + gap, 0, 1), sq(0, 1 + gap, 1), crs = crs))

test_that("corridors queen_listw(): snap = 2 m joins tracts whose simplified edges are up to 2 m apart", {
  g <- gap_polys(1, UTM)                                   # 1 m gaps, in a metric CRS: squares of 1 m are enough for the test
  w <- ECO$queen_listw(g); expect_equal(card(w$neighbours), c(2, 2, 2))                 # queen: squares 2 and 3 touch at a corner too
  expect_equal(sum(card(suppressWarnings(poly2nb(g, queen = TRUE, snap = 0)))), 0)      # without the snap: islands
  expect_equal(sum(card(suppressWarnings(poly2nb(gap_polys(3, UTM), queen = TRUE, snap = 2)))), 0)                        # 3 m gaps: not joined by a 2 m snap
})

test_that("health_models queen_listw(): snap = 2e-5 degrees (about 2 m) for the app's lon/lat tracts", {
  g <- gap_polys(1e-5, 4326)
  w <- suppressWarnings(EH$queen_listw(g)); expect_equal(card(w$neighbours), c(2, 2, 2))
  expect_equal(sum(card(suppressWarnings(poly2nb(g, queen = TRUE, snap = 0)))), 0)
  expect_equal(formals(EH$queen_listw)$snap, 2e-5); expect_equal(formals(ECO$queen_listw)$snap, 2)
})

test_that("health_models z(): standardised log1p, NA-safe", {
  x <- c(0, 1, 3, NA); zz <- EH$z(x)
  expect_equal(zz[1:3], (log1p(x[1:3]) - mean(log1p(x[1:3]))) / sd(log1p(x[1:3]))); expect_true(is.na(zz[4]))
  expect_equal(names(EH$OUT)[1], "log_asthma"); expect_equal(length(EH$REG), 5)
})

test_that("ej_panel add_shares(): shares over the table's own universe, falling back to the population; log value NA for 0", {
  cen <- data.table(GEOID = c("1", "2", "3"), census = 1990, pop = c(1000, 1000, 1000), nhblk = c(100, 50, 0), hisp = c(200, 100, 0), white = c(700, 850, 1000),
                    fb = c(90, 90, 90), fb_den = c(900, NA, 0), ppov = c(100, 100, 100), ppov_den = c(800, NA, 0), own = c(200, 300, NA), rentocc = c(200, 100, NA),
                    mval_2020 = c(100000, 0, NA), mrent_2020 = c(1000, 500, 0))
  out <- EJ$add_shares(copy(cen))
  expect_equal(out$p_black, c(10, 5, 0)); expect_equal(out$p_white, c(70, 85, 100))                      # white stands in for nhwht in the NHGIS panel
  expect_equal(out$p_fb, c(10, 9, 9)); expect_equal(out$ppov, c(12.5, 10, 10))
  expect_equal(out$p_owner, c(50, 75, NA))
  expect_equal(out$lmval, c(log(100000), NA, NA)); expect_equal(out$lmrent, c(log(1000), log(500), NA))
  cen2 <- data.table(GEOID = "1", census = 2000, pop = 100, nhblk = 10, hisp = 10); out2 <- EJ$add_shares(copy(cen2))   # missing columns are added as NA
  expect_true(all(c("fb", "ppov", "own", "lmval") %in% names(out2))); expect_true(is.na(out2$p_fb))
})
