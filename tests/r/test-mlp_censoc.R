EM <- script_env("mlp_residential_history.R"); EC <- script_env("censoc_denver_1940.R")

test_that("mlp pct_within_500(): earlier censuses leave out residents without a geocoded address (NA) instead of returning NA", {
  AH <- data.table(year = c(1920, 1920, 1920, 1920, 1930, 1930), haz_500_then = c(1, 0, NA, 1, NA, NA))
  P <- data.table(x = c(1, 2, NA), haz_500_w40 = c(1, 0, NA))
  expect_equal(EM$pct_within_500(1920, P, AH), round(100 * 2 / 3, 1))
  expect_true(is.nan(EM$pct_within_500(1930, P, AH)) || is.na(EM$pct_within_500(1930, P, AH)))   # nobody geocoded that year
  expect_equal(EM$pct_within_500(1940, P, AH), 50)                                              # 1940: the residents with an address point
  expect_equal(EM$KMIN, 20)
})

test_that("mlp kern(): Gaussian kernel (500 m) and any-within-500 m; no sites gives zeros", {
  xy <- rbind(c(0, 0), c(1000, 0), c(5000, 0)); hk <- rbind(c(0, 0), c(0, 400))
  k <- EM$kern(hk, xy)
  expect_equal(k$w500, c(1, 0, 0)); expect_equal(k$k[1], 1 + exp(-0.5 * (400 / 500)^2)); expect_equal(k$k[3], 0)   # beyond the 2 km cutoff
  k0 <- EM$kern(matrix(numeric(0), 0, 2), xy); expect_equal(k0$k, c(0, 0, 0)); expect_equal(k0$w500, c(0, 0, 0))
})

test_that("mlp pctl(): percentiles with ties sharing the average rank", {
  expect_equal(EM$pctl(c(1, 2, 2, 10)), 100 * c(1, 2.5, 2.5, 4) / 4)
})

test_that("mlp in_win(): sites listed in the decade up to the census", {
  EM$Hs <- data.table(first_year = c(1905, 1912, 1921, 1890), last_year = c(1915, 1912, 1930, 1900))
  expect_equal(EM$in_win(1920), c(TRUE, TRUE, FALSE, FALSE)); expect_equal(EM$in_win(1910), c(TRUE, FALSE, FALSE, FALSE))
})

test_that("censoc rd(): reads a CenSoc file, keeps conservative links, derives death_age and labels the file", {
  f <- file.path(tempdir(), "censoc_dmf_test.csv")
  fwrite(data.table(HISTID = c("a1", "a2", "a3"), byear = c(1900, 1900, 1910), bmonth = c(6, 6, 1), dyear = c(1980, 1980, 1990), dmonth = c(5, 7, 3), weight = 1, link_abe_exact_conservative = c(1, 1, 0)), f)
  x <- EC$rd(f)
  expect_equal(nrow(x), 2); expect_equal(x$histid, c("A1", "A2")); expect_equal(x$death_age, c(79, 80)); expect_equal(unique(x$sex), 1)
  expect_match(x$file[1], "^DMF")
  f2 <- file.path(tempdir(), "censoc_numident_test.csv"); fwrite(data.table(histid = "b1", byear = 1900, bmonth = 1, dyear = 1990, dmonth = 1, death_age = 90, sex = 2, weight = 2), f2)
  y <- EC$rd(f2); expect_match(y$file, "^Numident"); expect_equal(y$death_age, 90); expect_equal(y$sex, 2)
})

test_that("censoc HAZ_IND covers the Frickel & Elliott industries (IND1950 codes)", {
  expect_true(all(c(206, 239, 336, 346, 356, 376, 466, 476, 478) %in% EC$HAZ_IND)); expect_false(any(c(205, 240, 340, 479) %in% EC$HAZ_IND))
})

test_that("censoc kern(): kernel over the unique address points (UXY), 2 km cutoff", {
  EC$UXY <- rbind(c(0, 0), c(3000, 0)); EC$U <- data.table(x = c(0, 3000))
  expect_equal(EC$kern(rbind(c(0, 500))), c(exp(-0.5), 0)); expect_equal(EC$kern(matrix(numeric(0), 0, 2)), c(0, 0))
})
