E <- script_env("fetch_census.R")

test_that("interp(): medians exclude 0 (suppressed), weight value by owner units and rent by renter units, and need MIN_U units", {
  expect_equal(E$MIN_U, 10)
  M <- data.table(GEOID = c("A", "A", "B", "C"), census = 1950, w = c(1, 0.5, 1, 1),
                  pop = c(1000, 400, 100, 300), nhblk = c(10, 4, 1, 3), white = c(900, 300, 90, 290), hisp = c(50, 20, 5, 10), fb = c(100, 40, 10, 30), ppov = NA_real_,
                  own = c(100, 40, 4, NA), rentocc = c(50, 80, 20, NA), mval = c(10000, 0, 5000, 7000), mrent = c(30, 50, 25, 40))
  out <- E$interp(copy(M)); setkey(out, GEOID)
  expect_equal(out["A", pop], 1000 + 0.5 * 400)                                   # counts are split by area
  expect_equal(out["A", mval], 10000)                                            # the 0 median is missing, not a value
  expect_equal(out["A", mrent], (30 * 50 * 1 + 50 * 80 * 0.5) / (50 * 1 + 80 * 0.5))   # rent weighted by renter units x overlap
  expect_true(is.na(out["B", mval]))                                              # 4 owner units < MIN_U
  expect_equal(out["B", mrent], 25)                                               # 20 renter units are enough
  expect_equal(out["C", mval], 7000)                                              # no tenure table: the population stands in as the weight
  expect_true(all(is.na(out$ppov)))                                               # an all-NA count stays NA, not 0
})

test_that("interp() does not weight medians by population or include suppressed zeros (the old logic)", {
  M <- data.table(GEOID = "A", census = 1960, w = 1, pop = c(5000, 100), own = c(20, 400), rentocc = c(10, 10), mval = c(100000, 20000), mrent = c(0, 60))
  out <- E$interp(copy(M))
  expect_equal(out$mval, (100000 * 20 + 20000 * 400) / 420)   # owner-unit weights: the small tract with many owners dominates
  expect_false(isTRUE(all.equal(out$mval, (100000 * 5000 + 20000 * 100) / 5100)))
  expect_equal(out$mrent, 60)
})

test_that("grouped_median() interpolates within the bin holding the median and returns NA under 10 units", {
  m <- data.table(var = c("b1", "b2", "b3"), label = c("Under $5,000", "$5,000 - $9,999", "$10,000 or more"))
  D <- data.table(b1 = c(4, 1), b2 = c(10, 2), b3 = c(6, 1))
  expect_equal(E$grouped_median(D, m), c(5000 + (10 - 4) / 10 * 5000, NA_real_))
  # bins given out of order are sorted by their lower bound
  m2 <- m[c(3, 1, 2)]; expect_equal(E$grouped_median(D, m2)[1], 8000)
})

test_that("num() and gj() parse NHGIS values and GISJOINs", {
  expect_equal(E$num(c("2,000+", "-", "15")), c(2000, NA, 15))
  expect_equal(E$gj("G0800310000101"), "08031000101")
})
