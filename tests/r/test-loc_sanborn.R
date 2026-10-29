E <- script_env("loc_sanborn_1903.R")

test_that("st_base(): ordinal and type-insensitive street keys ('38th' matches 38th St and 38th Ave)", {
  expect_equal(E$st_base(c("Thirty-Eighth Street", "38th St.", "38th Ave", "W. 38th Avenue", "Larimer St", "Wazee (not opened)", NA, "")), c("38", "38", "38", "38", "LARIMER", "WAZEE", "", ""))
  expect_equal(E$st_base("Twenty-Third St"), "23"); expect_equal(E$st_base("Eleventh"), "11")
})

test_that("streets_label(): sorted unique bounding streets joined by '/', unnamed sides give no stray separator", {
  expect_equal(E$streets_label(c("Larimer St", NA, "", "38th Ave")), "38/LARIMER")
  expect_equal(E$streets_label(c("Larimer St", "Larimer Street", NA, NA)), "LARIMER")
  expect_equal(E$streets_label(c(NA, NA, NA, NA)), "")
  expect_false(grepl("^/|/$|//", E$streets_label(c("Larimer St", NA, "Wazee St", NA))))
})

test_that("dmin(): edge-to-edge distance to the nearest OTHER hazardous block or plant; across the street = within 30 m", {
  # three 50 m blocks: 1 and 2 are 20 m apart (a street), 3 is 100 m from 2
  E$BG <- sf::st_sfc(sq(0, 0, 50), sq(70, 0, 50), sq(220, 0, 50), crs = UTM); E$OPG <- sf::st_sfc(crs = UTM)
  d <- E$dmin(c(TRUE, FALSE, FALSE), logical(0))
  expect_equal(d, c(Inf, 20, 170))                      # a block's own trades do not count for itself
  expect_equal(E$ACROSS_M, 30)
  expect_equal(d <= E$ACROSS_M, c(FALSE, TRUE, FALSE))
  E$OPG <- sf::st_sfc(sq(300, 0, 50), crs = UTM)       # a plant on unplatted ground 30 m east of block 3
  expect_equal(E$dmin(c(FALSE, FALSE, FALSE), TRUE), c(250, 180, 30))
})

test_that("exposure_of(): the exposure ladder", {
  out <- E$exposure_of(mixed_haz = c(TRUE, FALSE, FALSE, FALSE, FALSE, FALSE), dwellings = c(5, 5, 5, 5, 5, 0),
                       across_haz = c(TRUE, TRUE, FALSE, FALSE, FALSE, TRUE), dwellings_facing_industry = c(0, 0, 2, 0, 0, 0), n_industrial = c(1, 0, 0, 1, 0, 0),
                       near_haz_150 = c(TRUE, TRUE, TRUE, TRUE, TRUE, TRUE))
  expect_equal(out, c("Same block as a hazardous trade", "Across the street from a hazardous trade", "Same block as other industry, or facing industry",
                      "Same block as other industry, or facing industry", "Within 150 m of a hazardous trade", "Within 150 m of a hazardous trade"))
  expect_equal(E$exposure_of(FALSE, 3, FALSE, 0, 0, FALSE), "No hazardous trade within 150 m")
})

test_that("block_poly(): four corners give a shrunk block outline; missing corners give a 50 m circle", {
  E$CX <- new.env(); E$GAZ <- NULL
  E$RO <- sf::st_sf(base = c("A", "B", "C", "D"), geometry = sf::st_sfc(line_xy(-50, 100, 250, 100), line_xy(-50, 0, 250, 0), line_xy(200, -50, 200, 150), line_xy(0, -50, 0, 150), crs = UTM))
  p <- E$block_poly(100, 50, "A", "B", "C", "D")
  expect_equal(p$corners, 4L); expect_equal(as.numeric(sf::st_area(p$g)), (200 - 24) * (100 - 24))
  q <- E$block_poly(100, 50, "A", "", "C", "")
  expect_equal(q$corners, 0L); expect_equal(as.numeric(sf::st_area(q$g)), pi * 50^2, tolerance = 0.01)
})
