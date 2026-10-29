suppressPackageStartupMessages({ library(sandwich); library(lmtest) })
E <- script_env("holc_covenants.R")

test_that("change_periods(): poverty and Hispanic changes start in 1970, the others in 1940", {
  expect_equal(E$change_periods("p_hisp"), list(c(1970, 1980), c(1980, 2010), c(1970, 2010)))
  expect_equal(E$change_periods("p_pov")[[1]][1], 1970)
  expect_equal(E$change_periods("p_black"), list(c(1940, 1980), c(1980, 2010), c(1940, 2010)))
  expect_equal(E$change_periods("lmval")[[1]][1], 1940)
})

test_that("fill_hisp_1940(): fills only 1940 rows with no value, and only from districts holding 200+ residents", {
  pan <- data.table(GEOID = c("1", "1", "2", "3", "4"), census = c(1940, 1950, 1940, 1940, 1940), p_hisp = c(NA, NA, NA, 12, NA))
  h40 <- data.table(GEOID = c("1", "2", "3", "4"), pop40 = c(500, 150, 800, 200), hisp40 = c(50, 15, 80, 20))
  out <- E$fill_hisp_1940(copy(pan), h40)
  expect_equal(out[GEOID == "1" & census == 1940, p_hisp], 10)
  expect_true(is.na(out[GEOID == "1" & census == 1950, p_hisp]))   # not a 1940 row
  expect_true(is.na(out[GEOID == "2", p_hisp]))                     # 150 residents: below the floor
  expect_equal(out[GEOID == "3", p_hisp], 12)                       # an existing value is kept
  expect_equal(out[GEOID == "4", p_hisp], 10)                       # exactly 200 counts
  expect_false(any(c("pop40", "hisp40") %in% names(out)))
  expect_equal(E$MIN_POP40, 200)
})

mk_d <- function(n = c(A = 12, B = 12, C = 12, D = 2)) { set.seed(1)
  d <- data.table(grade = factor(rep(names(n), n), c("A", "B", "C", "D", "Industrial", "Commercial")))
  d[, `:=`(base = rnorm(.N, 10), black40 = runif(.N, 0, 20), firms40 = log1p(rpois(.N, 2)))]; d[, dy := 1 + 0.5 * base + as.integer(grade) + rnorm(.N)]; d[] }

test_that("drop_small_classes(): classes with fewer than 5 tracts are dropped and levels re-set", {
  d <- E$drop_small_classes(mk_d())
  expect_equal(levels(d$grade), c("A", "B", "C")); expect_equal(nrow(d), 36)
  expect_equal(E$MIN_CLS, 5)
  d5 <- E$drop_small_classes(mk_d(c(A = 10, D = 5))); expect_equal(levels(d5$grade), c("A", "D"))
})

test_that("drop_small_classes(): the A reference class is kept even when it holds fewer than 5 tracts (Denver has 4), so the models still run", {
  d <- E$drop_small_classes(mk_d(c(A = 4, B = 12, C = 12, D = 12, Industrial = 2)))
  expect_true("A" %in% levels(d$grade)); expect_equal(levels(d$grade), c("A", "B", "C", "D")); expect_equal(sum(d$grade == "A"), 4)
  cm <- E$change_model(d); expect_true(all(c("gradeB", "gradeC", "gradeD") %in% rownames(cm$ct)))   # A is the reference: no gradeA row
  expect_false("gradeA" %in% rownames(cm$ct))
  expect_equal(formals(E$drop_small_classes)$ref, "A")
})

test_that("change_model(): returns HC1 and classical errors; the classical ones equal summary(lm)", {
  d <- E$drop_small_classes(mk_d()); cm <- E$change_model(d)
  expect_true(all(c("gradeB", "gradeC") %in% rownames(cm$ct))); expect_false("gradeD" %in% rownames(cm$ct))
  expect_equal(unname(cm$ct0["gradeB", 2]), unname(summary(cm$m)$coefficients["gradeB", 2]))
  expect_equal(unname(cm$ct["gradeB", 2]), unname(sqrt(diag(vcovHC(cm$m, type = "HC1")))["gradeB"]))
  expect_false(isTRUE(all.equal(cm$ct["gradeB", 2], cm$ct0["gradeB", 2])))
})

test_that("a class of one or two tracts is dropped before the model, so it never gets a dummy fitted to itself", {
  d <- mk_d(c(A = 12, B = 12, C = 12, D = 1)); cm <- E$change_model(d)   # without dropping: a dummy for one tract
  expect_true("gradeD" %in% rownames(cm$ct)); expect_equal(sum(d$grade == "D"), 1)
  cm2 <- E$change_model(E$drop_small_classes(d)); expect_false("gradeD" %in% rownames(cm2$ct))
})
